"""Exercise only the local Compose API. Exit nonzero on a broken application path."""
import json,time,urllib.request
from pathlib import Path
for attempt in range(60):
 try:
  with urllib.request.urlopen('http://127.0.0.1:18080/readyz',timeout=2) as r:
   if r.status==200:break
 except Exception:time.sleep(2)
else:raise SystemExit('Local API never became ready')
for i in range(5):
 req=urllib.request.Request('http://127.0.0.1:18080/checkout',data=b'',method='POST',headers={'Idempotency-Key':'veriqta-smoke-'+str(i)})
 with urllib.request.urlopen(req,timeout=10) as r:
  assert json.load(r)['status']=='accepted'
print('Local gateway -> checkout -> payment/inventory -> PostgreSQL path passed.')
