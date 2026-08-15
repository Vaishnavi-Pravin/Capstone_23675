{{ config(materialized='table', schema ='SILVER') }}

WITH src_product AS (

    SELECT *

    FROM {{ ref('snapshot_product') }}

    WHERE dbt_valid_to IS NULL

),

cleaned AS (

    SELECT

        -------------------------------------------------
        -- Keys
        -------------------------------------------------

        product_id,

        -------------------------------------------------
        -- Product Details
        --
        -- Pascal Case normalization
        -------------------------------------------------

        INITCAP(
            TRIM(raw_data:name::STRING)
        ) AS product_name,

        INITCAP(
            TRIM(raw_data:brand::STRING)
        ) AS brand,

        INITCAP(
            TRIM(raw_data:category::STRING)
        ) AS category,

        INITCAP(
            TRIM(raw_data:subcategory::STRING)
        ) AS subcategory,

        INITCAP(
            TRIM(raw_data:product_line::STRING)
        ) AS product_line,

        INITCAP(
            TRIM(raw_data:color::STRING)
        ) AS color,

        INITCAP(
            TRIM(raw_data:size::STRING)
        ) AS size,

        TRIM(
            raw_data:dimensions::STRING
        ) AS dimensions,

        TRIM(
            raw_data:weight::STRING
        ) AS weight,

        TRIM(
            raw_data:warranty_period::STRING
        ) AS warranty_period,

        TRIM(
            raw_data:supplier_id::STRING
        ) AS supplier_id,

        -------------------------------------------------
        -- Description
        -------------------------------------------------

        TRIM(
            raw_data:short_description::STRING
        ) AS short_description,

        TRIM(
            raw_data:technical_specs::STRING
        ) AS technical_specs,

        -------------------------------------------------
        -- Full Product Description
        --
        -- Requirement:
        -- name | short_description | technical_specs
        -------------------------------------------------

        CONCAT_WS(
            ' | ',

            NULLIF(
                INITCAP(
                    TRIM(raw_data:name::STRING)
                ),
                ''
            ),

            NULLIF(
                TRIM(
                    raw_data:short_description::STRING
                ),
                ''
            ),

            NULLIF(
                TRIM(
                    raw_data:technical_specs::STRING
                ),
                ''
            )

        ) AS full_description,

        -------------------------------------------------
        -- Prices
        -------------------------------------------------

        TRY_TO_DECIMAL(
            raw_data:unit_price::STRING,
            18,
            2
        ) AS unit_price,

        TRY_TO_DECIMAL(
            raw_data:cost_price::STRING,
            18,
            2
        ) AS cost_price,

        -------------------------------------------------
        -- Inventory
        -------------------------------------------------

        TRY_TO_NUMBER(
            raw_data:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            raw_data:reorder_level::STRING
        ) AS reorder_level,

        -------------------------------------------------
        -- Dates
        -------------------------------------------------

        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:launch_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:launch_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:launch_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS launch_date,

        COALESCE(

            TRY_TO_DATE(
                TRIM(raw_data:last_modified_date::STRING),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:last_modified_date::STRING),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(raw_data:last_modified_date::STRING),
                'MM/DD/YYYY'
            )

        ) AS last_modified_date,

        -------------------------------------------------
        -- Flags
        -------------------------------------------------

        raw_data:is_featured::BOOLEAN AS is_featured,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM src_product

),

final AS (

    SELECT

        *,

        -------------------------------------------------
        -- Category Hierarchy
        --
        -- category > subcategory > product_line
        -------------------------------------------------

        CONCAT_WS(
            ' > ',

            NULLIF(category, ''),
            NULLIF(subcategory, ''),
            NULLIF(product_line, '')

        ) AS category_hierarchy,

        -------------------------------------------------
        -- Profit Margin Percentage
        --
        -- Formula:
        -- ((unit_price - cost_price) / unit_price) * 100
        --
        -- Guard against zero/null unit price
        -------------------------------------------------

        CASE

            WHEN unit_price IS NOT NULL
             AND unit_price > 0
             AND cost_price IS NOT NULL

            THEN ROUND(
                (
                    (unit_price - cost_price)
                    / unit_price
                ) * 100,
                2
            )

            ELSE NULL

        END AS profit_margin_percentage,

        -------------------------------------------------
        -- Low Stock Flag
        --
        -- Requirement:
        -- stock_quantity < reorder_level
        -------------------------------------------------

        CASE

            WHEN stock_quantity IS NOT NULL
             AND reorder_level IS NOT NULL
             AND stock_quantity < reorder_level

            THEN TRUE

            ELSE FALSE

        END AS low_stock_flag

    FROM cleaned

)

SELECT *

FROM final