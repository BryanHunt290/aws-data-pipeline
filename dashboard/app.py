"""
Sales Analytics Dashboard - Two tiles
Tile 1: Time-based (line chart) - Revenue over time
Tile 2: Categorical (bar chart) - Revenue by category

Connects to Athena (Glue Catalog) or Redshift. Set env vars in .env
"""

import os

import pandas as pd
import streamlit as st
from dotenv import load_dotenv

load_dotenv()

# Config: Athena (default) or Redshift
USE_REDSHIFT = os.getenv("USE_REDSHIFT", "false").lower() == "true"
GLUE_DATABASE = os.getenv("GLUE_DATABASE", "data_pipeline_demo_catalog")
ATHENA_WORKGROUP = os.getenv("ATHENA_WORKGROUP", "data-pipeline-demo")
ATHENA_RESULTS = os.getenv("ATHENA_RESULTS_BUCKET", "")

st.set_page_config(page_title="Sales Analytics", layout="wide")
st.title("Sales Analytics Dashboard")
st.caption("Tile 1: Time-based | Tile 2: Categorical")


def get_data_athena():
    """Query via Athena (Glue Catalog over S3)."""
    from pyathena import connect

    if not ATHENA_RESULTS:
        st.error("Set ATHENA_RESULTS_BUCKET in .env (terraform output athena_results_bucket)")
        return None, None

    conn = connect(
        s3_staging_dir=f"s3://{ATHENA_RESULTS}/results/",
        region_name=os.getenv("AWS_REGION", "us-east-1"),
        work_group=ATHENA_WORKGROUP,
    )

    # Glue Crawler for s3://bucket/processed/ creates table "processed"
    table_name = os.getenv("GLUE_TABLE", "processed")
    qualified = f'"{GLUE_DATABASE}"."{table_name}"'

    sql_time = f"""
        SELECT year, month, SUM(total_revenue) AS total_revenue
        FROM {qualified}
        GROUP BY year, month
        ORDER BY year, month
    """
    sql_cat = f"""
        SELECT category, SUM(total_revenue) AS total_revenue
        FROM {qualified}
        GROUP BY category
        ORDER BY total_revenue DESC
    """

    df_time = pd.read_sql(sql_time, conn)
    df_cat = pd.read_sql(sql_cat, conn)
    return df_time, df_cat


def get_data_redshift():
    """Query via Redshift."""
    import psycopg2

    conn = psycopg2.connect(
        host=os.getenv("REDSHIFT_HOST"),
        port=os.getenv("REDSHIFT_PORT", "5439"),
        dbname=os.getenv("REDSHIFT_DATABASE", "sales"),
        user=os.getenv("REDSHIFT_USER"),
        password=os.getenv("REDSHIFT_PASSWORD"),
    )

    df_time = pd.read_sql(
        "SELECT * FROM analytics.fct_sales_over_time ORDER BY year, month",
        conn
    )
    df_cat = pd.read_sql(
        "SELECT * FROM analytics.fct_sales_by_category ORDER BY total_revenue DESC",
        conn
    )
    return df_time, df_cat


try:
    if USE_REDSHIFT:
        df_time, df_cat = get_data_redshift()
    else:
        df_time, df_cat = get_data_athena()

    if df_time is None:
        st.stop()

    col1, col2 = st.columns(2)

    with col1:
        st.subheader("Tile 1: Revenue Over Time (Line Chart)")
        if not df_time.empty:
            df_time["sale_month"] = pd.to_datetime(
                df_time["year"].astype(str) + "-" + df_time["month"].astype(str).str.zfill(2) + "-01"
            )
            st.line_chart(df_time.set_index("sale_month")[["total_revenue"]])
        else:
            st.info("No data. Run pipeline and Glue Crawler first.")

    with col2:
        st.subheader("Tile 2: Revenue by Category (Bar Chart)")
        if not df_cat.empty:
            st.bar_chart(df_cat.set_index("category")[["total_revenue"]])
        else:
            st.info("No data. Run pipeline and Glue Crawler first.")

except Exception as e:
    st.error(f"Error: {e}")
    st.info("Ensure pipeline has run, Glue Crawler has been executed, and .env is configured.")
