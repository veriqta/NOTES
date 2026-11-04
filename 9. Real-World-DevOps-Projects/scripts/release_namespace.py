import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
v=json.loads((root/'.private/foundation.json').read_text())
(root/'.private/release-serviceaccount.json').write_text(json.dumps({'apiVersion':'v1','kind':'ServiceAccount','metadata':{'name':'veriqta-app','namespace':'veriqta-release'}}))
(root/'.private/release-config.json').write_text(json.dumps({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'veriqta-config','namespace':'veriqta-release'},'data':{'DB_HOST':v['db_host'],'DB_SECRET_ARN':v['secret_arn']}}))
