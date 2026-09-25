# Frontier Tank online (0.11, Leilão na 0.12)

Três peças: **PostgreSQL**, a **API** em Go (`server/api/`) e o **servidor de jogo**, que é este mesmo projeto Godot rodando sem tela (`server/game/`). A arquitetura está em `ARCHITECTURE.md`, seções Online e Leilão e Correio. O Leilão (0.12) não pede configuração nova: a migração `002_auction.sql` roda sozinha quando a API sobe.

## Subir tudo com Docker

```bash
cd server
cp .env.example .env
docker compose up --build -d
```

Antes, troque em `.env` a senha do banco (`DB_PASSWORD`) e a chave interna (`INTERNAL_KEY`, com pelo menos 16 caracteres). A primeira construção baixa o Godot 4.7.2 e importa os assets, o que leva alguns minutos.

- API pública: `http://localhost:8080` (o jogo usa esse endereço por padrão). Teste com `curl localhost:8080/v1/servers`.
- Servidor de jogo: `ws://localhost:7350`. A API mostra na lista o endereço de `GAME_PUBLIC_URL`, então para jogar de outro computador use ali o IP ou o domínio da máquina.
- A porta interna da API (8081) não sai da rede do Docker.
- `docker compose stop game` desliga o servidor de jogo com calma: ele salva todos os perfis e libera as contas antes de sair.
- Os dados ficam no volume `db-data`. `docker compose down` mantém o volume; `docker compose down -v` apaga tudo.

Variáveis do `.env`:

| Variável | Para quê |
|---|---|
| `DB_PASSWORD` | Senha do PostgreSQL. |
| `INTERNAL_KEY` | Chave que a API exige dos servidores de jogo. |
| `GAME_PUBLIC_URL` | Endereço que os jogadores usam para chegar ao servidor de jogo (`ws://` ou `wss://`). |
| `GAME_NAME` | Nome que aparece na tela de entrada. |
| `TEST_COUPONS` | `1` libera os cupons de teste (TESTARTUDO, MOEDAS, MAPAS...). Só para testes fechados. |
| `BOT_FILL_SECONDS` | Quanto tempo uma sala procura outra sala antes de completar com rivais de IA. |
| `ALLOW_ORIGIN` | Origem liberada no CORS para a versão web. |
| `LEGAL_VERSION` | Versão dos Termos de Uso e da Política de Privacidade (`legal/*.md`, igual a `Legal.VERSION` no jogo). Mudar faz todos aceitarem de novo antes de jogar online. |
| `REPORT_MUTE` | Quantos jogadores diferentes denunciando alguém em 10 minutos o silenciam no chat por 10 minutos (3). |
| `REPORT_RETENTION_DAYS` | Por quanto tempo uma denúncia analisada fica guardada (180). |
| `AUDIT_RETENTION_DAYS`, `CHAT_RETENTION_DAYS`, `ACCESS_LOG_DAYS` | Prazos da Política de Privacidade: registro de atividades (365), chat dentro dele (90) e registros de acesso do Marco Civil (183, isto é, 6 meses). |

## Jogar

1. Abra o jogo (Jogar.cmd). Na tela de entrada aparece **S1 · Nova Era** (vindo da API) e o **Modo offline**.
2. Escolha o servidor, digite uma conta e uma senha e clique em **CRIAR CONTA** (depois basta **ENTRAR**). "Lembrar" guarda a sessão em `user://online.cfg`.
3. Na cidade, crie o personagem (o nome é único no servidor). O Salão mostra as salas e os jogadores de verdade.
4. **Sala → Início** procura outra sala do mesmo tamanho e nível parecido; sem ninguém, depois de `BOT_FILL_SECONDS` entram rivais de IA. Na **Instância**, os outros jogadores entram na sala, clicam em **Preparar** e o dono clica em **Início**.

Para o jogo usar outra API: `--api=https://api.seudominio` na linha de comando, ou a chave `api` em `user://online.cfg`.

## Sem Docker (LAN ou testes)

O servidor de jogo roda sozinho, com contas em memória (nada é salvo e qualquer conta entra):

```bash
godot --headless --path . -- --server --api=memory --test-coupons=1
```

Parâmetros (ou as variáveis de ambiente `FT_*` equivalentes): `--port` (7350), `--bind`, `--public-url`, `--name`, `--id`, `--capacity`, `--test-coupons`, `--bot-fill`, `--api` (URL da porta interna ou `memory`), `--api-key`. No modo `memory` não há API para listar servidores; é o modo usado por `tests/net_e2e_tests.gd`.

## Produção (antes de abrir ao público)

- Coloque um proxy com TLS (Caddy ou nginx) na frente: `https://` para a API e `wss://` para o servidor de jogo, e use `TRUST_PROXY=1` na API.
- Um servidor de jogo aguenta várias batalhas ao mesmo tempo (cada uma é uma cópia da partida no mesmo processo). Para mais jogadores, suba mais serviços `game` com `FT_ID`, `FT_NAME` e portas diferentes; todos aparecem na lista e a presença impede a mesma conta em dois servidores.
- Faça backup do PostgreSQL (`pg_dump`) com frequência.
- **Privacidade**: a API guarda a versão dos textos aceita (`accounts.terms_version`), os registros de acesso (`access_log`: IP, data e hora do cadastro e dos logins, 6 meses pelo Marco Civil) e apaga o registro de atividades pelos prazos acima. Rotas: `GET /v1/legal`, `POST /v1/me/terms`, `GET /v1/me/export` (cópia dos dados), `DELETE /v1/me` e, para o servidor de jogo, `POST /internal/accounts/{id}/delete`. Antes de abrir ao público, preencha `legal/controller.json` e faça a revisão jurídica dos textos.
- **Denúncias no chat**: ficam em `chat_reports`, com a mensagem, as linhas em volta, o motivo e se o servidor silenciou o jogador. A equipe analisa pela porta interna, na própria máquina ou por um túnel SSH (`ssh -L 8081:localhost:8081 ...`): `python tools/moderate.py --key <INTERNAL_KEY> list` mostra as abertas e `python tools/moderate.py --key <INTERNAL_KEY> review <id> dismissed|warned|banned --reviewer <nome>` decide. **banned** suspende a conta (o login e os servidores de jogo recusam) e o servidor de jogo desconecta o jogador em até 10 s (no próximo heartbeat).
- `audit_log` guarda compras, craft, cupons, cartas, partidas e chat, para investigar fraudes e reclamações. O Leilão grava `auction.list`, `auction.buy`, `auction.sold`, `auction.cancel`, `auction.expire` e `mail.claim` na mesma transação da operação.
- Leilão: os itens à venda ficam em `auction_listings` e o que espera entrega em `mail`. Um anúncio vencido volta ao correio do vendedor em até um minuto. Para ver o que um jogador tem à venda: `SELECT id, item_id, price_solar, price_estrela, status FROM auction_listings WHERE seller_id = <conta>;`.

## Testes

```bash
# API (Go), com um PostgreSQL de teste
docker run -d --name ft-pg-test -e POSTGRES_USER=frontier -e POSTGRES_PASSWORD=frontier -e POSTGRES_DB=frontier -p 5433:5432 postgres:17-alpine
cd server/api && TEST_DATABASE_URL=postgres://frontier:frontier@localhost:5433/frontier?sslmode=disable go test ./...

# Lockstep, operações e recompensas; servidor + dois jogadores de verdade
godot --headless --path . --script tests/net_tests.gd
godot --headless --path . --script tests/net_e2e_tests.gd

# Contra a pilha Docker no ar (cria uma conta e joga uma partida contra IA)
godot --headless --path . --script tests/online_stack_check.gd -- --api=http://localhost:8080

# Leilão contra a API e o PostgreSQL de verdade (o servidor de jogo roda dentro do teste;
# precisa alcançar a porta interna 8081, que o docker-compose não publica: rode a API
# fora do Docker ou publique a porta só na sua máquina)
godot --headless --path . --script tests/auction_stack_check.gd -- --api=http://localhost:8080 --internal=http://localhost:8081 --key=<INTERNAL_KEY>
```

## O que ainda falta

- Troca de moedas (Estrela ↔ Solar) e lances no Leilão; o Correio só leva o que vem do Leilão.
- Login pela Steam (GodotSteam) e pagamentos; hoje é conta e senha.
- Se duas cópias de uma batalha divergirem (o jogador avisa o servidor com `desync`), o jogador continua vendo a própria cópia até o fim; o resultado que vale é sempre o do servidor. O registro de auditoria conta quantas vezes isso acontece.
