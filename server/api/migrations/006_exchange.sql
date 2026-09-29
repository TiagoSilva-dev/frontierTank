-- Currency exchange: escrow is give_unit * remaining; fills use whole lots.
CREATE TABLE exchange_orders (
 id BIGSERIAL PRIMARY KEY,
 account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
 give_id TEXT NOT NULL, want_id TEXT NOT NULL,
 give_unit BIGINT NOT NULL CHECK (give_unit BETWEEN 1 AND 1000000),
 want_unit BIGINT NOT NULL CHECK (want_unit BETWEEN 1 AND 1000000),
 lots BIGINT NOT NULL CHECK (lots BETWEEN 1 AND 1000000),
 remaining BIGINT NOT NULL CHECK (remaining >= 0 AND remaining <= lots),
 fee BIGINT NOT NULL CHECK (fee >= 0),
 status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','filled','cancelled')),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK ((status = 'filled') = (remaining = 0)),
 CHECK (give_id <> want_id), CHECK (give_unit * lots <= 1000000 AND want_unit * lots <= 1000000)
);
CREATE INDEX exchange_book ON exchange_orders(give_id,want_id,id) WHERE status='active';
CREATE INDEX exchange_owner ON exchange_orders(account_id,id DESC);
