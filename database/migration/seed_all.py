#!/usr/bin/env python3
"""
Run all seed_*.sql scripts in FK-safe order.

Prerequisites (same as the individual seeds):
  • Alpine Bakery tenant (newTables/seed_fnd_tenants.sql runs first from this script)
  • Legacy staging tables: customer, item, item_price (or item_prices), ordr, citem, ar, pmt_detail

Order:
  1. seed_fnd_pricebooks            — distinct cus_price_cd -> books; truncate pricebooks CASCADE
  2. seed_fnd_customers             — truncate customers + orders/lines; legacy customer
  3. seed_fnd_customer_pricebooks   — PRIMARY price book per customer (cus_price_cd)
  4. seed_fnd_items                 — truncate items + cascaded dependents (incl. pricebook_items)
  5. seed_bps_items
  6. seed_fnd_item_bom
  7. seed_fnd_pricebook_items       — item_price rows -> fnd_pricebook_items
  8. seed_om_orders
  9. seed_om_order_lines           — ordr_detail -> om_order_lines (after orders)
  10. seed_om_order_shipments      — optional qty events from ordr_detail
  11. seed_ar_transactions          — om_orders + legacy ordr -> ar_transactions (INVOICE)
  12. seed_ar_transaction_lines     — INVOICE/DISCOUNT from shipments + legacy allowance
  13. seed_ar_payments              — legacy public.ar (PMT) -> ar_payments
  14. seed_ar_payment_applications  — pmt_detail -> ar_payment_applications (payment + invoice links)

Usage (from repo root):
  python dataMigration/seed_all.py

Requires SUPABASE_* vars in .env (same as _run_sql.py).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

load_dotenv(ROOT / ".env", override=True)

# Bootstrap tenant + sample people (requires tables from newTables/fnd_users … fnd_contact_points).
BOOTSTRAP_SQL = ROOT / "newTables" / "seed_fnd_tenants.sql"

SEEDS: list[str] = [
    "seed_fnd_pricebooks.sql",
    "seed_fnd_customers.sql",
    "seed_fnd_customer_pricebooks.sql",
    "seed_fnd_items.sql",
    "seed_bps_items.sql",
    "seed_fnd_item_bom.sql",
    "seed_fnd_pricebook_items.sql",
    "seed_om_orders.sql",
    "seed_om_order_lines.sql",
    "seed_om_order_shipments.sql",
    "seed_ar_transactions.sql",
    "seed_ar_transaction_lines.sql",
    "seed_ar_payments.sql",
    "seed_ar_payment_applications.sql",
]


def main() -> int:
    host = os.getenv("SUPABASE_HOST")
    password = os.getenv("SUPABASE_PASSWORD")
    if not host or not password:
        print("Missing SUPABASE_HOST or SUPABASE_PASSWORD in .env", file=sys.stderr)
        return 1

    conn = psycopg2.connect(
        host=host,
        port=int(os.getenv("SUPABASE_PORT", "5432")),
        dbname=os.getenv("SUPABASE_DB"),
        user=os.getenv("SUPABASE_USER"),
        password=password,
        sslmode="require",
        connect_timeout=30,
    )
    conn.autocommit = False

    try:
        with conn.cursor() as cur:
            cur.execute("SELECT set_config('app.audit_enabled', 'false', false)")
        conn.commit()

        seed_paths: list[tuple[str, Path]] = []
        if BOOTSTRAP_SQL.is_file():
            seed_paths.append((BOOTSTRAP_SQL.name, BOOTSTRAP_SQL))
        else:
            print(f"WARNING: missing {BOOTSTRAP_SQL} — skip tenant bootstrap", file=sys.stderr)

        for name in SEEDS:
            seed_paths.append((name, HERE / name))

        for label, path in seed_paths:
            if not path.is_file():
                print(f"FAILED: missing file {path}", file=sys.stderr)
                return 1
            sql = path.read_text(encoding="utf-8")
            print(f"--- {label} ---")
            try:
                with conn.cursor() as cur:
                    cur.execute(sql)
                conn.commit()
                print(f"SUCCESS: {label}\n")
            except Exception as e:
                conn.rollback()
                print(f"FAILED: {label}: {e}", file=sys.stderr)
                return 1
            if conn.notices:
                for n in conn.notices:
                    print(n.strip())
                del conn.notices[:]

        with conn.cursor() as cur:
            cur.execute("SELECT set_config('app.audit_enabled', 'true', false)")
        conn.commit()
    finally:
        conn.close()

    print("seed_all: all steps finished.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
