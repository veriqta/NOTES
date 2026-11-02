"""Run inside an application instance: write a marker before an exercise, verify after restoration."""
import argparse
from app import connect
p = argparse.ArgumentParser()
p.add_argument('action', choices=['write', 'read'])
p.add_argument('marker')
a = p.parse_args()
with connect() as conn, conn.cursor() as cur:
    if a.action == 'write':
        cur.execute('CREATE TABLE IF NOT EXISTS recovery_markers (id text PRIMARY KEY, written_at timestamptz DEFAULT now())')
        cur.execute('INSERT INTO recovery_markers (id) VALUES (%s) ON CONFLICT DO NOTHING', (a.marker,))
    cur.execute('SELECT id, written_at FROM recovery_markers WHERE id=%s', (a.marker,))
    row = cur.fetchone()
    if row is None:
        raise SystemExit('Marker absent: record the resulting data-loss window; do not claim zero RPO.')
    print(row[0], row[1].isoformat())
