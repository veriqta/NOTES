"""Durable local incident store. BEGIN IMMEDIATE serializes remediation claims."""
import json,sqlite3,time,uuid
class IncidentStore:
    def __init__(self,path):
        self.path=str(path)
        with self.connect() as c:
            c.executescript("""
            CREATE TABLE IF NOT EXISTS incidents(id TEXT PRIMARY KEY,correlation TEXT,opened REAL,status TEXT);
            CREATE TABLE IF NOT EXISTS alerts(event_id TEXT PRIMARY KEY,incident_id TEXT,payload TEXT);
            CREATE TABLE IF NOT EXISTS actions(incident_id TEXT PRIMARY KEY,runbook TEXT,status TEXT,approver TEXT,execution_id TEXT);
            CREATE TABLE IF NOT EXISTS timeline(incident_id TEXT,at REAL,event TEXT);
            """)
    def connect(self):return sqlite3.connect(self.path,timeout=10,isolation_level=None)
    def ingest(self,event,now=None):
        now=time.time() if now is None else now
        for key in ('event_id','service','dependency','environment'):
            if not isinstance(event.get(key),str) or not event[key]:raise ValueError('missing '+key)
        event=dict(event)
        event['owner']='veriqta-platform' if event['service']=='checkout' else 'unassigned-escalate'
        burn=float(event.get('burn_rate',0))
        event['severity']='SEV1' if burn>=14.4 and event.get('impact') else 'SEV2' if burn>=6 else 'SEV3'
        correlation='|'.join(event[k] for k in ('environment','service','dependency'))
        with self.connect() as c:
            c.execute('BEGIN IMMEDIATE')
            old=c.execute('SELECT incident_id FROM alerts WHERE event_id=?',(event['event_id'],)).fetchone()
            if old:c.commit();return old[0]
            row=c.execute("SELECT id FROM incidents WHERE correlation=? AND status='open' AND opened>=? ORDER BY opened DESC LIMIT 1",(correlation,now-900)).fetchone()
            incident=row[0] if row else str(uuid.uuid4())
            if not row:c.execute('INSERT INTO incidents VALUES (?,?,?,?)',(incident,correlation,now,'open'))
            c.execute('INSERT INTO alerts VALUES (?,?,?)',(event['event_id'],incident,json.dumps(event)))
            c.execute('INSERT INTO timeline VALUES (?,?,?)',(incident,now,'alert '+event['event_id']))
            c.commit();return incident
    def claim(self,incident,runbook,approver):
        if runbook not in ('diagnose-database','restore-capacity'):raise ValueError('runbook not allowlisted')
        if not approver:raise ValueError('trusted authenticated approval required')
        with self.connect() as c:
            c.execute('BEGIN IMMEDIATE')
            if not c.execute("SELECT id FROM incidents WHERE id=? AND status='open'",(incident,)).fetchone():raise ValueError('open incident required')
            try:c.execute('INSERT INTO actions VALUES (?,?,?,?,?)',(incident,runbook,'claimed',approver,None))
            except sqlite3.IntegrityError:c.rollback();return False
            c.execute('INSERT INTO timeline VALUES (?,?,?)',(incident,time.time(),'approved '+runbook+' by '+approver))
            c.commit();return True
    def execution(self,incident,execution_id):
        with self.connect() as c:
            c.execute("UPDATE actions SET status='started',execution_id=? WHERE incident_id=? AND status='claimed'",(execution_id,incident))
    def resolve(self,incident,checks):
        if not all(checks.get(k) is True for k in ('checkout','latency','error_rate')):raise ValueError('independent recovery checks must all pass')
        with self.connect() as c:
            c.execute('BEGIN IMMEDIATE');c.execute("UPDATE incidents SET status='resolved' WHERE id=?",(incident,))
            c.execute('INSERT INTO timeline VALUES (?,?,?)',(incident,time.time(),'recovery independently verified'));c.commit()
    def report(self,incident):
        with self.connect() as c:
            return {'incident':c.execute('SELECT * FROM incidents WHERE id=?',(incident,)).fetchone(),
                    'alerts':c.execute('SELECT payload FROM alerts WHERE incident_id=?',(incident,)).fetchall(),
                    'actions':c.execute('SELECT runbook,status,approver,execution_id FROM actions WHERE incident_id=?',(incident,)).fetchall(),
                    'timeline':c.execute('SELECT at,event FROM timeline WHERE incident_id=? ORDER BY at',(incident,)).fetchall()}
