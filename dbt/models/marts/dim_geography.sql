{{ config(materialized='table') }}

/* Conformed geography dimension. ONS codes are the natural key and are stable
   across releases, so they make a better surrogate than a generated id. */

with distinct_geo as (

    select distinct
        geographic_level,
        country_code,
        country_name,
        region_code,
        region_name
    from {{ ref('stg_apprenticeships') }}

)

select
    to_hex(md5(concat(geographic_level, '|', coalesce(region_code, 'NA')))) as geography_key,
    geographic_level,
    country_code,
    country_name,
    region_code,
    region_name,
    coalesce(region_name, country_name) as display_name,
    -- "Outside of England and unknown" is a residual bucket, not a place;
    -- dashboards should be able to exclude it explicitly.
    region_name = 'Outside of England and unknown' as is_residual_bucket
from distinct_geo
