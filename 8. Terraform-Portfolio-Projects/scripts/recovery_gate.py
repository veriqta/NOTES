"""Block apply during an incident and reject expired or mismatched plan metadata."""
import argparse
import datetime as dt
import json
from pathlib import Path

def check(meta, freeze, commit, state_key, now=None):
    now=now or dt.datetime.now(dt.timezone.utc)
    if freeze.get('enabled'):
        raise ValueError('Apply frozen: '+freeze.get('reason','incident review required'))
    if meta['commit'] != commit or meta['state_key'] != state_key:
        raise ValueError('Plan commit or state key mismatch')
    created=dt.datetime.fromisoformat(meta['created_at'])
    if created.tzinfo is None:
        raise ValueError('Plan timestamp must include timezone')
    age=(now-created).total_seconds()
    if age<0 or age>1800:
        raise ValueError('Plan expired or timestamp is in the future; create and approve a new plan')

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('metadata',type=Path);p.add_argument('freeze',type=Path)
    p.add_argument('commit');p.add_argument('state_key')
    a=p.parse_args()
    try:
        check(json.loads(a.metadata.read_text()),json.loads(a.freeze.read_text()),a.commit,a.state_key)
    except (ValueError,KeyError) as e:
        raise SystemExit(str(e))
    print('Freshness and incident gates passed.')
