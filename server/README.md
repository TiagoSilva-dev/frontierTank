# Frontier Tank online (0.11)

Três peças: **PostgreSQL**, a **API** em Go (`server/api/`) e o **servidor de jogo**, que é este mesmo projeto Godot rodando sem tela (`server/game/`). A arquitetura está em `ARCHITECTURE.md`, seção Online.

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
- `audit_log` guarda compras, craft, cupons, cartas, partidas e chat, para investigar fraudes e reclamações.

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
```

## O que ainda falta

- Leilão (0.12), correio do jogo e troca de moedas.
- Login pela Steam (GodotSteam) e pagamentos; hoje é conta e senha.
- Botão de excluir a conta dentro do jogo (a API já apaga: `DELETE /v1/me`), denúncia no chat.
- Se duas cópias de uma batalha divergirem (o jogador avisa o servidor com `desync`), o jogador continua vendo a própria cópia até o fim; o resultado que vale é sempre o do servidor. O registro de auditoria conta quantas vezes isso acontece.
