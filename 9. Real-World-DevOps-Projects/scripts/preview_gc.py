"""Identify only rendered, expired preview requests. Print commands; never delete on a clock alone."""
import argparse,datetime as dt,json,shlex
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('directory',type=Path);a=p.parse_args()
for f in a.directory.glob('veriqta-*/request.json'):
    r=json.loads(f.read_text())
    if r.get('environment')!='preview':continue
    expiry=dt.datetime.fromisoformat(r['expires_at'])
    if expiry.tzinfo and expiry<dt.datetime.now(dt.timezone.utc):
        print('REVIEW expired preview:',r['name'],'owner:',r['owner'])
        print('kubectl --context YOUR-EXPLICIT-LAB-CONTEXT delete namespace '+shlex.quote(r['name']))
