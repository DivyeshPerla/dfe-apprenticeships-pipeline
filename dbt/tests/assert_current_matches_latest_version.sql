-- The set of is_current records must be exactly the newest published version.
-- If SCD-2 validity intervals are wrong, this drifts immediately.
-- Returns rows on failure.

with current_count as (
    select count(*) as n
    from {{ ref('fct_apprenticeship_headline') }}
    where is_current
),
expected as (
    select total_results as n
    from {{ ref('dataset_versions') }}
    qualify row_number() over (order by version_seq desc) = 1
)
select
    c.n as current_records,
    e.n as expected_records
from current_count c
cross join expected e
where c.n != e.n
