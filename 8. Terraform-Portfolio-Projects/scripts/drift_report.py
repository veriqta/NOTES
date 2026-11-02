"""Compare observed remote drift with the actions Terraform proposes. Read-only."""
import argparse
import ipaddress
import json
from pathlib import Path

def relation(old, new):
    try:
        a, b = ipaddress.ip_network(old), ipaddress.ip_network(new)
        if a.version != b.version:
            return 'different address families; review'
        if a == b:
            return 'unchanged'
        if b.subnet_of(a):
            return 'narrower'
        if a.subnet_of(b):
            return 'wider'
        return 'different range; review'
    except (ValueError, TypeError):
        return 'not comparable'

def report(plan, records):
    changes = {r['address']:r for r in plan.get('resource_changes', [])}
    rows = []
    for drift in plan.get('resource_drift', []):
        addr = drift['address']
        observed = drift.get('change', {}).get('after') or {}
        action = changes.get(addr, {}).get('change', {})
        desired = action.get('after') or {}
        record = records.get(addr, {})
        rows.append({'address':addr, 'observed':observed, 'desired':desired,
                     'actions':action.get('actions', []),
                     'reconciliation_direction':relation(observed.get('cidr_ipv4'), desired.get('cidr_ipv4')),
                     'classification':record.get('classification', 'unclassified'),
                     'evidence':record.get('evidence', 'investigate CloudTrail, change records and controller ownership')})
    return rows

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('plan', type=Path)
    p.add_argument('--records', type=Path)
    a = p.parse_args()
    records = json.loads(a.records.read_text()) if a.records else {}
    print(json.dumps(report(json.loads(a.plan.read_text()), records), indent=2))
