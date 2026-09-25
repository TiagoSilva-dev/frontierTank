-- Lançamento (roadmap item 4): consentimento com os Termos de Uso e a Política de
-- Privacidade (LGPD/GDPR). A versão aceita fica na conta; quando os textos mudam
-- (LEGAL_VERSION na API), o jogo mostra os textos novos e pede o aceite de novo antes
-- de entrar num servidor de jogo.
ALTER TABLE accounts ADD COLUMN terms_version TEXT NOT NULL DEFAULT '';
ALTER TABLE accounts ADD COLUMN terms_accepted_at TIMESTAMPTZ;

-- O registro de auditoria é apagado depois do prazo da política de privacidade
-- (AUDIT_RETENTION_DAYS; o chat antes, CHAT_RETENTION_DAYS).
CREATE INDEX audit_created_idx ON audit_log (created_at);

-- Marco Civil da Internet (Lei 12.965/2014, art. 15): registros de acesso (IP, data e
-- hora) guardados por 6 meses (ACCESS_LOG_DAYS). Ficam mesmo depois da exclusão da conta
-- (obrigação legal, LGPD art. 16, I), por isso a conta não é chave estrangeira.
CREATE TABLE access_log (
	id BIGSERIAL PRIMARY KEY,
	account_id BIGINT NOT NULL,
	ip TEXT NOT NULL,
	action TEXT NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX access_log_account_idx ON access_log (account_id, created_at);
CREATE INDEX access_log_created_idx ON access_log (created_at);
