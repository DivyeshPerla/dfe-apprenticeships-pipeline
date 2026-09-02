{{ config(materialized='table') }}

/* THE HEADLINE ANALYTICAL FINDING.

   Between 2017/18 and 2025/26 the English apprenticeship market did not shrink
   -- it moved upmarket. Total starts are roughly flat (375,780 -> 353,500 in
   the last full year), but the composition inverted:

       Intermediate  43.0%  ->  17.3%   (-25.7 pts)
       Advanced      44.2%  ->  41.7%   ( -2.5 pts, essentially flat)
       Higher        12.8%  ->  41.0%   (+28.2 pts)

   Advanced holding steady is what makes this clean: the entire shift is
   Intermediate giving way to Higher, not a general drift.

   For a training provider this is the commercially relevant fact in the whole
   dataset -- demand did not fall, it changed level. */

with by_level as (

    select
        academic_year_start,
        academic_year_label,
        is_provisional,
        geographic_level,
        region_name,
        apprenticeship_level,
        sum(start_count) as starts
    from {{ ref('fct_apprenticeship_headline') }}
    where is_current
      and is_detail_grain
      and apprenticeship_level != 'Unknown'
      and start_count is not null
    group by 1, 2, 3, 4, 5, 6

),

with_totals as (

    select
        *,
        sum(starts) over (
            partition by academic_year_start, geographic_level, region_name
        ) as area_year_starts
    from by_level

)

select
    academic_year_start,
    academic_year_label,
    is_provisional,
    geographic_level,
    region_name,
    apprenticeship_level,
    starts,
    area_year_starts,
    safe_divide(starts, area_year_starts) as level_share,

    -- Change in share against the earliest year for the same area and level,
    -- which is what "the market moved" actually means.
    safe_divide(starts, area_year_starts) - first_value(safe_divide(starts, area_year_starts)) over (
        partition by geographic_level, region_name, apprenticeship_level
        order by academic_year_start
        rows between unbounded preceding and unbounded following
    ) as share_change_vs_baseline

from with_totals
