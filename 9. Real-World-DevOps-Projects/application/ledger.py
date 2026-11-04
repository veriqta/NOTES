"""Write ownership is checked under the same database lock/transaction as the write."""
class Fenced(Exception): pass
class Conflict(Exception): pass

def write(conn, owner, epoch, key, amount):
    if amount <= 0:
        raise ValueError('amount must be positive')
    authority=conn.execute('SELECT owner,epoch,expires_at>clock_timestamp() FROM write_authority WHERE id=1 FOR UPDATE').fetchone()
    if authority is None or authority != (owner,epoch,True):
        raise Fenced('writer is not current or lease expired')
    row=conn.execute('SELECT amount_cents FROM ledger WHERE idempotency_key=%s',(key,)).fetchone()
    if row:
        if row[0] != amount: raise Conflict('idempotency key reused with a different amount')
        return False
    conn.execute('INSERT INTO ledger(idempotency_key,amount_cents,owner,epoch) VALUES (%s,%s,%s,%s)',(key,amount,owner,epoch))
    return True

def promote(conn, expected_owner, expected_epoch, new_owner, seconds=300):
    if new_owner == expected_owner or not 1 <= seconds <= 3600:
        raise ValueError('invalid promotion')
    row=conn.execute('SELECT owner,epoch FROM write_authority WHERE id=1 FOR UPDATE').fetchone()
    if row != (expected_owner,expected_epoch):raise Fenced('authority changed; review again')
    conn.execute("UPDATE write_authority SET owner=%s,epoch=epoch+1,expires_at=clock_timestamp()+(%s*interval '1 second') WHERE id=1",(new_owner,seconds))
    return expected_epoch+1
