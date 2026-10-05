# Skins, novos espaços de equipamento e skins épicas — roadmap 0.24 a 0.29 (0.24 a 0.28 feitas)

Plano de 04/10/2026. O texto diz o que existe hoje, o que muda, em que ordem e as decisões tomadas (seção "Decisões"). Os números são pontos de partida para testar. O andamento está em "Estado da implementação", no fim.

## Por que mexer

1. **O que o jogo chama de "roupa" é uma skin**: o slot `roupa` troca o boneco inteiro (`cosmetic.skin` → `assets/characters/<skin>/`, com 4 direções e 7 clipes deitado). Mesmo assim ela carrega atributos (`attrs` Defesa 30–50, Ataque, Agilidade, Sorte) e entra no Ferreiro (`strengthen.slots` e `affixes.slots` têm `roupa`, com Defesa e vida por nível).
2. **Não podemos vender cosmético que dá atributo.** A loja premium já vende só itens sem atributos (`PremiumStore.valid`), mas isso cria um problema: a Skin premium, as Asas da Aurora, o cabelo e a Solaris **ocupam o mesmo slot de um item com poder**. Quem compra aparência abre mão de atributos (a própria `FOUNDER_PACK.md` registra isso para a Solaris). É um "imposto" para quem paga, e o contrário do que queremos: o pagante tem de poder usar a skin **e** o equipamento forte juntos.
3. **Cabelo na loja premium** (4 tinturas a R$ 4,99 e o pacote a R$ 14,99) é uma venda fraca, em um slot que o jogador mal vê no combate (o boneco deitado é pequeno). Sai da loja.
4. Faltam espaços de equipamento que dão profundidade ao *build* (anéis e amuleto) e um jeito de ver a skin sem nada por cima.

## Regra de ouro (vira teste)

> **Slot de poder nunca é vendido por dinheiro. Slot de aparência nunca tem atributo.**

| Tipo | Slots | Atributos | Onde se consegue | Leilão |
|---|---|---|---|---|
| **Poder** | arma, auxiliar, camisa, calça, chapéu, óculos, asas, anel 1, anel 2, amuleto | sim (e afixos, Ferreiro, moedas) | drops, loja de ouro, craft | sim |
| **Aparência** | skin, cabelo | **nunca** | loja de ouro (comuns), loja premium (raras, épicas, lendárias), eventos, temporada | só as de ouro e de drop; as premium continuam vinculadas |

Consequência direta: **só o slot `skin` e itens cosméticos "dentro" da skin podem ser premium**. `PremiumStore.valid` passa a exigir `slot ∈ COSMETIC_SLOTS` e `attrs` vazio, e um teste falha se um produto de `store.json` tocar um slot de poder. As Asas da Aurora e a Solaris do Founder Pack são o caso a resolver (decisão D4).

## Novo mapa de espaços (12)

| # | Slot | Hoje | Depois | Aparece no boneco? |
|---|---|---|---|---|
| 1 | Arma | existe | igual | arma nas costas em batalha |
| 2 | Auxiliar | existe | igual | não |
| 3 | **Skin** | era `roupa` | **só aparência**, sem atributos, sem Ferreiro | sim, é o boneco |
| 4 | **Camisa** | não existe | poder: Defesa e vida (cabe Ferreiro) | não (D1) |
| 5 | **Calça** | não existe | poder: Defesa e Agilidade (cabe Ferreiro) | não (D1) |
| 6 | Chapéu | existe | igual (poder) | sim, sobre a skin |
| 7 | Óculos | existe | igual (poder) | sim, sobre a skin |
| 8 | Asas | existe | igual (poder) | sim, atrás da skin |
| 9 | Cabelo | existe, com `sorte 5`, 4 premium | **só aparência**, sem atributos, fora da loja premium | sim, tinge o cabelo da skin |
| 10 | **Anel 1** | não existe | poder: os 4 atributos | não |
| 11 | **Anel 2** | não existe | poder, mesmo catálogo do anel 1 | não |
| 12 | **Amuleto** | não existe | poder: **Vida** obrigatória + um atributo secundário | não |

Anéis: o mesmo item não pode ocupar os dois espaços (anel único por `id`), para o jogador não empilhar o melhor anel duas vezes. Os anéis têm `id` de anel; o espaço 1 e o 2 são só duas posições de `equipped` (`anel_1`, `anel_2`), sem lado "esquerdo/direito".

### Opção "só a skin" (ver a skin limpa)
Um interruptor por jogador, `look.skin_only`, que esconde chapéu, óculos, asas e cabelo (e o brilho das armas na tela de menu), e deixa só a skin e as camadas **dela** (halo, auras da skin). Fica salvo no perfil (operação nova `skin_only` em `PlayerProfile.apply_op`, com checagem de tipo), vai no `look` da partida, então os outros jogadores também veem a skin limpa. Os atributos **não mudam**: o interruptor só desliga o desenho, o item continua equipado. Onde aparece: tela do personagem (botão ao lado do boneco), loja premium (pré-visualização sempre limpa), Salão e cidade. Em batalha respeita o interruptor, mas a arma nas costas continua desenhada (regra de leitura: o jogador precisa ver a arma).

## O que muda no código (mapa)

| Peça | Arquivo | Mudança |
|---|---|---|
| Lista de slots | `armory.gd` (`EQUIP_SLOTS`, `SLOT_NAMES`), `character_screen.gd` (`SLOT_ORDER`) | `roupa` → `skin`; entram `camisa`, `calca`, `anel_1`, `anel_2`, `amuleto`. Constantes novas `COSMETIC_SLOTS` e `POWER_SLOTS` |
| `slot_of` dos anéis | `armory.gd` | um item `anel_x` equipa no primeiro espaço livre; arrastar para o espaço certo continua valendo (`can_equip_key`) |
| Atributo de vida | `armory.gd` (`item_attrs`, `character_stats`) | hoje o resultado só tem Ataque, Defesa, Agilidade e Sorte; entra a chave `vida` somada ao `bonus_hp`. As moedas e os afixos já têm `vida` (pool `armor` em `items.json`) |
| Dados | `shared/balance/items.json` | seção `cosmetics` com `slot: "skin"`, `rarity`, `gender`, `layers`; seção nova `gear` (camisa, calça, anel, amuleto) com `slot`, `attrs`, `icon`, `price`; `strengthen.slots` e `affixes.slots` passam a `["arma","camisa","calca","chapeu"]` etc. |
| Perfil | `profile.gd` | **v11**: lê v1–v10 (`roupa` → `skin`, `roupa_*` de ouro viram skins sem atributos; ver D2). `equip`, `unequip`, `remove_instance` e `apply_op` ganham os slots. Hoje o `look.clothes_level` vem do nível da roupa: passa a vir da camisa (D3) |
| Boneco | `look_rig.gd`, `Armory.look_for` | `look.skin_only` e `look.rarity`; a camada própria da skin (modelo do `FounderFx`) sai do `FounderPack` e vira `SkinFx` genérico |
| Loja premium | `premium_store.gd`, `store.json`, `shop_screen.gd`, rotas de pagamento em `server/api` | `valid()` mais rígido; os 5 SKUs de tintura saem; produtos de skin entram |
| Leilão | `auction.gd`, `server/api/migrations` | migração SQL `roupa` → `skin` nos anúncios existentes e filtros por slot novos |
| Ferreiro e moedas | `smith_screen.gd`, `crafting.gd` | slots novos e os afixos de anel e amuleto |
| Bots e instâncias | `Armory.random_loadout`, `combat.json` (`bots`, `instances`) | bots usam camisa, calça, anéis e amuleto; rebalancear a curva (ver 0.26) |
| i18n e wiki | `locale/`, `tools/build_site.py` | nomes de slots e dos itens novos; a wiki lista os novos espaços |
| Testes | `armory_tests`, `bag_tests`, `craft_tests`, `forge_tests`, `premium_tests`, `founder_tests`, `ui_tests`, `net_e2e_tests` | atualizar; novo `slot_rules_tests.gd` com a regra de ouro |

O servidor de jogo é este mesmo projeto: **reimplantar depois de cada fase** (os arquivos `items` e `store` entram no hash de conteúdo).

## Roadmap

| Versão | Entrega | Precisa de servidor? | Arte? |
|---|---|---|---|
| 0.24 | **Fundação de slots e migração** | sim (perfil e anúncios) | não |
| 0.25 | **Camisa e Calça** | sim | ícones |
| 0.26 | **Anéis (2) e Amuleto (Vida)** e a nova tela do personagem | sim | ícones |
| 0.27 | **Opção "só a skin"**, limpeza da loja premium, pré-visualização | sim | pouca |
| 0.28 | **Skins épicas — temporada 1** (3 skins) — **feita** | sim | **muita** |
| 0.29 | **Skins épicas — temporada 1 (restante), cores alternativas e vitrine** | sim | média |

A arte das skins épicas é a parte lenta. Para não travar, **a arte começa em paralelo já na 0.24** (conceito e personagem em pé) e a 0.28 só liga o que já estiver pronto.

### 0.24 — Fundação de slots e migração
- [x] `COSMETIC_SLOTS` e `POWER_SLOTS` em `Armory`; renomear `roupa` → `skin` em código, dados, anúncios e textos (a id interna dos itens `roupa_*` continua, como já se fez com os nomes antigos; o **slot** muda).
- [x] `PlayerProfile` v11 com leitura de v1–v10 e a migração de `equipped["roupa"]`; teste de leitura de um save v10 com roupa equipada, fortalecida e com afixos.
- [x] Migração SQL do leilão (`slot = 'roupa'` → `'skin'`) e do cache de perfil; teste Go com banco descartável. **Dispensada**: só entram no leilão peças que caíram nas instâncias, e uma roupa nunca caiu; não há anúncio de `roupa` para migrar.
- [x] Tirar `attrs` das skins de ouro e tirá-las do Ferreiro (`strengthen.slots`, `affixes.slots`); o `clothes_level` e o brilho da roupa passam para a camisa na 0.25 (até lá o brilho fica desligado).
- [x] `PremiumStore.valid` rígido (só `COSMETIC_SLOTS`, `attrs` vazio) e o teste da regra de ouro.
- [x] Cabelo sem atributos (some o `sorte 5`); preço em ouro mantido ou reduzido.
- [x] Começar a arte: conceito, referência e personagem em pé das 3 primeiras skins épicas. **Feito na 0.28**, junto com a arte completa (ver `docs/PIXELLAB_SKINS.md`).

### 0.25 — Camisa e Calça
- [x] 8 peças (4 famílias de camisa e calça, na lista `cosmetics` de `items.json` com `slot` `camisa` e `calca`): Algodão, Aventureiro e Guerra na loja de ouro; Celeste só cai nas instâncias (`drop_only`). Cada par soma o que a roupa antiga dava (Defesa 30 a 70).
- [x] Ferreiro: `+` de Defesa e vida por nível passam a valer nos dois (hoje `defense_per_level` 8 e `hp_per_level` 25, só em roupa e chapéu).
- [x] Afixos de armadura (`armor` em `items.json`) valem em camisa e calça; Super Verdadeira cai nos mapas altos.
- [x] Loja de ouro, drop, leilão e as tabelas do Salão.
- [x] Ícones: `create_object_pro_flash` 96×96 por peça (ver custo); uma família por vez, com mesmo estilo de contorno.
- [x] **Brilho de força**: o brilho da roupa por nível (`clothes_level`) vem da camisa.

### 0.26 — Anéis e Amuleto
- [x] Dados de anel (4 famílias, um por atributo principal, mais um misto) e amuleto (4 famílias, **Vida base obrigatória**, atributo secundário). Ponto de partida: vida base 150 / 195 / 240 / 300 por qualidade (Normal, Excelente, Verdadeira, Super), contra 1.500 de vida base do jogador e +40 por nível; ajustar com simulação.
- [x] Afixos próprios: anel puxa Ataque, Sorte, crítico, dano do POW; amuleto puxa vida, Defesa, energia por turno, delay. Anel e amuleto **não** vão ao Ferreiro (não se fortalecem); o poder deles vem dos afixos e das moedas do craft, o que dá mais uso às moedas.
- [x] `character_stats`: `vida` do item entra no HP inicial da partida (no `LocalMatch`, igual para servidor e cliente: é determinístico).
- [x] **Tela do personagem**: 12 espaços; refazer o painel (hoje 7). Os três novos têm de caber também em celular (modo toque, `touch_mode.gd`) e na mochila de arrastar e soltar. (Feita e capturada; o encaixe no modo toque do celular ainda precisa de teste em aparelho.)
- [x] **Rebalancear**: com 5 slots de poder a mais (camisa, calça, 2 anéis, amuleto) e a skin sem atributos, o total de atributos de um jogador completo muda. Rodar `instance_balance.gd`, `hunt_balance.gd` e os bots; ajustar `combat.json` (instâncias, mapas de nível, bots) para que o desafio de agora continue o desafio de depois, e **comparar com o equipamento antigo**. (Simulação de instâncias feita, sem ajuste em `combat.json`; `hunt_balance.gd` e os bônus F1 ainda não foram medidos.)
- [ ] Missões, conquistas e cupons com os itens novos (`TESTARTUDO` etc.). **Parcial**: o cupom `TESTARTUDO` já entrega camisas, calças, anéis e amuletos; missões e conquistas não ganharam nada com os itens novos.

### 0.27 — Só a skin e loja premium sem cabelo
- [x] `look.skin_only`: interruptor no perfil, na tela do personagem e na pré-visualização da loja; `apply_op` valida o tipo.
- [x] Remover os 5 produtos de cabelo de `store.json` e do Stripe (desativar os preços; **quem já comprou fica com o item**, igual ao Founder Pack) e o aviso nos textos da loja. **Feito**: o Stripe recebe o preço inline em cada pedido (`price_data` em `stripe_client.go`), então não há preço cadastrado para desativar.
- [x] Cabelo continua como cosmético sem atributos: loja de ouro e recompensas de evento. As 4 tinturas premium viraram itens de ouro (300 moedas) e quem já comprou segue com elas; recompensas de evento ficam para quando houver evento.
- [x] Loja premium reorganizada em vitrine (skins primeiro, etiqueta ÉPICA/LENDÁRIA/CONVENIÊNCIA, campo `section`) e pré-visualização com as 4 direções e a pose deitada (andar, atirar, POW, vitória). **Feito na 0.28**: o provador ganhou **Em pé** e **Batalha** (`client/ui/skin_stage.gd`). Não há sub-abas por seção: a lista só ordena as skins antes das conveniências.
- [x] Teste: `skin_only` esconde só o que deve, não muda atributos, e o servidor leva o mesmo `look` aos outros jogadores.

### 0.28 e 0.29 — Skins épicas
Ver abaixo. A 0.28 entregou 3 skins (feita em 05/10/2026, ver "Estado da implementação"); a 0.29 traz as outras 3, as cores alternativas e a Épica Deluxe.

## Skins épicas

**Meta**: o jogador abre a loja e **quer** a skin; quem já tem a vê todo dia (cidade, Salão, salas, partida). Isso se faz com arte acima das 8 skins de ouro, não com mais efeitos de poder.

### Níveis de skin
| Nível | Como se consegue | O que tem | Preço de partida (a testar) |
|---|---|---|---|
| Comum | ouro (as 8 de hoje, sem atributos) | boneco em 4 direções e 7 clipes deitado | ouro |
| Rara | premium | idem, com paleta e acessórios da própria arte, 2 cores alternativas | R$ 19,90 |
| **Épica** | premium ou temporada | **camada própria animada** (como o Halo do Paladino), clipe de POW próprio, entrada no Salão e pose de vitória única, 2 cores alternativas, versão masculina **e** feminina | R$ 39,90 a 59,90 |
| Lendária | limitada (Founder Pack e o futuro) | tudo da épica mais arma e animação de POW próprias | R$ 149,90 (Founder) |

Compra **sem caixa aleatória** (ECA Digital): o jogador vê o que leva. Nada de poder: as camadas da skin nunca têm atributo, e a regra de "o efeito nunca parece maior que a área de dano real" de `FOUNDER_PACK.md` vale para todas.

### Padrão de qualidade (portão para publicar)
Uma skin só vai para a loja se passar neste roteiro; um `tests/skin_visual_check.gd` novo gera as capturas de conferência.
1. **Leitura a 80 px**: a silhueta deitada é reconhecível e diferente das outras skins (teste lado a lado de silhuetas); cabeça grande e contorno limpo (`2a1c30`, não preto puro).
2. **Paleta fechada** de 12 a 20 cores, rampas de 4 a 6 tons por material, sem antisserrilhado. Uma cor de destaque só, para o olho achar a skin em meio ao cenário.
3. **Quadros completos**: 4 direções em pé, mais 7 clipes deitado (idle 6, crawl 8, shoot 6, hit 4, victory 6, defeat 6, pow 4), com a direção leste já virada para a direita.
4. **Camada própria** (`SkinFx`): brasas, raios, gelo, vapor etc., em partículas de grade de 2 px, **sem tapar** a trajetória, o vento ou o inimigo, e desligada em `skin_only` apenas se o jogador pedir. Desempenho: cabe no web e no celular (sem threads; `CPUParticles2D`).
5. **Âncoras e compatibilidade**: `character_anchors.py` rodado; chapéu, óculos e asas assentam sem cortar (as peças de cabeça de uma skin com capacete usam `NO_DYE` e escondem o chapéu: ver o caso do Paladino); o cabelo não pinta o elmo.
6. **Gênero**: cada skin épica sai em **versão masculina e feminina**, com o mesmo nome e o mesmo produto. Hoje as roupas são presas a um gênero (`gender` `m` ou `f`); skin épica é vendida igual para os dois (custa o dobro de arte; é a escolha para não perder metade dos compradores).
7. **Retrato e cut-in do POW**: a skin aparece no cut-in com a pose própria (o cut-in usa o retrato com `no_aura`).
8. **Pré-visualização**: 4 direções, as 7 animações e o teste de cores alternativas, sem erros no `i18n.py --check`.
9. **Revisão por captura em três fundos** (cidade, Salão e as 5 mapas de batalha) antes de publicar.

### Como produzir (uma skin)
- **Conceito em texto** (silhueta, paleta, camada própria), e passar pelo **Jev** (`tools/jev_review.py`) como no Founder Pack quando houver mais de uma opção de silhueta ou de camada: ele pesou leitura, identidade e viabilidade (tabela em `FOUNDER_PACK.md`). Não se usa o Jev para gerar arte.
- **PixelLab**: `create_character` padrão (chibi, `side`, 4 direções, 96 → tela 136), **2 variações** a 1 geração cada, escolher a melhor; `create_character_state` para o deitado (~20–40); `animate_character` v3 para os 7 clipes (2–4 por clipe). Estimativa por versão: **cerca de 65 gerações** e **cerca de 130 por skin** nas duas versões, com folga para repetir (~260 no pior caso). 6 skins ≈ 800 a 1.600 gerações; o plano atual (4.500 por ciclo) comporta. Conferir o saldo com `get_balance` antes de cada lote.
- **Código**: `tools/import_pixellab_skin.py <zip> Idle Prone <id>` e `tools/character_anchors.py <id>`; a **camada própria** em `tools/skin_art.py` (generalização do `tools/founder_art.py`), pixel a pixel em paleta fechada, sem IA.
- **Acabamento à mão** quando a IA errar um detalhe (a meia-cintura da Lani, a cor do cabelo que vaza na tintura): mais barato que gerar de novo.
- **Cores alternativas** (`recolor`): um deslocamento de paleta no *shader* do `look.gdshader`, sem arte nova; vendidas como "Cor extra" a preço baixo ou liberadas com a skin.
- **Documentar** em `docs/PIXELLAB_SKINS.md` (o que foi gerado, as seeds, os descartes e o custo), como as notas de `PIXELLAB_FOUNDER.md`.

### Catálogo da temporada 1 (decidido, D6)
Temas feitos para o mundo do jogo (ilhas no céu, artilharia, elementos, moedas Eclipse e Tempestade), sem copiar outros jogos.
| # | Skin | Ideia | Camada própria |
|---|---|---|---|
| 1 | **Senhor da Tempestade** | armadura azul-aço e capa rasgada, olhos de raio | arcos elétricos que correm nos ombros; um raio fino no POW |
| 2 | **Rainha do Gelo** | vestido de cristal, coroa de estilhaços | flocos que giram; brilho de geada no chão ao andar |
| 3 | **Lorde do Magma** | rocha escura e rachaduras de brasa | brasas que sobem; as rachaduras pulsam ao carregar a força |
| 4 | **Capitã Fantasma** | casaco naufragado, chama verde-azulada no lugar do rosto | chama fria e fumaça; a barra do casaco some em névoa |
| 5 | **Guardião de Jade** | armadura de dinastia, máscara de dragão | serpente de jade que circula o boneco |
| 6 | **Caçador do Eclipse** | preto e dourado, um sol negro nas costas | disco do eclipse atrás da cabeça, com um anel de luz no POW |

0.28 entrega 1, 2 e 3 (elementos reconhecíveis e fáceis de ler em batalha); 0.29 entrega 4, 5 e 6, mais as cores alternativas e a vitrine.


### Preços (decididos, D6)
Preços de partida, em reais (loja Stripe/Pix) com o equivalente em dólar (Steam). A Steam fica com 30%: os valores já cabem nisso. Ajustar depois de ver a conversão do primeiro mês.

| Produto | R$ | US$ | Conteúdo |
|---|---|---|---|
| Skin Rara | 19,90 | 3,99 | skin, 2 cores extras |
| **Skin Épica** | **44,90** | **8,99** | skin masculina e feminina, camada própria, POW próprio, 2 cores extras |
| **Épica Deluxe** | **59,90** | **11,99** | a Épica mais o emote da skin e uma cor exclusiva |
| Cor extra avulsa | 6,90 | 1,49 | só quem já tem a skin |
| Pacote da temporada (3 Épicas) | 109,90 | 21,99 | as três skins da entrega, com 18% de desconto |
| Founder Pack (Lendária, já existe) | 149,90 | 29,99 | continua como está |

Faixa por tema: as 3 primeiras (Tempestade, Gelo, Magma) são **Épicas**; as outras 3 (Fantasma, Jade, Eclipse) entram como **Épica Deluxe** por terem mais animação (a Capitã e o Caçador ganham o POW com cena própria). Nada é "caixa". As skins de ouro (comuns) continuam entre 300 e 900 moedas, sem atributos.

### Vontade de comprar (o que ajuda de verdade, sem vender poder)
- **Pré-visualizar e experimentar** na loja (0.27): ver andando, atirando e no POW, e vestir no próprio personagem antes de pagar.
- **Aparecer**: skin épica é vista na cidade, no Salão (entrada no lobby só para lendárias), nas salas, no ranking e no cut-in do POW. Nada que esconda quem joga com a skin comum.
- **Skins de conquista**: uma skin épica por temporada da liga **não** vendável (só quem chegou lá). Dá prestígio e valoriza as vendidas.
- **Temporada**: uma skin nova por temporada de 8 semanas, com vitrine na cidade, e skins antigas voltando de vez em quando (as lendárias não voltam).
- **Pacotes**: skin + cor extra + emote da skin por um preço menor que o das partes. Nunca "caixa-surpresa".
- **Vitrine no site**: o `website/` e o vídeo para as redes mostram a skin em movimento (reaproveita `make_trailer.py`).

## Decisões
Respondidas em 04/10/2026: D1 camisa e calça **não** aparecem no boneco; D2 sim; D3, D4 e D5 como recomendado; D6 (temas e preços) ficou a meu critério, definido abaixo; D7 anel e amuleto fora do Ferreiro.

| # | Pergunta | Decisão / recomendação |
|---|---|---|
| **D1** | Camisa e calça aparecem no boneco? | **Não.** A skin é o corpo; desenhar camisa e calça por cima de 7 clipes × 2 gêneros × cada peça é inviável e brigaria com as skins. Camisa, calça, anéis e amuleto são poder, com ícone na mochila e sem desenho no boneco. Se você quiser que apareçam, só no menu e só quando a skin for a básica. |
| **D2** | O que acontece com as roupas de ouro que o jogador já tem (nível, afixos, anúncios no leilão)? | Antes do lançamento ainda não há jogadores de verdade: converter a roupa em **skin sem atributos**, dar uma **camisa e uma calça** iniciais de qualidade igual e devolver as Pedras de Fortalecimento gastas. Anúncios abertos viram skin pelo SQL. |
| **D3** | O brilho de força (nível da roupa) fica? | Sim, vem da **camisa**. |
| **D4** | Como ficam as Asas da Aurora e a Solaris do Founder Pack, que hoje ocupam slots de poder sem dar atributos? | **Asas**: passam a ser camada da skin (como o Halo), saem do slot `asas` e já vêm com a skin. **Solaris**: a arma é poder; o jeito certo é **"skin de arma"** (visual que se põe sobre qualquer arma, com POW e projétil próprios), planejado para depois da 0.29; até lá segue como está e a regra vale para tudo novo. |
| **D5** | Cabelo: mantém o slot ou funde na skin? | Mantém como cosmético sem atributos (ouro e eventos); some só da loja premium. |
| **D6** | Os 6 temas, a ordem e a faixa de preço. | Os da tabela acima; preço a definir com você e pelo Stripe/Steam. |
| **D7** | Anel e amuleto entram no Ferreiro? | Não; ficam no craft com as moedas. Se quiser fortalecer, é só incluir o slot em `strengthen.slots`. |

## Riscos
- **Equilíbrio**: 5 slots de poder a mais mudam o total de atributos de todo mundo, dos bots e dos mapas. Por isso o rebalanceamento está na própria 0.26, não depois.
- **Arte épica é cara e lenta**: pior caso 260 gerações por skin; por isso 3 skins por entrega, e a arte começa antes do código.
- **Quem comprou cabelo premium**: mantém o item (aparece só como cosmético sem atributos); registrar no changelog.
- **Servidor**: toda fase muda `items.json` ou `store.json`: reimplantar o servidor de jogo e a API juntos; o perfil v11 tem de ser lido pelos dois.
- **Stripe**: sem risco com as tinturas: o preço vai inline em cada pedido, então nada ficou cadastrado no painel. Pedidos de tintura abertos antes do deploy ainda se pagam e entregam (a entrega usa os itens do pedido, não o catálogo).
- **Pixel art de verdade**: nada de HD, vetor ou 3D, e nada que lembre as skins ou os nomes de outro jogo (`tests/launch_tests.gd` já vigia marca e nomes).

## Estado da implementação

### 0.24 e 0.25 — feitos em 04/10/2026 (juntos, para ninguém ficar sem Defesa no meio)
- `roupa` virou `skin` (`Armory.EQUIP_SLOTS`, dados, loja, leilão, tela do personagem); as skins de ouro e o cabelo perderam os atributos. `Armory.COSMETIC_SLOTS` (skin, cabelo) e `POWER_SLOTS`; `Armory.ARMOR_SLOTS` (camisa, calça, chapéu) recebem a Defesa e a vida do Ferreiro.
- `camisa` e `calca` com 8 peças e ícones do PixelLab (`assets/cosmetics/camisa_*/icon.png`), afixos de armadura, Ferreiro, loja de ouro e drop (as peças `drop_only`). **Não aparecem no boneco**; só o brilho de força (`look.clothes_level`) vem da camisa.
- Perfil **v11** (`PlayerProfile.load_data`): `roupa` → `skin`; cada roupa antiga vira a skin simples e gera **uma camisa e uma calça** da família equivalente (`LEGACY_OUTFITS`) com o nível, a qualidade e os bônus da roupa; se a roupa estava vestida, as duas vêm vestidas. Equipamento num slot que não é o do item é descartado ao carregar (as Asas da Aurora).
- **Asas da Aurora** viraram camada da skin Paladino do Sol (`layers.wings`; `look_for` as desenha por cima das asas vestidas) e um item "selo" (guardado como prova da compra, `PlayerProfile.is_keepsake`).
- `PremiumStore.valid` só aceita slot de aparência, "selo" ou a Solaris (`LEGACY_POWER`).
- Testes: `tests/slot_rules_tests.gd` (regra de ouro, camisa e calça, camada da skin, migração v10 → v11); `craft_tests` e demais ajustados; inglês em `locale/en.po`.
- Não foi preciso migrar o leilão em SQL: só entram no leilão peças que caíram nas instâncias, e uma roupa nunca caiu.
- Pendente da 0.25: tabelas de drop e do Salão conferidas só por teste; falta ver a tela do personagem e a loja em captura.

### 0.26 — feita em 04/10/2026
- Slots de uso `anel1`, `anel2` e `amuleto` em `Armory.EQUIP_SLOTS`; o item tem o slot `anel` ou `amuleto` e `Armory.worn_places(slot)` diz onde ele vai (`anel` → as duas mãos). `Profile.equip(uid, place)` escolhe a primeira mão vazia ou a que o jogador soltou o anel; nunca o mesmo anel nas duas mãos. O op `toggle_equip` aceita a mão como segundo argumento.
- Dados em `items.json`: 5 anéis (Bronze/Ataque, Safira/Defesa, Vento/Agilidade, Esmeralda/Sorte e o Solar, só nas instâncias) e 4 amuletos (Pedra/Defesa, Lobo/Ataque, Coruja/Sorte e o Celeste, só nas instâncias). O amuleto leva o campo `hp` (150, 150, 150 e 200 em Normal) e `Armory.item_hp` o escala pela qualidade (x1, x1,3, x1,6, x2); `character_stats` soma no HP inicial, igual no servidor e no cliente.
- Afixos: `affixes.slots` ganhou os dois e `affixes.pools` dá a lista curta de cada um (anel: Ataque, Sorte, dano crítico, dano do POW; amuleto: vida, Defesa, energia, Delay). Não vão ao Ferreiro; caem nas instâncias como o resto do equipamento.
- Tela do personagem: amuleto e anéis na coluna direita, o mascote foi para o palco, ao lado do boneco. Loja de ouro (abas Anéis e Amuletos), leilão (filtros), tooltip (linha de Vida), bots (usam camisa, calça, anéis e amuleto só com atributos), wiki e README.
- Ícones: 9 de 96x96 com `create_object_pro_flash` (5 gerações cada, 45 no total, todos na primeira tentativa).
- Testes: `tests/slot_rules_tests.gd` (82 checagens).
- Rebalanceamento: `instance_balance.gd` ganhou o herói "nv15 +joias" (dois anéis e o Amuleto de Pedra de loja, sem bônus: +25 Ataque, +25 Sorte, +15 Defesa e +150 de vida). Com 4 tentativas por linha, ele ficou dentro do ruído do herói sem joias (por exemplo, Templo do Sol L5 4/4 contra 3/4 e Fiorde L5 1/4 contra 2/4), então **as joias de loja não pedem ajuste em `combat.json`**. Os bônus F1 de anel e amuleto (dano crítico, dano do POW, vida) não foram medidos: vale simular de novo quando as instâncias altas derem peças com 4 bônus.
- A loja de ouro tem uma aba só, **Joias**, para os dois slots (as abas não cabiam em inglês); o leilão filtra Anéis e Amuletos à parte.
- Pendente: `hunt_balance.gd` e uma captura do leilão.

### 0.27 — feita em 04/10/2026
- **Só a skin**: `PlayerProfile.skin_only` (salvo no perfil, lido como desligado em saves sem o campo, sem mudar a versão v11) e o op `skin_only` (só `true` liga; qualquer outro valor desliga). `Armory.look_for(gender, equipped, skin_only)` deixa chapéu, óculos, asas e a tintura do cabelo fora do `look`; arma, aura e o que a própria skin carrega (as asas do Paladino) continuam. Como o servidor monta o `look` com a mesma função, a sala, a partida e os outros jogadores veem o mesmo. Os atributos leem o equipamento, não o `look`, e um teste confere que não mudam.
- **Onde ligar**: caixa "Só a skin" na tela do personagem (canto do palco) e no provador da loja; a do provador é só para ver e não mexe no perfil.
- **Cabelo fora da loja paga**: saíram `tintura_*` e `pacote_tinturas` de `store.json` (o catálogo premium ficou com o Passe do Caçador, as 6 abas e o Pacote Fundador). Rosa Neon, Branco Gelo, Chama e Aurora viraram cabelos de ouro (300 moedas, sem atributos); quem comprou segue com o item.
- Testes: `slot_rules_tests` (95 checagens, 13 novas); `launch_tests` e `net_e2e_tests` passaram a usar a aba de mochila no lugar da tintura como produto de teste; inglês em `locale/en.po`.
- **Não saiu** (ver a lista da 0.27): vitrine por seção e pré-visualização com 4 direções e pose deitada, ambas movidas para a 0.28.
- **Servidor**: `items.json` e `store.json` mudaram; reimplantar servidor de jogo e API.

### 0.28 — feita em 05/10/2026 (skins épicas, temporada 1)
- **Três skins, para os dois gêneros**: Tempestade Viva (`epica_tempestade`), Coroa de Gelo (`epica_gelo`) e Coração de Magma (`epica_magma`). Cada uma é **um item e um produto** (`slot` skin, `gender` u, `rarity` epica, `premium`, sem atributos), com `skin` (masculina) e `skin_f` (feminina); `Armory.skin_folder(def, gender)` escolhe a pasta, `look_for` e o ícone da Mochila e da loja (`Armory.viewer_gender`, posto pelo perfil) também. **Os nomes viraram neutros** (Tempestade Viva, Coroa de Gelo, Coração de Magma), porque o mesmo nome serve ao Senhor e à Senhora da Tempestade, ao Rei e à Rainha do Gelo, ao Lorde e à Lady do Magma.
- **Arte** (`assets/characters/epica_<tema>_<m|f>/`): 4 direções em pé, `prone/` com as 4 direções e os 7 clipes (idle 6, crawl 8, shoot 6, hit 4, victory 6, defeat 6, pow 4), `anchors.json` sem tintura de cabelo (`tools/character_anchors.py` trata `epica_*` como `NO_DYE`). Gerada no PixelLab; o registro (ids, custos, descartes) está em `docs/PIXELLAB_SKINS.md`. As skins deitam **de mãos vazias**: a arma equipada vai nas costas, como em todas as outras.
- **Camada própria** (`client/components/skin_fx.gd`, `SkinFx`): `look.skin_fx` (`storm`, `ice` ou `magma`, do campo `fx` do item) faz o `LookRig` criar uma `SkinFx`. Células de 2 px opacas (a grade do sprite; nos avatares maiores a célula cresce com a cabeça), `CanvasItem._draw`, sem partículas de GPU, sem `randf()` (ruído puro por `sin`): cabe na web e no celular e nada volta para a partida. Tempestade: arcos que correm nos ombros e um raio fino do céu no POW; Gelo: flocos que caem, geada que brilha no chão ao andar, brilho na coroa e um anel de estilhaços no POW; Magma: brasas que sobem, rachaduras que pulsam (mais ao mirar) e uma erupção de brasas no POW. O que a camada faz fica sobre o personagem e acima da cabeça: nunca cobre a linha do tiro nem a área de dano. "Só a skin" **mantém** a camada (ela é a skin).
- **POW da skin**: `battle_screen.show_special` chama `TankFighter.skin_pow`, que toca o clipe `pow` da skin e o floreio da camada enquanto o *cut-in* segura o tiro; não muda dano, alcance nem projétil (o determinismo não é tocado).
- **Loja** (`store.json`): `skin_tempestade` 2101, `skin_gelo` 2102, `skin_magma` 2103 (R$ 44,90 / US$ 8,99) e `pacote_temporada_1` 2110 (R$ 109,90 / US$ 21,99, 18% abaixo das três), todos com `section` ("skins" ou "conveniencias"; as skins vêm primeiro) e uma etiqueta no cartão (ÉPICA, LENDÁRIA ou CONVENIÊNCIA). O pacote é `bundle`: **não se vende por cima de skins que o jogador já tem** (`PremiumStore.overlaps`, checado no servidor em `store_buy` e `store_checkout`); quem já tem uma compra as outras avulsas.
- **Provador** (`client/ui/skin_stage.gd`): **Em pé** (setas giram nas 4 direções) e **Batalha** (o boneco deitado, sem a placa, com ANDAR, ATIRAR, POW e VITÓRIA). Vale para toda skin da loja, não só as épicas. A prova continua local e some ao fechar.
- **Cupom** `TESTARTUDO` ganhou `epicas` (as três skins). Capturas: `--screen=shop --tab=premium --try=epica_magma --view=battle`, `--demo=epica_gelo`, e `tests/skin_visual_check.gd` (seis skins lado a lado em três fundos).
- **Testes**: `tests/epic_skin_tests.gd` (96 checagens): itens, arte e quadros, silhuetas diferentes, gênero e `look`, atributos que não se mexem, produtos, pacote que não se vende duas vezes, camada em cada estado. Inglês em `locale/en.po`.
- **Servidor**: `items.json` e `store.json` mudaram (e `PremiumStore`/`game_server.gd`): reimplantar servidor de jogo e API juntos.
- **Não saiu / ficou para a 0.29**: cores alternativas e "Cor extra", a Épica Deluxe (Capitã Fantasma, Guardião de Jade e Caçador do Eclipse), o emote da skin, a skin de conquista da liga e o som de cada POW (nenhum som foi ouvido; só medido). A **entrada no Salão** só para lendárias continua como estava. (O POW do Gelo foi refeito uma vez, com "chest arches up, arms thrown wide, glowing white-blue", e agora tem clarão e redemoinho de gelo.)

### 0.29 — parte 1: cores alternativas (feita em 05/10/2026)
- **Sem arte nova**: cada skin épica traz `recolor` (`from` = matiz em que foi desenhada, `range` = meia-largura da faixa, em graus) e `colors` (duas cores `{id, name, shift}`). O *shader* `look.gdshader` (uniform `recolor`) gira o matiz só dos pixels saturados dentro da faixa: pele, cabelo e contorno ficam como estão. A `SkinFx` gira as próprias cores pelo mesmo `shift` (em `cell()`).
- **Cores**: Tempestade Viva (220°, ±35): Aurora Verde, Relâmpago Violeta; Coroa de Gelo (200°, ±30): Geada Rosa, Gelo de Jade; Coração de Magma (5°, ±40): Plasma Azul, Magma Venenoso.
- **Perfil**: `skin_colors` ({id da skin: id da cor}, sem mudar a versão do save, como `skin_only`), op `skin_color` [skin, cor] (a skin tem de ser do jogador; `""` volta ao original), limpeza no `load_data` (`clean_skin_colors`). `Armory.look_for(..., skin_colors)` põe `look.recolor` e `look.skin_color`.
- **Interface**: `client/ui/skin_colors.gd` (`SkinColors.build`, três bolinhas) na Mochila (salva) e no provador da loja (só prova). Captura: `--demo=epica_gelo --color=rosa`, `--screen=shop --tab=premium --try=epica_magma --color=veneno`.
- **Decisão**: as duas cores **vêm com a skin** (como na tabela de preços); a "Cor extra avulsa" (R$ 6,90) e a cor exclusiva da Deluxe ficam para quando houver o que vender.
- **Testes**: `tests/epic_skin_tests.gd` (127 checagens).
- **Capitania Fantasma feita** (05/10/2026, nome neutro, ver `docs/PIXELLAB_SKINS.md`): arte nas duas versões, camada `ghost`, três cores (a terceira, Chama Rubi, é a "cor exclusiva" da Deluxe), SKU `skin_fantasma` a R$ 44,90. `recolor.sat` (saturação mínima) passou a ser configurável por skin.
- **Falta na 0.29**: Guardião de Jade e Caçador do Eclipse, o emote (e com ele o preço Deluxe de R$ 59,90) e a skin de conquista da liga.

### Próximo: 0.29 (skins épicas, temporada 1: o resto)
Capitã Fantasma, Guardião de Jade e Caçador do Eclipse (Épica Deluxe), as cores alternativas (`recolor`, deslocamento de paleta no *shader*) e a "Cor extra". Saldo do PixelLab depois da 0.28: **953 gerações até 24/10/2026**; três skins para os dois gêneros custam cerca de 320 se nada for refeito.
