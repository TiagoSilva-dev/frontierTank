-- Leilão 0.12: anúncios em custódia, correio do jogo e as operações já feitas.
-- O servidor de jogo conhece as regras (o que pode ser vendido, taxa, comissão) e manda
-- os campos prontos; aqui ficam a custódia e as transações que movem itens e moedas.

-- Um anúncio guarda o item (o JSON da Mochila ou do mapa) enquanto está à venda.
-- As colunas de busca vêm do servidor de jogo: slot ("arma", "roupa"... ou "mapa"), o id
-- do item (ou a instância do mapa), a qualidade, o nível do item (ou do mapa), o
-- fortalecimento e os ids dos bônus. O preço é em Solares e/ou Estrelas; a comissão fica
-- decidida ao anunciar e é descontada do que o vendedor recebe.
CREATE TABLE auction_listings (
	id BIGSERIAL PRIMARY KEY,
	seller_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
	seller_name TEXT NOT NULL DEFAULT '',
	kind TEXT NOT NULL CHECK (kind IN ('item', 'map')),
	item JSONB NOT NULL,
	slot TEXT NOT NULL,
	item_id TEXT NOT NULL,
	quality TEXT NOT NULL,
	item_level INT NOT NULL,
	strengthen INT NOT NULL DEFAULT 0,
	mods TEXT[] NOT NULL DEFAULT '{}',
	price_solar INT NOT NULL CHECK (price_solar >= 0),
	price_estrela INT NOT NULL CHECK (price_estrela >= 0),
	fee_solar INT NOT NULL DEFAULT 0 CHECK (fee_solar >= 0 AND fee_solar <= price_solar),
	fee_estrela INT NOT NULL DEFAULT 0 CHECK (fee_estrela >= 0 AND fee_estrela <= price_estrela),
	status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'sold', 'cancelled', 'expired')),
	buyer_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	expires_at TIMESTAMPTZ NOT NULL,
	closed_at TIMESTAMPTZ,
	CHECK (price_solar + price_estrela > 0)
);
CREATE INDEX auction_active_idx ON auction_listings (slot, created_at DESC) WHERE status = 'active';
CREATE INDEX auction_expiry_idx ON auction_listings (expires_at) WHERE status = 'active';
CREATE INDEX auction_seller_idx ON auction_listings (seller_id, status, created_at DESC);
CREATE INDEX auction_sold_idx ON auction_listings (kind, item_id, closed_at DESC) WHERE status = 'sold';

-- Correio: o que chega de fora do servidor de jogo (a venda de um anúncio, o item
-- comprado, o item de um anúncio cancelado ou vencido). Fica guardado até o jogador
-- receber; receber grava o perfil na mesma transação.
CREATE TABLE mail (
	id BIGSERIAL PRIMARY KEY,
	account_id BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
	kind TEXT NOT NULL,
	listing_id BIGINT REFERENCES auction_listings(id) ON DELETE SET NULL,
	item_kind TEXT NOT NULL DEFAULT '',
	item JSONB,
	currencies JSONB NOT NULL DEFAULT '{}',
	coins INT NOT NULL DEFAULT 0,
	detail JSONB NOT NULL DEFAULT '{}',
	created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
	claimed_at TIMESTAMPTZ
);
CREATE INDEX mail_unclaimed_idx ON mail (account_id, id) WHERE claimed_at IS NULL;

-- Cada operação do leilão leva um id escolhido pelo servidor de jogo. Se a resposta se
-- perder no caminho, o servidor repete com o mesmo id e recebe o mesmo resultado, sem
-- vender ou devolver duas vezes.
CREATE TABLE auction_ops (
	op_id TEXT PRIMARY KEY,
	account_id BIGINT REFERENCES accounts(id) ON DELETE CASCADE,
	result JSONB NOT NULL,
	created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX auction_ops_created_idx ON auction_ops (created_at);
