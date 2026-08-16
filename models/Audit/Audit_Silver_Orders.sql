{{ config(
    materialized='table',
    schema='AUDIT'
) }}

SELECT

    /* =====================================================
       IDENTIFICATION
       ===================================================== */

    order_id,
    customer_id,
    employee_id,
    store_id,
    campaign_id,

    order_date,
    order_status,


    /* =====================================================
       COMPLETENESS CHECKS
       ===================================================== */

    CASE
        WHEN order_id IS NULL
          OR TRIM(order_id) = ''
        THEN TRUE
        ELSE FALSE
    END AS missing_order_id_flag,

    CASE
        WHEN customer_id IS NULL
          OR TRIM(customer_id) = ''
        THEN TRUE
        ELSE FALSE
    END AS missing_customer_id_flag,

    CASE
        WHEN order_date IS NULL
        THEN TRUE
        ELSE FALSE
    END AS missing_order_date_flag,


    /* =====================================================
       QUANTITY CHECKS
       ===================================================== */

    CASE
        WHEN total_items IS NULL
          OR total_items < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_total_items_flag,

    CASE
        WHEN total_quantity IS NULL
          OR total_quantity < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_total_quantity_flag,


    /* =====================================================
       FINANCIAL CHECKS
       ===================================================== */

    CASE
        WHEN line_revenue IS NULL
          OR line_revenue < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_revenue_flag,

    CASE
        WHEN line_cost IS NULL
          OR line_cost < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_cost_flag,

    CASE
        WHEN profit_amount IS NULL
        THEN TRUE
        ELSE FALSE
    END AS missing_profit_flag,


    /* =====================================================
       SHIPPING CHECKS
       ===================================================== */

    CASE
        WHEN processing_days IS NOT NULL
         AND processing_days < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_processing_days_flag,

    CASE
        WHEN shipping_days IS NOT NULL
         AND shipping_days < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_shipping_days_flag,

    CASE
        WHEN delivery_status IS NULL
        THEN TRUE
        ELSE FALSE
    END AS missing_delivery_status_flag,


    /* =====================================================
       ORDER STATUS CHECK
       ===================================================== */

    CASE
        WHEN order_status IS NULL
          OR TRIM(order_status) = ''
        THEN TRUE
        ELSE FALSE
    END AS missing_order_status_flag,


    /* =====================================================
       OVERALL AUDIT RESULT
       ===================================================== */

    CASE

        WHEN order_id IS NULL
          OR TRIM(order_id) = ''

          OR customer_id IS NULL
          OR TRIM(customer_id) = ''

          OR order_date IS NULL

          OR total_items IS NULL
          OR total_items < 0

          OR total_quantity IS NULL
          OR total_quantity < 0

          OR line_revenue IS NULL
          OR line_revenue < 0

          OR line_cost IS NULL
          OR line_cost < 0

          OR profit_amount IS NULL

          OR (
                processing_days IS NOT NULL
                AND processing_days < 0
             )

          OR (
                shipping_days IS NOT NULL
                AND shipping_days < 0
             )

          OR delivery_status IS NULL

          OR order_status IS NULL
          OR TRIM(order_status) = ''

        THEN 'FAIL'

        ELSE 'PASS'

    END AS audit_status,


    /* =====================================================
       SOURCE INFORMATION
       ===================================================== */

    loaded_at,
    source_file,
    batch_id

FROM {{ ref('silver_orders') }}