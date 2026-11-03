CREATE TABLE IF NOT EXISTS orders (
 id text PRIMARY KEY,
 amount_cents bigint NOT NULL CHECK (amount_cents > 0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS outbox (
 id text PRIMARY KEY REFERENCES orders(id),
 delivered boolean NOT NULL DEFAULT false
);
CREATE TABLE IF NOT EXISTS receipts (
 id text PRIMARY KEY REFERENCES orders(id),
 processed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE IF NOT EXISTS inventory (id integer PRIMARY KEY, available integer NOT NULL);
INSERT INTO inventory VALUES (1,100000) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS write_authority (
 id integer PRIMARY KEY CHECK(id=1), owner text NOT NULL, epoch bigint NOT NULL,
 expires_at timestamptz NOT NULL
);
INSERT INTO write_authority VALUES (1,'primary',1,clock_timestamp()+interval '1 hour') ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS ledger (
 idempotency_key text PRIMARY KEY, amount_cents bigint NOT NULL CHECK(amount_cents>0),
 owner text NOT NULL, epoch bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
