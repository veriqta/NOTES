"""Normalize plans for review; exceptions must come from a separately trusted approval process."""
import datetime as dt,hashlib,json

def validate_exception(exception,plan,approvers,now=None):
    now=now or dt.datetime.now(dt.timezone.utc)
    expiry=dt.datetime.fromisoformat(exception['expires_at'])
    issued=dt.datetime.fromisoformat(exception['issued_at'])
    if issued.tzinfo is None or expiry.tzinfo is None:raise ValueError('timezone required')
    if not issued<=now<expiry or (expiry-issued).total_seconds()>259200:raise ValueError('exception expired or exceeds 72 hours')
    if exception['approver'] not in approvers or exception['approver']==exception['requester']:raise ValueError('independent trusted approver required')
    digest=hashlib.sha256(json.dumps(plan,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    if exception['plan_digest']!=digest:raise ValueError('approval is for a different plan')
    if not exception.get('ticket') or not exception.get('resource') or not exception.get('rule'):raise ValueError('exact scope and change ticket required')
    return True

def drift_direction(observed,desired):
    import ipaddress
    try:
        a,b=ipaddress.ip_network(observed),ipaddress.ip_network(desired)
        if a==b:return 'unchanged'
        if a.version!=b.version:return 'review'
        return 'widening' if a.subnet_of(b) else 'narrowing' if b.subnet_of(a) else 'review'
    except (ValueError,TypeError):return 'unknown'
