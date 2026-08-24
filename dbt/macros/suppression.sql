{#
  The published extract carries statistical disclosure control markers inside
  the numeric columns. Every measure must therefore be split into two fields:
  a typed value (NULL when withheld) and a status explaining *why* it is NULL.

  Zero-filling a suppressed value would silently understate every aggregate,
  so the value side uses SAFE_CAST and the status side preserves the reason.

  Observed markers (see docs/profiling/PROFILE.md):
    'low' -- value too small to publish without disclosing an individual
    'c'   -- suppressed for confidentiality
    'z'   -- not applicable for this breakdown
#}

{% macro measure_value(column, type='INT64') %}
    SAFE_CAST(NULLIF(TRIM({{ column }}), '') AS {{ type }})
{%- endmacro %}


{% macro measure_status(column) %}
    CASE
        WHEN {{ column }} IS NULL OR TRIM({{ column }}) = '' THEN 'missing'
        WHEN SAFE_CAST(TRIM({{ column }}) AS FLOAT64) IS NOT NULL THEN 'published'
        WHEN LOWER(TRIM({{ column }})) = 'low' THEN 'suppressed_low'
        WHEN LOWER(TRIM({{ column }})) = 'c'   THEN 'suppressed_confidential'
        WHEN LOWER(TRIM({{ column }})) = 'z'   THEN 'not_applicable'
        ELSE 'unrecognised'
    END
{%- endmacro %}


{#
  How many of the five filter dimensions are rolled up to 'Total' on this row.
  0 = true detail grain; 5 = the single published grand-total row.
  Aggregating without filtering on this overstates by ~24x -- see
  sql/analysis/double_counting_proof.sql.
#}
{% macro aggregation_depth() %}
    (
        IF({{ 'apprenticeship_level' }} = 'Total', 1, 0)
      + IF({{ 'age_youth_adult'    }} = 'Total', 1, 0)
      + IF({{ 'age_group'          }} = 'Total', 1, 0)
      + IF({{ 'funding_type'       }} = 'Total', 1, 0)
      + IF({{ 'provider_type'      }} = 'Total', 1, 0)
    )
{%- endmacro %}
