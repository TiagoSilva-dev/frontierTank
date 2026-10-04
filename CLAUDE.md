# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Projeto

Gustfire (antes *Frontier Tank: Nova Era*): artilharia por turnos em pixel art no estilo DDTank, em **Godot 4.7** (GDScript), com modo offline e online. Os nomes internos antigos continuam (pasta `frontierTank`, projeto Docker `frontier-tank`, banco `frontier`, identidade Steam `frontiertank`); não renomeie. Textos, docs e commits estão em português; o português é o idioma-fonte do jogo.

`ARCHITECTURE.md` é a referência detalhada (fluxo de telas, partida, instâncias, online, leilão); `README.md` e `server/README.md` cobrem as funções e o deploy. Leia a seção relevante antes de mexer em um sistema.

## Comandos

Godot: `GODOT_BIN` ou `godot` no PATH (`tools/run.ps1` procura o executável do Windows). Abrir o jogo: `Jogar.cmd` / `tools/run.ps1` (`-Editor` abre o editor).

```bash
# importar assets (necessário depois de mudar arte/áudio/scripts novos)
godot --headless --path . --editor --import --quit

# um teste (cada arquivo de tests/ é um SceneTree que sai com quit(1) se falhar)
godot --headless --path . --script tests/combat_tests.gd

# suíte completa (todo tests/*_tests.gd; `net` e `net_e2e` por último):
#   powershell -File tools/run.ps1 -Test        # Windows
#   tools/test.sh [-j] [suite ...]              # Linux/macOS/WSL; -j roda em paralelo
# `exchange_online_tests` fica de fora: precisa da API com PostgreSQL no ar (docs/CAMBIO.md)

# i18n: toda mudança em textos visíveis exige atualizar locale/
python tools/i18n.py            # atualiza messages.pot e en.po
python tools/i18n.py --check    # falha se o .pot estiver velho ou faltar inglês

# site/wiki: os números saem de shared/balance/*.json
python tools/build_site.py

# stack completa (Postgres + API Go + servidor de jogo + web) em http://localhost:8000
tools/local.sh [status|logs|stop|reset]    # Windows: SubirLocal.cmd

# celular, sem loja (docs/MOBILE.md): modo toque no navegador, APK e projeto Xcode
tools/local.sh                             # jogo no celular: http://<ip>:8000/jogar/ (GAME_PUBLIC_URL com o IP da rede; o Docker Desktop publica a porta)
python tools/mobile_build.py android --api http://<ip>:8000   # APK em build/android (templates e setup-android antes)
python tools/mobile_build.py ios           # projeto Xcode zipado em build/Gustfire-xcode.zip (rodar no Mac)
python tools/mobile_build.py share         # APK e zip em http://<ip>:8062/ (nginx em Docker, sem passo de administrador)
godot --path . -- --touch=1 --screen=battle --demo=1 --out=x.png   # captura em modo toque (?touch=1 na web)

# API em Go (usa um banco DESCARTÁVEL: o harness recria as tabelas)
cd server/api && TEST_DATABASE_URL=postgres://frontier:frontier@localhost:5433/frontier?sslmode=disable go test ./...
```

Os `tests/*_visual_check.gd` e `*_balance.gd` geram capturas/simulações, não fazem parte da suíte. Teste de desempenho: `python tools/web_build.py export` e `node tools/web_bench.cjs`.

## Arquitetura (o que exige ler vários arquivos)

- **Três peças online**: o cliente Godot (`client/`), a **API em Go** (`server/api/`, PostgreSQL, migrações em `server/api/migrations`, roda sozinhas ao subir) e o **servidor de jogo**, que é **este mesmo projeto Godot rodando sem tela** (`server/game/`). O código de regras em `client/` e `shared/` roda nos dois lados; mudar uma regra no cliente muda o servidor.
- **Lockstep**: online, servidor e cada jogador rodam a mesma `LocalMatch` (`client/systems/match.gd`) a partir da mesma semente, e só os comandos cruzam a rede (`client/net/lockstep_driver.gd`). Tudo na simulação tem de ser **determinístico**: passo fixo, o `rng` da partida e nada de `randf()` global, tempo real ou ordem de dicionário não controlada. O visual (`projectile.gd`, `*_fx.gd`, escala de sprites) não pode alterar o acerto; `tests/pow_tests.gd` e `tests/ability_tests.gd` verificam isso.
- **Autoridade**: offline é local; online o servidor decide tudo (compras, Ferreiro, drops, EXP, cartas, leilão). `PlayerProfile.apply_op` (`client/systems/profile.gd`) é a **porta única** das mudanças do perfil, com checagem de tipos; o mesmo código atende o save local e o JSON do servidor. Mexer em saves exige manter a leitura dos formatos antigos (hoje v10, lê v1–v9; cada versão está comentada no topo de `profile.gd`).
- **Dados de balanceamento** ficam em `shared/balance/combat.json` (mapas, itens, ferramentas, PvE, instâncias, inimigos, bots) e `items.json` (armas, qualidades, fortalecimento, afixos, moedas); `pets.json` (mascotes e Caçada), `missions.json`, `store.json`, `achievements.json` e `tutorial.json` (as lições do treino) completam. Os que mudam regras do servidor (`combat`, `items`, `store`, `missions`, `pets`) entram no hash de conteúdo (`NetClient.content_version`): mudou um, reimplante o servidor. Eles alimentam o jogo, os testes **e a wiki** (`tools/build_site.py`); rode a ferramenta depois de mudar números.
- **Modo toque** (celular/tablet, `client/systems/touch_mode.gd`, `touch_assist.gd`, `client/ui/touch_controls.gd`): os botões da batalha apertam as **mesmas teclas** do teclado (`Input.parse_input_event`), então partida, intenções online e lockstep não mudam; `TouchAssist` faz o mouse a partir do dedo (encaixe no botão vizinho, toque longo no lugar do hover, rolagem). A posição do ponteiro vem de `TouchMode.pointer(self)`, nunca de `get_global_mouse_position()`. As fontes não têm ▲ ▼ (use ↑ ↓ nos textos).
- **Fluxo de telas**: `client/scripts/main.gd` troca as telas num `CanvasLayer` (entrada → cidade → salão → sala → partida → resultado). Mochila, Ferreiro, Loja, Leilão e Correio abrem por cima. `ui_kit.gd` concentra molduras, fonte e helpers.
- **Terreno**: máscara RGBA onde o alfa é a colisão (`terrain.gd`); a mesma máscara serve de apoio, colisão, crateras e desenho.
- **Arte e áudio** são gerados por ferramentas, não pintados à mão: PixelLab (MCP `pixellab`, `docs/PIXELLAB_*.md`), `tools/make_sfx.py`/`make_music.py` (síntese) e `tools/import_pixellab_skin.py`. `tools/character_anchors.py` e `terrain_pieces.py` produzem dados que o jogo lê; rode de novo quando a arte mudar.

## Convenções

- Texto visível ao jogador: `tr("...")` / `Lang.t("...")` com o literal inteiro como argumento, ou comentário `# i18n` no fim da linha em tabelas constantes. Rode `tools/i18n.py --check`.
- Resolução lógica 1280×720, filtro nearest, renderizador Compatibility (precisa funcionar na versão web, sem threads). Tamanho mínimo de fonte 16.
- `server/.env` e `api.env` ficam fora do git (`server/.env.example` é o modelo).

## Jev (TypeSafe)

`tools/jev_triage.py` e `tools/jev_review.py` já usam o Jev (modelo System One que devolve respostas tipadas, não texto): a triagem classifica um pedido antes de explorar o código e a revisão pontua opções de design. A chave vem **só** de `TYPESAFE_API_KEY` no ambiente e vai **só** para `api.typesafe.ai`. O Jev não gera código nem acelera o Claude Code; use-o dentro do produto ou dessas ferramentas, nunca em simulação determinística.

## Armadilhas

- `.mcp.json` é versionado e deve usar `Bearer ${PIXELLAB_API_TOKEN}`; não escreva o token no arquivo.
- `tests/*.gd` rodam com `--script` e dependem de `.godot/` importado; sem o `--import` antes, falham por classes não encontradas.
- Os testes de rede e do Go que usam PostgreSQL só podem apontar para banco descartável.
