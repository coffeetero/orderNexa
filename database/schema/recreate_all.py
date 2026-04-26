#!/usr/bin/env python3
"""
Drop all foundation tables (bps_*, fnd_*), enum, and fnd_entity_id_seq, then
re-apply newTables DDL in dependency order.

Does not run dataMigration seeds.

Prerequisites: .env with SUPABASE_* (same as _run_sql.py).

Usage (from repo root):
  python newTables/recreate_all.py
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

DROP_SCRIPT = HERE / "recreate_all_drop.sql"

DDL_SCRIPTS: list[str] = [
    "fnd_entity_id_seq.sql",
    "fnd_customers.sql",
    "fnd_tenants.sql",
    "fnd_users.sql",
    "fnd_user_tenants.sql",
    "fnd_people.sql",
    "fnd_contact_points.sql",
    "fnd_user_customers.sql",
    "fnd_currencies.sql",
    "fnd_items.sql",
    "bps_items.sql",
    "fnd_pricebooks.sql",
    "fnd_customer_pricebooks.sql",
    "fnd_pricebook_items.sql",
    "om_orders.sql",
    "om_order_lines.sql",
    "om_order_shipments.sql",
    "ar_transactions.sql",
    "ar_transaction_lines.sql",
    "ar_payments.sql",
    "ar_payment_applications.sql",
    "fnd_item_bom.sql",
]


def main() -> int:
    host = os.getenv("SUPABASE_HOST")
    password = os.getenv("SUPABASE_PASSWORD")
    if not host or not password:
        print("Missing SUPABASE_HOST or SUPABASE_PASSWORD in .env", file=sys.stderr)
        return 1

    if not DROP_SCRIPT.is_file():
        print(f"Missing {DROP_SCRIPT}", file=sys.stderr)
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

    steps: list[tuple[str, Path]] = [("recreate_all_drop.sql", DROP_SCRIPT)]
    for name in DDL_SCRIPTS:
        p = HERE / name
        if not p.is_file():
            print(f"FAILED: missing {p}", file=sys.stderr)
            conn.close()
            return 1
        steps.append((name, p))

    try:
        for label, path in steps:
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
    finally:
        conn.close()

    print("recreate_all: drop + DDL finished.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
