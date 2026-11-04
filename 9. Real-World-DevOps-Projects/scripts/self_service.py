import argparse,json
from pathlib import Path
from engineering.platform import render
p=argparse.ArgumentParser();p.add_argument('request',type=Path);p.add_argument('--output',type=Path,default=Path('artifacts/generated'));a=p.parse_args()
print(render(json.loads(a.request.read_text()),a.output))
