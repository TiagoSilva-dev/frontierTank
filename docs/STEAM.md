# Steam — integração e página "em breve"

Roadmap, item 4: lançamento na Steam. Este documento junta o que está pronto no código, o que precisa ser configurado na Steamworks e a ordem dos passos até a página "em breve" e o acesso antecipado.

## O que está pronto

| Parte | O que faz | Onde |
|---|---|---|
| **GodotSteam no jogo** | `SteamService` usa o singleton `Steam` do GodotSteam **pelo nome**, então o projeto roda sem a extensão (web, testes, builds sem Steam). Inicia a Steam (`steamInitEx`, nas duas ordens de argumentos que o GodotSteam já teve), roda os callbacks, pede o ticket da Web API (`getAuthTicketForWebApi` com a identidade `frontiertank`), repassa a resposta do overlay de compra (`microtransaction_auth_response`) e libera conquistas (`setAchievement` + `storeStats`). | `client/net/steam_service.gd` |
| **Login por ticket** | Rodando pela Steam, a entrada mostra **ENTRAR COM A STEAM** (e "Usar conta e senha"). O ticket vai para `POST /v1/auth/steam`; a API confere na Steam (`ISteamUserAuth/AuthenticateUserTicket`) e entra na conta ligada àquele SteamID. Um SteamID novo só ganha conta depois do aceite dos Termos e da Política (a mesma tela do cadastro). A conta criada assim não tem senha: excluir pede para digitar EXCLUIR e um ticket novo da mesma Steam. | `client/ui/title_screen.gd`, `server/api/steam.go` |
| **Vincular** | Quem criou conta com senha (testes na web) liga a Steam em **AJUDA → Minha conta → Vincular à Steam** (`POST /v1/me/steam`); depois entra pela Steam na mesma conta. | `client/ui/account_screen.gd` |
| **Loja paga (microtransações)** | Aba **Premium** da loja com o catálogo `shared/balance/store.json`. **Comprar na Steam** → o servidor de jogo confere o produto e pede `/internal/store/init` → a API descobre a moeda da carteira (`GetUserInfo`), grava o pedido e chama `InitTxn` → o overlay da Steam pergunta ao jogador → o jogo recebe a resposta e pede `store_finalize` → a API chama `FinalizeTxn` e, **na mesma transação**, marca o pedido como pago e põe os itens no **Correio**. Recusado: o pedido é cancelado. Aprovado com o jogo fechado: o próximo login entrega (`/internal/store/reconcile` com `QueryTxn`). | `client/systems/premium_store.gd`, `server/game/game_server.gd`, `server/api/steam.go` |
| **Nada de vender poder** | Só entram na loja paga cosméticos marcados `premium` em `items.json`, **sem atributos** (o teste falha se alguém colocar um item com atributo). Chegam vinculados (não vão ao leilão), sem bônus, e ficam fora da loja de ouro, do cupom de teste e das roupas dos bots. O catálogo inicial são 4 tinturas de cabelo e o pacote com as 4. | `shared/balance/items.json`, `tests/launch_tests.gd` |
| **Conquistas** | 11 conquistas em `shared/balance/achievements.json` (vitórias, partidas, nível, +12, arma Verdadeira, Super Verdadeira, mapa 16, colecionador). Saem do **perfil online** (a cópia do servidor), nunca do modo offline, cujo save o jogador pode editar. | `client/systems/achievements.gd` |
| **Builds** | Presets **Windows Desktop** e **Linux** (Steam Deck) em `export_presets.cfg`, com o recurso `steam` e os mesmos filtros da web. O export Linux foi testado aqui: roda e faz o teste de desempenho. | `export_presets.cfg` |
| **Página da loja** | Textos em pt e en (`store/steam/page_pt.md`, `page_en.md`), cápsulas em todos os tamanhos, ícones das conquistas com a tabela para cadastrar, capturas nos dois idiomas e os modelos do SteamPipe. | `store/steam/`, `tools/steam_store.py` |

Testes: `server/api/steam_test.go` (Steam falsa em Go: login, vínculo, moeda, pedido, aprovação, idempotência, reconciliação, cancelamento, exclusão com ticket, exportação), `tests/launch_tests.gd` e `tests/net_e2e_tests.gd` (GodotSteam falso: inicialização nas duas versões, ticket, overlay, conquistas, aba Premium, compra recusada e aprovada até o Correio). A cadeia inteira (jogo → API → Steam Web API falsa → servidor de jogo → Correio) também foi conferida com a pilha rodando.

## Instalar o GodotSteam (só para as builds da Steam)

1. No Godot 4.7, AssetLib → "GodotSteam GDExtension 4.x" (a versão para Godot 4.4+). Instalar em `addons/godotsteam/`. A extensão traz a `steam_api64.dll`/`libsteam_api.so` da Steamworks SDK.
2. Para testar no editor sem a loja: criar `steam_appid.txt` na raiz do projeto com o App ID (480 é o "Spacewar" de testes da Valve) e abrir a Steam. `SteamService.APP_ID = 0` deixa a Steam decidir; quando a Valve der o App ID do jogo, pôr aqui.
3. O export copia as bibliotecas do GodotSteam junto do executável. `steam_appid.txt` **não** vai no depot (o SteamPipe já exclui).
4. `TICKET_IDENTITY` (`frontiertank`) no jogo precisa ser igual a `STEAM_IDENTITY` na API.

Sem a extensão, nada muda: a entrada mostra conta e senha, a aba Premium avisa "Só na versão Steam" e as conquistas ficam paradas.

## Configurar a API

Variáveis em `server/.env` (modelo em `server/.env.example`):

| Variável | Para quê |
|---|---|
| `STEAM_APP_ID` | App ID do jogo. |
| `STEAM_WEB_API_KEY` | Chave **de publicador** (Steamworks → Users & Permissions → Manage Web API Key). Fica só no servidor; nunca no jogo. |
| `STEAM_IDENTITY` | Identidade dos tickets (`frontiertank`). |
| `STEAM_MICROTXN_SANDBOX` | `1` usa `ISteamMicroTxnSandbox`: compras de teste, ninguém é cobrado. Só trocar para `0` com a loja aprovada. |
| `ORDER_RETENTION_DAYS` | Quanto tempo os pedidos ficam (1826 = 5 anos, obrigações fiscais e de consumo). |

Sem `STEAM_APP_ID` e `STEAM_WEB_API_KEY` a Steam fica desligada (`/v1/auth/steam` responde `steam_unavailable`).

**Preços**: cada produto de `store.json` tem o preço em centavos por moeda (USD, EUR, GBP, BRL, CAD, AUD, MXN e PLN hoje). A API usa a moeda da carteira do jogador; moeda sem preço é recusada (`currency_unsupported`) em vez de cobrar em outra. Antes de abrir a loja, revisar os preços e acrescentar as moedas que a Steam aceita para o público do jogo.

## Na Steamworks

1. **Pagar a taxa** (US$ 100 por app) e preencher dados fiscais e bancários da empresa (os mesmos de `legal/controller.json`).
2. **Página da loja** (Store Page Admin): textos de `store/steam/page_pt.md` e `page_en.md`; imagens de `store/steam/capsules/` (cápsulas horizontal, pequena, principal, vertical, fundo da página) e `screenshots/` (pelo menos 5; as geradas são 1280×720, o mínimo aceito); etiquetas, idiomas, requisitos e o questionário de conteúdo (chat de usuários, compras dentro do jogo).
3. **Biblioteca** (Library Assets): `library_capsule.png` (600×900), `library_header.png` (920×430), `library_hero.png` (3840×1240, sem texto) e `library_logo.png` (transparente).
4. **Conquistas** (Stats & Achievements): uma por linha de `store/steam/achievements/achievements.csv`, com o **API Name** igual ao `id`, nomes e descrições em pt-BR e en e os dois ícones 256×256. Publicar as mudanças.
5. **Microtransações**: ativar as compras dentro do jogo e informar a URL/IP do servidor da API se a Valve pedir. Testar tudo com `STEAM_MICROTXN_SANDBOX=1` antes.
6. **"Em breve"**: enviar a página para revisão (alguns dias úteis). A Valve pede que a página fique "em breve" por pelo menos 2 semanas antes do lançamento; o plano é **meses antes**, para juntar listas de desejos.
7. **Build**: exportar os presets Windows e Linux para `build/windows` e `build/linux`, preencher os IDs em `store/steam/steampipe/*.vdf` e enviar com `steamcmd +login <conta> +run_app_build store/steam/steampipe/app_build.vdf +quit`. Colocar no ar num branch (beta) para testar antes do padrão.
8. **Acesso antecipado gratuito**: marcar Early Access e Free to Play; as respostas estão nos textos da página.

## Gerar de novo a arte e as listas

```bash
pip install pillow
python tools/steam_store.py capsules       # store/steam/capsules/
python tools/steam_store.py achievements   # store/steam/achievements/ (ícones e CSV)
python tools/steam_store.py screenshots    # store/steam/screenshots/pt e en (usa o Godot; xvfb-run no Linux sem tela)
```

As cápsulas saem da arte da entrada (`assets/title`) em escala inteira, para os pixels ficarem quadrados. Se o logotipo mudar (ver a pendência do subtítulo abaixo), é só gerar de novo.

## Pendências antes da página "em breve"

- **Subtítulo "Nova Era"**: é também o nome de uma edição brasileira do DDTank (`docs/ROADMAP.md`, revisão de nomes). Decidir antes de publicar, porque está no logotipo, nas cápsulas e no nome da página.
- **Revisão jurídica** dos Termos, da Política e das exigências do ECA Digital (verificação de idade, ferramentas para responsáveis) para um jogo com chat e compras.
- **Estornos**: a Steam informa reembolsos e chargebacks por `ISteamMicroTxn/GetReport`. Falta a rotina que lê o relatório e retira os itens (o pedido já guarda tudo o que ela precisa).
- **Catálogo**: 4 tinturas são o começo; a arte dos cosméticos exclusivos (e o passe de temporada) vem depois. Nenhum item com atributo pode entrar.
- **Capturas em 1920×1080**: as de agora são 1280×720 (o mínimo). Para a página definitiva, capturar em 1080p quando houver arte em escala para isso.
