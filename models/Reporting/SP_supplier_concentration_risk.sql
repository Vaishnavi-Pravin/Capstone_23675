{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH supplier_purchase AS (

    SELECT

        fi.supplier_key,

        ds.supplier_id,

        ds.supplier_name,

        SUM(
            GREATEST(
                COALESCE(
                    fi.inventory_purchased_quantity,
                    0
                ),
                0
            )
        ) AS total_purchased_quantity

    FROM {{ ref('FACT_Inventory') }} fi

    LEFT JOIN {{ ref('DIM_Supplier') }} ds

        ON fi.supplier_key = ds.supplier_key

    GROUP BY

        fi.supplier_key,

        ds.supplier_id,

        ds.supplier_name

),

totals AS (

    SELECT

        SUM(
            total_purchased_quantity
        ) AS total_purchased_quantity

    FROM supplier_purchase

),

supplier_share AS (

    SELECT

        sp.supplier_key,

        sp.supplier_id,

        sp.supplier_name,

        sp.total_purchased_quantity,

        ROUND(

            CASE

                WHEN t.total_purchased_quantity > 0

                THEN

                    (
                        sp.total_purchased_quantity
                        /
                        t.total_purchased_quantity
                    ) * 100

                ELSE NULL

            END,

            2

        ) AS purchase_share_percentage

    FROM supplier_purchase sp

    CROSS JOIN totals t

)

SELECT

    supplier_key,

    supplier_id,

    supplier_name,

    total_purchased_quantity,

    purchase_share_percentage,

    CASE

        WHEN purchase_share_percentage >= 50

            THEN 'High Risk'

        WHEN purchase_share_percentage >= 25

            THEN 'Medium Risk'

        ELSE 'Low Risk'

    END AS supplier_concentration_risk

FROM supplier_share