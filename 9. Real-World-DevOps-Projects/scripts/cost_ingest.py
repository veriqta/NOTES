"""Read-only Cost Explorer export. Requires an approved billing role; does not send notifications."""
import argparse,json
from pathlib import Path
import boto3
p=argparse.ArgumentParser();p.add_argument('start');p.add_argument('end');p.add_argument('--output',type=Path,required=True);a=p.parse_args()
client=boto3.client('ce',region_name='us-east-1');token=None;pages=[]
while True:
    request={'TimePeriod':{'Start':a.start,'End':a.end},'Granularity':'DAILY','Metrics':['UnblendedCost'],'GroupBy':[{'Type':'DIMENSION','Key':'SERVICE'},{'Type':'TAG','Key':'Owner'}]}
    if token:request['NextPageToken']=token
    response=client.get_cost_and_usage(**request);pages.append(response)
    token=response.get('NextPageToken')
    if not token:break
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(pages,default=str,indent=2))
print('Private billing export written; preserve currency, estimated flags, credits, account scope and exclusive end date when comparing.')
