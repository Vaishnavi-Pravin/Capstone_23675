{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *

    FROM {{ ref('silver_supplier') }}

),

final AS (

    SELECT

        /* Surrogate Key */
       {{ dbt_utils.generate_surrogate_key(['supplier_id']) }} AS supplier_key,
 
        /* Natural Key */
        supplier_id,



        supplier_name,

        supplier_type,



        contact_person,

        email,

        phone_number,

        address,



        payment_terms,

        on_time_delivery_rate
    FROM src

    WHERE supplier_id IS NOT NULL

      AND TRIM(supplier_id) <> ''

)

SELECT *

FROM final