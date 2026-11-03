"""Run in an authenticated operator environment. Every incident has one durable claim and deterministic SSM token."""
import argparse,os,boto3
from engineering.incident import IncidentStore
p=argparse.ArgumentParser();p.add_argument('incident');p.add_argument('--database',required=True);p.add_argument('--execution-role',required=True);a=p.parse_args()
operator=os.environ.get('AUTHENTICATED_OPERATOR','')
if not operator:raise SystemExit('A trusted operator environment must identify the approver.')
store=IncidentStore('.private/incidents.db')
claimed=store.claim(a.incident,'diagnose-database',operator)
report=store.report(a.incident)
actions=report['actions']
if not actions or actions[0][0]!='diagnose-database':raise SystemExit('Conflicting remediation claim; inspect the timeline.')
# Repeating an ambiguous request reuses the SAME parameters and token. Never switch runbooks on the retry.
response=boto3.client('ssm').start_automation_execution(DocumentName='veriqta-diagnose-database',
    ClientToken=a.incident,Parameters={'AutomationAssumeRole':[a.execution_role],'DatabaseIdentifier':[a.database]})
store.execution(a.incident,response['AutomationExecutionId'])
print(response['AutomationExecutionId'])
