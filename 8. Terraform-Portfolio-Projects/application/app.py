"""Veriqta portfolio API. Credentials stay in memory; every readiness check queries PostgreSQL."""
import json
import logging
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit
import boto3
import psycopg

logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
secrets = boto3.client('secretsmanager', region_name=os.environ['AWS_DEFAULT_REGION'])

def connect():
    secret = json.loads(secrets.get_secret_value(SecretId=os.environ['SECRET_ARN'])['SecretString'])
    host = os.environ['DB_HOST'].split(':')[0]
    return psycopg.connect(host=host, port=5432, dbname='veriqta',
                          user=secret['username'], password=secret['password'],
                          sslmode='verify-full', sslrootcert='/opt/veriqta/rds-ca.pem',
                          connect_timeout=3, options='-c statement_timeout=3000')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path not in ('/', '/readyz', '/api'):
            self.respond(404, {'error': 'not found'})
            return
        try:
            with connect() as conn, conn.cursor() as cur:
                cur.execute('SELECT current_database(), now()')
                name, now = cur.fetchone()
            self.respond(200, {'service': 'veriqta', 'database': name, 'database_time': now.isoformat()})
        except Exception:
            logging.exception('database readiness failed')
            self.respond(503, {'status': 'database unavailable'})

    def respond(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        logging.info('%s %s', self.address_string(), fmt % args)

if __name__ == '__main__':
    ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
