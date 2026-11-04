"""Bounded faults against the local Compose lab only."""
import argparse,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('kind',choices=['db-lock','db-loss','restore-db']);a=p.parse_args()
base=['docker','compose','--env-file',str(ROOT/'.private/lab.env'),'-f',str(ROOT/'compose.yaml')]
if a.kind=='db-lock':
    subprocess.run(base+['exec','-T','primary','psql','-U','veriqta','-d','veriqta','-v','ON_ERROR_STOP=1','-c',"BEGIN; SELECT * FROM inventory WHERE id=1 FOR UPDATE; SELECT pg_sleep(20); ROLLBACK;"],check=True)
elif a.kind=='db-loss':subprocess.run(base+['stop','primary'],check=True)
else:subprocess.run(base+['start','primary'],check=True)
