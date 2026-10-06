-- Painel administrativo (/admin/): a equipe tem contas próprias, separadas das dos jogadores
-- (papel, senha com PBKDF2 e segundo fator TOTP), sessões curtas e um registro de tudo o que
-- fez. Nada aqui é lido pelo jogo nem pelo servidor de jogo.

CREATE TABLE admin_users (
	id BIGSERIAL PRIMARY KEY,
	username TEXT NOT NULL,
	password_hash TEXT NOT NULL,
	-- viewer (só números), support (jogadores, denúncias, presentes pequenos), admin (banir,
	-- presentes grandes, cancelar anúncios) e owner (equipe, exclusão de contas, sistema).
	role TEXT NOT NULL CHECK (role IN ('viewer', 'support', 'admin', 'owner')),
	-- O segredo do TOTP fica cifrado (AES-GCM com uma chave derivada de INTERNAL_KEY).
	totp_secret TEXT NOT NULL DEFAULT '',
	totp_enabled BOOLEAN NOT NULL DEFAULT false,
	-- Último passo de 30 s aceito: o mesmo código não vale duas vezes.
	totp_last_step BIGINT NOT NULL DEFAULT 0,
	active BOOLEAN NOT NULL DEFAULT true,
	must_change_password BOOLEAN NOT NULL DEFAULT false,
	failed_logins INT NOT NULL DEFAULT 0,
	locked_until TIMESTAMPTZ,
	created_by TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	last_login TIMESTAMPTZ
);
CREATE UNIQUE INDEX admin_users_username_key ON admin_users (lower(username));

-- Só o hash do token fica no banco. `stage` = 'enroll': a senha confere mas o segundo fator
-- ainda não foi cadastrado, então a sessão só serve para cadastrá-lo.
CREATE TABLE admin_sessions (
	token_hash BYTEA PRIMARY KEY,
	admin_id BIGINT NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
	csrf TEXT NOT NULL,
	stage TEXT NOT NULL DEFAULT 'full' CHECK (stage IN ('full', 'enroll')),
	ip TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	last_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
	expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX admin_sessions_admin_idx ON admin_sessions (admin_id);

-- O que a equipe fez: quem, o quê, em quem e por quê. `account_id` não é chave estrangeira:
-- o registro continua depois que a conta é excluída. `request_id` (gerado pelo navegador) faz
-- um presente ou envio em massa valer uma vez só, mesmo com duplo clique.
CREATE TABLE admin_audit (
	id BIGSERIAL PRIMARY KEY,
	admin_id BIGINT REFERENCES admin_users(id) ON DELETE SET NULL,
	admin_name TEXT NOT NULL,
	action TEXT NOT NULL,
	target_type TEXT NOT NULL DEFAULT '',
	target_id TEXT NOT NULL DEFAULT '',
	account_id BIGINT,
	reason TEXT NOT NULL DEFAULT '',
	detail JSONB NOT NULL DEFAULT '{}',
	request_id TEXT,
	ip TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX admin_audit_created_idx ON admin_audit (created_at DESC);
CREATE INDEX admin_audit_account_idx ON admin_audit (account_id, created_at DESC) WHERE account_id IS NOT NULL;
CREATE INDEX admin_audit_admin_idx ON admin_audit (admin_id, created_at DESC);
CREATE UNIQUE INDEX admin_audit_request_key ON admin_audit (request_id) WHERE request_id IS NOT NULL;

-- Anotações internas da equipe sobre um jogador (somem junto com a conta).
CREATE TABLE account_notes (
	id BIGSERIAL PRIMARY KEY,
	account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
	admin_name TEXT NOT NULL,
	note TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX account_notes_account_idx ON account_notes (account_id, created_at DESC);

-- Banimento com motivo e prazo. `banned` continua sendo o que o login e os servidores de jogo
-- leem; um banimento com prazo é desfeito pela rotina da API (a cada minuto).
ALTER TABLE accounts ADD COLUMN ban_reason TEXT NOT NULL DEFAULT '';
ALTER TABLE accounts ADD COLUMN ban_until TIMESTAMPTZ;
ALTER TABLE accounts ADD COLUMN banned_at TIMESTAMPTZ;
ALTER TABLE accounts ADD COLUMN banned_by TEXT NOT NULL DEFAULT '';
CREATE INDEX accounts_ban_until_idx ON accounts (ban_until) WHERE banned AND ban_until IS NOT NULL;
CREATE INDEX accounts_last_login_idx ON accounts (last_login);
CREATE INDEX accounts_created_idx ON accounts (created_at);
-- Contas que entraram do mesmo endereço (indício de várias contas de uma pessoa).
CREATE INDEX access_log_ip_idx ON access_log (ip, created_at);
