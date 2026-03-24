-- retail_sales_yoy_growth: Year-over-year growth by category
-- Partition pruning: filter year for latest analysis

CREATE OR REPLACE VIEW retail_sales_yoy_growth AS
WITH yearly_totals AS (
    SELECT
        year,
        category,
        SUM(sales) AS total_sales
    FROM retail_sales
    WHERE year IS NOT NULL
      AND sales IS NOT NULL
    GROUP BY year, category
),
with_prior AS (
    SELECT
        y.year,
        y.category,
        y.total_sales,
        p.total_sales AS prior_year_sales
    FROM yearly_totals y
    LEFT JOIN yearly_totals p
        ON y.category = p.category
        AND y.year = p.year + 1
)
SELECT
    year,
    category,
    total_sales,
    prior_year_sales,
    ROUND(
        100.0 * (total_sales - prior_year_sales) / NULLIF(prior_year_sales, 0),
        2
    ) AS yoy_growth_pct
FROM with_prior
ORDER BY year DESC, category;
