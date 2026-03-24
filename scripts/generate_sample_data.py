#!/usr/bin/env python3
"""
Generate sample sales CSV for the pipeline.
Output: data/sample_data.csv (or --output path)
Schema: id,product,category,quantity,unit_price,sale_date
"""

import argparse
import csv
import random
from datetime import datetime, timedelta

PRODUCTS = [
    ("Widget A", "Electronics", 29.99),
    ("Widget B", "Electronics", 49.99),
    ("Gadget X", "Home", 14.99),
    ("Gadget Y", "Home", 24.99),
    ("Tool Pro", "Hardware", 79.99),
    ("Tool Basic", "Hardware", 19.99),
    ("Book Alpha", "Books", 9.99),
    ("Book Beta", "Books", 14.99),
    ("Phone Case", "Electronics", 12.99),
    ("Desk Lamp", "Home", 34.99),
    ("Drill Set", "Hardware", 89.99),
    ("Novel X", "Books", 12.99),
    ("Headphones", "Electronics", 59.99),
    ("Throw Pillow", "Home", 19.99),
    ("Wrench", "Hardware", 24.99),
    ("Cookbook", "Books", 18.99),
]

def main():
    parser = argparse.ArgumentParser(description="Generate sample sales CSV")
    parser.add_argument("-n", "--rows", type=int, default=200, help="Number of rows")
    parser.add_argument("-o", "--output", default="data/sample_data.csv", help="Output path")
    parser.add_argument("--start-date", default="2024-01-01", help="Start date YYYY-MM-DD")
    parser.add_argument("--end-date", default="2024-12-31", help="End date YYYY-MM-DD")
    args = parser.parse_args()

    start = datetime.strptime(args.start_date, "%Y-%m-%d").date()
    end = datetime.strptime(args.end_date, "%Y-%m-%d").date()
    delta = (end - start).days

    rows = []
    for i in range(1, args.rows + 1):
        product, category, unit_price = random.choice(PRODUCTS)
        quantity = random.randint(1, 25)
        sale_date = start + timedelta(days=random.randint(0, delta))
        rows.append({
            "id": i,
            "product": product,
            "category": category,
            "quantity": quantity,
            "unit_price": unit_price,
            "sale_date": sale_date.strftime("%Y-%m-%d"),
        })

    with open(args.output, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["id", "product", "category", "quantity", "unit_price", "sale_date"])
        w.writeheader()
        w.writerows(rows)

    print(f"Generated {len(rows)} rows -> {args.output}")

if __name__ == "__main__":
    main()
