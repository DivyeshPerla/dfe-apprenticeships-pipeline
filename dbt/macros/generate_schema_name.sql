{#
  Default dbt behaviour is <profile_dataset>_<custom_schema>, which would give
  silver_silver / gold_gold and create datasets outside Terraform's control.
  The medallion datasets are provisioned by Terraform, so use the custom schema
  verbatim and fall back to the profile target only when none is set.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
