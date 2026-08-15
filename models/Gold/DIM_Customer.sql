{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *

    FROM {{ ref('silver_customer') }}

),

final AS (

    SELECT

        -------------------------------------------------
        -- Surrogate Key
        -------------------------------------------------

        ROW_NUMBER() OVER (
            ORDER BY customer_id
        ) AS customer_key,

        -------------------------------------------------
        -- Natural Key
        -------------------------------------------------

        customer_id,

        -------------------------------------------------
        -- Customer Name
        -------------------------------------------------

        first_name,

        last_name,

        full_name,

        -------------------------------------------------
        -- Contact Information
        -------------------------------------------------

        email,

        is_valid_email,

        phone_number,

        is_valid_phone,

        -------------------------------------------------
        -- Customer Dates
        -------------------------------------------------

        birth_date,

        registration_date,

        last_purchase_date,

        -------------------------------------------------
        -- Customer Segmentation
        -------------------------------------------------

        age,

        customer_segment,

        -------------------------------------------------
        -- Address
        -------------------------------------------------

        street,

        city,

        state,

        country,

        zip_code,

        full_address,

        -------------------------------------------------
        -- Customer Attributes
        -------------------------------------------------

        occupation,

        income_bracket,

        loyalty_tier,

        preferred_communication,

        preferred_payment_method,

        marketing_opt_in,

        -------------------------------------------------
        -- Purchase Information
        -------------------------------------------------

        total_purchases,

        total_spend

    FROM src

    WHERE customer_id IS NOT NULL

      AND TRIM(customer_id) <> ''

)

SELECT *

FROM final