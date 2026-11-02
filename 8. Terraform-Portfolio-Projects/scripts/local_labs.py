"""Run real local-state migration and stale-plan experiments in temporary directories. No AWS."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[1]
TF=os.environ.get('TERRAFORM','terraform')
def run(d,*args,ok=True):
    r=subprocess.run([TF,*args,'-no-color'],cwd=d,capture_output=True,text=True)
    if ok and r.returncode:
        raise RuntimeError(r.stdout+r.stderr)
    return r
with tempfile.TemporaryDirectory(prefix='veriqta-labs-') as temp:
    d=Path(temp)/'migration';d.mkdir()
    shutil.copy(ROOT/'labs/module-migration/v1/main.tf',d/'main.tf')
    run(d,'init','-input=false');run(d,'apply','-auto-approve','-input=false')
    old=run(d,'output','-raw','database_identity').stdout
    shutil.copy(ROOT/'labs/module-migration/v2-broken/main.tf',d/'main.tf')
    run(d,'plan','-input=false','-out=broken.tfplan')
    import json
    broken=json.loads(run(d,'show','-json','broken.tfplan').stdout)
    assert any('delete' in r['change']['actions'] for r in broken['resource_changes'])
    print('PASS a missing moved block proposes deletion and creation')
    shutil.copy(ROOT/'labs/module-migration/v2-fixed/main.tf',d/'main.tf')
    run(d,'apply','-auto-approve','-input=false')
    assert run(d,'output','-raw','database_identity').stdout==old,'Migration replaced the object'
    print('PASS moved block preserves the existing resource ID')
    c=Path(temp)/'concurrency';c.mkdir()
    shutil.copy(ROOT/'labs/concurrency/main.tf',c/'main.tf')
    run(c,'init','-input=false');run(c,'apply','-auto-approve','-input=false')
    run(c,'plan','-input=false','-var=release=A','-out=a.tfplan')
    run(c,'plan','-input=false','-var=release=B','-out=b.tfplan')
    run(c,'apply','-input=false','a.tfplan')
    stale=run(c,'apply','-input=false','b.tfplan',ok=False)
    assert stale.returncode!=0 and 'stale' in (stale.stdout+stale.stderr).lower()
    print('PASS Terraform rejects a saved plan after the state changes')
