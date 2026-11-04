import json,os,unittest
from unittest.mock import patch,MagicMock
from psycopg.conninfo import conninfo_to_dict
from application.db import SecretConnection
class Rotation(unittest.TestCase):
 def test_new_connections_fetch_current_secret(self):
  client=MagicMock()
  client.get_secret_value.side_effect=[{'SecretString':json.dumps({'username':'veriqta','password':'old-test-value'})},{'SecretString':json.dumps({'username':'veriqta','password':'new-test-value'})}]
  with patch('application.db.secrets_client',return_value=client),patch('psycopg.Connection.connect',return_value=object()) as connect,patch.dict(os.environ,{'DB_SECRET_ARN':'test-secret'}):
   SecretConnection.connect('host=db.example.invalid sslmode=verify-full')
   SecretConnection.connect('host=db.example.invalid sslmode=verify-full')
  self.assertEqual(client.get_secret_value.call_count,2)
  self.assertEqual(conninfo_to_dict(connect.call_args_list[0].args[0])['password'],'old-test-value')
  self.assertEqual(conninfo_to_dict(connect.call_args_list[1].args[0])['password'],'new-test-value')
