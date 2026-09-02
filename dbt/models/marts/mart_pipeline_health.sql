{{ config(materialized='table') }}

/* Operational view of the warehouse, for monitoring rather than analysis.

   Answers the questions an on-call person actually asks:
     - is the data fresh, or has the pipeline silently stopped?
     - did the last load land the row counts we expect?
     - how much of each measure is withheld, and is that drifting?
     - are we still reconciling to the publisher's own totals?

   Deliberately one row per academic year rather than per run: this source
   publishes quarterly, so a run-level view would be mostly empty. Run history
   lives in Cloud Monitoring, which is the right tool for it. */

with fact as (

    select * from {{ ref('fct_apprenticeship_headline') }} where is_current

),

per_year as (

    select
        academic_year_start,
        academic_year_label,
        is_provisional,

        count(*)                                              as fact_rows,
        countif(is_detail_grain)                              as detail_rows,

        -- Volume: a sudden move here is the clearest sign of a bad load.
        sum(if(is_detail_grain and geographic_level = 'National', start_count, 0)) as national_starts,

        -- Completeness: the share of cells the publisher withheld. Drift here
        -- changes what the totals mean, even when nothing technically breaks.
        safe_divide(
            countif(start_count_status != 'published'),
            count(*)
        )                                                     as suppression_rate,

        -- Integrity: any unrecognised marker means the source introduced a
        -- code we have never seen. Should always be zero.
        countif(start_count_status = 'unrecognised')          as unrecognised_markers

    from fact
    group by 1, 2, 3

),

reconciliation as (

    -- The business-logic check, carried as a metric rather than only as a test,
    -- so a dashboard can show the margin rather than just pass/fail.
    select
        d.academic_year_start,
        d.detail_starts,
        p.published_starts,
        safe_divide(abs(d.detail_starts - p.published_starts), p.published_starts) as reconciliation_error
    from (
        select academic_year_start, sum(start_count) as detail_starts
        from fact
        where geographic_level = 'National' and is_detail_grain
        group by 1
    ) d
    left join (
        select academic_year_start, start_count as published_starts
        from fact
        where geographic_level = 'National' and aggregation_depth = 5
          and start_count is not null
    ) p using (academic_year_start)

),

lineage as (

    select
        max(ingested_date)   as last_ingested_date,
        max(dataset_version) as latest_version_loaded
    from {{ ref('stg_apprenticeships') }}

)

select
    y.*,
    r.detail_starts,
    r.published_starts,
    r.reconciliation_error,

    l.last_ingested_date,
    l.latest_version_loaded,
    date_diff(current_date(), l.last_ingested_date, day) as days_since_last_load,

    -- Traffic light for a dashboard tile. Thresholds are deliberate:
    -- 0.1% matches the reconciliation test's tolerance, and 120 days is one
    -- quarter plus a month's grace, because the source publishes quarterly.
    case
        when y.unrecognised_markers > 0                                     then 'critical'
        when r.reconciliation_error > 0.001                                 then 'critical'
        when date_diff(current_date(), l.last_ingested_date, day) > 120     then 'warning'
        when y.suppression_rate > 0.35                                      then 'warning'
        else 'ok'
    end as health_status

from per_year y
left join reconciliation r using (academic_year_start)
cross join lineage l
