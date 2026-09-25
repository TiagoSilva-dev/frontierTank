# Roadmap — próximas implementações

Lista do que vamos fazer depois da 0.7. Cada item traz o objetivo, o que existe hoje no código, a proposta e o que ainda está em aberto. Os números são pontos de partida para testar, não valores fechados.

| # | Item | Precisa de servidor? | Entrega |
|---|------|----------------------|---------|
| 1 | POW mais bonito, arma e projétil maiores | Não | 0.8 |
| 2 | Instâncias de 3 fases e **sistema de mapas** (no lugar das dificuldades) | Não para desenvolver e jogar solo; sim para grupos | 0.9 |
| 3 | Atributos aleatórios, moedas estilo PoE 2 e Leilão | Moedas e craft não; o leilão sim | 0.10 (moedas e craft), 0.11 (leilão) |
| 4 | Distribuição e monetização | Sim | Decidido: Steam no lançamento, web para testes |

## Decisões tomadas (25/09/2026)
- **Vamos ganhar dinheiro com o jogo.** Lançamento na Steam; a versão web serve para testes fechados; não haverá launcher próprio (item 4).
- **Sem qualidade nova de arma.** O topo continua sendo a linha Verdadeira: Verdadeira e as 3 Super Verdadeiras que já são exclusivas de drop. As "armas lendárias" do loot são essas.
- **Itens terão atributos bônus aleatórios**, que as moedas do item 3 modificam.
- **Monetização sem vender poder**: jogo gratuito com cosméticos e conveniências (item 4.2).
- **Mapas de nível 1 a 16.**
- **Moedas com nomes próprios** (item 3.2).
- **Público internacional desde o começo**: jogo em português e inglês no lançamento (item 4.3).
- **Nada de tempo com bots agora.** A escala por grupo considera só jogadores; regras para bots aliados ficam para depois.
- **As dificuldades Normal, Difícil, Heroico e Pesadelo saem.** Entra o sistema de mapas do PoE 2: mapas são itens que caem nas instâncias, e o nível do mapa define a dificuldade e a recompensa.

## Dependência: servidor
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
- [ ] **Animação em fases**: preparação (o personagem recua e a arma brilha), carga (a aura cresce e as partículas são puxadas para a arma), disparo (clarão e recuo), voo (projétil com halo e rastro próprio do POW) e impacto (hit-stop de 60–100 ms, tremor, ondas e fumaça).
- [ ] **Mais quadros**: animar a arte de cada POW com PixelLab (`animate_image`, cerca de 2 gerações por clipe de 8 quadros) em vez de só escalar uma imagem parada; curvas de easing em todos os tweens.
- [ ] **Um impacto próprio por arma**: hoje o estouro é quase o mesmo para todas. Cada um dos 12 POW ganha a sua cor, forma e partículas (lava na Fogo Intenso, cristais de gelo, raios duplos no Trovão, corações no Bumerangue do Amor e assim por diante).
- [ ] **Partículas de verdade** (`CPUParticles2D`, que funciona no renderizador Compatibility e no web) para brasas, faíscas e poeira, no lugar de parte do desenho feito à mão.
- [ ] **Projétil maior**: por exemplo 24 → 36 px no tiro normal e 1,6× a mais no tiro de POW, ajustado vendo capturas. O projétil é só visual; `hit_radius` e o raio da explosão não mudam.
- [ ] **Arma maior durante a batalha inteira** (decidido): a arma nas costas fica maior o tempo todo, não só no POW. Conferir que ela não cobre a cabeça nem a placa de nome e que continua alinhada ao rastejar.
- [ ] **Teste de regressão**: criar um teste que confirma que o dano, o raio da cratera e a detecção de acerto são os mesmos antes e depois do aumento visual.

**Em aberto:**
- Quanto maior (arma e projétil): vamos decidir em cima de capturas lado a lado (atual × 1,5× × 2×).

---

## 2. Instâncias de 3 fases e sistema de mapas

**Objetivo:** várias instâncias, cada uma com 3 fases e o chefão na terceira. A dificuldade deixa de ser escolhida numa lista e passa a vir do **mapa**, um item que cai nas instâncias: quanto maior o nível do mapa, mais difícil e mais recompensadora a instância. Mapas têm atributos aleatórios (chance de mapa, XP, ouro, mais itens…), como os do PoE 2. Mais jogadores no grupo também deixam a instância mais difícil e mais recompensadora.

**Hoje:**
- Uma instância só, o Templo do Sol, com uma fase só (Rei Hélio), 4 dificuldades (`pve.difficulties` em `combat.json`) e grupo de até 4.
- A vida do chefe já sobe com o grupo: `0,4 + 0,2 × jogadores` (`match.gd`). O dano e as recompensas não sobem.
- O loot são as cartas de `rewards.cards` mais a chance de Super Verdadeira (`drops.super_chance` 8% + 4% por dificuldade).
- As dificuldades aparecem em `main.gd`, `match.gd`, `lobby.gd`, `room_screen.gd` (seletor com os ícones `difficulty_*.png`), `result_screen.gd` e nos testes `pve_tests.gd` e `ui_tests.gd`. Tudo isso passa a usar o nível do mapa.

### 2.1 Estrutura das instâncias
- [ ] **Fase 1 — Entrada**: ondas de lacaios (2–4 inimigos fracos).
- [ ] **Fase 2 — Guardião**: um mini-chefe com lacaios ou um objetivo (destruir totens, sobreviver N turnos).
- [ ] **Fase 3 — Chefão**: o chefe com mecânicas próprias e fúria, como o Rei Hélio.
- [ ] Entre as fases: tela de transição, vida recupera 30% e o POW continua. Quem morreu volta na fase seguinte com pouca vida. As cartas de recompensa aparecem só no fim, e o baú do chefe é maior.
- [ ] Dados em `combat.json` → `instances[]` (id, nome, mapas das 3 fases, inimigos por fase, chefe, tabela de loot), no lugar do bloco `pve` único.

**Instâncias sugeridas** (aproveitando os mapas que já existem e criando novos com a receita de `PIXELLAB_0_6.md`):
1. **Templo do Sol** — converter a atual para 3 fases: Pátio do Templo → Câmara do Guardião → Rei Hélio.
2. **Trono das Máscaras** — tema de fogo e máscaras; chefe novo.
3. **Picos Gelados** — mapa e chefe novos (gelo, congelar o turno).
4. **Ilha Celeste em Ruínas** — chefe voador que troca de posição.

Cada chefe novo precisa de arte PixelLab (pose, repouso e ataque). Temos um limite de gerações por mês, então vamos planejar isso por instância.

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

### 2.4 Loot
- [ ] Armas Verdadeiras e as Super Verdadeiras no loot das instâncias, **com atributos bônus aleatórios** (item 3). Uma Verdadeira com bons bônus é o item mais cobiçado.
- [ ] **Garantia** de Super Verdadeira: um contador por instância que garante uma depois de N vitórias de chefão sem ela.
- [ ] Mapas e moedas no loot.
- [ ] As cartas de recompensa ganham uma raridade nova para mapas e moedas raras, com arte própria.
- [ ] Proposta: a Loja passa a vender só Normal e Excelente, sem bônus. A Verdadeira vem de drop ou da Coroa; se não, o ouro compra o que deveria vir das instâncias.

**Em aberto:**
- Cada mapa é de uma instância específica (proposta acima) ou o mapa sorteia a instância?
- Limite de entradas por dia? Com mapas consumíveis talvez nem precise.

---

## 3. Atributos aleatórios, moedas e Leilão

**Objetivo:** um leilão em que os jogadores vendem itens e mapas uns para os outros, com moedas parecidas com as do PoE 2. O **Solar** é a moeda principal do leilão. As moedas caem nas instâncias e servem para craftar itens e mapas.

**Por que as moedas do PoE funcionam:** toda moeda tem um **uso**, e usar gasta a moeda. Isso cria demanda e tira moedas do jogo, por isso elas mantêm valor e viram dinheiro entre os jogadores. Aqui, o uso é mexer nos atributos aleatórios de itens e mapas.

### 3.1 Atributos bônus aleatórios nos itens
- **Quantos**, pela qualidade: Normal 0; Excelente 1–2; Verdadeira 3–4; Super Verdadeira sempre 4.
- **Nível do item** = nível do mapa onde caiu. Cada bônus tem faixas (F1 é a melhor), e as faixas altas só aparecem em itens de nível alto.
- **Bônus por tipo de peça.**
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
- Nada de bônus que mude o raio da explosão ou o hitbox.
- **Fortalecimento** (+1 a +12) continua aumentando só os atributos base; os bônus não mudam. **Composição** (Cristal Dourado) continua como está.
- Itens da Loja e de cupons vêm sem bônus.

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
- [ ] Novas abas do Ferreiro para usar as moedas em itens e mapas.
- [ ] Onde caem: cartas e baús das instâncias (as raras só em mapas de nível alto) e um pouco no PvP.

### 3.3 Leilão (precisa do servidor)
- [ ] Prédio do Leilão na cidade, com busca e filtros (tipo, qualidade, nível do item, fortalecimento, bônus, nível do mapa e faixa de preço).
- [ ] Anunciar com preço em Solares e/ou Estrelas, duração de 12, 24 ou 48 h e compra imediata. Lances podem vir depois.
- [ ] **Custódia no servidor**: ao anunciar, o item sai do inventário e fica com o servidor; na venda, as moedas vão para o vendedor pelo correio do jogo. Tudo em transação no PostgreSQL, para não haver duplicação.
- [ ] **Saídas de moedas**: taxa para anunciar (em ouro) e comissão sobre a venda (por exemplo 5%), para controlar a inflação.
- [ ] **Vinculados** (não vão ao leilão): itens de cupom, de missão e da Loja. Proposta para as Super Verdadeiras: vinculam ao equipar (dá para vender enquanto ninguém equipou).
- [ ] Limite de anúncios por jogador, histórico de preços e registro de todas as transações para investigar fraudes.
- [ ] **Troca de moedas** (Estrela ↔ Solar com cotação do mercado) numa segunda etapa.


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
- [ ] **Tradução desde já**: todo texto do jogo sai do código para tabelas de tradução do Godot (`TranslationServer`, CSV ou PO). Começar com português e inglês; espanhol é um bom terceiro idioma (a América Latina conhece o DDTank). Quanto mais tarde, mais texto para migrar, então isso deve entrar já na 0.8.
- [ ] A fonte Pixel Operator precisa cobrir os acentos de todos os idiomas escolhidos (testar espanhol e francês, por exemplo).
- [ ] Nomes de itens, moedas e mapas com versão própria em cada idioma, não tradução literal.
- [ ] **Servidor**: uma região no começo (Estados Unidos, com latência razoável para Brasil e Europa) e mais regiões se o público crescer. O turno de 20 s tolera bem a latência.
- [ ] **Pagamentos**: a Steam cuida de moedas locais e impostos na versão Steam. Na web, Stripe cobre o exterior e o Mercado Pago cobre PIX.
- [ ] **Privacidade**: seguir a LGPD (Brasil) e o GDPR (Europa): consentimento, exclusão de conta e dados, política de privacidade nos dois idiomas.
- [ ] Chat moderado: filtro de palavrões e denúncia, já que o jogo terá chat público e jogadores de vários países.

### Checklist de preparação
- [ ] **Backend** (ver "Dependência: servidor").
- [ ] Export web de teste (sem threads, sem cabeçalhos COOP/COEP) e medir o FPS na batalha.
- [ ] **Revisão de nomes e identidade antes de publicar**: armas, itens e textos com o mesmo nome do DDTank (Quebra Tijolos, Canhão Arco-Íris, Cesto de Frutas de Newton…) e qualquer menção a "DDTank" no material público. A mecânica pode ser parecida, mas nomes e marcas iguais são um risco numa loja comercial.
- [ ] Página "em breve" na Steam **meses antes** do lançamento, para juntar listas de desejos: cápsulas, capturas, trailer e descrição em pt-BR e inglês.
- [ ] Integração com a Steam (GodotSteam): login por ticket, microtransações, conquistas.
- [ ] Política de privacidade e termos de uso (obrigatórios com contas, pagamentos e dados de jogadores).


---

## Ordem sugerida

1. **0.8 — POW e tradução** (item 1 e 4.3): o POW novo e a base de tradução (português e inglês), antes que o jogo tenha ainda mais texto.
2. **0.9 — Instâncias e mapas** (item 2): 3 fases, mapas com nível e atributos no lugar das dificuldades, escala por grupo pronta, loot com Verdadeiras e Super Verdadeiras. Offline e solo.
3. **0.10 — Atributos e moedas** (item 3.1 e 3.2): bônus aleatórios nos itens, moedas no loot, craft de itens e mapas no Ferreiro. Offline.
4. **Backend**: contas, grupos reais, partida com autoridade do servidor, e drops, rolagens e moedas no servidor.
5. **0.11 — Leilão** (item 3.3) em cima do backend.
6. **Lançamento** (item 4): testes fechados na web → página da Steam → acesso antecipado gratuito na Steam.
