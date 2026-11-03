import json
import logging
import os
import time
from contextlib import asynccontextmanager
import httpx
from fastapi import FastAPI,HTTPException,Request
from fastapi.responses import JSONResponse,Response
from prometheus_client import Counter,Histogram,Gauge,generate_latest,CONTENT_TYPE_LATEST
from opentelemetry import trace,propagate
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.trace import Status,StatusCode,SpanKind
from application.db import pool,initialize
from application.ledger import write,Fenced,Conflict

SERVICE=os.getenv('SERVICE_NAME','checkout')
provider=TracerProvider(resource=Resource.create({'service.name':SERVICE,'service.version':os.getenv('RELEASE','v1')}))
if os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT'):
    provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter(endpoint=os.environ['OTEL_EXPORTER_OTLP_ENDPOINT'].rstrip('/')+'/v1/traces')))
trace.set_tracer_provider(provider)
tracer=trace.get_tracer('veriqta')
if os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT'):
    from opentelemetry.sdk._logs import LoggerProvider,LoggingHandler
    from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
    from opentelemetry.exporter.otlp.proto.http._log_exporter import OTLPLogExporter
    logs=LoggerProvider(resource=Resource.create({'service.name':SERVICE}))
    logs.add_log_record_processor(BatchLogRecordProcessor(OTLPLogExporter(endpoint=os.environ['OTEL_EXPORTER_OTLP_ENDPOINT'].rstrip('/')+'/v1/logs')))
    logging.getLogger().addHandler(LoggingHandler(level=logging.INFO,logger_provider=logs))
requests=Counter('veriqta_http_requests_total','Completed requests',['service','route','status','release'])
latency=Histogram('veriqta_http_duration_seconds','Request duration',['service','route','release'],buckets=(.01,.05,.1,.25,.5,1,2,5,10))
active=Gauge('veriqta_http_active','In-flight requests',['service'])
logging.basicConfig(level=logging.INFO,format='%(message)s')
logging.getLogger().setLevel(logging.INFO)

@asynccontextmanager
async def lifespan(app):
    # Schema migration is explicit; replicas do not race to perform DDL at startup.
    pool().wait(timeout=30)
    yield
    pool().close()

app=FastAPI(title='Veriqta engineering lab',lifespan=lifespan)

@app.middleware('http')
async def telemetry(request,call_next):
    start=time.monotonic();status=500
    route=request.url.path if request.url.path in ('/healthz','/readyz','/checkout','/pay','/reserve','/ledger','/metrics') else '/other'
    active.labels(SERVICE).inc()
    with tracer.start_as_current_span(SERVICE+route,context=propagate.extract(dict(request.headers)),kind=SpanKind.SERVER) as span:
        try:
            result=await call_next(request);status=result.status_code
            if status>=500:span.set_status(Status(StatusCode.ERROR))
            return result
        finally:
            elapsed=time.monotonic()-start
            requests.labels(SERVICE,route,str(status),os.getenv('RELEASE','v1')).inc()
            latency.labels(SERVICE,route,os.getenv('RELEASE','v1')).observe(elapsed)
            active.labels(SERVICE).dec()
            logging.info(json.dumps({'service':SERVICE,'route':route,'status':status,'duration_ms':round(elapsed*1000,2),'trace_id':format(span.get_span_context().trace_id,'032x'),'release':os.getenv('RELEASE','v1')}))

@app.get('/healthz')
def health():return {'process':'alive'}

@app.get('/readyz')
def ready():
    try:
        with pool().connection() as conn:conn.execute('SELECT 1')
        return {'database':'reachable'}
    except Exception:raise HTTPException(503,'database unavailable')

@app.get('/metrics')
def metrics():return Response(generate_latest(),media_type=CONTENT_TYPE_LATEST)

def call(url,key):
    with tracer.start_as_current_span('dependency '+url,kind=SpanKind.CLIENT):
        headers={'Idempotency-Key':key};propagate.inject(headers)
        with httpx.Client(timeout=4) as client:
            response=client.post(url,headers=headers)
            response.raise_for_status()
            return response.json()

@app.post('/checkout')
def checkout(request:Request):
    key=request.headers.get('Idempotency-Key','')
    if not key or len(key)>100:raise HTTPException(400,'use an idempotency key up to 100 characters')
    try:
        if SERVICE=='gateway':return call(os.getenv('CHECKOUT_URL','http://checkout:8080/checkout'),key)
        call(os.getenv('PAYMENT_URL','http://payment:8080/pay'),key)
        call(os.getenv('INVENTORY_URL','http://inventory:8080/reserve'),key)
        with pool().connection() as conn:
            conn.execute('INSERT INTO orders(id,amount_cents) VALUES (%s,1000) ON CONFLICT DO NOTHING',(key,))
            conn.execute('INSERT INTO outbox(id) VALUES (%s) ON CONFLICT DO NOTHING',(key,))
        return {'order':key,'status':'accepted'}
    except Exception:
        logging.exception('checkout failed')
        raise HTTPException(503,'checkout unavailable')

@app.post('/pay')
def pay():
    delay=float(os.getenv('PAYMENT_DELAY_SECONDS','0'))
    time.sleep(min(max(delay,0),5))
    if os.getenv('PAYMENT_FAIL','false')=='true':raise HTTPException(503,'injected payment failure')
    return {'simulation':'payment approved; no external money movement'}

@app.post('/reserve')
def reserve():
    try:
        with pool().connection() as conn:conn.execute('SELECT available FROM inventory WHERE id=1 FOR UPDATE').fetchone()
        return {'simulation':'inventory checked; no stock mutation'}
    except Exception:raise HTTPException(503,'inventory dependency unavailable')

@app.post('/ledger')
async def ledger(request:Request):
    body=await request.json()
    try:
        key=request.headers.get('Idempotency-Key','')
        if not key or len(key)>100:raise ValueError('invalid idempotency key')
        amount=body['amount_cents']
        if type(amount) is not int:raise ValueError('integer cents required')
        with pool().connection() as conn:
            created=write(conn,os.getenv('WRITE_OWNER','primary'),int(os.getenv('WRITE_EPOCH','1')),key,amount)
        return {'created':created,'key':key}
    except Fenced:raise HTTPException(409,'writer fenced')
    except (Conflict,ValueError,KeyError,TypeError):raise HTTPException(400,'invalid or conflicting transaction')
