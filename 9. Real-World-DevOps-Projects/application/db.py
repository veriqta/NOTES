import json
import os
from functools import lru_cache
from pathlib import Path
import boto3
from botocore.config import Config
import psycopg
from psycopg.conninfo import make_conninfo
from psycopg_pool import ConnectionPool

@lru_cache(maxsize=1)
def secrets_client():
    return boto3.client('secretsmanager',config=Config(connect_timeout=3,read_timeout=3,retries={'max_attempts':2}))

class SecretConnection(psycopg.Connection):
    @classmethod
    def connect(cls,conninfo='',**kwargs):
        # Each new pooled connection reads the current managed password. Passwords are not cached in the pool's connection string.
        secret=json.loads(secrets_client().get_secret_value(SecretId=os.environ['DB_SECRET_ARN'])['SecretString'])
        return super().connect(make_conninfo(conninfo,user=secret['username'],password=secret['password']),**kwargs)

@lru_cache(maxsize=1)
def pool():
    connection_class=psycopg.Connection
    if os.getenv('DATABASE_URL'):
        conninfo=os.environ['DATABASE_URL']
    else:
        conninfo=make_conninfo(host=os.environ['DB_HOST'],dbname='veriqta',sslmode='verify-full',
                              sslrootcert='/app/rds-ca.pem',connect_timeout=3)
        connection_class=SecretConnection
    return ConnectionPool(conninfo,connection_class=connection_class,min_size=1,max_size=int(os.getenv('POOL_SIZE','5')),
                          timeout=2,kwargs={'options':'-c statement_timeout=3000 -c lock_timeout=1500'})

def initialize():
    with pool().connection() as conn:
        conn.execute(Path(__file__).with_name('schema.sql').read_text())
