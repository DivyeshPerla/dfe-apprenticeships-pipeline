{{
  config(
    materialized='table',
    partition_by={'field': 'academic_year_start', 'data_type': 'int64',
                  'range': {'start': 2017, 'end': 2030, 'interval': 1}},
    cluster_by=['row_key', 'region_code', 'apprenticeship_level']
  )
}}

/*
  Type 2 slowly-changing fact across published dataset versions.

  The source restates history: between releases, rows are added, removed AND
  revised in place. This model collapses the six published versions into
  validity intervals so the warehouse can answer "what did DfE report as of
  version X?" rather than only "what do they say now".

  THE CRITICAL DETAIL -- the comparison is on TYPED values, never on the raw
  strings. Version 1.0.2 -> 2.0 reformatted ~4,200 values ('4' -> '4.0') with
  no change in meaning. Diffing strings would open a phantom SCD-2 record for
  every one of them. See docs/profiling/PROFILE.md, Finding 4.
*/

with base as (

    select
        s.row_key,
        v.version_seq,
        s.dataset_version,
        v.published_at,

        s.academic_year_start,
        s.academic_year_label,
        s.geographic_level,
        s.country_code,
        s.country_name,
        s.region_code,
        s.region_name,
        s.apprenticeship_level,
        s.age_youth_adult,
        s.age_group,
        s.funding_type,
        s.provider_type,
        s.aggregation_depth,
        s.is_detail_grain,
        s.is_provisional,

        s.start_count,
        s.start_count_status,
        s.achievement_count,
        s.achievement_count_status,
        s.participation_count,
        s.participation_count_status,
        s.starts_percent,
        s.starts_percent_status,
        s.achievements_percent,
        s.achievements_percent_status

    from {{ ref('stg_apprenticeships') }} s
    join {{ ref('dataset_versions') }} v
      on s.dataset_version = v.version

),

flagged as (

    select
        *,
        -- Compare typed measures plus their suppression status. A move from
        -- 'low' to a published 10 is a genuine revision and must be captured,
        -- even though both sides cast to different things.
        case
            when lag(start_count)                over w is distinct from start_count                then 1
            when lag(achievement_count)          over w is distinct from achievement_count          then 1
            when lag(participation_count)        over w is distinct from participation_count        then 1
            when lag(starts_percent)             over w is distinct from starts_percent             then 1
            when lag(achievements_percent)       over w is distinct from achievements_percent       then 1
            when lag(start_count_status)         over w is distinct from start_count_status         then 1
            when lag(achievement_count_status)   over w is distinct from achievement_count_status   then 1
            when lag(participation_count_status) over w is distinct from participation_count_status then 1
            when lag(starts_percent_status)      over w is distinct from starts_percent_status      then 1
            when lag(achievements_percent_status) over w is distinct from achievements_percent_status then 1
            else 0
        end as is_change

    from base
    window w as (partition by row_key order by version_seq)

),

grouped as (

    -- Running sum of change flags gives every unchanged run a shared id,
    -- collapsing consecutive identical versions into one SCD-2 record.
    select
        *,
        sum(is_change) over (
            partition by row_key order by version_seq
            rows between unbounded preceding and current row
        ) as validity_group
    from flagged

),

latest as (

    select max(version_seq) as max_seq from {{ ref('dataset_versions') }}

),

collapsed as (

    select
        row_key,
        validity_group,

        min(version_seq)      as valid_from_seq,
        max(version_seq)      as valid_to_seq,
        min(dataset_version)  as valid_from_version,
        max(dataset_version)  as valid_to_version,
        min(published_at)     as valid_from_published,

        -- dimensions are constant within a row_key
        any_value(academic_year_start)   as academic_year_start,
        any_value(academic_year_label)   as academic_year_label,
        any_value(geographic_level)      as geographic_level,
        any_value(country_code)          as country_code,
        any_value(country_name)          as country_name,
        any_value(region_code)           as region_code,
        any_value(region_name)           as region_name,
        any_value(apprenticeship_level)  as apprenticeship_level,
        any_value(age_youth_adult)       as age_youth_adult,
        any_value(age_group)             as age_group,
        any_value(funding_type)          as funding_type,
        any_value(provider_type)         as provider_type,
        any_value(aggregation_depth)     as aggregation_depth,
        any_value(is_detail_grain)       as is_detail_grain,
        any_value(is_provisional)        as is_provisional,

        -- measures are constant within a validity group by construction
        any_value(start_count)                   as start_count,
        any_value(start_count_status)            as start_count_status,
        any_value(achievement_count)             as achievement_count,
        any_value(achievement_count_status)      as achievement_count_status,
        any_value(participation_count)           as participation_count,
        any_value(participation_count_status)    as participation_count_status,
        any_value(starts_percent)                as starts_percent,
        any_value(starts_percent_status)         as starts_percent_status,
        any_value(achievements_percent)          as achievements_percent,
        any_value(achievements_percent_status)   as achievements_percent_status

    from grouped
    group by row_key, validity_group

)

select
    c.*,
    -- Current only if this record survives into the newest published version.
    -- Keys that disappeared are soft-deleted: they keep their history but are
    -- never is_current, and are never hard-deleted.
    c.valid_to_seq = l.max_seq as is_current,
    c.valid_to_seq < l.max_seq as is_soft_deleted
from collapsed c
cross join latest l
