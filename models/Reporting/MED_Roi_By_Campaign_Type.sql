{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH campaign_performance AS (

    SELECT

        fm.campaign_key,

        dc.campaign_id,
        dc.campaign_name,
        dc.campaign_type,

        /* Campaign financial attributes */
        dc.total_cost,
        dc.total_revenue,

        /* Total sales influenced by the campaign */
        SUM(
            COALESCE(
                fm.total_sales_influenced,
                0
            )
        ) AS total_sales_influenced,

        /* New customers acquired */
        SUM(
            COALESCE(
                fm.new_customers_acquired,
                0
            )
        ) AS new_customers_acquired,

        /*
           Repeat purchase rate:
           The fact contains a cumulative rate for each
           campaign activity date, so MAX gives the latest
           cumulative campaign rate.
        */
        MAX(
            fm.repeat_purchase_rate
        ) AS repeat_purchase_rate

    FROM {{ ref('FACT_MarketingPerformance') }} fm

    LEFT JOIN {{ ref('DIM_Campaign') }} dc

        ON fm.campaign_key = dc.campaign_key

    WHERE dc.campaign_id IS NOT NULL

    GROUP BY

        fm.campaign_key,

        dc.campaign_id,
        dc.campaign_name,
        dc.campaign_type,

        dc.total_cost,
        dc.total_revenue

),

final AS (

    SELECT

        campaign_key,

        campaign_id,

        campaign_name,

        campaign_type,

        total_cost,

        total_revenue,

        total_sales_influenced,

        new_customers_acquired,

        repeat_purchase_rate,

        /*
           Campaign ROI

           ROI =
           (Sales Influenced - Campaign Cost)
           / Campaign Cost × 100
        */

        CASE

            WHEN total_cost > 0

            THEN ROUND(

                (
                    total_sales_influenced
                    - total_cost
                )
                / total_cost
                * 100,

                2

            )

            ELSE NULL

        END AS roi

    FROM campaign_performance

)

SELECT *

FROM final