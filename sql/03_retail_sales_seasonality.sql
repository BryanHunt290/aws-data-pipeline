-- retail_sales_seasonality: Month-over-month patterns by category
-- Partition pruning: filter year, month

CREATE OR REPLACE VIEW retail_sales_seasonality AS
WITH monthly_sales AS (
    SELECT
        year,
        month,
        category,
        sales,
        LAG(sales) OVER (PARTITION BY category, year ORDER BY month) AS prev_month_sales
    FROM retail_sales
    WHERE year IS NOT NULL
      AND month IS NOT NULL
      AND sales IS NOT NULL
)
SELECT
    year,
    month,
    category,
    sales,
    prev_month_sales,
    ROUND(
        100.0 * (sales - prev_month_sales) / NULLIF(prev_month_sales, 0),
        2
    ) AS mom_growth_pct
FROM monthly_sales
ORDER BY year DESC, month DESC, category;
