import argparse,json
from pathlib import Path
from engineering import recovery,release,finops
p=argparse.ArgumentParser();p.add_argument('kind',choices=['recovery','release','finops']);p.add_argument('input',type=Path);a=p.parse_args()
data=json.loads(a.input.read_text())
result=recovery.decide(data['state'],data['observed']) if a.kind=='recovery' else release.decision(data) if a.kind=='release' else [finops.assess(row) for row in data]
print(json.dumps(result,indent=2))
