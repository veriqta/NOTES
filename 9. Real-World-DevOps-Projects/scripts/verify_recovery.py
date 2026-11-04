import argparse,json,time,os
import psycopg
p=argparse.ArgumentParser();p.add_argument('--marker',required=True);a=p.parse_args()
primary=os.environ['PRIMARY_DATABASE_URL'];recovery=os.environ['RECOVERY_DATABASE_URL']
def snapshot(dsn):
    with psycopg.connect(dsn) as c:
        return {'orders':c.execute('SELECT id,amount_cents FROM orders ORDER BY id').fetchall(),
                'marker':c.execute('SELECT id,created_at FROM orders WHERE id=%s',(a.marker,)).fetchone(),
                'ledger':c.execute('SELECT idempotency_key,amount_cents FROM ledger ORDER BY idempotency_key').fetchall()}
a1,a2=snapshot(primary),snapshot(recovery)
if a1!=a2:raise SystemExit('Data differs: inspect writes after the backup and the measured data-loss window.')
if not a2['marker']:raise SystemExit('Required marker missing.')
print('Exact ordered business records and required marker match. Run a new write/read in the recovered application next.')
