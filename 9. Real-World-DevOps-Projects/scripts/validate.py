"""Run credential-free validation. Terraform mocks replace AWS providers in all .tftest.hcl files."""
import ast,json,os,subprocess,sys
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
for p in ROOT.rglob('*.py'):
 if not any(x in p.parts for x in ('.venv','.terraform','__pycache__','.private','artifacts')):ast.parse(p.read_text(),filename=str(p))
for p in [*ROOT.rglob('*.yaml'),*ROOT.rglob('*.yml')]:
 if not any(x in p.parts for x in ('.terraform','.private','artifacts')):list(yaml.safe_load_all(p.read_text()))
subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-v'],check=True)
cache=Path(os.environ.get('TF_PLUGIN_CACHE_DIR',str(Path.home()/'.cache/veriqta/terraform/providers')));cache.mkdir(parents=True,exist_ok=True)
os.environ['TF_PLUGIN_CACHE_DIR']=str(cache)
tf=os.environ.get('TERRAFORM','terraform')
subprocess.run([tf,'fmt','-recursive','-check','infrastructure'],check=True)
for root in sorted({p.parent for p in (ROOT/'infrastructure').rglob('*.tf') if '.terraform' not in p.parts}):
 for args in [['init','-backend=false','-input=false','-no-color'],['validate','-no-color']]:subprocess.run([tf,*args],cwd=root,check=True)
 if (root/'tests').exists():subprocess.run([tf,'test','-no-color'],cwd=root,check=True)
print('Credential-free checks passed. Cloud authorization, deployment and recovery still require the explicit live exercises.')
