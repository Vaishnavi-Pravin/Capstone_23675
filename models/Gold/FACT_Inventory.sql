{{ config(
    materialized='table',
    schema='GOLD'
) }}

/* =========================================================
   FACT_INVENTORY

   GRAIN:
   One row per PRODUCT + STORE + INVENTORY SNAPSHOT DATE
   ONLY when a real completed sale occurred for that
   product/store during the inventory snapshot interval.

   SOURCE:
   silver_inventory

   DIMENSIONS:
   - DIM_Product
   - DIM_Store
   - DIM_Supplier
   - DIM_Date

   IMPORTANT:
   No CROSS JOIN is used.

   Store rows are created only when a real completed sale
   occurred for the product during:

       inventory_previous_snapshot_date
       <
       sold_date
       <=
       inventory_snapshot_date

   Inventory quantities remain product/company-level because
   the source does not contain actual store-level inventory
   quantities.
   ========================================================= */


WITH inventory AS (

    SELECT *

    FROM {{ ref('silver_inventory') }}

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

   IMPORTANT:
   Sales are summed across the complete interval between
   inventory snapshots rather than requiring an exact
   snapshot-date match.

   This prevents missing sales when inventory snapshots
   are several days apart.
   ========================================================= */

sold_by_store AS (

    SELECT

        i.product_id,

        i.inventory_snapshot_date,

        sbd.store_id,

        SUM(
            sbd.sold_quantity
        ) AS sold_quantity

    FROM inventory i

    INNER JOIN sold_by_store_daily sbd

        ON UPPER(
            TRIM(
                i.product_id
            )
        ) = sbd.product_id

       AND (
            i.inventory_previous_snapshot_date IS NULL

            OR

            sbd.sold_date >
            i.inventory_previous_snapshot_date
       )

       AND sbd.sold_date <=
           i.inventory_snapshot_date

    GROUP BY

        i.product_id,

        i.inventory_snapshot_date,

        sbd.store_id

),


/* =========================================================
   INVENTORY + REAL STORE SALES

   Keeps every inventory product-date from silver_inventory.

   If a product had no completed sale during the interval,
   store_id and sold_quantity will be NULL.

   No artificial product × store combinations are created.
   ========================================================= */

joined AS (

    SELECT

        i.product_id,

        i.inventory_snapshot_date,

        sb.store_id,


        /* =================================================
           INVENTORY MEASURES
           ================================================= */

        i.beginning_inventory,

        i.inventory_purchased_quantity,

        sb.sold_quantity,

        i.ending_inventory

    FROM inventory i

    LEFT JOIN sold_by_store sb

        ON UPPER(
            TRIM(
                i.product_id
            )
        ) = UPPER(
            TRIM(
                sb.product_id
            )
        )

       AND i.inventory_snapshot_date =
           sb.inventory_snapshot_date

),


/* =========================================================
   TOTAL PURCHASED QUANTITY BY SNAPSHOT DATE

   Used as denominator for Supplier Contribution %.

   Negative purchased values are clamped to zero.
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
   PURCHASED QUANTITY BY SUPPLIER + SNAPSHOT DATE
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

with_dims AS (

    SELECT

        /* =================================================
           NATURAL KEYS
           ================================================= */

        j.product_id,

        j.store_id,

        j.inventory_snapshot_date,


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

           Store is now obtained only from an actual sale.
           ================================================= */

        CAST(
            ds_store.store_key AS VARCHAR
        ) AS store_key,


        /* =================================================
           SUPPLIER DIMENSION
           ================================================= */

        CAST(
            ds_supplier.supplier_key AS VARCHAR
        ) AS supplier_key,


        /* =================================================
           SUPPLIER NATURAL KEY
           ================================================= */

        dp.supplier_id,


        /* =================================================
           INVENTORY MEASURES
           ================================================= */

        j.beginning_inventory,

        j.inventory_purchased_quantity,

        COALESCE(
            j.sold_quantity,
            0
        ) AS inventory_sold_quantity,

        j.ending_inventory,


        /* =================================================
           INVENTORY VALUE

           Ending inventory × product cost price
           ================================================= */

        CASE

            WHEN j.ending_inventory IS NOT NULL

             AND dp.cost_price IS NOT NULL

            THEN
                j.ending_inventory
                * dp.cost_price

            ELSE NULL

        END AS inventory_value

    FROM joined j


    /* =====================================================
       PRODUCT DIMENSION
       ===================================================== */

    LEFT JOIN {{ ref('DIM_Product') }} dp

        ON UPPER(
            TRIM(
                j.product_id
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

        ON j.inventory_snapshot_date =
           dd.full_date


    /* =====================================================
       SUPPLIER DIMENSION
       ===================================================== */

    LEFT JOIN {{ ref('DIM_Supplier') }} ds_supplier

        ON UPPER(
            TRIM(
                dp.supplier_id
            )
        ) = UPPER(
            TRIM(
                ds_supplier.supplier_id
            )
        )


    /* =====================================================
       STORE DIMENSION
       ===================================================== */

    LEFT JOIN {{ ref('DIM_Store') }} ds_store

        ON UPPER(
            TRIM(
                j.store_id
            )
        ) = UPPER(
            TRIM(
                ds_store.store_id
            )
        )

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
                        COALESCE(
                            beginning_inventory,
                            0
                        )
                        +
                        COALESCE(
                            ending_inventory,
                            0
                        )
                    ) / 2.0
                )

            ELSE NULL

        END AS stock_turnover_ratio

    FROM with_dims

)


/* =========================================================
   FINAL FACT_INVENTORY
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
   TOTAL PURCHASED BY SNAPSHOT DATE
   ========================================================= */

LEFT JOIN daily_total_purchased dtp

    ON wr.inventory_snapshot_date =
       dtp.inventory_snapshot_date


/* =========================================================
   SUPPLIER PURCHASED BY SNAPSHOT DATE
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