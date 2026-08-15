{% snapshot snapshot_inventory %}

{{
    config(
        target_schema='SILVER',
        unique_key='product_id',
        strategy='timestamp',
        updated_at='last_modified_date',
        invalidate_hard_deletes=True
    )
}}

WITH product_inventory AS (

    SELECT

        -------------------------------------------------
        -- Product Key
        -------------------------------------------------

        TRIM(
            product_id
        ) AS product_id,

        -------------------------------------------------
        -- Inventory Attributes
        -------------------------------------------------

        TRY_TO_NUMBER(
            raw_data:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            raw_data:reorder_level::STRING
        ) AS reorder_level,

        -------------------------------------------------
        -- Product Information
        -------------------------------------------------

        INITCAP(
            TRIM(raw_data:name::STRING)
        ) AS product_name,

        INITCAP(
            TRIM(raw_data:category::STRING)
        ) AS category,

        INITCAP(
            TRIM(raw_data:subcategory::STRING)
        ) AS subcategory,

        INITCAP(
            TRIM(raw_data:product_line::STRING)
        ) AS product_line,

        -------------------------------------------------
        -- Source Last Modified
        -------------------------------------------------

        TRY_TO_DATE(
            TRIM(raw_data:last_modified_date::STRING),
            'YYYY-MM-DD'
        ) AS last_modified_date,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        LOADED_AT,
        SOURCE_FILE,
        BATCH_ID

    FROM {{ ref('snapshot_product') }}

    WHERE dbt_valid_to IS NULL

)

SELECT *

FROM product_inventory

WHERE product_id IS NOT NULL
  AND TRIM(product_id) <> ''

QUALIFY ROW_NUMBER() OVER (

    PARTITION BY product_id

    ORDER BY
        last_modified_date DESC NULLS LAST,
        LOADED_AT DESC

) = 1

{% endsnapshot %}