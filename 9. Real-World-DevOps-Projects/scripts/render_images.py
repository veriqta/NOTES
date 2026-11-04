"""Render only local files. This script never contacts a Kubernetes API or registry."""
import argparse,copy,json,re
from pathlib import Path
import yaml
p=argparse.ArgumentParser();p.add_argument('--directory',type=Path,required=True);p.add_argument('--image',required=True);p.add_argument('--migration',action='store_true');a=p.parse_args()
if not re.fullmatch(r'[^\s]+@sha256:[a-f0-9]{64}',a.image):raise SystemExit('Supply the full reviewed image digest.')
checkout=None
for path in a.directory.glob('*.yaml'):
    data=yaml.safe_load(path.read_text())
    if not isinstance(data,dict) or data.get('kind') not in ('Deployment','Rollout'):continue
    for c in data['spec']['template']['spec']['containers']:c['image']=a.image
    if data['metadata']['name']=='checkout':checkout=copy.deepcopy(data['spec']['template'])
    path.write_text(yaml.safe_dump(data,sort_keys=False))
if a.migration:
    if checkout is None:raise SystemExit('Checkout template missing.')
    checkout['metadata']['labels']={'app':'veriqta-schema'}
    checkout['spec'].pop('topologySpreadConstraints',None)
    checkout['spec']['restartPolicy']='Never'
    c=checkout['spec']['containers'][0];c['command']=['python','-c','from application.db import initialize; initialize()']
    for field in ('readinessProbe','livenessProbe','ports'):c.pop(field,None)
    job={'apiVersion':'batch/v1','kind':'Job','metadata':{'name':'veriqta-schema','namespace':'veriqta'},'spec':{'backoffLimit':1,'template':checkout}}
    Path('.private').mkdir(exist_ok=True)
    Path('.private/migration-job.json').write_text(json.dumps(job,indent=2))
