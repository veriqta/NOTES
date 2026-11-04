import argparse,json,os
from pathlib import Path
from engineering.incident import IncidentStore
p=argparse.ArgumentParser();p.add_argument('action',choices=['claim','resolve','report']);p.add_argument('incident');p.add_argument('--runbook',default='diagnose-database');p.add_argument('--checks',type=Path);a=p.parse_args()
store=IncidentStore('.private/incidents.db')
if a.action=='claim':
    # This CLI must run in a protected operator environment. An arbitrary environment variable is not an identity provider.
    approved=os.environ.get('AUTHENTICATED_OPERATOR','')
    print('claimed' if store.claim(a.incident,a.runbook,approved) else 'already claimed; inspect execution before retrying')
elif a.action=='resolve':store.resolve(a.incident,json.loads(a.checks.read_text()))
else:print(json.dumps(store.report(a.incident),indent=2))
