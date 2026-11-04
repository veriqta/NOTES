"""Create local secrets once. Existing secrets are never replaced."""
from pathlib import Path
import os,secrets
from cryptography.fernet import Fernet
root=Path(__file__).resolve().parents[1]
p=root/'.private';p.mkdir(mode=0o700,exist_ok=True)
for name,value in [('lab.env','PGPASSWORD='+secrets.token_hex(24)+'\nGRAFANA_PASSWORD='+secrets.token_hex(24)+'\n'),('backup.key',Fernet.generate_key().decode())]:
    path=p/name
    if not path.exists():
        fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(fd,'w') as stream:stream.write(value)
print('Local secret files are ready in .private/. Keep the backup key separate from backup storage.')
