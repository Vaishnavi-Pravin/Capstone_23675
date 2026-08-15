{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH products_flattened AS (

    SELECT

        -------------------------------------------------
        -- Product Key
        -------------------------------------------------

        UPPER(
            TRIM(product.value:product_id::STRING)
        ) AS product_id,


        -------------------------------------------------
        -- Product Details
        -------------------------------------------------

        INITCAP(
            TRIM(product.value:name::STRING)
        ) AS product_name,

        INITCAP(
            TRIM(product.value:brand::STRING)
        ) AS brand,

        INITCAP(
            TRIM(product.value:category::STRING)
        ) AS category,

        INITCAP(
            TRIM(product.value:subcategory::STRING)
        ) AS subcategory,

        INITCAP(
            TRIM(product.value:product_line::STRING)
        ) AS product_line,


        -------------------------------------------------
        -- Inventory Fields
        -------------------------------------------------

        TRY_TO_NUMBER(
            product.value:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            product.value:reorder_level::STRING
        ) AS reorder_level,


        -------------------------------------------------
        -- Product Last Modified Date
        -------------------------------------------------

        COALESCE(

            TRY_TO_DATE(
                TRIM(
                    product.value:last_modified_date::STRING
                ),
                'YYYY-MM-DD'
            ),

            TRY_TO_DATE(
                TRIM(
                    product.value:last_modified_date::STRING
                ),
                'DD-MM-YYYY'
            ),

            TRY_TO_DATE(
                TRIM(
                    product.value:last_modified_date::STRING
                ),
                'MM/DD/YYYY'
            )

        ) AS last_modified_date,


        -------------------------------------------------
        -- Inventory Snapshot Date
        --
        -- Extracted from source file name
        -------------------------------------------------

        TRY_TO_DATE(
            REGEXP_SUBSTR(
                SOURCE_FILE,
                '[0-9]{4}-[0-9]{2}-[0-9]{2}'
            )
        ) AS inventory_snapshot_date,


        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        SOURCE_FILE AS source_file,

        ROW_NUMBER AS row_number,

        LOADED_AT AS loaded_at,

        BATCH_ID AS batch_id


    FROM {{ ref('bronze_product') }},

         LATERAL FLATTEN(
             INPUT => RAW_DATA:products_data
         ) product

),


/* =========================================================
   DEDUPLICATE PRODUCT SNAPSHOTS
   ========================================================= */

deduped AS (

    SELECT *

    FROM products_flattened

    WHERE product_id IS NOT NULL

      AND inventory_snapshot_date IS NOT NULL

    QUALIFY ROW_NUMBER() OVER (

        PARTITION BY
            product_id,
            inventory_snapshot_date

        ORDER BY
            loaded_at DESC,
            source_file DESC,
            row_number DESC

    ) = 1

),


/* =========================================================
   STOCK HISTORY
   ========================================================= */

stock_history AS (

    SELECT

        product_id,

        product_name,

        brand,

        category,

        subcategory,

        product_line,

        inventory_snapshot_date,

        reorder_level,

        stock_quantity AS ending_stock,


        -------------------------------------------------
        -- Previous Snapshot
        -------------------------------------------------

        LAG(
            inventory_snapshot_date
        ) OVER (

            PARTITION BY product_id

            ORDER BY inventory_snapshot_date

        ) AS previous_inventory_snapshot_date,


        -------------------------------------------------
        -- Beginning Stock
        -------------------------------------------------

        LAG(
            stock_quantity
        ) OVER (

            PARTITION BY product_id

            ORDER BY inventory_snapshot_date

        ) AS beginning_stock,


        last_modified_date,

        source_file,

        row_number,

        loaded_at,

        batch_id


    FROM deduped

),


/* =========================================================
   SNAPSHOT CALCULATIONS
   ========================================================= */

stock_with_lag AS (

    SELECT

        product_id,

        product_name,

        brand,

        category,

        subcategory,

        product_line,

        inventory_snapshot_date,

        previous_inventory_snapshot_date,

        beginning_stock,

        ending_stock,

        reorder_level,

        last_modified_date,


        -------------------------------------------------
        -- Days Between Snapshots
        -------------------------------------------------

        DATEDIFF(
            DAY,
            previous_inventory_snapshot_date,
            inventory_snapshot_date
        ) AS days_since_last_snapshot,


        source_file,

        row_number,

        loaded_at,

        batch_id


    FROM stock_history

),


/* =========================================================
   COMPLETED ORDER QUANTITIES
   ========================================================= */

sold_quantities AS (

    SELECT

        UPPER(
            TRIM(
                item.value:product_id::STRING
            )
        ) AS product_id,

        TRY_TO_TIMESTAMP_NTZ(
            ord.raw_data:order_date::STRING
        )::DATE AS sold_date,


        SUM(
            TRY_TO_NUMBER(
                item.value:quantity::STRING
            )
        ) AS sold_quantity


    FROM {{ ref('snapshot_orders') }} ord,

         LATERAL FLATTEN(
             INPUT => ord.raw_data:order_items
         ) item


    WHERE ord.dbt_valid_to IS NULL

      AND UPPER(
            TRIM(
                COALESCE(
                    ord.raw_data:status::STRING,
                    ord.raw_data:order_status::STRING
                )
            )
          ) = 'COMPLETED'

      AND item.value:product_id IS NOT NULL

      AND TRY_TO_NUMBER(
            item.value:quantity::STRING
          ) IS NOT NULL


    GROUP BY
        1,
        2

),


/* =========================================================
   JOIN INVENTORY WITH SALES
   ========================================================= */

joined AS (

    SELECT

        s.product_id,

        s.product_name,

        s.brand,

        s.category,

        s.subcategory,

        s.product_line,

        s.inventory_snapshot_date,

        s.previous_inventory_snapshot_date,

        s.beginning_stock,

        s.ending_stock,

        s.reorder_level,

        s.days_since_last_snapshot,

        s.last_modified_date,

        s.source_file,

        s.row_number,

        s.loaded_at,

        s.batch_id,


        -------------------------------------------------
        -- Sales During Snapshot Interval
        -------------------------------------------------

        SUM(
            COALESCE(
                sq.sold_quantity,
                0
            )
        ) AS sold_quantity


    FROM stock_with_lag s


    LEFT JOIN sold_quantities sq

        ON s.product_id = sq.product_id

       AND sq.sold_date >
           s.previous_inventory_snapshot_date

       AND sq.sold_date <=
           s.inventory_snapshot_date


    GROUP BY

        s.product_id,

        s.product_name,

        s.brand,

        s.category,

        s.subcategory,

        s.product_line,

        s.inventory_snapshot_date,

        s.previous_inventory_snapshot_date,

        s.beginning_stock,

        s.ending_stock,

        s.reorder_level,

        s.days_since_last_snapshot,

        s.last_modified_date,

        s.source_file,

        s.row_number,

        s.loaded_at,

        s.batch_id

)


/* =========================================================
   FINAL SILVER INVENTORY
   ========================================================= */

SELECT

    -------------------------------------------------
    -- Product
    -------------------------------------------------

    product_id,

    product_name,

    brand,

    category,

    subcategory,

    product_line,


    -------------------------------------------------
    -- Inventory Snapshot
    -------------------------------------------------

    inventory_snapshot_date,

    previous_inventory_snapshot_date,

    beginning_stock,

    ending_stock,

    sold_quantity,


    -------------------------------------------------
    -- Purchased Quantity
    -------------------------------------------------

    (
        ending_stock
        - COALESCE(
            beginning_stock,
            ending_stock
          )
        + sold_quantity
    ) AS purchased_quantity,


    -------------------------------------------------
    -- Inventory Flags
    -------------------------------------------------

    CASE

        WHEN ending_stock IS NOT NULL

         AND reorder_level IS NOT NULL

         AND ending_stock < reorder_level

        THEN TRUE

        ELSE FALSE

    END AS low_stock_flag,


    CASE

        WHEN days_since_last_snapshot > 1

        THEN TRUE

        ELSE FALSE

    END AS stale_snapshot_flag,


    days_since_last_snapshot,


    CASE

        WHEN ending_stock < 0

          OR beginning_stock < 0

        THEN TRUE

        ELSE FALSE

    END AS negative_balance_flag,


    reorder_level,


    -------------------------------------------------
    -- Product Metadata
    -------------------------------------------------

    last_modified_date,

    loaded_at,

    source_file,

    row_number,

    batch_id


FROM joined

WHERE beginning_stock IS NOT NULL