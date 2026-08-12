{% macro External_table(
    table_name,
    folder_name,
    database_name='CT_VAISHNAVI_PRAVIN_DB',
    schema_name='EXTERNAL',
    stage_name='CT_VAISHNAVI_PRAVIN_DB.BRONZE.BLOB_STAGE',
    file_format_name='CT_VAISHNAVI_PRAVIN_DB.BRONZE.JSON_FORMAT',
    pattern=none,
    auto_refresh=false
) %}
 
    {% set ddl %}
        create or replace external table {{ database_name }}.{{ schema_name }}.{{ table_name }} 
        (
            raw_data variant as (value)
        )
        location = @{{ stage_name }}/Capstone_Project_Data/{{ folder_name }}/
        {% if pattern is not none %}
        pattern = '{{ pattern }}'
        {% endif %}
        file_format = {{ file_format_name }}
        auto_refresh = {{ auto_refresh }};
    {% endset %}
 
    {% do log("Creating external table " ~ schema_name ~ "." ~ table_name ~ "_ext from " ~ file_path, info=true) %}
    {% do run_query(ddl) %}
 
{% endmacro %}
 