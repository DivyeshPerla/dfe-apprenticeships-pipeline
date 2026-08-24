
  
    

    create or replace table `dfe-apprenticeships-2026`.`silver`.`stg_apprenticeships`
      
    partition by range_bucket(
            academic_year_start,
            generate_array(2017, 2030, 1)
        )
    cluster by dataset_version, region_code, apprenticeship_level

    
    OPTIONS()
    as (
      

/*
  Silver: typed, suppression-aware, one row per natural key per dataset version.

  Three things happen here and nowhere else:
    1. Each measure splits into a typed value + a status code (see macros).
    2. `aggregation_depth` is derived so downstream models can avoid the
       subtotal double-count trap.
    3. `time_period` (202425) becomes a usable year pair.
*/

with source as (

    select * from `dfe-apprenticeships-2026`.`bronze`.`raw_apprenticeships`

),

typed as (

    select
        -- ---- lineage -----------------------------------------------------
        version                                   as dataset_version,
        -- hive AUTO partitioning already infers this as DATE
        ingest_date                               as ingested_date,

        -- ---- time --------------------------------------------------------
        -- '202425' -> 2024 (start) / 2025 (end), label '2024/25'
        cast(substr(time_period, 1, 4) as int64)  as academic_year_start,
        cast(substr(time_period, 1, 4) as int64) + 1 as academic_year_end,
        concat(substr(time_period, 1, 4), '/', substr(time_period, 5, 2))
                                                  as academic_year_label,
        time_identifier,

        -- ---- geography ---------------------------------------------------
        geographic_level,
        country_code,
        country_name,
        nullif(region_code, '')                   as region_code,
        nullif(region_name, '')                   as region_name,

        -- ---- filter dimensions -------------------------------------------
        apprenticeship_level,
        age_youth_adult,
        age_group,
        funding_type,
        provider_type,

        -- ---- measures: value + why-it-is-null ----------------------------
        
    SAFE_CAST(NULLIF(TRIM(start_count), '') AS INT64)          as start_count,
        
    CASE
        WHEN start_count IS NULL OR TRIM(start_count) = '' THEN 'missing'
        WHEN SAFE_CAST(TRIM(start_count) AS FLOAT64) IS NOT NULL THEN 'published'
        WHEN LOWER(TRIM(start_count)) = 'low' THEN 'suppressed_low'
        WHEN LOWER(TRIM(start_count)) = 'c'   THEN 'suppressed_confidential'
        WHEN LOWER(TRIM(start_count)) = 'z'   THEN 'not_applicable'
        ELSE 'unrecognised'
    END                  as start_count_status,

        
    SAFE_CAST(NULLIF(TRIM(achievement_count), '') AS INT64)    as achievement_count,
        
    CASE
        WHEN achievement_count IS NULL OR TRIM(achievement_count) = '' THEN 'missing'
        WHEN SAFE_CAST(TRIM(achievement_count) AS FLOAT64) IS NOT NULL THEN 'published'
        WHEN LOWER(TRIM(achievement_count)) = 'low' THEN 'suppressed_low'
        WHEN LOWER(TRIM(achievement_count)) = 'c'   THEN 'suppressed_confidential'
        WHEN LOWER(TRIM(achievement_count)) = 'z'   THEN 'not_applicable'
        ELSE 'unrecognised'
    END            as achievement_count_status,

        
    SAFE_CAST(NULLIF(TRIM(participation_count), '') AS INT64)  as participation_count,
        
    CASE
        WHEN participation_count IS NULL OR TRIM(participation_count) = '' THEN 'missing'
        WHEN SAFE_CAST(TRIM(participation_count) AS FLOAT64) IS NOT NULL THEN 'published'
        WHEN LOWER(TRIM(participation_count)) = 'low' THEN 'suppressed_low'
        WHEN LOWER(TRIM(participation_count)) = 'c'   THEN 'suppressed_confidential'
        WHEN LOWER(TRIM(participation_count)) = 'z'   THEN 'not_applicable'
        ELSE 'unrecognised'
    END          as participation_count_status,

        
    SAFE_CAST(NULLIF(TRIM(starts_percent), '') AS FLOAT64)     as starts_percent,
        
    CASE
        WHEN starts_percent IS NULL OR TRIM(starts_percent) = '' THEN 'missing'
        WHEN SAFE_CAST(TRIM(starts_percent) AS FLOAT64) IS NOT NULL THEN 'published'
        WHEN LOWER(TRIM(starts_percent)) = 'low' THEN 'suppressed_low'
        WHEN LOWER(TRIM(starts_percent)) = 'c'   THEN 'suppressed_confidential'
        WHEN LOWER(TRIM(starts_percent)) = 'z'   THEN 'not_applicable'
        ELSE 'unrecognised'
    END               as starts_percent_status,

        
    SAFE_CAST(NULLIF(TRIM(achievements_percent), '') AS FLOAT64) as achievements_percent,
        
    CASE
        WHEN achievements_percent IS NULL OR TRIM(achievements_percent) = '' THEN 'missing'
        WHEN SAFE_CAST(TRIM(achievements_percent) AS FLOAT64) IS NOT NULL THEN 'published'
        WHEN LOWER(TRIM(achievements_percent)) = 'low' THEN 'suppressed_low'
        WHEN LOWER(TRIM(achievements_percent)) = 'c'   THEN 'suppressed_confidential'
        WHEN LOWER(TRIM(achievements_percent)) = 'z'   THEN 'not_applicable'
        ELSE 'unrecognised'
    END         as achievements_percent_status,

        -- ---- grain -------------------------------------------------------
        
    (
        IF(apprenticeship_level = 'Total', 1, 0)
      + IF(age_youth_adult = 'Total', 1, 0)
      + IF(age_group = 'Total', 1, 0)
      + IF(funding_type = 'Total', 1, 0)
      + IF(provider_type = 'Total', 1, 0)
    )                 as aggregation_depth

    from source

)

select
    -- Stable surrogate over the 8-part natural key. Used downstream to detect
    -- restatements between dataset versions.
    to_hex(md5(concat(
        cast(academic_year_start as string), '|',
        geographic_level, '|', coalesce(region_code, 'NA'), '|',
        apprenticeship_level, '|', age_youth_adult, '|',
        age_group, '|', funding_type, '|', provider_type
    )))                                            as row_key,

    *,
    aggregation_depth = 0                          as is_detail_grain,

    -- 2025/26 is part-year (first three quarters) and will be revised.
    academic_year_start = 2025                     as is_provisional

from typed
    );
  