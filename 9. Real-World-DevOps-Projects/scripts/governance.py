import argparse,json,subprocess,re
from pathlib import Path
from engineering.governance import validate_exception
p=argparse.ArgumentParser();p.add_argument('plan',type=Path)
p.add_argument('--approval-repository',type=Path);p.add_argument('--approval-commit')
a=p.parse_args();plan=json.loads(a.plan.read_text())
result=subprocess.run(['opa','eval','--format=json','--data','policies/terraform.rego','--input',str(a.plan),'data.veriqta.terraform.violations'],capture_output=True,text=True,check=True)
findings=json.loads(result.stdout)['result'][0]['expressions'][0]['value']
if a.approval_repository:
    if not re.fullmatch('[a-f0-9]{40}',a.approval_commit or ''):raise SystemExit('Pin the trusted approval commit.')
    commit=subprocess.check_output(['git','-C',str(a.approval_repository),'rev-parse','HEAD'],text=True).strip()
    if commit!=a.approval_commit:raise SystemExit('Wrong approval checkout.')
    # Read committed objects, not a dirty working tree that untrusted code could have modified.
    def read(name):return json.loads(subprocess.check_output(['git','-C',str(a.approval_repository),'show',commit+':'+name],text=True))
    approvers=read('approvers.json');exceptions=read('approved.json')
    for e in exceptions:
        validate_exception(e,plan,approvers)
        findings=[f for f in findings if not (f['address']==e['resource'] and f['rule']==e['rule'])]
print(json.dumps(findings,indent=2));raise SystemExit(2 if findings else 0)
