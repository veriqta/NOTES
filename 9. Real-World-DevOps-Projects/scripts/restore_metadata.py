"""Prepare an RDS restore metadata candidate; review it before starting a restore."""
import argparse,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('response',type=Path);p.add_argument('--identifier',required=True);p.add_argument('--subnet-group',required=True);p.add_argument('--security-group',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
m=json.loads(a.response.read_text())['RestoreMetadata']
m.update({'DBInstanceIdentifier':a.identifier,'DBSubnetGroupName':a.subnet_group,'VpcSecurityGroupIds':json.dumps([a.security_group]),'PubliclyAccessible':'false','MultiAZ':'true'})
a.output.write_text(json.dumps(m,indent=2));print('Candidate metadata written. Review engine, keys, option groups and every regional dependency before use.')
