{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH turnover AS (

    SELECT



        fi.product_key,

        dp.product_id,

        dp.product_name,

        dp.category,

        dp.subcategory,

        dp.product_line,




        
            AVG(
                fi.stock_turnover_ratio
            )
            AS stock_turnover_ratio,




        SUM(
            COALESCE(
                fi.inventory_sold_quantity,
                0
            )
        ) AS total_sold_quantity,



        AVG(
            (
                COALESCE(
                    fi.beginning_inventory,
                    0
                )
                +
                COALESCE(
                    fi.ending_inventory,
                    0
                )
            ) / 2.0
        ) AS average_inventory


    FROM {{ ref('FACT_Inventory') }} fi


    LEFT JOIN {{ ref('DIM_Product') }} dp

        ON fi.product_key = dp.product_key




    GROUP BY

        fi.product_key,

        dp.product_id,

        dp.product_name,

        dp.category,

        dp.subcategory,

        dp.product_line

)

SELECT *

FROM turnover