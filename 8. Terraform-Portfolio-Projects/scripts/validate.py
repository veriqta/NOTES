"""Credential-free checks. Install Terraform 1.13.5 and Python 3.11+ first."""
import os
from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[1]
TF=os.environ.get('TERRAFORM','terraform')
cache=Path(os.environ.get('TF_PLUGIN_CACHE_DIR',str(Path.home()/'.cache/veriqta/terraform/providers'))).expanduser()
cache.mkdir(parents=True,exist_ok=True)
os.environ['TF_PLUGIN_CACHE_DIR']=str(cache)
def run(args,cwd=ROOT):
    subprocess.run(args,cwd=cwd,check=True)
run([TF,'fmt','-recursive','-check'])
roots=sorted({p.parent for p in ROOT.rglob('*.tf') if '.terraform' not in p.parts})
for root in roots:
    run([TF,'init','-backend=false','-input=false','-no-color'],root)
    run([TF,'validate','-no-color'],root)
    if (root/'tests').exists() and list((root/'tests').glob('*.tftest.hcl')):
        run([TF,'test','-no-color'],root)
run(['python3','-m','unittest','discover','-s','tests','-v'])
run(['python3','scripts/local_labs.py'])
print(f'Validated {len(roots)} Terraform directories; no AWS deployment commands were run.')
