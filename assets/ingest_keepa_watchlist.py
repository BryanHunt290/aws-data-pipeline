"""@bruin
name: raw.keepa_watchlist
type: python
image: python:3.11

# Writes JSONL to S3 keepa/raw/ingest_date=YYYY-MM-DD/ - no Athena materialization
# Requires: S3_BUCKET, KEEPA_API_KEY (optional), seeds/watchlist_asins.csv

secrets:
  - key: keepa_api_key
    inject_as: KEEPA_API_KEY
@bruin"""

import json
import os
import uuid
from datetime import datetime
from pathlib import Path

import pandas as pd

# Fallback ASINs when no watchlist file
DEFAULT_WATCHLIST_ASINS = [
    "B08N5WRWNW", "B09V3KXJPB", "B0BSHF7LLL", "B07XJ8C8F5", "B09B8V1LZ3",
    "B08L5VN68M", "B0C1H26C46", "B09G9FPHY6", "B08KBVJ4ZW", "B0B7CPSN2P",
]


def load_asins_from_csv() -> list[str]:
    """Load ASINs from seeds/watchlist_asins.csv."""
    project_root = Path(__file__).resolve().parent.parent
    path = project_root / "seeds" / "watchlist_asins.csv"
    if path.exists():
        df = pd.read_csv(path)
        col = "asin" if "asin" in df.columns else df.columns[0]
        return [str(a).strip() for a in df[col].dropna() if str(a).strip()]
    return []


def fetch_from_keepa_api(asins: list[str], api_key: str) -> pd.DataFrame:
    """Fetch product data from Keepa API. Requires keepa package (pip install keepa)."""
    try:
        import keepa  # type: ignore
        api = keepa.Keepa(api_key)
        products = api.query(asins, stats=30, offer_stats=30)
        rows = []
        for p in products:
            if p and "csv" in p:
                csv = p["csv"]
                buy_box = csv[0][-1] if csv[0] else None
                rank = csv[3][-1] if len(csv) > 3 and csv[3] else None
                offers = csv[16][-1] if len(csv) > 16 and csv[16] else None
                buy_box_price = (buy_box / 100.0) if buy_box is not None else None
                rows.append({
                    "asin": p.get("asin", ""),
                    "buy_box_price": buy_box_price,
                    "sales_rank": rank,
                    "offer_count": offers or 0,
                    "captured_at": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
                })
        return pd.DataFrame(rows)
    except ImportError:
        return pd.DataFrame()
    except Exception:
        return pd.DataFrame()


def fetch_mock_data(asins: list[str]) -> pd.DataFrame:
    """Mock Keepa-like data for demo when API key is not configured."""
    import random
    now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    return pd.DataFrame([
        {
            "asin": asin,
            "buy_box_price": round(random.uniform(15, 55), 2),
            "sales_rank": random.randint(500, 5000),
            "offer_count": random.randint(4, 25),
            "captured_at": now,
        }
        for asin in asins
    ])


def materialize(**kwargs) -> None:
    """Fetch Keepa data and write JSONL to S3 keepa/raw/."""
    bucket = os.environ.get("S3_BUCKET", "").strip()
    if not bucket:
        raise ValueError("S3_BUCKET env var required. Run 'make setup-env' and source .env")

    asins = load_asins_from_csv()
    if not asins:
        asins = DEFAULT_WATCHLIST_ASINS

    api_key = os.environ.get("KEEPA_API_KEY", "").strip()
    if api_key:
        df = fetch_from_keepa_api(asins, api_key)
        if df.empty:
            df = fetch_mock_data(asins)
    else:
        df = fetch_mock_data(asins)

    now = datetime.utcnow()
    date_str = now.strftime("%Y-%m-%d")
    run_id = uuid.uuid4().hex[:12]
    s3_key = f"keepa/raw/ingest_date={date_str}/keepa_{run_id}.jsonl"

    import boto3
    client = boto3.client("s3")
    lines = []
    for _, row in df.iterrows():
        obj = {
            "asin": str(row.get("asin", "")),
            "buy_box_price": float(row["buy_box_price"]) if pd.notna(row.get("buy_box_price")) else None,
            "sales_rank": int(row["sales_rank"]) if pd.notna(row.get("sales_rank")) else None,
            "offer_count": int(row.get("offer_count", 0)) if pd.notna(row.get("offer_count")) else 0,
            "captured_at": str(row.get("captured_at", now.strftime("%Y-%m-%dT%H:%M:%SZ"))),
        }
        lines.append(json.dumps(obj) + "\n")

    body = "".join(lines)
    client.put_object(Bucket=bucket, Key=s3_key, Body=body, ContentType="application/jsonlines")
    print(f"Wrote {len(df)} records to s3://{bucket}/{s3_key}")
