-- Pagamento por dinheiro real fora da Steam (web e celular): Stripe Checkout com cartão e
-- Pix. O pedido continua na mesma tabela da Steam e é entregue pelo mesmo caminho (cartas
-- do Correio na transação que marca o pedido como pago); só muda quem confirma o pagamento.
-- steam_id e steam_item_id deixam de ser obrigatórios (pedido do Stripe não tem Steam).
ALTER TABLE store_orders ALTER COLUMN steam_id DROP NOT NULL;
ALTER TABLE store_orders ALTER COLUMN steam_item_id DROP NOT NULL;
ALTER TABLE store_orders ADD COLUMN provider TEXT NOT NULL DEFAULT 'steam' CHECK (provider IN ('steam', 'stripe'));
-- Sessão do Checkout (cs_...) e o pagamento (pi_...), para achar o pedido nos eventos.
ALTER TABLE store_orders ADD COLUMN provider_ref TEXT;
ALTER TABLE store_orders ADD COLUMN payment_ref TEXT;
-- Endereço da página de pagamento: reabrir o mesmo pedido não cria outra sessão.
ALTER TABLE store_orders ADD COLUMN checkout_url TEXT;
CREATE UNIQUE INDEX store_orders_provider_ref_key ON store_orders (provider_ref) WHERE provider_ref IS NOT NULL;
CREATE INDEX store_orders_payment_ref_idx ON store_orders (payment_ref) WHERE payment_ref IS NOT NULL;
-- Eventos do Stripe já tratados (o Stripe reenvia): cada id vale uma vez.
CREATE TABLE stripe_events (
	event_id TEXT PRIMARY KEY,
	kind TEXT NOT NULL,
	received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
