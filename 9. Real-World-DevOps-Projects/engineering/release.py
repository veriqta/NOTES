import math

def decision(m):
    if m.get('schema_backward_compatible') is not True:return 'FORWARD_FIX_REQUIRED'
    required=('requests','errors','p95_seconds','age_seconds')
    if any(k not in m or not isinstance(m[k],(int,float)) or not math.isfinite(m[k]) for k in required):return 'PAUSE_NO_EVIDENCE'
    if m['requests']<100 or m['age_seconds']>120 or m['age_seconds']<0:return 'PAUSE_NO_EVIDENCE'
    if m['errors']<0 or m['errors']>m['requests'] or m['p95_seconds']<0:return 'PAUSE_NO_EVIDENCE'
    if m['errors']/m['requests']>0.01 or m['p95_seconds']>0.5:return 'ABORT_TO_STABLE'
    return 'PROMOTE'
