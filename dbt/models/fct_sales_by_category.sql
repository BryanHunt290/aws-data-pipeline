{{
  config(
    materialized='table',
    schema='analytics'
  )
}}

-- Categorical aggregation: total revenue by category (for bar chart)
select
    category,
    sum(total_revenue) as total_revenue,
    sum(total_quantity) as total_quantity,
    sum(transaction_count) as transaction_count
from {{ ref('stg_sales') }}
group by category
order by total_revenue desc
