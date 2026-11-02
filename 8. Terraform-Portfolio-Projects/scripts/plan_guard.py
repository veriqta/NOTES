"""Review a Terraform plan JSON. Exit 2 for destructive or public-management changes."""
import argparse
import ipaddress
import json
from pathlib import Path

def evaluate(plan):
    findings = []
    for change in plan.get('resource_changes', []):
        c = change.get('change', {})
        actions = c.get('actions', [])
        if actions in (['no-op'], ['read']):
            continue
        address = change.get('address', '?')
        if 'delete' in actions:
            findings.append(f'{address}: deletion or replacement requires a separate reviewed change')
        after = c.get('after') or {}
        if change.get('type') == 'aws_vpc_security_group_ingress_rule':
            cidr = after.get('cidr_ipv4') or after.get('cidr_ipv6')
            public = cidr and ipaddress.ip_network(cidr).prefixlen == 0
            protocol = str(after.get('ip_protocol'))
            lo, hi = after.get('from_port'), after.get('to_port')
            management = protocol == '-1' or (lo is not None and hi is not None and
                                               any(lo <= port <= hi for port in (22, 3389)))
            if public and management:
                findings.append(f'{address}: public management access')
            if any(c.get('after_unknown', {}).get(k) for k in ('cidr_ipv4','cidr_ipv6','ip_protocol','from_port','to_port')):
                findings.append(f'{address}: unresolved ingress fields require review')
        # Inline SG rules are deliberately not auto-approved by this narrow policy.
        if change.get('type') == 'aws_security_group' and after.get('ingress'):
            findings.append(f'{address}: review inline ingress manually')
    if plan.get('errored'):
        findings.append('Terraform reported an errored plan')
    return findings

if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('plan', type=Path)
    a = p.parse_args()
    findings = evaluate(json.loads(a.plan.read_text()))
    print('\n'.join(findings) if findings else 'Policy checks passed; human review is still required.')
    raise SystemExit(2 if findings else 0)
