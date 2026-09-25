# Roadmap — próximas implementações

Lista do que vamos fazer depois da 0.7. Cada item traz o objetivo, o que existe hoje no código, a proposta e o que ainda está em aberto. Os números são pontos de partida para testar, não valores fechados.

| # | Item | Precisa de servidor? | Entrega |
|---|------|----------------------|---------|
| 1 | POW mais bonito, arma e projétil maiores | Não | 0.8 — **feito** |
| 2 | Instâncias de 3 fases e **sistema de mapas** (no lugar das dificuldades) | Não para desenvolver e jogar solo; sim para grupos | 0.9 — **feito** (offline e solo); grupos online na 0.11 — **feito** |
| 3 | Atributos aleatórios, moedas estilo PoE 2 e Leilão | Moedas e craft não; o leilão sim | 0.10 (moedas e craft) — **feito**; 0.12 (leilão) — **feito** |
| — | **Backend**: contas, servidor de jogo, partidas online | É o servidor | 0.11 — **feito** |
| 4 | Distribuição e monetização | Sim | Decidido: Steam no lançamento, web para testes; português e inglês — **feito**; preparação do lançamento (web, nomes, privacidade, denúncia, Steam) na 0.13 — **feito**, faltam as pendências externas do checklist |

## Decisões tomadas (25/09/2026)
- **Vamos ganhar dinheiro com o jogo.** Lançamento na Steam; a versão web serve para testes fechados; não haverá launcher próprio (item 4).
- **Sem qualidade nova de arma.** O topo continua sendo a linha Verdadeira: Verdadeira e as 3 Super Verdadeiras que já são exclusivas de drop. As "armas lendárias" do loot são essas.
- **Itens terão atributos bônus aleatórios**, que as moedas do item 3 modificam.
- **Monetização sem vender poder**: jogo gratuito com cosméticos e conveniências (item 4.2).
- **Mapas de nível 1 a 16.**
- **Moedas com nomes próprios** (item 3.2).
- **Público internacional desde o começo**: jogo em português e inglês no lançamento (item 4.3).
- **Nada de tempo com bots agora.** A escala por grupo considera só jogadores; regras para bots aliados ficam para depois.
- **Primeiro a web, a Steam depois (25/09/2026).** A taxa da Steam (US$ 100) fica para mais tarde; os primeiros testes são na versão de navegador, primeiro tudo no computador (`SubirLocal.cmd` / `tools/local.sh`) e depois numa VM com a mesma pilha. O que já foi feito para a Steam (login por ticket, loja, conquistas, página) fica pronto para quando ela vier.
- **As dificuldades Normal, Difícil, Heroico e Pesadelo saem.** Entra o sistema de mapas do PoE 2: mapas são itens que caem nas instâncias, e o nível do mapa define a dificuldade e a recompensa.

## Dependência: servidor
**Feito na 0.11** (detalhes em `ARCHITECTURE.md`, seção Online, e em `server/README.md`). Uma mudança em relação à sugestão abaixo: as regras da economia (compra, Ferreiro, moedas, cupons, drops, cartas) rodam no **servidor de jogo em Godot**, com o mesmo GDScript do jogo, e não em Go. Assim não existe uma segunda cópia das regras para manter igual; o Go ficou com contas, sessões, o perfil gravado no PostgreSQL (com versão contra gravações concorrentes), nomes únicos, auditoria, lista de servidores e presença. O leilão (0.12) entrou no Go, com a custódia em transação no PostgreSQL; as regras de o que pode ser vendido, taxa e comissão ficam no servidor de jogo (`Auction`).

Texto original:
O jogo hoje não tem servidor. `LobbyDirectory` simula salas e jogadores, e o progresso fica salvo só no computador (`ARCHITECTURE.md`, seção Rede). Grupos de jogadores reais, o leilão e qualquer economia que valha dinheiro precisam de um backend com autoridade sobre dano, drops, rolagens e moedas. Como vamos monetizar e ter troca entre jogadores, isso é obrigatório antes do lançamento: com o save local, qualquer um edita o arquivo e cria Solares.

- Até o backend, as versões 0.9 e 0.10 rodam offline e solo para desenvolver e testar. Na migração, drops, rolagens e craft passam para o servidor e o save local vira só cache.
- **Sugestão de arquitetura:** Go + PostgreSQL para contas, inventário, moedas e leilão, como já estava planejado; a **partida** roda num Godot sem tela (headless) no servidor, reaproveitando `match.gd`, `terrain.gd` e `ballistics.gd`. Assim a física não é reescrita em Go e o problema de paridade entre linguagens citado na arquitetura some.
- Comunicação por **WebSocket** (`WebSocketPeer`), porque o navegador não abre conexão direta (ENet). O mesmo servidor atende a Steam e a web.

---

## 1. Especiais POW: animação fluida, efeitos melhores, arma e projétil maiores

**Objetivo:** o POW deve parecer um golpe especial de verdade, com animação suave e efeitos bonitos, e a arma e o projétil devem ficar maiores na tela **sem aumentar o hitbox**.

**Hoje:**
- `pow_fx.gd` tem a aura (chamas douradas enquanto o POW está armado) e o `burst` (clarão, coluna de luz, ondas, raios e a arte PixelLab do POW crescendo de 1,5× para 3,2× com um tween).
- `pow_banner.gd` mostra o estouro "POW!" com linhas de velocidade e o nome do especial.
- `projectile.gd` desenha o sprite com `sprite_size` (vem de `projectile.size` em `items.json`, hoje 24 px). O acerto é calculado pela posição do projétil contra `fighter.hit_radius` e contra a máscara do terreno, então o tamanho desenhado **já está separado da colisão**.
- A arma nas costas é escalada em `look_rig.gd` (`back_weapon.scale`).

**Proposta:**
- [x] **Animação em fases**: preparação (o personagem recua e a arma brilha), carga (a aura cresce e as partículas são puxadas para a arma), disparo (clarão e recuo), voo (projétil com halo e rastro próprio do POW) e impacto (hit-stop de 60–100 ms, tremor, ondas e fumaça).
- [x] **Mais quadros**: animar a arte de cada POW com PixelLab (`animate_image`, cerca de 2 gerações por clipe de 8 quadros) em vez de só escalar uma imagem parada; curvas de easing em todos os tweens.
- [x] **Um impacto próprio por arma**: hoje o estouro é quase o mesmo para todas. Cada um dos 12 POW ganha a sua cor, forma e partículas (lava na Fogo Intenso, cristais de gelo, raios duplos no Trovão, corações no Bumerangue do Amor e assim por diante).
- [x] **Partículas de verdade** (`CPUParticles2D`, que funciona no renderizador Compatibility e no web) para brasas, faíscas e poeira, no lugar de parte do desenho feito à mão.
- [x] **Projétil maior**: por exemplo 24 → 36 px no tiro normal e 1,6× a mais no tiro de POW, ajustado vendo capturas. O projétil é só visual; `hit_radius` e o raio da explosão não mudam.
- [x] **Arma maior durante a batalha inteira** (decidido): a arma nas costas fica maior o tempo todo, não só no POW. Conferir que ela não cobre a cabeça nem a placa de nome e que continua alinhada ao rastejar.
- [x] **Teste de regressão**: criar um teste que confirma que o dano, o raio da cratera e a detecção de acerto são os mesmos antes e depois do aumento visual.

**Feito na 0.8 (25/09/2026):** `pow_fx.gd` (preparação e carga), `pow_impact.gd` (impacto por arma), `fx_particles.gd` (`CPUParticles2D`), halo e rastro do POW em `projectile.gd`, hit-stop de 80 ms em `LocalMatch.hitstop`, arte animada de cada POW em `assets/effects/pow/<arma>/` (PixelLab), arma nas costas maior em `look_rig.gd`, teste `tests/pow_tests.gd`.

**Decidido provisoriamente:** arma nas costas e projétil em **1,5×**, tiro de POW mais **1,6×** (`items.json` → `visual`). Captura lado a lado 1× · 1,5× · 2× em `docs/screens/scale_compare.png`; basta trocar os números para 2× se preferir.

---

## 2. Instâncias de 3 fases e sistema de mapas

**Objetivo:** várias instâncias, cada uma com 3 fases e o chefão na terceira. A dificuldade deixa de ser escolhida numa lista e passa a vir do **mapa**, um item que cai nas instâncias: quanto maior o nível do mapa, mais difícil e mais recompensadora a instância. Mapas têm atributos aleatórios (chance de mapa, XP, ouro, mais itens…), como os do PoE 2. Mais jogadores no grupo também deixam a instância mais difícil e mais recompensadora.

**Hoje:**
- Uma instância só, o Templo do Sol, com uma fase só (Rei Hélio), 4 dificuldades (`pve.difficulties` em `combat.json`) e grupo de até 4.
- A vida do chefe já sobe com o grupo: `0,4 + 0,2 × jogadores` (`match.gd`). O dano e as recompensas não sobem.
- O loot são as cartas de `rewards.cards` mais a chance de Super Verdadeira (`drops.super_chance` 8% + 4% por dificuldade).
- As dificuldades aparecem em `main.gd`, `match.gd`, `lobby.gd`, `room_screen.gd` (seletor com os ícones `difficulty_*.png`), `result_screen.gd` e nos testes `pve_tests.gd` e `ui_tests.gd`. Tudo isso passa a usar o nível do mapa.

### 2.1 Estrutura das instâncias
- [x] **Fase 1 — Entrada**: ondas de lacaios (2–4 inimigos fracos).
- [x] **Fase 2 — Guardião**: um mini-chefe com lacaios ou um objetivo (destruir totens, sobreviver N turnos).
- [x] **Fase 3 — Chefão**: o chefe com mecânicas próprias e fúria, como o Rei Hélio.
- [x] Entre as fases: tela de transição, vida recupera 30% e o POW continua. Quem morreu volta na fase seguinte com pouca vida. As cartas de recompensa aparecem só no fim, e o baú do chefe é maior.
- [x] Dados em `combat.json` → `instances[]` (id, nome, mapas das 3 fases, inimigos por fase, chefe, tabela de loot), no lugar do bloco `pve` único.

**Instâncias sugeridas** (aproveitando os mapas que já existem e criando novos com a receita de `PIXELLAB_0_6.md`):
1. **Templo do Sol** — converter a atual para 3 fases: Pátio do Templo → Câmara do Guardião → Rei Hélio.
2. **Trono das Máscaras** — tema de fogo e máscaras; chefe novo.
3. **Picos Gelados** — mapa e chefe novos (gelo, congelar o turno).
4. **Ilha Celeste em Ruínas** — chefe voador que troca de posição.

Cada chefe novo precisa de arte PixelLab (pose, repouso e ataque). Temos um limite de gerações por mês, então vamos planejar isso por instância.

**Feito na 0.9:** as quatro instâncias, com lacaios, guardiões, chefes, totens e 7 mapas novos (arte em `docs/PIXELLAB_0_9.md`). Fase 2: Templo e Trono têm guardião com lacaio; Picos Gelados tem o objetivo "destruir os cristais"; Ilha em Ruínas tem "sobreviver 5 turnos". Mecânicas dos chefes: fúria (todos), invocar máscaras (Rei das Máscaras), congelar a vez (Rainha da Nevasca) e trocar de posição (Grifo da Tempestade).

### 2.2 Mapas (no lugar das dificuldades)
**Como funciona:**
- Cada instância tem uma **entrada livre** (sem mapa, recompensa baixa) para ninguém ficar travado. Ela dá os mapas de nível 1.
- Um **mapa** é um item: "Mapa do Templo do Sol — Nível 5". Ele abre aquela instância naquele nível e é **consumido ao entrar**.
- **Níveis 1 a 16**, como no PoE 2.
- **Mapas caem de mapas.** Em cada fase vencida há uma chance de cair um mapa, e o chefão tem chance maior. O nível do mapa que cai é o mesmo (70%), +1 (25%) ou +2 (5%). Meta inicial: sem atributos, cerca de 0,9 mapa por partida (quase se sustenta); com bons atributos, mais de 1. Assim subir de nível depende de rodar mapas bons.
- **Se o grupo todo cair, o mapa é perdido.** O que caiu nas fases já vencidas fica.
- Em grupo, o mapa é do líder; cada jogador recebe o **próprio loot** (sem briga por item).
- Mapas vão para uma aba **Mapas** na Mochila e são **negociáveis no leilão**.
- Na sala da instância, o seletor de dificuldade vira um **espaço para colocar o mapa**, que mostra o nível e os atributos.

**Efeito do nível** (valores iniciais):

| | Nível 1 | Por nível | Nível 16 |
|---|---|---|---|
| Vida dos inimigos | 1,0× | ×1,12 | ≈ 5,5× |
| Dano dos inimigos | 1,0× | ×1,07 | ≈ 2,8× |
| XP e ouro | 1,0× | +10% | 2,5× |
| Nível dos itens que caem | 1 | +1 | 16 |

- O **nível do item** limita os melhores valores de atributo bônus que ele pode ter (item 3). Por isso mapas altos dão itens melhores, e não só mais itens.
- A chance de Verdadeira e de moedas raras sobe com o nível. **Solar** só a partir do nível 5. A Super Verdadeira só cai do chefão, com chance maior em níveis altos.

**Qualidade e atributos do mapa** (as mesmas qualidades e moedas dos itens, como no PoE):
- **Normal**: sem atributos. **Excelente**: 1–2 atributos. **Verdadeira**: 3–4 atributos.
- **Ameaças** (deixam a instância mais difícil, e cada uma também dá +10% de quantidade de itens):
  - Inimigos com +X% de vida
  - Inimigos com +X% de dano
  - Lacaios extras em cada fase
  - Chefe começa em fúria
  - Vento sempre forte
  - Jogadores com −X% de energia (andam menos)
  - Turno de 15 s em vez de 20 s
  - Sem avião de papel
  - Inimigos com escudo no primeiro golpe
- **Recompensas**:
  - +X% chance de drop de mapa
  - +X% XP
  - +X% ouro
  - +X% quantidade de itens
  - +X% raridade (mais Excelente, Verdadeira e bônus melhores)
  - +X% chance de moeda
  - +1 carta no baú do chefe
  - +X% chance de Super Verdadeira
- As moedas do item 3 funcionam também nos mapas: Brasa e Coroa sobem a qualidade, Estrela acrescenta um atributo, Tormenta rerola tudo. **Os mapas são o principal gasto de moedas**, e isso é o que mantém o valor delas.

**Feito na 0.9:** mapas com nível, qualidade e atributos (`combat.json` → `map_items`, `InstanceRun`), consumidos ao entrar, espaço de mapa na sala, aba Mapas na Mochila, cupom `MAPAS` para teste. **Feito na 0.10:** Solar e moedas raras nos mapas altos e as moedas usadas nos mapas (aba Moedas do Ferreiro). **Feito na 0.12:** mapas negociados no leilão (item 3.3).

**Depois (opcional):** um "Atlas", com árvore de pontos ganhos ao completar mapas, para personalizar os drops (como no PoE 2).

### 2.3 Escala por tamanho do grupo
Vale só para jogadores. Multiplica os valores do nível do mapa.

| Jogadores | Vida dos inimigos | Dano dos inimigos | Lacaios extras | XP e ouro por jogador | Bônus de loot |
|-----------|-------------------|-------------------|----------------|------------------------|---------------|
| 1 | 1,0× | 1,0× | +0 | 1,0× | — |
| 2 | 1,8× | 1,1× | +1 | 1,15× | +1 carta |
| 3 | 2,5× | 1,2× | +2 | 1,3× | +1 carta, raridade +25% |
| 4 | 3,2× | 1,3× | +3 | 1,5× | +2 cartas, raridade +50% |

Com 3 ou 4 jogadores o chefe também ganha um ataque em área extra por rodada. Enquanto não houver servidor, só dá para jogar solo: a escala fica pronta e coberta por testes automáticos e passa a valer quando os grupos existirem.

**Feito na 0.9:** `combat.json` → `party_scaling`, aplicado por `InstanceRun` (conta só jogadores humanos) e coberto por `tests/pve_tests.gd`.

### 2.4 Loot
- [x] Armas Verdadeiras e as Super Verdadeiras no loot das instâncias (com nível do item = nível do mapa); os **atributos bônus aleatórios** entraram na 0.10. Uma Verdadeira com bons bônus é o item mais cobiçado.
- [x] **Garantia** de Super Verdadeira: um contador por instância que garante uma depois de N vitórias de chefão sem ela.
- [x] Mapas no loot; moedas no loot desde a 0.10.
- [x] As cartas de recompensa ganham uma raridade nova para mapas (carta esmeralda); moedas raras desde a 0.10.
- [x] Proposta: a Loja passa a vender só Normal e Excelente, sem bônus. A Verdadeira vem de drop ou da Coroa; se não, o ouro compra o que deveria vir das instâncias.

**Decidido provisoriamente na 0.9:**
- Cada mapa é de uma instância específica; 20% dos mapas que caem são de outra instância, para circular entre elas.
- Sem limite de entradas por dia (os mapas consumíveis já limitam).
- Garantia da Super Verdadeira: 20 vitórias de chefão sem ela.

---

## 3. Atributos aleatórios, moedas e Leilão

**Objetivo:** um leilão em que os jogadores vendem itens e mapas uns para os outros, com moedas parecidas com as do PoE 2. O **Solar** é a moeda principal do leilão. As moedas caem nas instâncias e servem para craftar itens e mapas.

**Por que as moedas do PoE funcionam:** toda moeda tem um **uso**, e usar gasta a moeda. Isso cria demanda e tira moedas do jogo, por isso elas mantêm valor e viram dinheiro entre os jogadores. Aqui, o uso é mexer nos atributos aleatórios de itens e mapas.

### 3.1 Atributos bônus aleatórios nos itens
- [x] **Quantos**, pela qualidade: Normal 0; Excelente 1–2; Verdadeira 3–4; Super Verdadeira sempre 4.
- [x] **Nível do item** = nível do mapa onde caiu. Cada bônus tem faixas (F1 é a melhor), e as faixas altas só aparecem em itens de nível alto.
- [x] **Bônus por tipo de peça.**
  - Arma:
    - +Ataque
    - +% dano
    - +% dano crítico
    - +% dano do POW
    - POW inicial
    - chance de não gastar a habilidade 1–9
  - Roupa, chapéu, óculos e asas:
    - +Defesa
    - +vida máxima
    - +Agilidade
    - +Sorte
    - +energia por turno
    - −Delay
    - −% efeito do vento
    - +% cura recebida
- [x] Nada de bônus que mude o raio da explosão ou o hitbox.
- [x] **Fortalecimento** (+1 a +12) continua aumentando só os atributos base; os bônus não mudam. **Composição** (Cristal Dourado) continua como está.
- [x] Itens da Loja e de cupons vêm sem bônus.

**Feito na 0.10 (25/09/2026):** `items.json` → `affixes` e `crafting.gd` (`Crafting`); bônus aplicados em `Armory.character_stats` e na partida (`TankFighter.bonus`, `LocalMatch`); rolados no drop das armas, da Super Verdadeira e dos equipamentos; Mochila mostra bônus, faixa e nível do item; save v5 (drops antigos ganham bônus uma vez ao carregar); teste `tests/craft_tests.gd`.

**Decidido provisoriamente na 0.10:**
- Faixas pelo nível do item: F5 a partir do nível 1, F4 do 4, F3 do 7, F2 do 10 e F1 do 13 (pesos 100/70/45/25/12; a raridade do mapa favorece as faixas melhores).
- Chapéus, óculos, asas e roupas (do gênero do personagem) também caem no baú das instâncias, com nível do item; sem isso só existiriam equipamentos de nível 1, que só rolam F5.
- Qualidade em roupas, chapéus, óculos e asas só define a quantidade de bônus e a cor; o multiplicador de dano e atributos da qualidade continua só nas armas.
- Limites: −% efeito do vento até 50% e chance de habilidade grátis até 40%; o −Delay deixa pelo menos 100 de Delay por turno.
- Itens da Loja, de cupons e cópias do Espelho Celeste ficam marcados como **vinculados** no save, já pensando no leilão.

### 3.2 Moedas
Nomes próprios, escolhidos para funcionar em português e em inglês e combinar com o tema do jogo (sol, céu, forja). São a proposta inicial; dá para trocar qualquer um.

| Moeda (pt / en) | Parecida com (PoE) | Uso em itens e mapas | Raridade |
|-----------------|--------------------|----------------------|----------|
| Brasa / Ember | Transmutation | Normal → Excelente, com 1 bônus | Comum |
| Coroa / Crown | Regal | Excelente → Verdadeira, com +1 bônus | Incomum |
| **Estrela / Star** | Exalted | Adiciona 1 bônus aleatório (até o limite) | Rara — "troco" do leilão |
| Tormenta / Storm | Chaos | Rerola todos os bônus | Rara |
| **Solar / Solar** | Divine | Rerola só os valores, mantendo quais bônus são | Muito rara — **moeda principal do leilão** |
| Eclipse / Eclipse | Annulment | Remove 1 bônus aleatório | Rara |
| Espelho Celeste / Sky Mirror | Mirror of Kalandra | Duplica um item (a cópia não pode ser negociada) | Lendária |

Preços no leilão ficam curtos de ler: "3 Solares", "12 Estrelas".

- As **moedas de ouro** que já existem continuam para NPC, Loja e Ferreiro.
- [x] Novas abas do Ferreiro para usar as moedas em itens e mapas.
- [x] Onde caem: cartas e baús das instâncias (as raras só em mapas de nível alto) e um pouco no PvP.

**Feito na 0.10:** `items.json` → `currencies`, `Crafting.apply`/`apply_map`, `PlayerProfile.craft`/`craft_map`, aba **Moedas** no Ferreiro (equipamentos e mapas), moedas por fase e cartas de moeda (`InstanceRun`), Brasa e Coroa nas cartas do PvP (`rewards.pvp_cards`), ícones provisórios (`tools/currency_icons.py`), cupom `MOEDAS`.

**Decidido provisoriamente na 0.10:**
- Chance de moeda por fase vencida: 35% (fase 1), 45% (fase 2) e 100% no chefão, vezes (1 + quantidade de itens do mapa); mais cartas de moeda no baú (peso 12, como as outras cartas raras).
- Peso de cada moeda (mais o ganho por nível do mapa) e nível mínimo: Brasa 40 (entrada livre), Coroa 18 (1+), Eclipse 6 +0,5/nível (2+), Estrela 5 +0,5 (3+), Tormenta 5 +0,4 (3+), Solar 1 +0,3 (5+), Espelho Celeste 0,05 +0,02 (10+). No nível 16 o Solar é cerca de 5,6% das moedas e o Espelho 0,4%.
- O Espelho Celeste só duplica equipamentos (não mapas). As outras seis funcionam nos mapas.
- Estrela e Tormenta precisam de item Excelente ou melhor; Brasa só em Normal e Coroa só em Excelente, como no PoE.

### 3.3 Leilão (0.12, em cima do backend da 0.11)
- [x] Prédio do Leilão na cidade, com busca e filtros (tipo, qualidade, nível do item, fortalecimento, bônus, nível do mapa e faixa de preço).
- [x] Anunciar com preço em Solares e/ou Estrelas, duração de 12, 24 ou 48 h e compra imediata. Lances podem vir depois.
- [x] **Custódia no servidor**: ao anunciar, o item sai do inventário e fica com o servidor; na venda, as moedas vão para o vendedor pelo correio do jogo. Tudo em transação no PostgreSQL, para não haver duplicação.
- [x] **Saídas de moedas**: taxa para anunciar (em ouro) e comissão sobre a venda (por exemplo 5%), para controlar a inflação.
- [x] **Vinculados** (não vão ao leilão): itens de cupom, de missão e da Loja. Proposta para as Super Verdadeiras: vinculam ao equipar (dá para vender enquanto ninguém equipou).
- [x] Limite de anúncios por jogador, histórico de preços e registro de todas as transações para investigar fraudes.
- [ ] **Troca de moedas** (Estrela ↔ Solar com cotação do mercado) numa segunda etapa.

**Feito na 0.12 (25/09/2026)** (detalhes em `ARCHITECTURE.md`, seção Leilão e Correio):
- **API em Go** (`server/api/auction_*.go`, migração `002_auction.sql`): anúncios em custódia, correio do jogo, busca com filtros e páginas, histórico de preços, "meus anúncios", vencimento a cada minuto (o item volta pelo correio) e as operações com id único, que o servidor de jogo pode repetir sem efeito duplicado. Anunciar, comprar e receber o correio gravam o perfil do jogador **na mesma transação** (com a versão do perfil), então o item nunca existe em dois lugares. Dois compradores ao mesmo tempo: um leva, o outro recebe "não está mais à venda". Excluir a conta tira os anúncios dela do leilão e o nome do histórico.
- **Servidor de jogo** (`server/game/game_server.gd`, `api_client.gd`): as regras (`client/systems/auction.gd`, `Auction`) e uma operação do leilão por vez por jogador. Se a API não confirmar (queda), a operação é repetida com o mesmo id; se continuar sem resposta, o jogador é desconectado sem gravar e o próximo login lê o perfil do banco (nada duplica nem some). A compra e o cancelamento já recebem o item do correio na hora. Quem vendeu e está no mesmo servidor é avisado na hora; o número de cartas chega no login.
- **Cliente**: `AuctionScreen` (Comprar, Vender, Meus anúncios) e `MailScreen` (Correio), com confirmação antes de comprar, anunciar e cancelar; contador no ícone CORREIO. Offline, os dois explicam que precisam do servidor.
- **Testes**: `tests/auction_tests.gd` (62), o Leilão no `tests/net_e2e_tests.gd` (dois jogadores de verdade), `server/api/auction_test.go` (PostgreSQL) e `tests/auction_stack_check.gd` (servidor de jogo contra a API e o PostgreSQL).

**Decidido provisoriamente na 0.12** (números em `items.json` → `auction`):
- **O que vai ao leilão**: equipamentos que caíram nas instâncias (têm nível do item: armas, roupas, chapéus, óculos e asas) e mapas, desde que não vinculados nem equipados. Não vão: Loja, cupons, cópias do Espelho Celeste, a arma inicial de toda conta (agora vinculada) e as Super Verdadeiras depois de equipadas (saves antigos: a que estiver equipada vincula ao carregar). Moedas, pedras e cristais ficam fora até a troca de moedas.
- **Taxa para anunciar**: 30, 50 ou 80 moedas de ouro para 12, 24 ou 48 h; não volta ao cancelar.
- **Comissão**: 5% de cada moeda do preço, arredondada para baixo (preços pequenos não pagam; 20 Estrelas pagam 1). Fica decidida no anúncio, que mostra quanto o vendedor vai receber.
- **Limites**: 10 anúncios ao mesmo tempo por jogador (mais anúncios são uma das conveniências do item 4.2) e até 999 de cada moeda por anúncio.
- A compra é imediata e o item vai para a Mochila; o que o vendedor recebe (ou o item que volta) chega pelo **Correio**, que também guarda o que não pôde ser entregue na hora.
- O histórico de preços mostra as últimas vendas do mesmo item e qualidade (ou mapas da mesma instância e qualidade) com nível até 2 acima ou abaixo.


---

## 4. Distribuição e monetização

### 4.1 Distribuição — decidido
**Steam no lançamento, web para testes fechados, sem launcher próprio.**

| | Web | Steam | Launcher próprio |
|---|---|---|---|
| Para o jogador | Abrir um link e jogar | Instalar pela Steam; atualização automática | Baixar um .exe de um site desconhecido |
| Custo | Grátis | US$ 100 por jogo (recuperado depois de US$ 1.000 em vendas); 30% das vendas | Certificado de assinatura (cerca de US$ 200–400 por ano) e hospedagem dos downloads |
| Login, atualização e pagamento | Temos que fazer | Prontos | Temos que fazer |
| Ser encontrado | Baixo | Alto (lista de desejos, festivais, recomendações) | Nenhum |

- **Web para testes:** o projeto usa o renderizador Compatibility (WebGL2) e não usa threads nem `OS.execute`, então o export web deve funcionar com poucos ajustes. Serve para chamar pessoas para testes sem instalar nada.
- **Steam no lançamento:** é onde as pessoas encontram o jogo, e a Steam já resolve login, atualização e pagamento. Windows e Linux (Steam Deck) saem do mesmo projeto.
- **Launcher descartado:** tem os custos das outras duas opções e não traz nada que a Steam não dê.

### 4.2 Monetização
**Decidido: jogo gratuito com loja de cosméticos e conveniências, sem vender poder.**
- **Vender**:
  - Cosméticos. O jogo já tem roupas, chapéus, óculos, asas, cabelos e auras, que é justamente o que o DDTank vendia.
  - Visual alternativo de POW e de projétil.
  - Passe de temporada com cosméticos.
  - Conveniências: espaço na Mochila, abas extras de mapas e mais anúncios simultâneos no leilão.
- **Não vender** Solares, Estrelas, outras moedas, armas, pedras ou mapas. Com leilão, tudo o que for vendido por dinheiro vira preço no mercado: quem paga compra poder, e o que os outros conseguem jogando perde valor. É o modelo do PoE, que sustenta a economia dele. O DDTank vendia poder e lucrava com isso, mas não tinha uma economia de troca como a que vamos ter.
- **Regras que precisamos seguir:**
  - Na versão Steam, toda compra dentro do jogo passa pela carteira Steam (API de microtransações); a Steam fica com 30%. Na web precisamos de um meio de pagamento próprio (PIX ou cartão via Mercado Pago ou Stripe).
  - **Nada de caixas aleatórias pagas.** No Brasil, o ECA Digital (Lei 15.211/2025) proíbe loot boxes em jogos voltados a crianças e adolescentes, e outros países também restringem. As cartas de recompensa, que são grátis, não entram nisso. Confirmar os detalhes antes do lançamento.
  - Os termos de uso proíbem vender moedas e itens por dinheiro fora do jogo; os registros do leilão ajudam a achar quem faz isso.

### 4.3 Público internacional — decidido
- [x] **Tradução desde já**: todo texto do jogo sai do código para tabelas de tradução do Godot (`TranslationServer`, CSV ou PO). Começar com português e inglês; espanhol é um bom terceiro idioma (a América Latina conhece o DDTank). Quanto mais tarde, mais texto para migrar, então isso deve entrar já na 0.8.
- [x] A fonte Pixel Operator precisa cobrir os acentos de todos os idiomas escolhidos (testar espanhol e francês, por exemplo).
- [x] Nomes de itens, moedas e mapas com versão própria em cada idioma, não tradução literal.

**Feito na 0.10 (25/09/2026):** gettext com PO (`locale/en.po`, 717 textos), português como idioma-fonte e cada texto como chave; `Lang` (`client/systems/lang.gd`), seletor Português/English na tela de entrada (fica salvo; a primeira abertura segue o sistema), `--lang=en` nas capturas, extrator `tools/i18n.py` e `tests/i18n_tests.gd`. A fonte cobre todas as letras de português, espanhol, francês, alemão e italiano; só as setas decorativas (▶ ◀ → ⇄ ↵) vêm da fonte do sistema. Nomes em inglês próprios (os das armas foram trocados de novo na revisão de nomes do checklist); Instância → *Dungeon*, Mochila → *Bag*, Ferreiro → *Blacksmith*, mapa-item → *Map* e local da partida → *Arena*, moedas de ouro → *gold*, Verdadeira → *True*; moedas *Ember, Crown, Star, Storm, Solar, Eclipse, Sky Mirror*.

**Decidido provisoriamente:** o nome da marca continua *Frontier Tank: Nova Era* nos dois idiomas (é o que está no logotipo). A revisão de nomes do checklist abaixo (25/09/2026) trocou os nomes nos dois idiomas; o subtítulo "Nova Era" continua em aberto.
- [ ] **Servidor**: uma região no começo (Estados Unidos, com latência razoável para Brasil e Europa) e mais regiões se o público crescer. O turno de 20 s tolera bem a latência.
- [ ] **Pagamentos**: a Steam cuida de moedas locais e impostos na versão Steam. Na web, Stripe cobre o exterior e o Mercado Pago cobre PIX.
- [x] **Privacidade**: seguir a LGPD (Brasil) e o GDPR (Europa): consentimento, exclusão de conta e dados, política de privacidade nos dois idiomas. *(25/09/2026: Termos de Uso e Política de Privacidade em pt e en (`legal/`), consentimento no cadastro com versão guardada na API e novo aceite quando os textos mudam, AJUDA → Minha conta com a cópia dos dados e a exclusão pelo servidor de jogo, prazos de retenção e os registros de acesso do Marco Civil. Falta: preencher `legal/controller.json`, revisão jurídica dos textos e das exigências do ECA Digital (verificação de idade e ferramentas para os responsáveis).)*
- [x] Chat moderado: filtro de palavrões e denúncia, já que o jogo terá chat público e jogadores de vários países. *(0.11: filtro de palavrões e limite de mensagens no servidor, e tudo fica no registro de auditoria. 25/09/2026: denúncia pelo nome do jogador no chat, com contexto, limites, silêncio automático por várias denúncias, análise com `tools/moderate.py` e suspensão que desconecta na hora. Falta quem modere: definir a equipe e o prazo de resposta antes do lançamento.)*

### Checklist de preparação
- [x] **Backend** (ver "Dependência: servidor"): 0.11.
- [x] Versão web completa em localhost com um comando: banco, API, servidor de jogo e o jogo no navegador em `http://localhost:8000`, com um nginx que encaminha `/v1/` e `/ws` (um endereço só, pronto para a VM).
- [ ] Testes fechados numa VM com a mesma pilha (e HTTPS com domínio).
- [x] Export web de teste (sem threads, sem cabeçalhos COOP/COEP) e medir o FPS na batalha. *(25/09/2026: preset Web, `tools/web_build.py`, teste de desempenho `?bench=30` e `tools/web_bench.cjs`; números no README, seção "Versão web para testes fechados". Falta medir numa máquina com placa de vídeo: o contêiner de testes só tem desenho em software.)*
- [x] **Revisão de nomes e identidade antes de publicar**: armas, itens e textos com o mesmo nome do DDTank (Quebra Tijolos, Canhão Arco-Íris, Cesto de Frutas de Newton…) e qualquer menção a "DDTank" no material público. A mecânica pode ser parecida, mas nomes e marcas iguais são um risco numa loja comercial. *(Feito em 25/09/2026, tabela abaixo.)*

**Revisão de nomes (25/09/2026).** Os nomes em inglês antigos eram traduções literais dos do DDTank, então os dois idiomas mudaram. As ids internas (`quebra_tijolos`, `escudo_bugou`...) ficaram iguais: estão nos saves, no PostgreSQL e nos anúncios do leilão, e o jogador não as vê. Em português os nomes novos são masculinos, para o modelo "Verdadeiro %s" continuar certo.

| id | Antes | Agora (pt) | Agora (en) |
|---|---|---|---|
| `quebra_tijolos` | Quebra Tijolos / Brickbreaker | Tijolaço | Bricklayer |
| `fogo_intenso` | Fogo Intenso / Blazing Fire | Braseiro | Brazier |
| `canhao_arco_iris` | Canhão Arco-Íris / Rainbow Cannon (POW Raio Arco-Íris) | Prisma (POW Raio Prismático) | Prism (Prismatic Ray) |
| `vento_de_deus` | Vento de Deus / Divine Wind (POW Furacão Divino) | Cata-Vento (POW Olho do Furacão) | Pinwheel (Eye of the Storm) |
| `cesto_newton` | Cesto de Frutas de Newton (POW Lei da Gravidade) | Pomar (POW Chuva de Frutas) | Orchard (Fruit Shower) |
| `kit_medico` | Kit Médico / Medic Kit | Tônico | Tonic |
| `eletrodomestico` | Eletrodoméstico / Home Appliance | Bota-Fora | Clear-Out |
| `trovao` | Trovão / Thunder | Para-Raios | Lightning Rod |
| `desentupidor` | Desentupidor / Plunger | Sugador | Suction Gun |
| `cabeca_de_boi` | Super Cabeça de Boi (POW Estouro do Touro) | Super Minotauro (POW Estouro da Manada) | Super Minotaur (Stampede) |
| `bumerangue_amor` | Super Bumerangue do Amor | Super Cupido | Super Cupid |
| `lanca_antiga` | Super Lança | Super Lança de Jade | Super Jade Spear |
| `dom_de_anjo`, `dom_de_anjo_v` | Dom de Anjo, Verdadeiro Dom de Anjo | Bálsamo, Grande Bálsamo | Balm, Grand Balm |
| `escudo_bugou`, `escudo_barao` | Escudo de Bugou, Escudo do Barão | Broquel de Latão, Égide de Aço | Brass Buckler, Steel Aegis |

- "DDTank" não aparece em nenhum texto do jogo, dos arquivos de balanceamento, das traduções, dos textos legais nem da página da Steam; nos scripts só em comentários, que o export deixa de fora (o `.pck` da web foi conferido). `tests/launch_tests.gd` falha se uma marca ou um nome antigo voltar.
- Os documentos internos (`docs/DDTANK_RESEARCH.md`, `docs/ddtank_references*`, este roadmap, `ARCHITECTURE.md`, `GAME_DESIGN_DOCUMENT.md`) continuam citando o DDTank como referência de desenvolvimento e **não devem ser publicados**; o README foi limpo. Se o repositório ficar público, tirar esses arquivos antes.
- **Continuam genéricos e ficaram**: Pedra de Fortalecimento, Cristal Dourado, POW, avião de papel, Salão de Jogos, Centro Comercial, Ferreiro, qualidades Normal/Excelente/Verdadeira.
- **Decisão pendente, a marca**: "Nova Era" também é o nome de uma edição brasileira do DDTank (ver `docs/DDTANK_RESEARCH.md`, complemento 0.4). O subtítulo aparece no logotipo, na janela, no nome do servidor padrão ("S1 · Nova Era") e na página da Steam. Antes da página "em breve", vale trocar o subtítulo (e redesenhar o logotipo) ou confirmar com um advogado que não há risco.
- [ ] Página "em breve" na Steam **meses antes** do lançamento, para juntar listas de desejos: cápsulas, capturas, trailer e descrição em pt-BR e inglês. *(25/09/2026: textos em pt e en, cápsulas em todos os tamanhos, capturas nos dois idiomas, ícones e tabela das conquistas e modelos do SteamPipe em `store/steam/`, com `tools/steam_store.py`. Faltam: o trailer, a decisão sobre o subtítulo "Nova Era", pagar a taxa e enviar a página na Steamworks — passo a passo em `docs/STEAM.md`.)*
- [x] Integração com a Steam (GodotSteam): login por ticket, microtransações, conquistas. *(25/09/2026: `SteamService` com GodotSteam opcional, ENTRAR COM A STEAM e Vincular à Steam, loja Premium paga pela carteira Steam com entrega pelo Correio, 11 conquistas pelo perfil online, presets Windows e Linux. Falta instalar a extensão e o App ID; estornos via `GetReport`.)*
- [x] Política de privacidade e termos de uso (obrigatórios com contas, pagamentos e dados de jogadores). *(Modelos prontos em `legal/`; precisam dos dados da empresa e de revisão jurídica.)*


---

### Pendências externas (não dá para resolver no código)
- Preencher `legal/controller.json` (empresa, CNPJ, e-mail, encarregado) e fazer a **revisão jurídica** dos Termos, da Política e do ECA Digital.
- Decidir o **subtítulo** do jogo ("Nova Era") antes da página da Steam.
- **Medir o FPS da web numa máquina com placa de vídeo** (`node tools/web_bench.cjs --headed` ou `?bench=30`).
- Definir quem **modera** as denúncias e em quanto tempo.
- Steamworks: taxa, App ID, chave de publicador, conquistas, microtransações e envio da página.

## Ordem sugerida

1. **0.8 — POW e tradução** (item 1 e 4.3): o POW novo (**feito**) e a base de tradução (português e inglês), antes que o jogo tenha ainda mais texto (**feito** junto com a 0.10).
2. **0.9 — Instâncias e mapas** (item 2, **feito**): 3 fases, mapas com nível e atributos no lugar das dificuldades, escala por grupo pronta, loot com Verdadeiras e Super Verdadeiras. Offline e solo.
3. **0.10 — Atributos e moedas** (item 3.1 e 3.2, **feito**): bônus aleatórios nos itens, moedas no loot, craft de itens e mapas no Ferreiro. Offline.
4. **0.11 — Backend** (**feito**): contas, grupos reais, partida com autoridade do servidor (lockstep), e drops, rolagens e moedas no servidor. Docker com PostgreSQL, API e servidor de jogo.
5. **0.12 — Leilão** (item 3.3, **feito**): anúncios em custódia no PostgreSQL, compra imediata, Correio, taxa e comissão, histórico de preços. Falta a troca de moedas.
6. **Lançamento** (item 4): testes fechados na web → página da Steam → acesso antecipado gratuito na Steam. Decidido em 25/09/2026: a web vem primeiro, tudo no computador (**feito**: `SubirLocal.cmd` / `tools/local.sh`, serviço `web` com nginx no Docker) e depois numa VM (passo a passo em `server/README.md`, seção "Numa VM"); a Steam fica para depois.
