{{ config(
    materialized='table',
    schema='SILVER'
) }}

WITH products_flattened AS (

    SELECT

        /* =================================================
           Product
           ================================================= */

        UPPER(
            TRIM(product.value:product_id::STRING)
        ) AS product_id,

        TRY_TO_NUMBER(
            product.value:stock_quantity::STRING
        ) AS stock_quantity,

        TRY_TO_NUMBER(
            product.value:reorder_level::STRING
        ) AS reorder_level,

        /* =================================================
           Inventory Snapshot Date

           Extracted from source file name.
           Example:
           inventory_2025-01-15.csv
           ================================================= */

        TRY_TO_DATE(
            REGEXP_SUBSTR(
                SOURCE_FILE,
                '[0-9]{4}-[0-9]{2}-[0-9]{2}'
            )
        ) AS inventory_snapshot_date,

        /* =================================================
           Metadata
           ================================================= */

        SOURCE_FILE,
        ROW_NUMBER,
        LOADED_AT,
        BATCH_ID

    FROM {{ ref('bronze_product') }},

         LATERAL FLATTEN(
             INPUT => RAW_DATA:products_data
         ) product

),


/* =========================================================
   DEDUPLICATION

   One product per inventory snapshot date.
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
            LOADED_AT DESC,
            SOURCE_FILE DESC,
            ROW_NUMBER DESC

    ) = 1

),


/* =========================================================
   STOCK HISTORY

   Calculate previous inventory snapshot and beginning
   inventory using LAG.
   ========================================================= */

stock_history AS (

    SELECT

        product_id,

        inventory_snapshot_date,

        reorder_level,

        stock_quantity AS ending_inventory,

        LAG(
            inventory_snapshot_date
        ) OVER (
            PARTITION BY product_id
            ORDER BY inventory_snapshot_date
        ) AS inventory_previous_snapshot_date,

        LAG(
            stock_quantity
        ) OVER (
            PARTITION BY product_id
            ORDER BY inventory_snapshot_date
        ) AS beginning_inventory,

        SOURCE_FILE,
        ROW_NUMBER,
        LOADED_AT,
        BATCH_ID

    FROM deduped

),


/* =========================================================
   INVENTORY SNAPSHOT METRICS
   ========================================================= */

stock_with_lag AS (

    SELECT

        product_id,

        inventory_snapshot_date,

        inventory_previous_snapshot_date,

        beginning_inventory,

        ending_inventory,

        reorder_level,

        DATEDIFF(
            DAY,
            inventory_previous_snapshot_date,
            inventory_snapshot_date
        ) AS inventory_days_since_last_snapshot,

        SOURCE_FILE,
        ROW_NUMBER,
        LOADED_AT,
        BATCH_ID

    FROM stock_history

),


/* =========================================================
   COMPLETED SALES

   Daily product-level completed sales.

   Orders are used because they contain actual sales
   quantities and dates.
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
   JOIN INVENTORY TO SALES

   Sales are calculated for the complete period:

       previous snapshot < sale date <= current snapshot

   This avoids losing sales that occurred between two
   inventory snapshots.
   ========================================================= */

joined AS (

    SELECT

        s.product_id,

        s.inventory_snapshot_date,

        s.inventory_previous_snapshot_date,

        s.beginning_inventory,

        s.ending_inventory,

        s.reorder_level,

        s.inventory_days_since_last_snapshot,

        s.SOURCE_FILE,

        s.ROW_NUMBER,

        s.LOADED_AT,

        s.BATCH_ID,

        SUM(
            COALESCE(
                sq.sold_quantity,
                0
            )
        ) AS inventory_sold_quantity

    FROM stock_with_lag s

    LEFT JOIN sold_quantities sq

        ON s.product_id = sq.product_id

       AND (
            s.inventory_previous_snapshot_date IS NULL
            OR sq.sold_date >
               s.inventory_previous_snapshot_date
       )

       AND sq.sold_date <=
           s.inventory_snapshot_date

    GROUP BY

        s.product_id,

        s.inventory_snapshot_date,

        s.inventory_previous_snapshot_date,

        s.beginning_inventory,

        s.ending_inventory,

        s.reorder_level,

        s.inventory_days_since_last_snapshot,

        s.SOURCE_FILE,

        s.ROW_NUMBER,

        s.LOADED_AT,

        s.BATCH_ID

)


/* =========================================================
   FINAL SILVER INVENTORY
   ========================================================= */

SELECT

    /* =====================================================
       Keys / Dates
       ===================================================== */

    product_id,

    inventory_snapshot_date,

    inventory_previous_snapshot_date,


    /* =====================================================
       Inventory Balances
       ===================================================== */

    beginning_inventory,

    ending_inventory,

    inventory_sold_quantity,


    /* =====================================================
       Purchased Quantity

       Formula:

       Ending Inventory
       - Beginning Inventory
       + Sold Quantity

       This represents inventory purchased during the
       snapshot interval.
       ===================================================== */

    (
        ending_inventory
        - COALESCE(
            beginning_inventory,
            ending_inventory
          )
        + inventory_sold_quantity
    ) AS inventory_purchased_quantity,


    /* =====================================================
       Low Stock
       ===================================================== */

    CASE

        WHEN ending_inventory IS NOT NULL

         AND reorder_level IS NOT NULL

         AND ending_inventory < reorder_level

        THEN TRUE

        ELSE FALSE

    END AS inventory_low_stock_flag,


    /* =====================================================
       Stale Snapshot
       ===================================================== */

    CASE

        WHEN inventory_days_since_last_snapshot > 1

        THEN TRUE

        ELSE FALSE

    END AS inventory_stale_snapshot_flag,


    /* =====================================================
       Snapshot Interval
       ===================================================== */

    inventory_days_since_last_snapshot,


    /* =====================================================
       Negative Inventory Flag
       ===================================================== */

    CASE

        WHEN ending_inventory < 0

          OR beginning_inventory < 0

        THEN TRUE

        ELSE FALSE

    END AS inventory_negative_balance_flag,


    /* =====================================================
       Reorder Level
       ===================================================== */

    reorder_level AS inventory_reorder_level,


    /* =====================================================
       Metadata
       ===================================================== */

    SOURCE_FILE,

    ROW_NUMBER,

    LOADED_AT,

    BATCH_ID

FROM joined

WHERE beginning_inventory IS NOT NULL