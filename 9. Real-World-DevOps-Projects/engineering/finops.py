"""Recommend only. Missing evidence rejects an action rather than treating missing usage as idle."""
from decimal import Decimal

def assess(row):
    import math
    reasons=[]
    for tag in ('owner','application','environment'):
        if not row.get(tag):reasons.append('missing '+tag)
    if row.get('observation_days',0)<14:reasons.append('insufficient observation window')
    if row.get('telemetry_age_minutes',9999)>60:reasons.append('stale telemetry')
    if row.get('critical_database',True):reasons.append('critical database requires an independent migration review')
    if row.get('standby_required',True):reasons.append('required recovery capacity')
    if row.get('remaining_peak_capacity',0)<row.get('required_peak_capacity',1):reasons.append('insufficient surviving capacity')
    for metric in ('p95_seconds','error_rate','rto_seconds','rpo_seconds'):
        values=(row.get(metric),row.get(metric+'_limit'))
        if any(type(v) not in (int,float) or not math.isfinite(v) or v<0 for v in values) or values[0]>values[1]:reasons.append('unproven '+metric)
    savings=Decimal(str(row.get('estimated_monthly_savings',0)))
    if not savings.is_finite() or savings<=0:reasons.append('no valid positive saving')
    if not row.get('rollback'):reasons.append('missing rollback')
    return {'resource':row.get('resource','unknown'),'owner':row.get('owner','unassigned'),
            'decision':'REJECT' if reasons else 'RECOMMEND_REVIEW','reasons':reasons,
            'estimated_monthly_savings':str(savings),'currency':row.get('currency','UNSPECIFIED')}
