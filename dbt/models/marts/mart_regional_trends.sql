{{ config(materialized='table') }}

/* Analyst-facing regional view.

   Pre-filtered to is_current and detail grain, so a consumer cannot
   accidentally reproduce the 24x double-count. Suppressed rows are retained
   with NULL measures and a count of how many were withheld, so a low regional
   total is distinguishable from a heavily suppressed one. */

select
    f.academic_year_start,
    f.academic_year_label,
    f.is_provisional,
    f.region_code,
    f.region_name,
    f.apprenticeship_level,

    sum(f.start_count)                                as starts,
    sum(f.achievement_count)                          as achievements,
    sum(f.participation_count)                        as participation,

    countif(f.start_count_status = 'published')       as start_rows_published,
    countif(f.start_count_status != 'published')      as start_rows_suppressed,
    safe_divide(
        countif(f.start_count_status != 'published'),
        count(*)
    )                                                 as suppression_rate,

    -- An achievement rate over a heavily suppressed base is not trustworthy;
    -- surface the ingredients rather than a single misleading ratio.
    safe_divide(sum(f.achievement_count), sum(f.start_count)) as achievement_ratio

from {{ ref('fct_apprenticeship_headline') }} f
where f.is_current
  and f.is_detail_grain
  and f.geographic_level = 'Regional'
group by 1, 2, 3, 4, 5, 6
