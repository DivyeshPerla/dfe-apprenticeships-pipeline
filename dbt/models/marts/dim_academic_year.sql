{{ config(materialized='table') }}

/* Academic year dimension. 2025/26 is part-year (first three quarters) and
   will be revised, so it is flagged rather than silently mixed with final
   years. */

with years as (
    select distinct
        academic_year_start,
        academic_year_end,
        academic_year_label,
        is_provisional
    from {{ ref('stg_apprenticeships') }}
)

select
    academic_year_start as academic_year_key,
    academic_year_start,
    academic_year_end,
    academic_year_label,
    is_provisional,
    academic_year_start = (select max(academic_year_start) from years) as is_latest_year
from years
