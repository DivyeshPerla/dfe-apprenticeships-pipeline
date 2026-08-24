
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  -- Summing detail-grain rows must reproduce the publisher's grand total to
-- within rounding tolerance.
--
-- WHY NOT EXACT: every published figure is rounded to the nearest 10 as part
-- of DfE's statistical disclosure control (verified: 42,045/42,045 published
-- start_count values are multiples of 10, minimum 10). Summing ~122
-- independently-rounded detail values cannot equal an independently-rounded
-- grand total. Expected error is roughly 5*sqrt(n) ~ 55 for n=122; observed
-- differences across the nine years are 0-90.
--
-- The tolerance is set at 0.1% of the published total (~350 on a 350,000
-- base) -- comfortably above rounding noise, but far below the ~24x error a
-- genuine aggregation_depth bug would produce.
--
-- Returns rows on failure.

with detail as (
    select
        academic_year_start,
        sum(start_count) as detail_starts
    from `dfe-apprenticeships-2026`.`gold`.`fct_apprenticeship_headline`
    where is_current
      and geographic_level = 'National'
      and is_detail_grain
    group by academic_year_start
),
published as (
    select
        academic_year_start,
        start_count as published_starts
    from `dfe-apprenticeships-2026`.`gold`.`fct_apprenticeship_headline`
    where is_current
      and geographic_level = 'National'
      and aggregation_depth = 5
      and start_count is not null
)
select
    p.academic_year_start,
    d.detail_starts,
    p.published_starts,
    d.detail_starts - p.published_starts as difference,
    safe_divide(abs(d.detail_starts - p.published_starts), p.published_starts) as rel_error
from published p
join detail d using (academic_year_start)
where safe_divide(abs(d.detail_starts - p.published_starts), p.published_starts) > 0.001
  
  
      
    ) dbt_internal_test