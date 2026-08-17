{{ config(
    materialized='table',
    schema='GOLD'
) }}

WITH inventory AS (

    SELECT *

    FROM {{ ref('silver_inventory') }}

),



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


joined AS (

    SELECT

        i.product_id,

        i.inventory_snapshot_date,

        sb.store_id,

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




with_dims AS (

    SELECT


        j.product_id,

        j.store_id,

        j.inventory_snapshot_date,




        CAST(
            dp.product_key AS VARCHAR
        ) AS product_key,




        CAST(
            dd.date_key AS VARCHAR
        ) AS date_key,




        CAST(
            ds_store.store_key AS VARCHAR
        ) AS store_key,




        CAST(
            ds_supplier.supplier_key AS VARCHAR
        ) AS supplier_key,




        dp.supplier_id,




        j.beginning_inventory,

        j.inventory_purchased_quantity,

        COALESCE(
            j.sold_quantity,
            0
        ) AS inventory_sold_quantity,

        j.ending_inventory,




        CASE

            WHEN j.ending_inventory IS NOT NULL

             AND dp.cost_price IS NOT NULL

            THEN
                j.ending_inventory
                * dp.cost_price

            ELSE NULL

        END AS inventory_value

    FROM joined j




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




    LEFT JOIN {{ ref('DIM_Date') }} dd

        ON j.inventory_snapshot_date =
           dd.full_date




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




SELECT


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




    beginning_inventory,

    inventory_purchased_quantity,

    inventory_sold_quantity,

    ending_inventory,

    inventory_value,

    stock_turnover_ratio,




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




LEFT JOIN daily_total_purchased dtp

    ON wr.inventory_snapshot_date =
       dtp.inventory_snapshot_date




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