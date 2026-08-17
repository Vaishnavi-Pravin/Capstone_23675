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

        -------------------------------------------------
        -- Supplier Details
        -------------------------------------------------

        supplier_name,

        supplier_type,

        -------------------------------------------------
        -- Contact Information
        -- Silver stores these as separate fields
        -------------------------------------------------

        contact_person,

        email,

        phone_number,

        address,

        -------------------------------------------------
        -- Payment Terms
        -------------------------------------------------

        payment_terms,

        on_time_delivery_rate
    FROM src

    WHERE supplier_id IS NOT NULL

      AND TRIM(supplier_id) <> ''

)

SELECT *

FROM final