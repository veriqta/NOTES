"""A remediation decision engine. It proposes actions; it never restarts a workload itself."""
import time

def decide(state,observed,now=None):
    now=time.time() if now is None else now
    if observed.get('dependency_healthy') is not True:return 'ESCALATE_DEPENDENCY'
    if observed.get('ready',0)<observed.get('minimum_ready',2):return 'RESTORE_CAPACITY'
    if state.get('attempts',0)>=3:return 'STOP_ATTEMPT_LIMIT'
    if now-state.get('last_attempt',0)<120:return 'WAIT_COOLDOWN'
    if observed.get('crash_loop',False):return 'RESTART_ONE'
    return 'OBSERVE'
