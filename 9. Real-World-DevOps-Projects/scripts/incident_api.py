"""Local incident intake. Approval is a separate authenticated operator path, never an alert field."""
import os,secrets
from pathlib import Path
from fastapi import FastAPI,HTTPException,Header
from engineering.incident import IncidentStore
app=FastAPI(title='Veriqta incident intake')
store=IncidentStore(Path(os.getenv('INCIDENT_DB','.private/incidents.db')))
@app.post('/alerts')
def alert(event:dict,authorization:str=Header(default='')):
    token=os.environ.get('INCIDENT_API_TOKEN','')
    if not token or not secrets.compare_digest(authorization,'Bearer '+token):raise HTTPException(401,'authentication required')
    try:return {'incident_id':store.ingest(event)}
    except ValueError as error:raise HTTPException(400,str(error))
@app.get('/incidents/{incident}')
def report(incident:str,authorization:str=Header(default='')):
    token=os.environ.get('INCIDENT_API_TOKEN','')
    if not token or not secrets.compare_digest(authorization,'Bearer '+token):raise HTTPException(401,'authentication required')
    return store.report(incident)
