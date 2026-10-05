# Pagamentos por dinheiro real (web e celular)

A loja Premium (`shared/balance/store.json`: Passe do Caçador, abas da Mochila, Pacote Fundador e, na 0.28, as skins épicas) vende de dois jeitos, com o **mesmo catálogo, o mesmo pedido e a mesma entrega pelo Correio**:

| Onde | Como paga | Quem confirma |
|---|---|---|
| Versão Steam | Carteira Steam (`docs/STEAM.md`) | a Steam, quando o jogador aprova no overlay |
| Navegador e celular (APK/Xcode/web) | **Stripe Checkout**: cartão e **Pix**, em **reais** (coluna `BRL` de `store.json`) | o Stripe, por webhook assinado (ou pela consulta da sessão) |

Só cosmético e conveniência; nada que dê poder. A regra "o servidor decide" vale igual: o cliente só pede o produto, quem abre o pedido e entrega é o servidor.

## Fluxo

1. O jogador toca em **COMPRAR** (Loja → Premium, Pacote Fundador ou Passe na Caçada). O cliente manda `store_checkout {sku}` ao servidor de jogo.
2. O servidor confere o produto (catálogo, à venda, personagem criado, ainda não tem) e chama `POST /internal/store/checkout` na API.
3. A API cria o pedido (`store_orders`, `provider = 'stripe'`, status `init`) e uma Checkout Session (`card` + `pix`, BRL, vale 1 h; o Pix expira em 30 min). Responde o endereço da página. Pedir o mesmo produto de novo enquanto o pedido está aberto devolve a **mesma página**; mais de 5 pedidos em 10 minutos por conta dão `rate_limited`.
4. O jogo abre a página no navegador (`OS.shell_open`, só `https://`) e passa a perguntar `store_status` a cada 4 s (10 s depois de 2 min, até 1 h). Se o navegador bloqueou a janela, o cartão da loja vira **ABRIR PAGAMENTO** (um clique abre sem bloqueio).
5. Pago, o Stripe chama `POST /v1/store/stripe/webhook`. A API confere a assinatura, o valor e a moeda, e `Store.PayOrder` marca o pedido pago e põe as cartas no Correio **na mesma transação**. O jogador recebe o aviso do Correio e um toast.
6. Plano B se o webhook atrasar ou se perder: `store_status` e a reconciliação do login (`/internal/store/reconcile`) leem a sessão no Stripe e fazem a mesma entrega. `PayOrder` entrega **uma vez só**, venham quantos eventos vierem.

## Eventos tratados

| Evento | Efeito |
|---|---|
| `checkout.session.completed` / `async_payment_succeeded` | se `payment_status = paid`: entrega. Pix ainda não pago fica aberto até o `async_payment_succeeded` |
| `checkout.session.async_payment_failed` | pedido `failed` |
| `checkout.session.expired` | pedido `cancelled` |
| `charge.refunded` | reembolso **total** → pedido `refunded`, cartas ainda fechadas são recolhidas, e o log de auditoria (`store.refunded`) diz quantas peças já tinham sido abertas (retirar do perfil é revisão manual); reembolso parcial não muda nada |

Eventos repetidos (mesmo `id`) são reconhecidos e ignorados (`stripe_events`). Assinatura inválida, evento com mais de 5 min ou webhook sem `STRIPE_WEBHOOK_SECRET` são recusados. Sessão com valor ou moeda diferentes do pedido **não entrega** e cai no log (`store.mismatch`).

## Configuração

| Variável | Para quê |
|---|---|
| `STRIPE_API_KEY` | chave **secreta** (`sk_test_...` para testar, `sk_live_...` em produção). Só no `server/.env` ou nas variáveis do host; nunca no git nem no jogo |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` do endpoint de webhook |
| `STORE_RETURN_URL` | para onde o Checkout devolve o jogador (`https://www.gustfire.online/jogar/`); recebe `?compra=ok|cancelado&pedido=N` |
| `STRIPE_API_BASE` | só para testes (servidor falso) |

Sem `STRIPE_API_KEY` a loja só vende pela Steam (`pay_unavailable`).

### Passo a passo (uma vez)

1. Stripe → **Settings → Payment methods**: ativar **Pix** (modo teste e, depois, produção; exige a conta Stripe do Brasil).
2. **Developers → Webhooks → Add endpoint**: `https://<domínio>/v1/store/stripe/webhook`, eventos `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `checkout.session.async_payment_failed`, `checkout.session.expired` e `charge.refunded`. Copiar o `whsec_...` para `STRIPE_WEBHOOK_SECRET`.
3. No Railway (produção): `STRIPE_API_KEY`, `STRIPE_WEBHOOK_SECRET`, `STORE_RETURN_URL` no serviço da API; **reimplantar a API e o servidor de jogo** (a migração `008_stripe.sql` roda sozinha ao subir).
4. Trocar para a chave `sk_live_...` só depois de uma compra de teste completa e de revisar os Termos.

### Testar no PC

```bash
tools/local.sh                    # sobe a stack; o Stripe fica ligado se STRIPE_API_KEY estiver no server/.env
# opcional, para ver o webhook de verdade (precisa da Stripe CLI):
stripe listen --forward-to localhost:8000/v1/store/stripe/webhook   # imprime o whsec_... para o .env
```

Sem a CLI tudo funciona igual pelo `store_status` (o jogo pergunta a cada 4 s). Cartão de teste: `4242 4242 4242 4242`, qualquer validade futura e CVC. O Pix em modo teste mostra um botão para simular o pagamento.

Testes: `server/api/stripe_test.go` (Go, Stripe falso: assinatura, repetição, valor adulterado, Pix que falha/expira, reembolso, limite) e `card_tests` em `tests/net_e2e_tests.gd` (cliente + servidor de jogo, API em memória, em que o pedido conta como pago na primeira consulta).

## Fora do escopo por enquanto

- Só **BRL**. Outras moedas pedem outra coluna de preços e `currency_unsupported` já cobre a falta.
- Disputa/chargeback (`charge.dispute.*`) não é tratada: aparece no painel do Stripe.
- Nota fiscal e imposto: ver com o contador.
- **Google Play e App Store**: bem digital dentro de app publicado em loja exige o pagamento da própria loja (comissão de 15–30%). Este caminho vale para o site, o APK avulso e o projeto Xcode (`docs/MOBILE.md`); antes de publicar em loja é preciso decidir.
