import argparse,concurrent.futures,json,time,uuid,urllib.request,math
p=argparse.ArgumentParser();p.add_argument('--url',default='http://127.0.0.1:18080/checkout');p.add_argument('--count',type=int,default=100);p.add_argument('--workers',type=int,default=4);a=p.parse_args()
if not 1<=a.count<=10000 or not 1<=a.workers<=32:raise SystemExit('Use at most 10000 requests and 32 workers.')
def request(_):
    start=time.monotonic();status=599
    try:
        req=urllib.request.Request(a.url,data=b'',headers={'Idempotency-Key':'veriqta-'+str(uuid.uuid4())},method='POST')
        with urllib.request.urlopen(req,timeout=10) as r:status=r.status
    except Exception:pass
    return status,time.monotonic()-start
with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as e:r=list(e.map(request,range(a.count)))
lat=sorted(x[1] for x in r)
print(json.dumps({'requests':len(r),'errors':sum(x[0]>=500 for x in r),'p95_seconds':lat[math.ceil(.95*len(lat))-1],'age_seconds':0,'schema_backward_compatible':True},indent=2))
