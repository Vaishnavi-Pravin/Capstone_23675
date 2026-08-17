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
        /* Surrogate Key */
       {{ dbt_utils.generate_surrogate_key(['customer_id']) }} AS customer_key,
 
        /* Natural Key */
        customer_id,



        first_name,

        last_name,

        full_name,



        email,

        is_valid_email,

        phone_number,

        is_valid_phone,



        birth_date,

        registration_date,

        last_purchase_date,



        age,

        customer_segment,



        street,

        city,

        state,

        country,

        zip_code,

        full_address,



        occupation,

        income_bracket,

        loyalty_tier,

        preferred_communication,

        preferred_payment_method,

        marketing_opt_in,



        total_purchases,

        total_spend

    FROM src

    WHERE customer_id IS NOT NULL

      AND TRIM(customer_id) <> ''

)

SELECT *

FROM final