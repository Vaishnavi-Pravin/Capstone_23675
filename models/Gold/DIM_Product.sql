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

        /* Surrogate Key */
       {{ dbt_utils.generate_surrogate_key(['product_id']) }} AS product_key,
 
        /* Natural Key */
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



        supplier_id,



        short_description,

        technical_specs,

        full_description,



        unit_price,

        cost_price,

        profit_margin_percentage,


        stock_quantity,

        reorder_level,

        low_stock_flag,



        launch_date,

        last_modified_date,



        is_featured,



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