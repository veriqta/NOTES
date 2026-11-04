"""Promote only within the SAME authoritative PostgreSQL ledger. Never use this to authorize two independent databases."""
import argparse,os,psycopg
from application.ledger import promote
p=argparse.ArgumentParser();p.add_argument('--from-owner',required=True);p.add_argument('--from-epoch',type=int,required=True);p.add_argument('--to-owner',required=True);a=p.parse_args()
if not os.environ.get('DATABASE_URL'):raise SystemExit('Set the intended authoritative database connection explicitly.')
with psycopg.connect(os.environ['DATABASE_URL']) as c:epoch=promote(c,a.from_owner,a.from_epoch,a.to_owner)
print('New epoch:',epoch,'; update the approved writer configuration and verify old-writer rejection.')
