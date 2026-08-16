{{ config(
    materialized='table',
    schema='AUDIT'
) }}

SELECT

    /* =====================================================
       IDENTIFICATION
       ===================================================== */

    product_id,

    inventory_snapshot_date,

    inventory_previous_snapshot_date,


    /* =====================================================
       COMPLETENESS CHECKS
       ===================================================== */

    CASE
        WHEN product_id IS NULL
          OR TRIM(product_id) = ''
        THEN TRUE
        ELSE FALSE
    END AS missing_product_id_flag,

    CASE
        WHEN inventory_snapshot_date IS NULL
        THEN TRUE
        ELSE FALSE
    END AS missing_snapshot_date_flag,


    /* =====================================================
       INVENTORY QUANTITY CHECKS
       ===================================================== */

    CASE
        WHEN beginning_inventory IS NULL
          OR beginning_inventory < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_beginning_inventory_flag,

    CASE
        WHEN ending_inventory IS NULL
          OR ending_inventory < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_ending_inventory_flag,

    CASE
        WHEN inventory_sold_quantity IS NULL
          OR inventory_sold_quantity < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_sold_quantity_flag,

    CASE
        WHEN inventory_purchased_quantity IS NULL
          OR inventory_purchased_quantity < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_purchased_quantity_flag,


    /* =====================================================
       REORDER LEVEL CHECK
       ===================================================== */

    CASE
        WHEN inventory_reorder_level IS NULL
          OR inventory_reorder_level < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_reorder_level_flag,


    /* =====================================================
       SNAPSHOT DATE CHECK
       ===================================================== */

    CASE
        WHEN inventory_previous_snapshot_date IS NOT NULL
         AND inventory_snapshot_date <= inventory_previous_snapshot_date
        THEN TRUE
        ELSE FALSE
    END AS invalid_snapshot_sequence_flag,

    CASE
        WHEN inventory_days_since_last_snapshot IS NOT NULL
         AND inventory_days_since_last_snapshot < 0
        THEN TRUE
        ELSE FALSE
    END AS invalid_snapshot_days_flag,


    /* =====================================================
       NEGATIVE BALANCE CHECK
       ===================================================== */

    CASE
        WHEN inventory_negative_balance_flag = TRUE
        THEN TRUE
        ELSE FALSE
    END AS negative_inventory_flag,


    /* =====================================================
       INVENTORY RECONCILIATION CHECK
       
       Expected:
       Ending = Beginning + Purchased - Sold
       ===================================================== */

    CASE

        WHEN beginning_inventory IS NOT NULL
         AND ending_inventory IS NOT NULL
         AND inventory_purchased_quantity IS NOT NULL
         AND inventory_sold_quantity IS NOT NULL

         AND ending_inventory !=
             (
                 beginning_inventory
                 + inventory_purchased_quantity
                 - inventory_sold_quantity
             )

        THEN TRUE

        ELSE FALSE

    END AS inventory_balance_mismatch_flag,


    /* =====================================================
       OVERALL AUDIT RESULT
       ===================================================== */

    CASE

        WHEN product_id IS NULL
          OR TRIM(product_id) = ''

          OR inventory_snapshot_date IS NULL

          OR beginning_inventory IS NULL
          OR beginning_inventory < 0

          OR ending_inventory IS NULL
          OR ending_inventory < 0

          OR inventory_sold_quantity IS NULL
          OR inventory_sold_quantity < 0

          OR inventory_purchased_quantity IS NULL
          OR inventory_purchased_quantity < 0

          OR inventory_reorder_level IS NULL
          OR inventory_reorder_level < 0

          OR (
                inventory_previous_snapshot_date IS NOT NULL
                AND inventory_snapshot_date <=
                    inventory_previous_snapshot_date
             )

          OR (
                inventory_days_since_last_snapshot IS NOT NULL
                AND inventory_days_since_last_snapshot < 0
             )

          OR inventory_negative_balance_flag = TRUE

          OR (
                beginning_inventory IS NOT NULL
                AND ending_inventory IS NOT NULL
                AND inventory_purchased_quantity IS NOT NULL
                AND inventory_sold_quantity IS NOT NULL
                AND ending_inventory !=
                    (
                        beginning_inventory
                        + inventory_purchased_quantity
                        - inventory_sold_quantity
                    )
             )

        THEN 'FAIL'

        ELSE 'PASS'

    END AS audit_status,


    /* =====================================================
       SOURCE INFORMATION
       ===================================================== */

    source_file,
    row_number,
    loaded_at,
    batch_id

FROM {{ ref('silver_inventory') }}