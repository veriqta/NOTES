import json
import os
import time
from functools import lru_cache
from pathlib import Path
import boto3
from psycopg.conninfo import make_conninfo
from psycopg_pool import ConnectionPool

@lru_cache(maxsize=1)
def pool():
    if os.getenv('DATABASE_URL'):
        conninfo=os.environ['DATABASE_URL']
    else:
        secret=json.loads(boto3.client('secretsmanager').get_secret_value(SecretId=os.environ['DB_SECRET_ARN'])['SecretString'])
        conninfo=make_conninfo(host=os.environ['DB_HOST'],dbname='veriqta',user=secret['username'],
                              password=secret['password'],sslmode='verify-full',
                              sslrootcert='/app/rds-ca.pem',connect_timeout=3)
    return ConnectionPool(conninfo,min_size=1,max_size=int(os.getenv('POOL_SIZE','5')),
                          timeout=2,kwargs={'options':'-c statement_timeout=3000 -c lock_timeout=1500'})

def initialize():
    with pool().connection() as conn:
        conn.execute(Path(__file__).with_name('schema.sql').read_text())
