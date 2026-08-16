{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH supplier_category AS (

    SELECT

        fi.supplier_key,

        ds.supplier_id,

        ds.supplier_name,

        dp.category,

        SUM(
            COALESCE(
                fi.inventory_purchased_quantity,
                0
            )
        ) AS total_purchased_quantity,

        SUM(
            COALESCE(
                fi.inventory_sold_quantity,
                0
            )
        ) AS total_sold_quantity,

        SUM(
            COALESCE(
                fi.inventory_value,
                0
            )
        ) AS total_inventory_value

    FROM {{ ref('FACT_Inventory') }} fi

    LEFT JOIN {{ ref('DIM_Product') }} dp

        ON fi.product_key = dp.product_key

    LEFT JOIN {{ ref('DIM_Supplier') }} ds

        ON fi.supplier_key = ds.supplier_key

    GROUP BY

        fi.supplier_key,

        ds.supplier_id,

        ds.supplier_name,

        dp.category

),

category_totals AS (

    SELECT

        category,

        SUM(
            total_purchased_quantity
        ) AS category_total_purchased

    FROM supplier_category

    GROUP BY category

)

SELECT

    sc.supplier_key,

    sc.supplier_id,

    sc.supplier_name,

    sc.category,

    sc.total_purchased_quantity,

    sc.total_sold_quantity,

    sc.total_inventory_value,

    ROUND(

        CASE

            WHEN ct.category_total_purchased > 0

            THEN

                (
                    sc.total_purchased_quantity
                    /
                    ct.category_total_purchased
                ) * 100

            ELSE NULL

        END,

        2

    ) AS supplier_contribution_percentage

FROM supplier_category sc

LEFT JOIN category_totals ct

    ON sc.category = ct.category