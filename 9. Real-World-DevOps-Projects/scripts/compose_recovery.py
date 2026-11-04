"""Run an isolated local restore/new-write drill after compose_smoke.py; no AWS APIs."""
import json,os,subprocess,sys,time,urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
def run(*args,env=None):subprocess.run([sys.executable,*args],check=True,env=env)
password=dict(line.split('=',1) for line in (ROOT/'.private/lab.env').read_text().splitlines())['PGPASSWORD']
objects=ROOT/'.private/objects';objects.mkdir(exist_ok=True)
(objects/'veriqta-probe.txt').write_text('veriqta recovery object\n')
started=time.monotonic()
run('scripts/lab.py','stop','gateway','checkout','worker')
run('scripts/backup.py','backup','.private/ci-backup.fernet')
run('scripts/backup.py','restore','.private/ci-backup.fernet','--objects','.private/recovered-objects')
assert (ROOT/'.private/recovered-objects/veriqta-probe.txt').read_bytes()==(objects/'veriqta-probe.txt').read_bytes()
env=dict(os.environ,PRIMARY_DATABASE_URL=f'postgresql://veriqta:{password}@127.0.0.1:15432/veriqta',RECOVERY_DATABASE_URL=f'postgresql://veriqta:{password}@127.0.0.1:15433/veriqta')
run('scripts/verify_recovery.py','--marker','veriqta-smoke-0',env=env)
env.update(DATABASE_URL=env['RECOVERY_DATABASE_URL'],SERVICE_NAME='checkout',PAYMENT_URL='http://127.0.0.1:18082/pay',INVENTORY_URL='http://127.0.0.1:18083/reserve')
env.pop('OTEL_EXPORTER_OTLP_ENDPOINT',None)
with open(ROOT/'.private/recovered-api.log','wb') as log:
 process=subprocess.Popen([sys.executable,'-m','uvicorn','application.api:app','--host','127.0.0.1','--port','18084'],env=env,stdout=log,stderr=log)
 try:
  for attempt in range(30):
   try:
    with urllib.request.urlopen('http://127.0.0.1:18084/readyz',timeout=2) as r:
     if r.status==200:break
   except Exception:time.sleep(1)
  else:raise RuntimeError('Recovered application never became ready')
  req=urllib.request.Request('http://127.0.0.1:18084/checkout',data=b'',method='POST',headers={'Idempotency-Key':'veriqta-recovered-new-write'})
  with urllib.request.urlopen(req,timeout=10) as r:assert json.load(r)['status']=='accepted'
 finally:
  process.terminate();process.wait(timeout=20)
print(json.dumps({'local_exercise_seconds':round(time.monotonic()-started,2),'data':'frozen source records and object match','recovered_application':'new checkout accepted','note':'Restart gateway/checkout/worker deliberately after the drill.'}))
