"""A bounded lab HTTP probe; reports measured successes and latency, without adding retries."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import math
import time
import urllib.request
p=argparse.ArgumentParser()
p.add_argument('url');p.add_argument('--requests',type=int,default=100);p.add_argument('--workers',type=int,default=4)
a=p.parse_args()
if not (1<=a.requests<=10000 and 1<=a.workers<=32):
    raise SystemExit('Use 1..10000 requests and 1..32 workers for this small lab probe.')
def request(_):
    start=time.perf_counter()
    try:
        with urllib.request.urlopen(a.url,timeout=10) as response:
            response.read(65536)
            success=response.status==200
    except Exception:
        success=False
    return success,(time.perf_counter()-start)*1000
with ThreadPoolExecutor(max_workers=a.workers) as pool:
    results=list(pool.map(request,range(a.requests)))
lat=sorted(r[1] for r in results);success=sum(r[0] for r in results)
print(f'requests={a.requests} successes={success} errors={a.requests-success}')
for percentile in (50,95,99):
    print(f'p{percentile}={lat[max(0,math.ceil(percentile/100*len(lat))-1)]:.2f}ms (all attempts)')
raise SystemExit(0 if success==a.requests else 1)
