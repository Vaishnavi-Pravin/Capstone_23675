{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH product_turnover AS (

    SELECT

        fi.product_key,

        dp.product_id,

        dp.product_name,

        dp.category,

        dp.subcategory,

        ROUND(
            AVG(
                fi.stock_turnover_ratio
            ),
            2
        ) AS stock_turnover_ratio,

        SUM(
            COALESCE(
                fi.inventory_sold_quantity,
                0
            )
        ) AS total_sold_quantity,

        SUM(
            COALESCE(
                fi.ending_inventory,
                0
            )
        ) AS total_ending_inventory

    FROM {{ ref('FACT_Inventory') }} fi

    LEFT JOIN {{ ref('DIM_Product') }} dp

        ON fi.product_key = dp.product_key

    GROUP BY

        fi.product_key,

        dp.product_id,

        dp.product_name,

        dp.category,

        dp.subcategory

),

overall_average AS (

    SELECT

        AVG(
            stock_turnover_ratio
        ) AS average_turnover_ratio

    FROM product_turnover

)

SELECT

    pt.product_key,

    pt.product_id,

    pt.product_name,

    pt.category,

    pt.subcategory,

    pt.stock_turnover_ratio,

    pt.total_sold_quantity,

    pt.total_ending_inventory,

    CASE

        WHEN pt.stock_turnover_ratio >=
             oa.average_turnover_ratio

        THEN 'Fast Moving'

        WHEN pt.stock_turnover_ratio <
             oa.average_turnover_ratio

        THEN 'Slow Moving'

        ELSE 'Unclassified'

    END AS movement_category

FROM product_turnover pt

CROSS JOIN overall_average oa