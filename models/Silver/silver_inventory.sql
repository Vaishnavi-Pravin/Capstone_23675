{{ config(materialized='table', schema ='SILVER') }}

WITH product_snapshots AS (

    SELECT

        product_id,

        product_name,

        category,

        subcategory,

        product_line,

        stock_quantity,

        reorder_level,

        last_modified_date,

        dbt_valid_from,

        dbt_valid_to,

        loaded_at,

        source_file,

        batch_id,

        -------------------------------------------------
        -- The actual inventory snapshot date is the
        -- date on which this version became valid.
        -------------------------------------------------

        CAST(
            dbt_valid_from AS DATE
        ) AS snapshot_date

    FROM {{ ref('snapshot_inventory') }}

),

/* =====================================================
   STEP 1
   Get the previous product snapshot
   ===================================================== */

product_snapshot_history AS (

    SELECT

        *,

        LAG(stock_quantity) OVER (

            PARTITION BY product_id

            ORDER BY snapshot_date

        ) AS previous_stock_quantity,

        LAG(snapshot_date) OVER (

            PARTITION BY product_id

            ORDER BY snapshot_date

        ) AS previous_snapshot_date

    FROM product_snapshots

),

/* =====================================================
   STEP 2
   Create a daily date spine

   This allows stock to be carried forward when there
   is no product snapshot on a particular day.
   ===================================================== */

date_bounds AS (

    SELECT

        MIN(snapshot_date) AS min_date,

        MAX(snapshot_date) AS max_date

    FROM product_snapshots

),

date_spine AS (

    SELECT

        DATEADD(
            DAY,
            SEQ4(),
            min_date
        ) AS inventory_date

    FROM date_bounds,

         TABLE(
             GENERATOR(
                 ROWCOUNT => 10000
             )
         )

    WHERE DATEADD(
        DAY,
        SEQ4(),
        min_date
    ) <= max_date

),

/* =====================================================
   STEP 3
   Get all products
   ===================================================== */

products AS (

    SELECT DISTINCT

        product_id

    FROM product_snapshots

),

/* =====================================================
   STEP 4
   Product × Date spine
   ===================================================== */

product_dates AS (

    SELECT

        p.product_id,

        d.inventory_date

    FROM products p

    CROSS JOIN date_spine d

),

/* =====================================================
   STEP 5
   Match actual product snapshots to dates
   ===================================================== */

daily_snapshot_matches AS (

    SELECT

        pd.product_id,

        pd.inventory_date,

        ps.product_name,

        ps.category,

        ps.subcategory,

        ps.product_line,

        ps.stock_quantity AS snapshot_stock_quantity,

        ps.reorder_level,

        ps.snapshot_date AS source_snapshot_date,

        ps.dbt_valid_from,

        ps.dbt_valid_to,

        ps.loaded_at,

        ps.source_file,

        ps.batch_id

    FROM product_dates pd

    LEFT JOIN product_snapshots ps

        ON pd.product_id = ps.product_id

       AND pd.inventory_date = ps.snapshot_date

),

/* =====================================================
   STEP 6
   Carry forward the latest known stock position.

   If there is no snapshot on a day, use the most
   recent available snapshot.
   ===================================================== */

carried_forward AS (

    SELECT

        *,

        LAST_VALUE(
            snapshot_stock_quantity
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS ending_stock,

        LAST_VALUE(
            reorder_level
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS current_reorder_level,

        LAST_VALUE(
            product_name
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS current_product_name,

        LAST_VALUE(
            category
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS current_category,

        LAST_VALUE(
            subcategory
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS current_subcategory,

        LAST_VALUE(
            product_line
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS current_product_line,

        LAST_VALUE(
            source_snapshot_date
        ) IGNORE NULLS OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

            ROWS BETWEEN UNBOUNDED PRECEDING
                 AND CURRENT ROW

        ) AS latest_snapshot_date

    FROM daily_snapshot_matches

),

/* =====================================================
   STEP 7
   Flatten completed order items

   Only COMPLETED orders contribute to sold quantity.
   ===================================================== */

completed_order_items AS (

    SELECT

        TRIM(
            o.raw_data:order_id::STRING
        ) AS order_id,

        TRIM(
            item.value:product_id::STRING
        ) AS product_id,

        TRY_TO_NUMBER(
            item.value:quantity::STRING
        ) AS quantity,

        TRY_TO_DATE(
            TRIM(
                o.raw_data:order_date::STRING
            )
        ) AS order_date

    FROM {{ ref('snapshot_orders') }} o,

         LATERAL FLATTEN(
             INPUT => o.raw_data:order_items
         ) item

    WHERE o.dbt_valid_to IS NULL

      AND UPPER(
          TRIM(
              o.raw_data:order_status::STRING
          )
      ) = 'COMPLETED'

      AND item.value:product_id IS NOT NULL

),

/* =====================================================
   STEP 8
   Aggregate sold quantity by product and day
   ===================================================== */

daily_sales AS (

    SELECT

        product_id,

        order_date AS inventory_date,

        SUM(
            quantity
        ) AS sold_quantity

    FROM completed_order_items

    GROUP BY

        product_id,

        order_date

),

/* =====================================================
   STEP 9
   Attach sales to inventory dates
   ===================================================== */

inventory_with_sales AS (

    SELECT

        cf.product_id,

        cf.inventory_date,

        cf.current_product_name AS product_name,

        cf.current_category AS category,

        cf.current_subcategory AS subcategory,

        cf.current_product_line AS product_line,

        cf.ending_stock,

        cf.current_reorder_level AS reorder_level,

        cf.latest_snapshot_date,

        COALESCE(
            ds.sold_quantity,
            0
        ) AS sold_quantity,

        cf.loaded_at,

        cf.source_file,

        cf.batch_id,

        cf.dbt_valid_from,

        cf.dbt_valid_to

    FROM carried_forward cf

    LEFT JOIN daily_sales ds

        ON cf.product_id = ds.product_id

       AND cf.inventory_date = ds.inventory_date

),

/* =====================================================
   STEP 10
   Calculate beginning stock.

   Beginning stock = prior day's ending stock.
   ===================================================== */

with_beginning_stock AS (

    SELECT

        *,

        LAG(
            ending_stock
        ) OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

        ) AS beginning_stock,

        LAG(
            inventory_date
        ) OVER (

            PARTITION BY product_id

            ORDER BY inventory_date

        ) AS previous_inventory_date

    FROM inventory_with_sales

),

/* =====================================================
   STEP 11
   Calculate inferred purchased quantity.

   Requirement:
   purchased_quantity =
       ending_stock
       - beginning_stock
       + sold_quantity

   This is inferred because receiving events do not
   exist in the source.
   ===================================================== */

with_purchases AS (

    SELECT

        *,

        CASE

            WHEN beginning_stock IS NOT NULL
             AND ending_stock IS NOT NULL

            THEN
                ending_stock
                - beginning_stock
                + sold_quantity

            ELSE NULL

        END AS purchased_quantity

    FROM with_beginning_stock

),

/* =====================================================
   STEP 12
   Detect snapshot gaps.

   > 12 days = stale / explicit carry-forward.
   ===================================================== */

with_gap_flag AS (

    SELECT

        *,

        DATEDIFF(
            DAY,
            latest_snapshot_date,
            inventory_date
        ) AS snapshot_age_days,

        CASE

            WHEN latest_snapshot_date IS NULL
                THEN 'No Snapshot'

            WHEN DATEDIFF(
                DAY,
                latest_snapshot_date,
                inventory_date
            ) > 12

                THEN 'Stale - Carry Forward'

            ELSE 'Current'

        END AS snapshot_status

    FROM with_purchases

),

/* =====================================================
   STEP 13
   Validate numeric balances and stock positions.
   ===================================================== */

final AS (

    SELECT

        product_id,

        product_name,

        category,

        subcategory,

        product_line,

        inventory_date,

        CAST(
            beginning_stock AS NUMBER(18,0)
        ) AS beginning_stock,

        CAST(
            ending_stock AS NUMBER(18,0)
        ) AS ending_stock,

        CAST(
            sold_quantity AS NUMBER(18,0)
        ) AS sold_quantity,

        CAST(
            purchased_quantity AS NUMBER(18,0)
        ) AS purchased_quantity,

        CAST(
            reorder_level AS NUMBER(18,0)
        ) AS reorder_level,

        -------------------------------------------------
        -- Low Stock Flag
        -------------------------------------------------

        CASE

            WHEN ending_stock IS NOT NULL
             AND reorder_level IS NOT NULL
             AND ending_stock < reorder_level

            THEN TRUE

            ELSE FALSE

        END AS low_stock_flag,

        -------------------------------------------------
        -- Negative Balance Validation
        -------------------------------------------------

        CASE

            WHEN beginning_stock < 0
                THEN TRUE

            WHEN ending_stock < 0
                THEN TRUE

            WHEN sold_quantity < 0
                THEN TRUE

            WHEN purchased_quantity < 0
                THEN TRUE

            ELSE FALSE

        END AS has_negative_balance,

        -------------------------------------------------
        -- Numeric Validation
        -------------------------------------------------

        CASE

            WHEN beginning_stock IS NULL
             AND inventory_date >
                 latest_snapshot_date

                THEN 'CARRY_FORWARD'

            WHEN beginning_stock IS NOT NULL
             AND ending_stock IS NOT NULL
             AND sold_quantity IS NOT NULL
             AND purchased_quantity IS NOT NULL

                THEN 'VALID'

            ELSE 'CHECK'

        END AS inventory_validation_status,

        -------------------------------------------------
        -- Snapshot Gap
        -------------------------------------------------

        snapshot_age_days,

        snapshot_status,

        latest_snapshot_date,

        -------------------------------------------------
        -- Metadata
        -------------------------------------------------

        loaded_at,

        source_file,

        batch_id,

        dbt_valid_from,

        dbt_valid_to

    FROM with_gap_flag

)

SELECT *

FROM final