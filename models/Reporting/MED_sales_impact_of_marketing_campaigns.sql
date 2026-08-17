{{ config(
    materialized='view',
    schema='REPORTING'
) }}

WITH campaign_sales AS (

    SELECT


        fm.campaign_key,



        dc.campaign_id,

        dc.campaign_name,

        dc.campaign_type,

        dc.channel,




        SUM(
            COALESCE(
                fm.total_sales_influenced,
                0
            )
        ) AS total_sales_influenced,




        SUM(
            COALESCE(
                fm.new_customers_acquired,
                0
            )
        ) AS new_customers_acquired


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

    total_sales_influenced,

    new_customers_acquired

FROM campaign_sales