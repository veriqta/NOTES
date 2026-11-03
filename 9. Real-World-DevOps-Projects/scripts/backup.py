"""Encrypted local PostgreSQL + object-directory backup/restore. No cloud API calls."""
import argparse,base64,datetime as dt,hashlib,json,subprocess
from pathlib import Path
from cryptography.fernet import Fernet
ROOT=Path(__file__).resolve().parents[1]
def compose(*args,input=None):
    return subprocess.run(['docker','compose','--env-file',str(ROOT/'.private/lab.env'),'-f',str(ROOT/'compose.yaml'),*args],input=input,capture_output=True,check=True).stdout
p=argparse.ArgumentParser();p.add_argument('action',choices=['backup','restore']);p.add_argument('file',type=Path);p.add_argument('--objects',type=Path,default=ROOT/'.private/objects');p.add_argument('--key',type=Path,default=ROOT/'.private/backup.key');a=p.parse_args()
fernet=Fernet(a.key.read_bytes().strip())
if a.action=='backup':
    dump=compose('exec','-T','primary','pg_dump','-U','veriqta','-d','veriqta','-Fc')
    objects={}
    if a.objects.exists():
        for f in a.objects.rglob('*'):
            if f.is_symlink():raise ValueError('symlink objects are not accepted')
            if f.is_file():objects[str(f.relative_to(a.objects))]=base64.b64encode(f.read_bytes()).decode()
    data={'captured_at':dt.datetime.now(dt.timezone.utc).isoformat(),'dump':base64.b64encode(dump).decode(),'objects':objects,
          'dump_digest':hashlib.sha256(dump).hexdigest()}
    a.file.parent.mkdir(parents=True,exist_ok=True);a.file.write_bytes(fernet.encrypt(json.dumps(data).encode()))
    print('Encrypted backup created; validate by restoring it to recovery.')
else:
    started=dt.datetime.now(dt.timezone.utc)
    data=json.loads(fernet.decrypt(a.file.read_bytes()))
    dump=base64.b64decode(data['dump'])
    if hashlib.sha256(dump).hexdigest()!=data['dump_digest']:raise ValueError('dump integrity failed')
    # Always the isolated recovery database; never default to the primary.
    compose('exec','-T','recovery','pg_restore','-U','veriqta','-d','veriqta','--clean','--if-exists','--no-owner','--exit-on-error',input=dump)
    a.objects.mkdir(parents=True,exist_ok=True)
    for name,encoded in data['objects'].items():
        target=(a.objects/name).resolve()
        if not target.is_relative_to(a.objects.resolve()):raise ValueError('unsafe object path')
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(base64.b64decode(encoded))
    print(json.dumps({'restore_seconds':(dt.datetime.now(dt.timezone.utc)-started).total_seconds(),'backup_captured_at':data['captured_at'],
                      'status':'restore completed; application/marker verification still required'}))
