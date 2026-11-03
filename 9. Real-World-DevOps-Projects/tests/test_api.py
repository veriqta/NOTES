import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient
from application.api import app
class Api(unittest.TestCase):
 def test_process_health_does_not_depend_on_db(self):self.assertEqual(TestClient(app).get('/healthz').status_code,200)
 def test_readiness_fails_without_database(self):
  with patch('application.api.pool',side_effect=RuntimeError('private connection information')):
   r=TestClient(app).get('/readyz');self.assertEqual(r.status_code,503);self.assertNotIn('private',r.text)
 def test_checkout_requires_idempotency_key(self):self.assertEqual(TestClient(app).post('/checkout').status_code,400)
 def test_metrics_endpoint(self):self.assertEqual(TestClient(app).get('/metrics').status_code,200)
