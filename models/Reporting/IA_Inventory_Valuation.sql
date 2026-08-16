{{ config(
    materialized='view',
    schema='REPORTING'
) }}

SELECT

    dp.product_key,

    dp.product_id,

    dp.product_name,

    dp.category,

    dp.subcategory,

    dp.product_line,

    ROUND(
        SUM(
            COALESCE(
                fi.inventory_value,
                0
            )
        ),
        2
    ) AS total_inventory_value,

    SUM(
        COALESCE(
            fi.beginning_inventory,
            0
        )
    ) AS total_beginning_inventory,

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
            fi.ending_inventory,
            0
        )
    ) AS total_ending_inventory

FROM {{ ref('FACT_Inventory') }} fi

LEFT JOIN {{ ref('DIM_Product') }} dp

    ON fi.product_key = dp.product_key

GROUP BY

    dp.product_key,

    dp.product_id,

    dp.product_name,

    dp.category,

    dp.subcategory,

    dp.product_line