{{
  config(
    materialized='table',
    schema='analytics'
  )
}}

-- Time-based aggregation: revenue over time (for line chart)
select
    year,
    month,
    to_date(year || '-' || lpad(month::varchar, 2, '0') || '-01') as sale_month,
    sum(total_revenue) as total_revenue,
    sum(total_quantity) as total_quantity
from {{ ref('stg_sales') }}
group by year, month
order by year, month
