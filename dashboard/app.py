"""
MRTS Retail Sales Dashboard - 2 tiles
- Line chart: Total sales over time (overall or by category)
- Bar chart: YoY growth by category (latest year)

Uses Athena via pyathena. Set AWS_REGION, ATHENA_WORKGROUP, GLUE_DATABASE, ATHENA_RESULTS_BUCKET in .env
"""

import os

from dotenv import load_dotenv
load_dotenv()

import pandas as pd
import streamlit as st
from pyathena import connect

# Config from env
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
ATHENA_WORKGROUP = os.getenv("ATHENA_WORKGROUP", "mrts-retail-sales-dev")
GLUE_DATABASE = os.getenv("GLUE_DATABASE", "mrts_retail_sales_dev_catalog")
ATHENA_RESULTS = os.getenv("ATHENA_RESULTS_BUCKET", "")

if not ATHENA_RESULTS:
    st.error("Set ATHENA_RESULTS_BUCKET (from terraform output athena_results_bucket)")
    st.stop()

st.set_page_config(page_title="MRTS Retail Sales", layout="wide")
st.title("US Census MRTS - Retail Sales Dashboard")

# Athena connection
@st.cache_resource
def get_conn():
    return connect(
        s3_staging_dir=f"s3://{ATHENA_RESULTS}/athena-results/",
        region_name=AWS_REGION,
        work_group=ATHENA_WORKGROUP,
    )


def run_query(sql: str) -> pd.DataFrame:
    conn = get_conn()
    return pd.read_sql(sql, conn)


# Tile 1: Line chart - Total sales over time
st.subheader("Tile 1: Total Sales Over Time")
category_filter = st.selectbox(
    "Category",
    options=["All", "retail_and_food_services", "retail_total", "food_and_beverage", "motor_vehicle"],
    index=0,
)

if category_filter == "All":
    sql_sales = f"""
        SELECT year, month, SUM(sales) AS total_sales
        FROM "{GLUE_DATABASE}".retail_sales
        WHERE year >= 2015
        GROUP BY year, month
        ORDER BY year, month
    """
else:
    sql_sales = f"""
        SELECT year, month, SUM(sales) AS total_sales
        FROM "{GLUE_DATABASE}".retail_sales
        WHERE category = '{category_filter}' AND year >= 2015
        GROUP BY year, month
        ORDER BY year, month
    """

try:
    df_sales = run_query(sql_sales)
    if not df_sales.empty:
        df_sales["date"] = pd.to_datetime(
            df_sales["year"].astype(str) + "-" + df_sales["month"].astype(str).str.zfill(2) + "-01"
        )
        st.line_chart(df_sales.set_index("date")[["total_sales"]])
    else:
        st.info("No data. Run ingestion and Glue ETL first.")
except Exception as e:
    st.error(f"Query failed: {e}")

# Tile 2: Bar chart - YoY growth by category (latest year)
st.subheader("Tile 2: Year-over-Year Growth by Category (Latest Year)")

try:
    df_yoy = run_query(f"""
        WITH yearly AS (
            SELECT year, category, SUM(sales) AS total_sales
            FROM "{GLUE_DATABASE}".retail_sales
            GROUP BY year, category
        ),
        with_prior AS (
            SELECT y.year, y.category, y.total_sales, p.total_sales AS prior_sales
            FROM yearly y
            LEFT JOIN yearly p ON y.category = p.category AND y.year = p.year + 1
        )
        SELECT year, category,
            ROUND(100.0 * (total_sales - prior_sales) / NULLIF(prior_sales, 0), 2) AS yoy_growth_pct
        FROM with_prior
        WHERE year = (SELECT MAX(year) FROM yearly)
        ORDER BY yoy_growth_pct DESC
    """)
    if not df_yoy.empty:
        st.bar_chart(df_yoy.set_index("category")[["yoy_growth_pct"]])
    else:
        st.info("No YoY data. Ensure multiple years of data exist.")
except Exception as e:
    st.error(f"Query failed: {e}")
