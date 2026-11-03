"""Local self-service renderer. No cloud credentials or repository-write token required."""
import json,re,os,tempfile,shutil
from pathlib import Path

def render(request,destination):
    allowed={'name','owner','environment','cpu_millicores','memory_mib','expires_at'}
    if set(request)-allowed:raise ValueError('unknown or privileged fields are not accepted')
    name=request.get('name','')
    if not re.fullmatch(r'veriqta-[a-z][a-z0-9-]{1,30}',name):raise ValueError('use a veriqta- service name')
    if request.get('owner') not in ('group:default/veriqta-platform','group:default/veriqta-payments'):raise ValueError('approved owner required')
    if request.get('environment') not in ('dev','preview'):raise ValueError('self-service production is not enabled')
    if not 50<=request.get('cpu_millicores',0)<=1000 or not 64<=request.get('memory_mib',0)<=1024:raise ValueError('resource quota exceeded')
    if request['environment']=='preview':
        import datetime as dt
        expiry=dt.datetime.fromisoformat(request.get('expires_at',''))
        if expiry.tzinfo is None or not 0<(expiry-dt.datetime.now(dt.timezone.utc)).total_seconds()<=172800:raise ValueError('preview expiry must be within 48 hours')
    destination=Path(destination).resolve();destination.mkdir(parents=True,exist_ok=True)
    target=destination/name
    if target.exists():
        if json.loads((target/'request.json').read_text())==request:return target
        raise ValueError('same service name has different inputs; use a reviewed update')
    temp=Path(tempfile.mkdtemp(prefix='.pending-',dir=destination))
    try:
        (temp/'request.json').write_text(json.dumps(request,sort_keys=True,indent=2))
        (temp/'catalog-info.yaml').write_text(json.dumps({'apiVersion':'backstage.io/v1alpha1','kind':'Component','metadata':{'name':name},'spec':{'type':'service','lifecycle':'experimental','owner':request['owner']}}))
        namespace={'apiVersion':'v1','kind':'Namespace','metadata':{'name':name,'labels':{'owner':'veriqta','environment':request['environment'],'pod-security.kubernetes.io/enforce':'restricted'}}}
        (temp/'namespace.yaml').write_text(json.dumps(namespace,indent=2))
        quota={'apiVersion':'v1','kind':'ResourceQuota','metadata':{'name':'service-budget','namespace':name},'spec':{'hard':{'requests.cpu':'1000m','requests.memory':'1Gi','limits.cpu':'2000m','limits.memory':'2Gi','pods':'10'}}}
        (temp/'quota.yaml').write_text(json.dumps(quota,indent=2))
        (temp/'README.md').write_text('# '+name+'\n\nOwner: '+request['owner']+'\n\nSubmit namespace/quota manifests to the protected GitOps repository. Provisioning and deployment remain controlled by its policies.\n')
        os.rename(temp,target)
    except BaseException:
        shutil.rmtree(temp,ignore_errors=True);raise
    return target
