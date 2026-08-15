{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH src AS (

    SELECT *

    FROM {{ ref('silver_product') }}

),

final AS (

    SELECT

        -------------------------------------------------
        -- Surrogate Key
        -------------------------------------------------

        ROW_NUMBER() OVER (
            ORDER BY product_id
        ) AS product_key,

        -------------------------------------------------
        -- Natural Key
        -------------------------------------------------

        product_id,

        -------------------------------------------------
        -- Product Details
        -------------------------------------------------

        product_name,

        brand,

        category,

        subcategory,

        product_line,

        color,

        size,

        dimensions,

        weight,

        warranty_period,

        -------------------------------------------------
        -- Supplier
        -------------------------------------------------

        supplier_id,

        -------------------------------------------------
        -- Product Description
        -------------------------------------------------

        short_description,

        technical_specs,

        full_description,

        -------------------------------------------------
        -- Pricing
        -------------------------------------------------

        unit_price,

        cost_price,

        profit_margin_percentage,

        -------------------------------------------------
        -- Inventory
        -------------------------------------------------

        stock_quantity,

        reorder_level,

        low_stock_flag,

        -------------------------------------------------
        -- Dates
        -------------------------------------------------

        launch_date,

        last_modified_date,

        -------------------------------------------------
        -- Product Flag
        -------------------------------------------------

        is_featured,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src

    WHERE product_id IS NOT NULL

      AND TRIM(product_id) <> ''

)

SELECT *

FROM final