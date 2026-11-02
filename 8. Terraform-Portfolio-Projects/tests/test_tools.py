import datetime as dt
import importlib.util
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'scripts'/f'{name}.py')
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
policy=load('plan_guard');drift=load('drift_report');cost=load('cost_report');gate=load('recovery_gate')
class Tools(unittest.TestCase):
    def test_replacement_blocked(self):
        self.assertTrue(policy.evaluate({'resource_changes':[{'address':'db','change':{'actions':['delete','create']}}]}))
    def test_private_ssh_allowed(self):
        p={'resource_changes':[{'type':'aws_vpc_security_group_ingress_rule','change':{'after':{'cidr_ipv4':'10.0.0.0/8','ip_protocol':'tcp','from_port':22,'to_port':22}}}]}
        self.assertEqual(policy.evaluate(p),[])
    def test_public_ipv6_ssh_blocked(self):
        self.assertTrue(policy.evaluate({'resource_changes':[{'type':'aws_vpc_security_group_ingress_rule','change':{'after':{'cidr_ipv6':'::/0','ip_protocol':'tcp','from_port':22,'to_port':22}}}]}))
    def test_unknown_ingress_blocked(self):
        self.assertTrue(policy.evaluate({'resource_changes':[{'type':'aws_vpc_security_group_ingress_rule','change':{'after_unknown':{'cidr_ipv4':True}}}]}))
    def test_drift_direction(self):
        self.assertEqual(drift.relation('10.0.0.0/16','0.0.0.0/0'),'wider')
        self.assertEqual(drift.relation('0.0.0.0/0','10.0.0.0/16'),'narrower')
    def test_cost_totals(self):
        a=cost.totals(ROOT/'fixtures/cost-before.csv');b=cost.totals(ROOT/'fixtures/cost-after.csv')
        self.assertEqual(str(sum(a.values())),'816.50');self.assertEqual(str(sum(b.values())),'2066.30')
        self.assertEqual(len(cost.compare(a,b)),5)
    def test_mixed_currencies_rejected(self):
        from decimal import Decimal
        rows={('Compute','USD','30'):Decimal('1'),('RDS','EUR','30'):Decimal('2')}
        with self.assertRaises(ValueError):cost.validate_windows(rows,rows)
    def test_noop_group_is_not_mistaken_for_managed_inline_change(self):
        self.assertEqual(policy.evaluate({'resource_changes':[{'type':'aws_security_group','change':{'actions':['no-op'],'after':{'ingress':[{'from_port':443}]}}}]}),[])
    def test_expired_plan_and_freeze(self):
        now=dt.datetime(2026,1,1,12,tzinfo=dt.timezone.utc)
        meta={'commit':'abc','state_key':'dev/test','created_at':now.isoformat()}
        gate.check(meta,{'enabled':False},'abc','dev/test',now)
        for freeze,commit,time in [({'enabled':True},'abc',now),({'enabled':False},'wrong',now),({'enabled':False},'abc',now+dt.timedelta(hours=1))]:
            with self.assertRaises(ValueError):gate.check(meta,freeze,commit,'dev/test',time)
if __name__=='__main__':unittest.main()
