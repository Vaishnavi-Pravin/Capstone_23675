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

        -------------------------------------------------
        -- Surrogate Key
        -------------------------------------------------

        ROW_NUMBER() OVER (
            ORDER BY supplier_id
        ) AS supplier_key,

        -------------------------------------------------
        -- Natural Key
        -------------------------------------------------

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

        payment_terms

    FROM src

    WHERE supplier_id IS NOT NULL

      AND TRIM(supplier_id) <> ''

)

SELECT *

FROM final