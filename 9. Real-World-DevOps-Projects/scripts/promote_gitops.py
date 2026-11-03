import argparse,re
from pathlib import Path
import yaml
p=argparse.ArgumentParser();p.add_argument('manifest',type=Path);p.add_argument('image');p.add_argument('commit');a=p.parse_args()
if not re.fullmatch(r'[^\s]+@sha256:[a-f0-9]{64}',a.image):raise SystemExit('Immutable image required.')
if not re.fullmatch('[a-f0-9]{40}',a.commit):raise SystemExit('Exact commit required.')
d=yaml.safe_load(a.manifest.read_text())
if d.get('kind')!='Deployment' or d.get('metadata',{}).get('name')!='checkout':raise SystemExit('Only the approved checkout Deployment may be changed.')
containers=d['spec']['template']['spec']['containers']
if len(containers)!=1 or containers[0]['name']!='checkout':raise SystemExit('Unexpected workload contract; review manually.')
containers[0]['image']=a.image
for e in containers[0].get('env',[]):
    if e['name']=='RELEASE':e.clear();e.update({'name':'RELEASE','value':a.commit})
a.manifest.write_text(yaml.safe_dump(d,sort_keys=False))
