{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH supply_analysis AS (

    SELECT

        order_id,

        order_date,

        processing_days,

        shipping_days,

        delivery_status

    FROM {{ ref('silver_orders') }}

    WHERE order_id IS NOT NULL

)

SELECT

    delivery_status,

    COUNT(DISTINCT order_id) AS total_orders,

    ROUND(
        AVG(processing_days),
        2
    ) AS average_processing_days,

    ROUND(
        AVG(shipping_days),
        2
    ) AS average_shipping_days,

    ROUND(
        100.0
        * COUNT(DISTINCT order_id)
        / NULLIF(
            SUM(COUNT(DISTINCT order_id))
                OVER (),
            0
        ),
        2
    ) AS percentage_of_orders

FROM supply_analysis

GROUP BY

    delivery_status

ORDER BY

    CASE delivery_status
        WHEN 'On Time' THEN 1
        WHEN 'Delayed' THEN 2
        WHEN 'Potentially Delayed' THEN 3
        WHEN 'In Transit' THEN 4
        ELSE 5
    END