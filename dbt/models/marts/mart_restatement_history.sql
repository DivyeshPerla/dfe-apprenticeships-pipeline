{{ config(materialized='table') }}

/* Every figure the publisher revised between releases.

   This is only possible because bronze retains all six published versions and
   the fact is SCD-2. It answers "what changed, when, and by how much" -- the
   question a downstream consumer of official statistics actually cares about,
   and one a current-state-only warehouse cannot answer at all. */

with versioned as (

    select
        row_key,
        academic_year_label,
        geographic_level,
        region_name,
        apprenticeship_level,
        age_group,
        provider_type,
        valid_from_version,
        valid_from_published,
        valid_from_seq,
        start_count,
        start_count_status,
        achievement_count,
        lag(start_count)        over w as prev_start_count,
        lag(start_count_status) over w as prev_start_count_status,
        lag(achievement_count)  over w as prev_achievement_count,
        lag(valid_from_version) over w as prev_version
    from {{ ref('fct_apprenticeship_headline') }}
    window w as (partition by row_key order by valid_from_seq)

)

select
    row_key,
    academic_year_label,
    geographic_level,
    region_name,
    apprenticeship_level,
    age_group,
    provider_type,

    prev_version                          as restated_from_version,
    valid_from_version                    as restated_in_version,
    valid_from_published                  as restated_on,

    prev_start_count                      as start_count_before,
    start_count                           as start_count_after,
    start_count - prev_start_count        as start_count_delta,
    safe_divide(start_count - prev_start_count, prev_start_count) as start_count_pct_change,

    prev_start_count_status               as status_before,
    start_count_status                    as status_after,
    -- A figure moving between suppressed and published is a disclosure
    -- decision, not a data revision. Worth separating in analysis.
    prev_start_count_status != start_count_status as disclosure_status_changed

from versioned
where prev_version is not null
