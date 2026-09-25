-- Steam (lançamento, roadmap item 4): conta ligada a um SteamID (login por ticket) e os
-- pedidos da loja paga pela carteira Steam (microtransações). O que foi comprado chega pelo
-- Correio, na mesma transação que marca o pedido como pago; assim nada se perde se a
-- conexão cair entre o pagamento e a entrega.
ALTER TABLE accounts ADD COLUMN steam_id TEXT;
CREATE UNIQUE INDEX accounts_steam_key ON accounts (steam_id) WHERE steam_id IS NOT NULL;

CREATE SEQUENCE store_order_seq START 100000;

-- Um pedido guarda o produto (sku e o item da Steam), os itens que ele entrega, o valor na
-- moeda da carteira do jogador e a situação: init (esperando o jogador aprovar na Steam),
-- paid (FinalizeTxn feito e itens no Correio), cancelled, failed ou refunded.
-- Fica 5 anos (obrigações fiscais e de consumo) mesmo se a conta for excluída.
CREATE TABLE store_orders (
	order_id BIGINT PRIMARY KEY,
	account_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
	steam_id TEXT NOT NULL,
	sku TEXT NOT NULL,
	steam_item_id BIGINT NOT NULL,
	description TEXT NOT NULL,
	items JSONB NOT NULL,
	amount INT NOT NULL CHECK (amount > 0),
	currency TEXT NOT NULL,
	status TEXT NOT NULL DEFAULT 'init' CHECK (status IN ('init', 'paid', 'cancelled', 'failed', 'refunded')),
	steam_status TEXT NOT NULL DEFAULT '',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX store_orders_account_idx ON store_orders (account_id, status, created_at);
CREATE INDEX store_orders_created_idx ON store_orders (created_at);
