{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH campaign_engagement AS (

    SELECT

        /* =================================================
           Campaign
           ================================================= */

        fm.campaign_key,

        dc.campaign_id,

        dc.campaign_name,

        dc.campaign_type,

        dc.channel,


        /* =================================================
           New Customers
           ================================================= */

        SUM(
            COALESCE(
                fm.new_customers_acquired,
                0
            )
        ) AS new_customers,


        /* =================================================
           Sales Influenced
           ================================================= */

        SUM(
            COALESCE(
                fm.total_sales_influenced,
                0
            )
        ) AS total_sales_influenced,


        /* =================================================
           Repeat Purchase Rate

           Fact contains the cumulative rate by campaign
           activity date. MAX gets the latest rate.
           ================================================= */

        MAX(
            fm.repeat_purchase_rate
        ) AS repeat_purchase_rate_percentage


    FROM {{ ref('FACT_MarketingPerformance') }} fm


    LEFT JOIN {{ ref('DIM_Campaign') }} dc

        ON fm.campaign_key = dc.campaign_key


    WHERE dc.campaign_id IS NOT NULL


    GROUP BY

        fm.campaign_key,

        dc.campaign_id,

        dc.campaign_name,

        dc.campaign_type,

        dc.channel

)


SELECT

    campaign_key,

    campaign_id,

    campaign_name,

    campaign_type,

    channel,

    new_customers,

    total_sales_influenced,

    ROUND(
        repeat_purchase_rate_percentage,
        2
    ) AS repeat_purchase_rate_percentage

FROM campaign_engagement