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


def _athena_sql_to_df(sql: str) -> pd.DataFrame:
    """Run Athena SQL and return a DataFrame (boto3 only — avoids PyAthena/pandas SQLAlchemy quirks)."""
    import time

    import boto3

    if not ATHENA_RESULTS:
        raise ValueError("ATHENA_RESULTS_BUCKET is not set")

    region = os.getenv("AWS_REGION", "us-east-1")
    client = boto3.client("athena", region_name=region)
    output = f"s3://{ATHENA_RESULTS}/results/"

    resp = client.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": GLUE_DATABASE},
        ResultConfiguration={"OutputLocation": output},
        WorkGroup=ATHENA_WORKGROUP,
    )
    qid = resp["QueryExecutionId"]

    while True:
        status = client.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]
        state = status["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(0.35)

    if state != "SUCCEEDED":
        reason = status.get("StateChangeReason", state)
        raise RuntimeError(f"Athena query failed: {reason}")

    rows_data: list[list[str | None]] = []
    columns: list[str] = []
    next_token = None

    while True:
        kwargs: dict = {"QueryExecutionId": qid, "MaxResults": 1000}
        if next_token:
            kwargs["NextToken"] = next_token
        page = client.get_query_results(**kwargs)
        rs = page["ResultSet"]
        rs_rows = rs["Rows"]
        if not columns and rs_rows:
            columns = [c.get("VarCharValue", "") for c in rs_rows[0]["Data"]]
            rs_rows = rs_rows[1:]
        for row in rs_rows:
            rows_data.append([d.get("VarCharValue") for d in row["Data"]])
        next_token = page.get("NextToken")
        if not next_token:
            break

    if not columns:
        return pd.DataFrame()
    df = pd.DataFrame(rows_data, columns=columns)
    # Numeric columns from Athena CSV-style results
    for col in df.columns:
        if col in ("year", "month", "total_quantity", "transaction_count"):
            df[col] = pd.to_numeric(df[col], errors="coerce")
        elif col == "total_revenue":
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def get_data_athena():
    """Query via Athena (Glue Catalog over S3)."""
    if not ATHENA_RESULTS:
        st.error("Set ATHENA_RESULTS_BUCKET in .env (terraform output athena_results_bucket)")
        return None, None

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

    df_time = _athena_sql_to_df(sql_time)
    df_cat = _athena_sql_to_df(sql_cat)
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
            st.info(
                "No data. Run in order: **1)** `make upload` → **2)** pipeline → **3)** crawler. "
                "Wait 2–3 min between steps."
            )

    with col2:
        st.subheader("Tile 2: Revenue by Category (Bar Chart)")
        if not df_cat.empty:
            st.bar_chart(df_cat.set_index("category")[["total_revenue"]])
        else:
            st.info(
                "No data. Run in order: **1)** `make upload` → **2)** pipeline → **3)** crawler. "
                "Wait 2–3 min between steps."
            )

except Exception as e:
    st.error(f"Error: {e}")
    st.markdown("**Fix:** Run pipeline, then crawler. Wait 2–3 min between steps, then refresh.")

    col1, col2, col3 = st.columns(3)
    with col1:
        if st.button("▶ Run pipeline (Step Functions)"):
            try:
                import boto3
                sfn = boto3.client("stepfunctions")
                arn = os.getenv("STATE_MACHINE_ARN")
                if arn:
                    sfn.start_execution(stateMachineArn=arn)
                    st.success("Pipeline started. Wait ~3 min.")
                else:
                    st.warning("Set STATE_MACHINE_ARN in .env (terraform output state_machine_arn)")
            except Exception as ex:
                st.error(str(ex))

    with col2:
        if st.button("▶ Run Glue Crawler"):
            try:
                import boto3
                glue = boto3.client("glue")
                glue.start_crawler(Name="data-pipeline-demo-crawler-processed")
                st.success("Crawler started. Wait ~2 min, then refresh.")
            except Exception as ex:
                st.error(str(ex))

    with col3:
        if st.button("🔄 Refresh"):
            st.rerun()
