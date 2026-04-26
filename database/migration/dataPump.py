"""
Sync SQL Anywhere tables → Supabase (PostgreSQL).

- Reads each table from SQL Anywhere via a 32-bit ODBC DSN (run with 32-bit
  Python) or a 64-bit DSN (64-bit Python).
- Drops each destination table in Supabase if it exists (CASCADE), then creates it
  fresh, inferring column types from the ODBC cursor metadata.
- Loads data with PostgreSQL COPY (text protocol) — the fastest bulk-insert
  path available via psycopg2.

Usage:
    python dataPump.py [options]              # DSN defaults to alpineDev
    python dataPump.py --dsn <DSN_NAME> [options]
    python dataPump.py --transactions-since 2025-01-01   # DSN defaults to alpineDev unless DATA_PUMP_DSN is set

Supabase credentials (CLI flags or environment variables / .env file):
    --pg-host       SUPABASE_HOST      e.g. db.xxxx.supabase.co
    --pg-port       SUPABASE_PORT      default 5432
    --pg-db         SUPABASE_DB        default postgres
    --pg-user       SUPABASE_USER      default postgres
    --pg-password   SUPABASE_PASSWORD

Additional options:
    --schema               Destination PostgreSQL schema (default: public)
    --tables               Comma-separated list of tables to sync (default: see DEFAULT_TABLES)
    --transactions-since   YYYY-MM-DD (required if the sync includes ordr, ordr_detail, ar, or pmt_detail):
                               ordr: date filter AND COALESCE(ordr_amt,0) <> 0
                               ordr_detail: lines for those orders; only if sold and returned qty both <> 0
                               ar: ar_trn_date >= date
                               pmt_detail: rows whose ar row (pd_ar_trn_id) has ar_trn_date >= date
    --orders-since         Deprecated alias for --transactions-since.

Requirements:
    pip install pyodbc psycopg2-binary python-dotenv
"""

import argparse
import datetime
import decimal
import io
import logging
import os
import sys

import psycopg2
import psycopg2.extensions
import pyodbc
from dotenv import load_dotenv

load_dotenv()

# ---------------------------------------------------------------------------
# Tables to sync
# ---------------------------------------------------------------------------
# Default: reference data first, then order / AR transactional tables (--tables overrides).
DEFAULT_TABLES = [
    "customer",
    "item",
    "item_price",
    "citem",
    "route",
    "route_stop",
    "box",
    "ordr",
    "ordr_detail",
    "ar",
    "pmt_detail",
]

# Tables that require --transactions-since (date-filtered SELECTs).
TRANSACTIONAL_TABLES = frozenset({"ordr", "ordr_detail", "ar", "pmt_detail"})

# Rows fetched from SQL Anywhere per batch
FETCH_BATCH = 5_000
# Rows accumulated before each COPY flush to Supabase
COPY_FLUSH_ROWS = 20_000

# ODBC DSN when --dsn omitted and DATA_PUMP_DSN is unset / empty.
DEFAULT_ODBC_DSN = "alpineDev"

# ---------------------------------------------------------------------------
# ODBC Python type  →  PostgreSQL DDL type
# ---------------------------------------------------------------------------
_ODBC_TYPE_MAP: dict[type, str] = {
    str: "TEXT",
    int: "BIGINT",
    float: "DOUBLE PRECISION",
    bytes: "BYTEA",
    datetime.datetime: "TIMESTAMP WITHOUT TIME ZONE",
    datetime.date: "DATE",
    datetime.time: "TIME WITHOUT TIME ZONE",
    decimal.Decimal: "NUMERIC",
    bool: "BOOLEAN",
}

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync SQL Anywhere tables to Supabase via ODBC + psycopg2 COPY."
    )
    parser.add_argument(
        "--dsn",
        default=(os.getenv("DATA_PUMP_DSN") or "").strip() or DEFAULT_ODBC_DSN,
        help=(
            f"SQL Anywhere ODBC DSN name (default: {DEFAULT_ODBC_DSN}; "
            "override with DATA_PUMP_DSN in .env)."
        ),
    )
    parser.add_argument(
        "--pg-host",
        default=os.getenv("SUPABASE_HOST", ""),
        help="Supabase host (env: SUPABASE_HOST).",
    )
    parser.add_argument(
        "--pg-port",
        type=int,
        default=int(os.getenv("SUPABASE_PORT", "5432")),
        help="PostgreSQL port (env: SUPABASE_PORT, default 5432).",
    )
    parser.add_argument(
        "--pg-db",
        default=os.getenv("SUPABASE_DB", "postgres"),
        help="PostgreSQL database (env: SUPABASE_DB, default postgres).",
    )
    parser.add_argument(
        "--pg-user",
        default=os.getenv("SUPABASE_USER", "postgres"),
        help="PostgreSQL user (env: SUPABASE_USER, default postgres).",
    )
    parser.add_argument(
        "--pg-password",
        default=os.getenv("SUPABASE_PASSWORD", ""),
        help="PostgreSQL password (env: SUPABASE_PASSWORD).",
    )
    parser.add_argument(
        "--schema",
        default="public",
        help="Destination PostgreSQL schema (default: public).",
    )
    parser.add_argument(
        "--tables",
        default="",
        help="Comma-separated list of tables to sync (default: DEFAULT_TABLES in dataPump.py).",
    )
    parser.add_argument(
        "--transactions-since",
        "--orders-since",
        default="",
        dest="transactions_since",
        metavar="YYYY-MM-DD",
        help=(
            "Include rows on or after this date (required for ordr, ordr_detail, ar, pmt_detail). "
            "See module docstring."
        ),
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Connections
# ---------------------------------------------------------------------------
def connect_sqlanywhere(dsn: str) -> pyodbc.Connection:
    log.info("Connecting to SQL Anywhere via DSN '%s' ...", dsn)
    conn = pyodbc.connect(f"DSN={dsn}", autocommit=True)
    log.info("SQL Anywhere connected.")
    return conn


def connect_supabase(args: argparse.Namespace) -> psycopg2.extensions.connection:
    if not args.pg_host:
        log.error(
            "Supabase host not specified. Use --pg-host or set SUPABASE_HOST."
        )
        sys.exit(1)
    if not args.pg_password:
        log.error(
            "Supabase password not specified. Use --pg-password or set SUPABASE_PASSWORD."
        )
        sys.exit(1)
    log.info("Connecting to Supabase at %s:%s/%s ...", args.pg_host, args.pg_port, args.pg_db)
    conn = psycopg2.connect(
        host=args.pg_host,
        port=args.pg_port,
        dbname=args.pg_db,
        user=args.pg_user,
        password=args.pg_password,
        connect_timeout=30,
        sslmode="require",
    )
    conn.autocommit = False
    log.info("Supabase connected.")
    return conn


# ---------------------------------------------------------------------------
# Schema helpers
# ---------------------------------------------------------------------------
def _pg_type(odbc_type: type | None) -> str:
    """Map a pyodbc column type to a PostgreSQL DDL type string."""
    if odbc_type is None:
        return "TEXT"
    return _ODBC_TYPE_MAP.get(odbc_type, "TEXT")


def drop_legacy_table(
    pg_conn: psycopg2.extensions.connection,
    schema: str,
    table: str,
) -> None:
    """Remove a prior pumped copy so the destination can be recreated with current ODBC types."""
    with pg_conn.cursor() as cur:
        cur.execute(f'DROP TABLE IF EXISTS "{schema}"."{table}" CASCADE')
    pg_conn.commit()
    log.info("  Dropped existing '%s.%s' (if any).", schema, table)


def ensure_table(
    pg_conn: psycopg2.extensions.connection,
    schema: str,
    table: str,
    columns: list[tuple[str, str]],
) -> None:
    """Create *schema.table* (caller must drop first if replacing)."""
    col_defs = ",\n    ".join(f'"{col}" {dtype}' for col, dtype in columns)
    ddl = f'CREATE TABLE "{schema}"."{table}" (\n    {col_defs}\n);'
    with pg_conn.cursor() as cur:
        cur.execute(ddl)
    pg_conn.commit()
    log.info("  Table '%s.%s' is ready.", schema, table)


# ---------------------------------------------------------------------------
# COPY bulk-insert (PostgreSQL text protocol)
# ---------------------------------------------------------------------------
def _escape_text(value: object) -> str:
    """
    Encode a Python value as a PostgreSQL COPY text-format field.

    Rules (https://www.postgresql.org/docs/current/sql-copy.html):
      NULL  → \\N  (backslash-N, unquoted)
      \\    → \\\\
      \\n   → \\n
      \\r   → \\r
      \\t   → \\t
    """
    if value is None:
        return "\\N"
    s = str(value)
    s = s.replace("\\", "\\\\")
    s = s.replace("\n", "\\n")
    s = s.replace("\r", "\\r")
    s = s.replace("\t", "\\t")
    return s


def _flush_copy(
    pg_conn: psycopg2.extensions.connection,
    schema: str,
    table: str,
    col_names: list[str],
    buffer: list[list[object]],
) -> None:
    """Write *buffer* to Supabase using a single COPY command."""
    if not buffer:
        return

    cols_sql = ", ".join(f'"{c}"' for c in col_names)
    copy_sql = f'COPY "{schema}"."{table}" ({cols_sql}) FROM STDIN'

    buf = io.StringIO()
    for row in buffer:
        buf.write("\t".join(_escape_text(v) for v in row))
        buf.write("\n")
    buf.seek(0)

    with pg_conn.cursor() as cur:
        cur.copy_expert(copy_sql, buf)
    pg_conn.commit()


# ---------------------------------------------------------------------------
# Per-table sync
# ---------------------------------------------------------------------------
def _select_sql_for_table(table: str, since: datetime.date | None) -> tuple[str, tuple]:
    """
    Build SQL Anywhere SELECT and parameters.

    Order date filter uses COALESCE(ordr_dt, ordr_prdctn_dt): ordr_dt is the logical
    order date, but some rows only have ordr_prdctn_dt.

    ordr: exclude zero COALESCE(ordr_amt, 0). ordr_detail: include only if
    COALESCE(od_qty_returned,0) <> 0 AND COALESCE(od_qty_sold,0) <> 0 (per legacy
    column names); parent orders must also pass the ordr amount filter via ordr_no.

    AR uses ar_trn_date. pmt_detail is filtered via join to ar on pd_ar_trn_id.

    Other tables (e.g. customer, item, route) use SELECT * even when *since* is set.
    """
    if table == "ordr":
        amt = "COALESCE(ordr_amt, 0) <> 0"
        if since is not None:
            return (
                "SELECT * FROM ordr WHERE COALESCE(ordr_dt, ordr_prdctn_dt) >= ? "
                f"AND {amt}",
                (since,),
            )
        return (f"SELECT * FROM ordr WHERE {amt}", ())

    if table == "ordr_detail":
        qty = (
            "COALESCE(od.od_qty_sold, 0) <> 0"
        )
        parent_amt = "COALESCE(o.ordr_amt, 0) <> 0"
        if since is not None:
            return (
                "SELECT od.* FROM ordr_detail AS od "
                "WHERE od.ordr_no IN ("
                "SELECT o.ordr_no FROM ordr AS o "
                "WHERE COALESCE(o.ordr_dt, o.ordr_prdctn_dt) >= ? "
                f"AND {parent_amt}"
                ") "
                f"AND {qty}",
                (since,),
            )
        return (
            "SELECT od.* FROM ordr_detail AS od "
            "WHERE od.ordr_no IN ("
            "SELECT o.ordr_no FROM ordr AS o "
            f"WHERE {parent_amt}"
            ") "
            f"AND {qty}",
            (),
        )

    if since is None:
        return (f"SELECT * FROM {table}", ())

    if table == "ar":
        return (
            "SELECT * FROM ar WHERE ar_trn_date >= ?",
            (since,),
        )
    if table == "pmt_detail":
        return (
            "SELECT pd.* FROM pmt_detail AS pd "
            "INNER JOIN ar AS a ON a.ar_trn_id = pd.pd_ar_trn_id "
            "WHERE a.ar_trn_date >= ?",
            (since,),
        )
    return (f"SELECT * FROM {table}", ())


def sync_table(
    sa_conn: pyodbc.Connection,
    pg_conn: psycopg2.extensions.connection,
    table: str,
    schema: str,
    transactions_since: datetime.date | None = None,
) -> tuple[bool, int]:
    """
    Sync one table from SQL Anywhere → Supabase.
    Returns (success, row_count).
    """
    try:
        cur = sa_conn.cursor()
        sql, params = _select_sql_for_table(table, transactions_since)
        if transactions_since is not None and table in TRANSACTIONAL_TABLES:
            log.info(
                "Reading '%s' from SQL Anywhere (transactions since %s) ...",
                table,
                transactions_since.isoformat(),
            )
        else:
            log.info("Reading '%s' from SQL Anywhere ...", table)
        cur.execute(sql, params)

        col_names: list[str] = [d[0] for d in cur.description]
        col_types: list[str] = [_pg_type(d[1]) for d in cur.description]
        columns = list(zip(col_names, col_types))

        drop_legacy_table(pg_conn, schema, table)
        ensure_table(pg_conn, schema, table, columns)

        row_count = 0
        copy_buffer: list[list[object]] = []

        while True:
            batch = cur.fetchmany(FETCH_BATCH)
            if not batch:
                break
            copy_buffer.extend(list(row) for row in batch)
            row_count += len(batch)

            if len(copy_buffer) >= COPY_FLUSH_ROWS:
                _flush_copy(pg_conn, schema, table, col_names, copy_buffer)
                log.info("  ... %d rows copied so far", row_count)
                copy_buffer.clear()

        # Final flush
        _flush_copy(pg_conn, schema, table, col_names, copy_buffer)
        cur.close()

        log.info("  '%s' → '%s.%s'  (%d rows)", table, schema, table, row_count)
        return True, row_count

    except Exception as exc:  # noqa: BLE001
        log.error("  FAILED to sync '%s': %s", table, exc)
        try:
            pg_conn.rollback()
        except Exception:  # noqa: BLE001
            pass
        return False, 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main() -> int:
    args = parse_args()

    tables = (
        [t.strip() for t in args.tables.split(",") if t.strip()]
        if args.tables
        else DEFAULT_TABLES
    )

    transactions_since: datetime.date | None = None
    if args.transactions_since:
        try:
            transactions_since = datetime.date.fromisoformat(args.transactions_since.strip())
        except ValueError:
            log.error(
                "Invalid --transactions-since %r; use YYYY-MM-DD (e.g. 2025-06-01).",
                args.transactions_since,
            )
            return 1

    tables_set = set(tables)
    if tables_set & TRANSACTIONAL_TABLES and transactions_since is None:
        log.error(
            "--transactions-since YYYY-MM-DD is required when syncing any of: %s",
            ", ".join(sorted(TRANSACTIONAL_TABLES)),
        )
        return 1

    try:
        sa_conn = connect_sqlanywhere(args.dsn)
    except Exception as exc:  # noqa: BLE001
        log.error("SQL Anywhere connection failed: %s", exc)
        return 1

    try:
        pg_conn = connect_supabase(args)
    except Exception as exc:  # noqa: BLE001
        log.error("Supabase connection failed: %s", exc)
        return 1

    failed: list[str] = []
    total_rows = 0

    for table in tables:
        success, row_count = sync_table(
            sa_conn,
            pg_conn,
            table,
            args.schema,
            transactions_since=transactions_since,
        )
        if success:
            total_rows += row_count
        else:
            failed.append(table)

    for conn in (sa_conn, pg_conn):
        try:
            conn.close()
        except Exception:  # noqa: BLE001
            pass

    log.info("---")
    log.info(
        "Sync complete. %d/%d table(s) synced, %d row(s) total.",
        len(tables) - len(failed),
        len(tables),
        total_rows,
    )
    if failed:
        log.warning("Failed tables: %s", ", ".join(failed))
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
