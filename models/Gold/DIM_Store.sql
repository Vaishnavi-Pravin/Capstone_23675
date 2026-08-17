{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *

    FROM {{ ref('silver_store') }}

),

final AS (

    SELECT

        /* Surrogate Key */
       {{ dbt_utils.generate_surrogate_key(['store_id']) }} AS store_key,
 
        /* Natural Key */
        store_id,



        store_name,

        store_type,

        region,



        full_address,



        opening_date,



        store_size_category

    FROM src

    WHERE store_id IS NOT NULL

      AND TRIM(store_id) <> ''

)

SELECT *

FROM final