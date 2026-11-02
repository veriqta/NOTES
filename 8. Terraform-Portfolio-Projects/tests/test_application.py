import importlib.util
import json
import os
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import MagicMock, patch
ROOT=Path(__file__).resolve().parents[1]
class Application(unittest.TestCase):
    def test_database_uses_verified_tls_and_in_memory_secret(self):
        sm=MagicMock()
        sm.get_secret_value.return_value={'SecretString':json.dumps({'username':'veriqta','password':'example-test-only'})}
        boto=types.SimpleNamespace(client=MagicMock(return_value=sm))
        pg=types.SimpleNamespace(connect=MagicMock())
        with patch.dict(sys.modules,{'boto3':boto,'psycopg':pg}), patch.dict(os.environ,{'AWS_DEFAULT_REGION':'us-east-1','SECRET_ARN':'test-secret','DB_HOST':'db.example.invalid:5432'}):
            spec=importlib.util.spec_from_file_location('veriqta_app',ROOT/'application/app.py')
            app=importlib.util.module_from_spec(spec);spec.loader.exec_module(app)
            app.connect()
        sm.get_secret_value.assert_called_once_with(SecretId='test-secret')
        kwargs=pg.connect.call_args.kwargs
        self.assertEqual(kwargs['sslmode'],'verify-full')
        self.assertEqual(kwargs['host'],'db.example.invalid')
        self.assertEqual(kwargs['connect_timeout'],3)
        self.assertEqual(kwargs['password'],'example-test-only')
    def test_failed_database_returns_503_without_exception_details(self):
        boto=types.SimpleNamespace(client=MagicMock())
        with patch.dict(sys.modules,{'boto3':boto,'psycopg':types.SimpleNamespace()}), patch.dict(os.environ,{'AWS_DEFAULT_REGION':'us-east-1'}):
            spec=importlib.util.spec_from_file_location('veriqta_app_failure',ROOT/'application/app.py')
            app=importlib.util.module_from_spec(spec);spec.loader.exec_module(app)
            request=object.__new__(app.Handler)
            request.path='/readyz'
            request.respond=MagicMock()
            with patch.object(app,'connect',side_effect=RuntimeError('private credential detail')), patch.object(app.logging,'exception'):
                request.do_GET()
            request.respond.assert_called_once_with(503,{'status':'database unavailable'})
if __name__=='__main__':unittest.main()
