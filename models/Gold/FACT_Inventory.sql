{{ config(
    materialized='table',
    schema='GOLD'
) }}

/* =========================================================
   FACT_INVENTORY

   GRAIN:
   One row per PRODUCT + STORE + INVENTORY SNAPSHOT DATE.

   SOURCE:
   silver_inventory

   DIMENSIONS:
   - dim_product
   - dim_store
   - dim_supplier
   - dim_date
   ========================================================= */


WITH inventory AS (

    SELECT *

    FROM {{ ref('silver_inventory') }}

),


/* =========================================================
   ACTIVE STORES
   ========================================================= */

active_stores AS (

    SELECT

        CAST(
            store_key AS VARCHAR
        ) AS store_key,

        TRIM(
            store_id
        ) AS store_id

    FROM {{ ref('DIM_Store') }}

    WHERE store_id IS NOT NULL

      AND TRIM(store_id) <> ''

),


/* =========================================================
   PRODUCT × STORE INVENTORY GRAIN
   ========================================================= */

inventory_by_store AS (

    SELECT

        i.*,

        s.store_id,

        s.store_key

    FROM inventory i

    CROSS JOIN active_stores s

),


/* =========================================================
   DAILY COMPLETED SALES BY PRODUCT AND STORE
   ========================================================= */

sold_by_store_daily AS (

    SELECT

        UPPER(
            TRIM(
                item.value:product_id::STRING
            )
        ) AS product_id,

        UPPER(
            TRIM(
                ord.raw_data:store_id::STRING
            )
        ) AS store_id,

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

      AND ord.raw_data:store_id IS NOT NULL

      AND TRY_TO_NUMBER(
            item.value:quantity::STRING
          ) IS NOT NULL

    GROUP BY
        1,
        2,
        3

),


/* =========================================================
   SALES BETWEEN INVENTORY SNAPSHOTS
   ========================================================= */

sold_by_store AS (

    SELECT

        ibs.product_id,

        ibs.store_id,

        ibs.inventory_snapshot_date,

        SUM(
            COALESCE(
                sbd.sold_quantity,
                0
            )
        ) AS sold_quantity

    FROM inventory_by_store ibs

    LEFT JOIN sold_by_store_daily sbd

        ON UPPER(
            TRIM(
                ibs.product_id
            )
        ) = sbd.product_id

       AND UPPER(
            TRIM(
                ibs.store_id
            )
        ) = sbd.store_id

       AND (
            ibs.inventory_previous_snapshot_date IS NULL
            OR sbd.sold_date >
               ibs.inventory_previous_snapshot_date
       )

       AND sbd.sold_date <=
           ibs.inventory_snapshot_date

    GROUP BY

        ibs.product_id,

        ibs.store_id,

        ibs.inventory_snapshot_date

),


/* =========================================================
   TOTAL PURCHASED QUANTITY BY SNAPSHOT DATE
   ========================================================= */

daily_total_purchased AS (

    SELECT

        inventory_snapshot_date,

        SUM(
            GREATEST(
                COALESCE(
                    inventory_purchased_quantity,
                    0
                ),
                0
            )
        ) AS total_purchased_all_products

    FROM inventory

    GROUP BY
        inventory_snapshot_date

),


/* =========================================================
   PURCHASED QUANTITY BY SUPPLIER AND SNAPSHOT DATE
   ========================================================= */

daily_supplier_purchased AS (

    SELECT

        i.inventory_snapshot_date,

        dp.supplier_id,

        SUM(
            GREATEST(
                COALESCE(
                    i.inventory_purchased_quantity,
                    0
                ),
                0
            )
        ) AS supplier_purchased_quantity

    FROM inventory i

    LEFT JOIN {{ ref('DIM_Product') }} dp

        ON UPPER(
            TRIM(
                i.product_id
            )
        ) = UPPER(
            TRIM(
                dp.product_id
            )
        )

    GROUP BY

        i.inventory_snapshot_date,

        dp.supplier_id

),


/* =========================================================
   JOIN ALL DIMENSIONS
   ========================================================= */

joined AS (

    SELECT

        /* =================================================
           Natural Keys
           ================================================= */

        ibs.product_id,

        ibs.store_id,

        ibs.inventory_snapshot_date,


        /* =================================================
           PRODUCT DIMENSION
           ================================================= */

        CAST(
            dp.product_key AS VARCHAR
        ) AS product_key,


        /* =================================================
           DATE DIMENSION
           ================================================= */

        CAST(
            dd.date_key AS VARCHAR
        ) AS date_key,


        /* =================================================
           STORE DIMENSION
           ================================================= */

        CAST(
            ibs.store_key AS VARCHAR
        ) AS store_key,


        /* =================================================
           SUPPLIER DIMENSION
           ================================================= */

        CAST(
            ds.supplier_key AS VARCHAR
        ) AS supplier_key,


        /* =================================================
           SUPPLIER NATURAL KEY
           ================================================= */

        dp.supplier_id,


        /* =================================================
           INVENTORY MEASURES

           These names EXACTLY match the CSV.
           ================================================= */

        ibs.beginning_inventory,

        ibs.inventory_purchased_quantity,

        COALESCE(
            sb.sold_quantity,
            ibs.inventory_sold_quantity,
            0
        ) AS inventory_sold_quantity,

        ibs.ending_inventory,


        /* =================================================
           INVENTORY VALUE

           Ending inventory × product cost price
           ================================================= */

        CASE

            WHEN ibs.ending_inventory IS NOT NULL

             AND dp.cost_price IS NOT NULL

            THEN
                ibs.ending_inventory
                * dp.cost_price

            ELSE NULL

        END AS inventory_value

    FROM inventory_by_store ibs


    /* =====================================================
       PRODUCT DIMENSION
       ===================================================== */

    LEFT JOIN {{ ref('DIM_Product') }} dp

        ON UPPER(
            TRIM(
                ibs.product_id
            )
        ) = UPPER(
            TRIM(
                dp.product_id
            )
        )


    /* =====================================================
       DATE DIMENSION
       ===================================================== */

    LEFT JOIN {{ ref('DIM_Date') }} dd

        ON ibs.inventory_snapshot_date =
           dd.full_date


    /* =====================================================
       SUPPLIER DIMENSION
       ===================================================== */

    LEFT JOIN {{ ref('DIM_Supplier') }} ds

        ON UPPER(
            TRIM(
                dp.supplier_id
            )
        ) = UPPER(
            TRIM(
                ds.supplier_id
            )
        )


    /* =====================================================
       STORE-SPECIFIC SALES
       ===================================================== */

    LEFT JOIN sold_by_store sb

        ON UPPER(
            TRIM(
                ibs.product_id
            )
        ) = UPPER(
            TRIM(
                sb.product_id
            )
        )

       AND UPPER(
            TRIM(
                ibs.store_id
            )
        ) = UPPER(
            TRIM(
                sb.store_id
            )
        )

       AND ibs.inventory_snapshot_date =
           sb.inventory_snapshot_date

),


/* =========================================================
   STOCK TURNOVER RATIO
   ========================================================= */

with_ratios AS (

    SELECT

        *,

        CASE

            WHEN (
                COALESCE(
                    beginning_inventory,
                    0
                )
                +
                COALESCE(
                    ending_inventory,
                    0
                )
            ) > 0

            THEN

                inventory_sold_quantity
                /
                (
                    (
                        beginning_inventory
                        +
                        ending_inventory
                    ) / 2.0
                )

            ELSE NULL

        END AS stock_turnover_ratio

    FROM joined

)


/* =========================================================
   FINAL FACT INVENTORY
   ========================================================= */

SELECT

    /* =====================================================
       INVENTORY SURROGATE KEY
       ===================================================== */

    CAST(
        {{ dbt_utils.generate_surrogate_key(
            [
                'wr.product_id',
                'wr.store_id',
                'wr.inventory_snapshot_date'
            ]
        ) }}
        AS VARCHAR
    ) AS inventory_key,


    /* =====================================================
       DIMENSION KEYS
       ===================================================== */

    CAST(
        product_key AS VARCHAR
    ) AS product_key,

    CAST(
        date_key AS VARCHAR
    ) AS date_key,

    CAST(
        store_key AS VARCHAR
    ) AS store_key,

    CAST(
        supplier_key AS VARCHAR
    ) AS supplier_key,


    /* =====================================================
       INVENTORY MEASURES
       ===================================================== */

    beginning_inventory,

    inventory_purchased_quantity,

    inventory_sold_quantity,

    ending_inventory,

    inventory_value,

    stock_turnover_ratio,


    /* =====================================================
       SUPPLIER CONTRIBUTION %
       ===================================================== */

    ROUND(

        CASE

            WHEN dtp.total_purchased_all_products > 0

            THEN

                (
                    COALESCE(
                        dsp.supplier_purchased_quantity,
                        0
                    )
                    /
                    dtp.total_purchased_all_products
                ) * 100

            ELSE NULL

        END,

        2

    ) AS supplier_contribution_percentage


FROM with_ratios wr


/* =========================================================
   TOTAL PURCHASED BY DATE
   ========================================================= */

LEFT JOIN daily_total_purchased dtp

    ON wr.inventory_snapshot_date =
       dtp.inventory_snapshot_date


/* =========================================================
   SUPPLIER PURCHASED BY DATE
   ========================================================= */

LEFT JOIN daily_supplier_purchased dsp

    ON wr.inventory_snapshot_date =
       dsp.inventory_snapshot_date

   AND UPPER(
        TRIM(
            wr.supplier_id
        )
       ) = UPPER(
        TRIM(
            dsp.supplier_id
        )
       )