import psycopg2, sys
from dotenv import load_dotenv
import os

load_dotenv(r'D:\Dev\bpsWeb\.env', override=True)
conn = psycopg2.connect(
    host=os.getenv('SUPABASE_HOST'), port=int(os.getenv('SUPABASE_PORT', 5432)),
    dbname=os.getenv('SUPABASE_DB'), user=os.getenv('SUPABASE_USER'),
    password=os.getenv('SUPABASE_PASSWORD'), sslmode='require', connect_timeout=30
)
sql = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read()
with conn.cursor() as cur:
    cur.execute(sql)
    if cur.description:
        cols = [d[0] for d in cur.description]
        print('\t'.join(cols))
        print('-' * 80)
        for row in cur.fetchall():
            print('\t'.join('' if v is None else str(v) for v in row))
conn.close()
