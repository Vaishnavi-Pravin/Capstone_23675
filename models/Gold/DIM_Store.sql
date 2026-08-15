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

        -------------------------------------------------
        -- Surrogate Key
        -------------------------------------------------

        ROW_NUMBER() OVER (
            ORDER BY store_id
        ) AS store_key,

        -------------------------------------------------
        -- Natural Key
        -------------------------------------------------

        store_id,

        -------------------------------------------------
        -- Store Details
        -------------------------------------------------

        store_name,

        store_type,

        region,

        -------------------------------------------------
        -- Address
        -------------------------------------------------

        full_address,

        -------------------------------------------------
        -- Store Dates
        -------------------------------------------------

        opening_date,

        -------------------------------------------------
        -- Store Size
        -------------------------------------------------

        store_size_category

    FROM src

    WHERE store_id IS NOT NULL

      AND TRIM(store_id) <> ''

)

SELECT *

FROM final