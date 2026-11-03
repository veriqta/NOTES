import datetime as dt,json,tempfile,threading,unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from engineering.recovery import decide
from engineering.release import decision
from engineering.finops import assess
from engineering.incident import IncidentStore
from engineering.platform import render
from engineering.governance import validate_exception,drift_direction
ROOT=Path(__file__).resolve().parents[1]
class Decisions(unittest.TestCase):
 def test_dependency_does_not_restart(self):self.assertEqual(decide({}, {'dependency_healthy':False}), 'ESCALATE_DEPENDENCY')
 def test_insufficient_capacity(self):self.assertEqual(decide({}, {'dependency_healthy':True,'ready':1,'minimum_ready':2}), 'RESTORE_CAPACITY')
 def test_cooldown(self):self.assertEqual(decide({'attempts':1,'last_attempt':100},{'dependency_healthy':True,'ready':3,'crash_loop':True},150),'WAIT_COOLDOWN')
 def test_attempt_limit(self):self.assertEqual(decide({'attempts':3},{'dependency_healthy':True,'ready':3}), 'STOP_ATTEMPT_LIMIT')
 def test_bounded_restart(self):self.assertEqual(decide({}, {'dependency_healthy':True,'ready':3,'crash_loop':True},1000),'RESTART_ONE')
 def test_bad_canary(self):self.assertEqual(decision(json.loads((ROOT/'projects/07-progressive-delivery/bad.json').read_text())),'ABORT_TO_STABLE')
 def test_good_canary(self):self.assertEqual(decision(json.loads((ROOT/'projects/07-progressive-delivery/good.json').read_text())),'PROMOTE')
 def test_missing_metrics_pause(self):self.assertEqual(decision({'schema_backward_compatible':True}),'PAUSE_NO_EVIDENCE')
 def test_irreversible_schema(self):self.assertEqual(decision({'schema_backward_compatible':False}),'FORWARD_FIX_REQUIRED')
 def test_finops_keeps_standby(self):
  rows=json.loads((ROOT/'projects/06-finops/recommendations.json').read_text())
  self.assertEqual([assess(r)['decision'] for r in rows],['RECOMMEND_REVIEW','REJECT','REJECT'])
 def test_finops_stale(self):
  r=json.loads((ROOT/'projects/06-finops/recommendations.json').read_text())[0];r['telemetry_age_minutes']=120
  self.assertEqual(assess(r)['decision'],'REJECT')
 def test_approved_platform_idempotency(self):
  req=json.loads((ROOT/'projects/05-self-service/request.json').read_text())
  with tempfile.TemporaryDirectory() as d:self.assertEqual(render(req,d),render(req,d))
 def test_reject_privileged_platform_request(self):
  req=json.loads((ROOT/'projects/05-self-service/request.json').read_text());req['iam_policy']='*'
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):render(req,d)
 def test_reject_duplicate_different_inputs(self):
  req=json.loads((ROOT/'projects/05-self-service/request.json').read_text())
  with tempfile.TemporaryDirectory() as d:
   render(req,d);req['memory_mib']=512
   with self.assertRaises(ValueError):render(req,d)
 def test_incident_correlates_and_deduplicates(self):
  events=json.loads((ROOT/'projects/10-incident-command/alerts.json').read_text())
  with tempfile.TemporaryDirectory() as d:
   s=IncidentStore(Path(d)/'incidents.db');a=s.ingest(events[0]);self.assertEqual(a,s.ingest(events[0]));self.assertEqual(a,s.ingest(events[1]));self.assertEqual(len(s.report(a)['alerts']),2)
 def test_only_one_remediation_claim(self):
  event=json.loads((ROOT/'projects/10-incident-command/alerts.json').read_text())[0]
  with tempfile.TemporaryDirectory() as d:
   s=IncidentStore(Path(d)/'incidents.db');i=s.ingest(event)
   with ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(lambda _:s.claim(i,'diagnose-database','veriqta-operator'),range(8)))
   self.assertEqual(sum(results),1)
 def test_recovery_requires_independent_signals(self):
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):IncidentStore(Path(d)/'incidents.db').resolve('id',{'checkout':True})
 def test_drift_preserves_security_restriction(self):self.assertEqual(drift_direction('10.0.0.0/16','0.0.0.0/0'),'widening')
 def test_exception_self_approval_rejected(self):
  now=dt.datetime.now(dt.timezone.utc)
  e={'issued_at':now.isoformat(),'expires_at':(now+dt.timedelta(hours=1)).isoformat(),'approver':'same','requester':'same'}
  with self.assertRaises(ValueError):validate_exception(e,{},['same'],now)
 def test_expired_exception_rejected(self):
  now=dt.datetime.now(dt.timezone.utc)
  with self.assertRaises(ValueError):validate_exception({'issued_at':(now-dt.timedelta(hours=2)).isoformat(),'expires_at':(now-dt.timedelta(hours=1)).isoformat()},{},[],now)
