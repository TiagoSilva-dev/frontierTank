-- Lançamento (roadmap item 4): denúncias no chat. O servidor de jogo manda a mensagem
-- denunciada com as mensagens em volta (contexto); a equipe analisa pela porta interna
-- (tools/moderate.py) e decide: descartar, avisar ou suspender a conta.
CREATE TABLE chat_reports (
	id BIGSERIAL PRIMARY KEY,
	server_id TEXT NOT NULL DEFAULT '',
	reporter_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
	reporter_name TEXT NOT NULL DEFAULT '',
	reported_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
	reported_name TEXT NOT NULL DEFAULT '',
	reason TEXT NOT NULL,
	note TEXT NOT NULL DEFAULT '',
	message TEXT NOT NULL,
	context JSONB NOT NULL DEFAULT '[]',
	-- O servidor de jogo silenciou o jogador por várias denúncias seguidas.
	auto_muted BOOLEAN NOT NULL DEFAULT false,
	status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'dismissed', 'warned', 'banned')),
	reviewer TEXT NOT NULL DEFAULT '',
	review_note TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	reviewed_at TIMESTAMPTZ
);
CREATE INDEX chat_reports_open_idx ON chat_reports (created_at) WHERE status = 'open';
CREATE INDEX chat_reports_reported_idx ON chat_reports (reported_id, created_at);
CREATE INDEX chat_reports_reviewed_idx ON chat_reports (reviewed_at) WHERE status <> 'open';
