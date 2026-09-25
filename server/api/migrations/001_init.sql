-- Backend 0.11: contas, sessões, perfis, registro de transações, servidores de jogo
-- e presença (em que servidor cada conta está jogando).

CREATE TABLE accounts (
	id BIGSERIAL PRIMARY KEY,
	username TEXT NOT NULL,
	password_hash TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	last_login TIMESTAMPTZ,
	banned BOOLEAN NOT NULL DEFAULT false
);
CREATE UNIQUE INDEX accounts_username_key ON accounts (lower(username));

-- Só o hash SHA-256 do token fica no banco.
CREATE TABLE sessions (
	token_hash BYTEA PRIMARY KEY,
	account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX sessions_account_idx ON sessions (account_id);

-- O perfil é o save do PlayerProfile (JSON v5). `version` protege contra gravações
-- concorrentes: o servidor de jogo manda a versão que leu e a gravação falha se mudou.
CREATE TABLE profiles (
	account_id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
	name TEXT,
	data JSONB NOT NULL,
	version BIGINT NOT NULL,
	updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX profiles_name_key ON profiles (lower(name));

-- Toda operação que mexe na economia (compra, craft, recompensa...) deixa um registro,
-- para investigar fraudes e reclamações.
CREATE TABLE audit_log (
	id BIGSERIAL PRIMARY KEY,
	account_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
	server_id TEXT NOT NULL DEFAULT '',
	kind TEXT NOT NULL,
	detail JSONB NOT NULL DEFAULT '{}',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_account_idx ON audit_log (account_id, created_at);

-- Servidores de jogo se anunciam a cada poucos segundos; a lista pública mostra os vivos.
CREATE TABLE game_servers (
	id TEXT PRIMARY KEY,
	name TEXT NOT NULL,
	url TEXT NOT NULL,
	online INT NOT NULL DEFAULT 0,
	capacity INT NOT NULL DEFAULT 0,
	updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Uma conta joga em um servidor por vez; a reserva expira se o servidor sumir.
CREATE TABLE presence (
	account_id BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
	server_id TEXT NOT NULL,
	expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX presence_server_idx ON presence (server_id);
