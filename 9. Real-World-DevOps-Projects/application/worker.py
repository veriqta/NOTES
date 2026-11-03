"""PostgreSQL outbox locally; SQS transport optionally. Both paths make effects idempotent."""
import json,os,time,logging
import boto3
from application.db import pool

def local_once():
    with pool().connection() as conn:
        row=conn.execute('SELECT id FROM outbox WHERE NOT delivered FOR UPDATE SKIP LOCKED LIMIT 1').fetchone()
        if row:
            conn.execute('INSERT INTO receipts(id) VALUES (%s) ON CONFLICT DO NOTHING',(row[0],))
            conn.execute('UPDATE outbox SET delivered=true WHERE id=%s',(row[0],))
        return row is not None

def sqs_once(client,url):
    # Publishing can succeed before a DB commit; duplicate deliveries are expected.
    with pool().connection() as conn:
        row=conn.execute('SELECT id FROM outbox WHERE NOT delivered FOR UPDATE SKIP LOCKED LIMIT 1').fetchone()
        if row:
            client.send_message(QueueUrl=url,MessageBody=json.dumps({'id':row[0]}))
            conn.execute('UPDATE outbox SET delivered=true WHERE id=%s',(row[0],))
    for message in client.receive_message(QueueUrl=url,MaxNumberOfMessages=10,WaitTimeSeconds=1).get('Messages',[]):
        key=json.loads(message['Body'])['id']
        with pool().connection() as conn:conn.execute('INSERT INTO receipts(id) VALUES (%s) ON CONFLICT DO NOTHING',(key,))
        # A crash before deletion replays the message, not the business effect.
        client.delete_message(QueueUrl=url,ReceiptHandle=message['ReceiptHandle'])

if __name__=='__main__':
    logging.basicConfig(level=logging.INFO)
    url=os.getenv('QUEUE_URL');client=boto3.client('sqs') if url else None
    while True:
        try:
            sqs_once(client,url) if url else local_once()
        except Exception:logging.exception('worker iteration failed; message retained for retry')
        time.sleep(1)
