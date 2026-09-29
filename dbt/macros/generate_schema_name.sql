-- Usa el schema personalizado tal cual (+schema: gold → GOLD).
-- Sin este macro, dbt lo concatena con el schema del perfil (SILVER) y crearía SILVER_GOLD.
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
