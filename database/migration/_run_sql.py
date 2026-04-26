import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

# Repo root = directory containing this script (so SQL paths do not depend on cwd).
_ROOT = Path(__file__).resolve().parent
load_dotenv(_ROOT / ".env", override=True)

conn = psycopg2.connect(
    host=os.getenv("SUPABASE_HOST"),
    port=int(os.getenv("SUPABASE_PORT", 5432)),
    dbname=os.getenv("SUPABASE_DB"),
    user=os.getenv("SUPABASE_USER"),
    password=os.getenv("SUPABASE_PASSWORD"),
    sslmode="require",
    connect_timeout=30,
)
conn.autocommit = False

rel = sys.argv[1]
sql_path = Path(rel)
if not sql_path.is_absolute():
    sql_path = (_ROOT / sql_path).resolve()

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
    print(f"FAILED: {e}")
finally:
    for n in conn.notices:
        print(n.strip())
    conn.close()
