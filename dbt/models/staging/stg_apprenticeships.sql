{{
  config(
    materialized='table',
    partition_by={'field': 'academic_year_start', 'data_type': 'int64',
                  'range': {'start': 2017, 'end': 2030, 'interval': 1}},
    cluster_by=['dataset_version', 'region_code', 'apprenticeship_level']
  )
}}

/*
  Silver: typed, suppression-aware, one row per natural key per dataset version.

  Three things happen here and nowhere else:
    1. Each measure splits into a typed value + a status code (see macros).
    2. `aggregation_depth` is derived so downstream models can avoid the
       subtotal double-count trap.
    3. `time_period` (202425) becomes a usable year pair.
*/

with source as (

    /* IDEMPOTENCY GUARD.

       Bronze is append-only: re-extracting a version lands a NEW
       ingest_date partition beside the old one, and the external table
       globs every partition. So a re-run of the same source version
       duplicates every one of its rows here.

       This is not hypothetical -- it fired the moment the calendar date
       rolled over between two runs, and the uniqueness test on
       (row_key, dataset_version) caught it before anything reached gold.

       Bronze keeps all copies (that is the point of an immutable raw
       layer); silver resolves each version to its most recent extraction. */

    select * except (_ingest_rank)
    from (
        select
            *,
            row_number() over (
                partition by
                    version, time_period, geographic_level, region_code,
                    apprenticeship_level, age_youth_adult, age_group,
                    funding_type, provider_type
                order by ingest_date desc
            ) as _ingest_rank
        from {{ source('bronze', 'raw_apprenticeships') }}
    )
    where _ingest_rank = 1

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
        {{ measure_value('start_count', 'INT64') }}          as start_count,
        {{ measure_status('start_count') }}                  as start_count_status,

        {{ measure_value('achievement_count', 'INT64') }}    as achievement_count,
        {{ measure_status('achievement_count') }}            as achievement_count_status,

        {{ measure_value('participation_count', 'INT64') }}  as participation_count,
        {{ measure_status('participation_count') }}          as participation_count_status,

        {{ measure_value('starts_percent', 'FLOAT64') }}     as starts_percent,
        {{ measure_status('starts_percent') }}               as starts_percent_status,

        {{ measure_value('achievements_percent', 'FLOAT64') }} as achievements_percent,
        {{ measure_status('achievements_percent') }}         as achievements_percent_status,

        -- ---- grain -------------------------------------------------------
        {{ aggregation_depth() }}                 as aggregation_depth

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
