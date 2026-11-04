import os,unittest
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import psycopg
from application.ledger import write,promote,Fenced,Conflict
DSN=os.getenv('TEST_DATABASE_URL')
@unittest.skipUnless(DSN,'TEST_DATABASE_URL is required for real PostgreSQL integration tests')
class Database(unittest.TestCase):
 def setUp(self):
  with psycopg.connect(DSN) as c:
   c.execute((Path(__file__).resolve().parents[1]/'application/schema.sql').read_text())
   c.execute('TRUNCATE ledger,receipts,outbox,orders')
   c.execute("UPDATE write_authority SET owner='primary',epoch=1,expires_at=clock_timestamp()+interval '1 hour' WHERE id=1")
 def test_replay_is_not_duplicate_payment(self):
  with psycopg.connect(DSN) as c:self.assertTrue(write(c,'primary',1,'test-replay',100))
  with psycopg.connect(DSN) as c:self.assertFalse(write(c,'primary',1,'test-replay',100))
 def test_different_amount_rejected(self):
  with psycopg.connect(DSN) as c:write(c,'primary',1,'test-conflict',100)
  with self.assertRaises(Conflict):
   with psycopg.connect(DSN) as c:write(c,'primary',1,'test-conflict',200)
 def test_old_writer_fenced_after_promotion(self):
  with psycopg.connect(DSN) as c:self.assertEqual(promote(c,'primary',1,'recovery'),2)
  with self.assertRaises(Fenced):
   with psycopg.connect(DSN) as c:write(c,'primary',1,'stale',100)
  with psycopg.connect(DSN) as c:self.assertTrue(write(c,'recovery',2,'new',100))
 def test_expired_lease_fails_closed(self):
  with psycopg.connect(DSN) as c:c.execute("UPDATE write_authority SET expires_at=clock_timestamp()-interval '1 second'")
  with self.assertRaises(Fenced):
   with psycopg.connect(DSN) as c:write(c,'primary',1,'expired',100)
 def test_concurrent_duplicate_is_one_row(self):
  def once(_):
   with psycopg.connect(DSN) as c:return write(c,'primary',1,'concurrent',100)
  with ThreadPoolExecutor(max_workers=6) as e:self.assertEqual(sum(e.map(once,range(6))),1)
  with psycopg.connect(DSN) as c:self.assertEqual(c.execute('SELECT count(*) FROM ledger').fetchone()[0],1)
