import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

# Repo root = directory containing this script (so SQL paths do not depend on cwd).
_ROOT = Path(__file__).resolve().parent
_REPO_ROOT = _ROOT.parent.parent
# migration/.env first for local overrides; repo root .env wins so empty keys in migration do not erase secrets.
load_dotenv(_ROOT / ".env", override=False)
load_dotenv(_REPO_ROOT / ".env", override=True)

# Required in .env. Optional: SUPABASE_SSLMODE (default require), SUPABASE_CONNECT_TIMEOUT (default 30).
_REQUIRED_ENV = (
    "SUPABASE_HOST",
    "SUPABASE_PORT",
    "SUPABASE_DATABASE",
    "SUPABASE_SEARCH_PATH",
    "SUPABASE_USER",
    "SUPABASE_PASSWORD",
)


def _env_nonempty(name: str) -> bool:
    v = os.getenv(name)
    return v is not None and str(v).strip() != ""

missing = [k for k in _REQUIRED_ENV if not _env_nonempty(k)]
if missing:
    print(
        "Missing or empty required environment variables:\n  "
        + "\n  ".join(missing)
        + "\n\n"
        "Add them to your .env file(s). This script loads, in order:\n"
        f"  1) {_ROOT / '.env'}\n"
        f"  2) {_REPO_ROOT / '.env'}  (overrides duplicate keys from step 1)\n\n"
        "Set required values explicitly, for example:\n"
        "  SUPABASE_HOST=<pooler or db host>\n"
        "  SUPABASE_PORT=<port>\n"
        "  SUPABASE_DATABASE=<database name>\n"
        "  SUPABASE_SEARCH_PATH=<comma-separated schemas, e.g. bps,public>\n"
        "  SUPABASE_USER=<db user>\n"
        "  SUPABASE_PASSWORD=<db password>\n"
        "\n"
        "Optional (defaults if unset or blank):\n"
        "  SUPABASE_SSLMODE=require\n"
        "  SUPABASE_CONNECT_TIMEOUT=30\n",
        file=sys.stderr,
    )
    sys.exit(1)

if len(sys.argv) < 2:
    print(
        "Usage: python _run_sql.py <path-to.sql>\n"
        "\n"
        "Examples (from this directory):\n"
        "  python _run_sql.py ../schema/fnd_contacts.sql\n"
        "\n"
        "<path-to.sql> may be absolute, or relative to this script's directory "
        f"({_ROOT}).",
        file=sys.stderr,
    )
    sys.exit(1)


def _must(name: str) -> str:
    return os.environ[name].strip()


rel = sys.argv[1]
sql_path = Path(rel)
if not sql_path.is_absolute():
    sql_path = (_ROOT / sql_path).resolve()

if not sql_path.is_file():
    print(f"No such file: {sql_path}", file=sys.stderr)
    sys.exit(1)

host = _must("SUPABASE_HOST")
port = int(_must("SUPABASE_PORT"))
dbname = _must("SUPABASE_DATABASE")
password = _must("SUPABASE_PASSWORD")
user = _must("SUPABASE_USER")
search_path = _must("SUPABASE_SEARCH_PATH")

_ssl = os.getenv("SUPABASE_SSLMODE")
sslmode = _ssl.strip() if _ssl and _ssl.strip() else "require"

_ct = os.getenv("SUPABASE_CONNECT_TIMEOUT")
connect_timeout = int(_ct.strip()) if _ct and _ct.strip() else 30

_connect_kw = dict(
    host=host,
    port=port,
    dbname=dbname,
    user=user,
    password=password,
    sslmode=sslmode,
    connect_timeout=connect_timeout,
    options=f"-c search_path={search_path}",
)

conn = psycopg2.connect(**_connect_kw)
conn.autocommit = False

print(f"EXECUTING: {sql_path}", file=sys.stderr)

with open(sql_path, encoding="utf-8") as f:
    sql = f.read()
try:
    with conn.cursor() as cur:
        cur.execute(sql)
    conn.commit()
    print(f"SUCCESS: {sql_path}")
except Exception as e:
    conn.rollback()
    print(f"FAILED: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    for n in conn.notices:
        print(n.strip())
    conn.close()
