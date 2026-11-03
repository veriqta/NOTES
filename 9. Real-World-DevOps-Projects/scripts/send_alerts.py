import argparse,json,os,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:18086');a=p.parse_args()
for event in json.loads((Path(__file__).resolve().parents[1]/'projects/10-incident-command/alerts.json').read_text()):
    req=urllib.request.Request(a.url.rstrip('/')+'/alerts',data=json.dumps(event).encode(),headers={'Content-Type':'application/json','Authorization':'Bearer '+os.environ['INCIDENT_API_TOKEN']},method='POST')
    with urllib.request.urlopen(req,timeout=5) as r:print(json.load(r))
