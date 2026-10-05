# Equipamentos de instância (0.31)

Camisas, calças, chapéus, óculos, anéis e amuletos que **só caem nas instâncias**, em quatro raridades:
**Comum, Raro, Épico e Lendário**. (As asas nasceram nesta linha, mas na 0.32 saíram do drop e passaram a ser
vendidas por dinheiro, sem atributos: ver [Asas](#asas-032-à-venda-por-dinheiro).) Quanto mais alto o nível do mapa, maior a chance das raridades melhores
(nunca uma garantia: o topo da raridade não tem contador nem "depois de N chefes"). Quanto melhor a raridade, mais
atributos **e mais bonita a arte**.

## Duas coisas diferentes: raridade e qualidade

| | Raridade (0.31) | Qualidade (0.10) |
|---|---|---|
| Vem de | da peça (`rarity` em `items.json`) | de um sorteio no drop e das moedas do Ferreiro |
| Valores | Comum, Raro, Épico, Lendário | Normal, Excelente, Verdadeira (Super só em arma) |
| Muda | atributos base, preço, arte, brilho | quantidade de bônus aleatórios (0, 1–2, 3–4) |
| Troca? | nunca (é a peça) | Brasa e Coroa mudam |

As duas se somam: um Anel do Dragão (Lendário) Verdadeiro tem os atributos do Lendário e 3–4 bônus aleatórios.
Peças da loja e as armas não têm raridade própria (a peça da loja vale Comum só para o texto).

## As peças

Uma por raridade em cada espaço, mais as quatro peças antigas de drop (`*_celeste`, `anel_solar`), que entraram
no sorteio como Raro. Multiplicadores sobre a base Comum: **1,0 / 1,5 / 2,1 / 2,8** (a vida do amuleto: 160 / 230 / 320 / 430).

| Espaço | Base Comum | Comum | Raro | Épico | Lendário |
|---|---|---|---|---|---|
| Camisa | Defesa 30, Ataque 8 | Gibão de Couro | Couraça de Aço Azul | Túnica Arcana | Armadura do Dragão |
| Calça | Defesa 22, Agilidade 10 | Calça de Couro | Grevas de Aço Azul | Calças Arcanas | Grevas do Dragão |
| Chapéu | Defesa 24, Sorte 8 | Capacete de Couro | Elmo de Aço Azul | Chapéu Arcano | Elmo do Dragão |
| Óculos | Sorte 14, Ataque 4 | Óculos de Aviador | Lentes de Cristal | Visor Arcano | Olhos de Dragão |
| Anel | Ataque 24, Sorte 8 | Anel de Ferro | Anel de Cobalto | Anel Arcano | Anel do Dragão |
| Amuleto | Vida 160, Defesa 10, Ataque 5 | Talismã de Osso | Medalhão de Safira | Amuleto Arcano | Coração do Dragão |

Preço (só dá o valor de venda, 1/4, e o do leilão): 200 / 500 / 1.200 / 3.200. Um conjunto Lendário completo
(com um anel Épico no segundo espaço, porque o mesmo anel não vai nos dois) dá cerca de +165 Ataque (≈ +16% de dano),
+240 Defesa (≈ −23% de dano recebido), +100 Sorte, +28 Agilidade e +430 de vida, mais os bônus aleatórios: forte, mas
dentro das curvas de `Armory.attack_scale`/`defense_scale`.

Todas são `drop_only` (a loja não lista, `PlayerProfile.buy` recusa, **inclusive chamando a operação direto**, e bots
não usam), unissex, e podem ir ao leilão (não vêm vinculadas). Chapéus e óculos aparecem sobre a skin (camisa,
calça, anéis e amuleto só na ficha, como sempre).

## De onde caem

1. **Cartas de recompensa** (`InstanceRun.roll_card`): o peso da carta de equipamento subiu de 7 para **16**
   (`map_items.loot.gear_weight`). Dentro dela (`gear_card`): 12% é item auxiliar; o resto é peça PvE: sorteia-se a
   **raridade pelo nível do mapa**, depois o espaço (os seis, com a mesma chance: sem asas desde a 0.32) e a peça.
2. **Monstros** (`roll_mob_drop`): o que um monstro solta se divide em pedra / moeda / arma / equipamento
   `0,70 / 0,20 / 0,05 / 0,05` (`strengthen.mob_drops.split`; antes 0,75 / 0,20 / 0,05 e nada de equipamento).

A raridade usa o nível efetivo do mapa (a entrada livre vale 1) e **a raridade do mapa** (`+x% de raridade`, mais a do
grupo) multiplica tudo que não é Comum:

`peso(raridade) = max(0, base + inclinação × (nível − 1))` (`map_items.loot.gear_rarity`), normalizado.

| Nível | Comum | Raro | Épico | Lendário |
|---|---|---|---|---|
| 1 | 74,0% | 22,0% | 3,6% | 0,4% |
| 2 | 71,6% | 22,9% | 4,7% | 0,8% |
| 4 | 66,8% | 24,7% | 6,8% | 1,7% |
| 6 | 61,6% | 26,6% | 9,1% | 2,7% |
| 8 | 56,2% | 28,6% | 11,6% | 3,6% |
| 10 | 50,6% | 30,7% | 14,1% | 4,7% |
| 12 | 44,6% | 32,9% | 16,8% | 5,8% |
| 14 | 38,3% | 35,2% | 19,6% | 6,9% |
| 16 | 31,6% | 37,7% | 22,6% | 8,1% |

Com um mapa de nível 16 e +40% de raridade: 24,8 / 41,4 / 24,8 / 8,9. **Nada é garantido**: não há contador de
"depois de N chefes", e o teste `gear_tests` confere que não existe sequência de Lendários. O tooltip do mapa mostra
essas chances (com a raridade do mapa) em "CHANCE DE EQUIPAMENTO".

A conta usa só o `rng` do baú da expedição (nunca o da partida), como o resto dos drops: o servidor sorteia, o lockstep
não muda. Mudou `items.json` ou `combat.json`: reimplante o servidor (o hash de conteúdo muda).

## Como aparece

- **Arte**: ícones de 96×96 (camisa, calça, anel, amuleto), chapéus e óculos em duas vistas (de frente e de lado, usadas
  no menu e deitado na batalha, com o encaixe em `assets/cosmetics/fit.json`) e uma asa por imagem (o par e o ícone são
  montados por `tools/gear_art.py`). As quatro raridades seguem uma linguagem: Comum couro e osso, sem gemas;
  Raro aço azul e safira; Épico prata e ametista com runas brilhando; Lendário ouro e rubi, escamas de dragão, chamas.
  Receitas e sementes em `docs/PIXELLAB_GEAR.md`.
- **Brilho** (`BagSlot.paint_glow`, `Armory.glow_color`): Comum sem brilho; Raro, Épico e Lendário brilham na cor da
  raridade (as mesmas do mascote: cinza `c4cdd8`, azul `5aa8ff`, roxo `c07bff`, laranja `ffb347`); o Épico "respira" e o
  Lendário brilha com um reflexo que cruza a célula (como a Super Verdadeira). O losango do canto mostra a qualidade
  quando é Excelente ou melhor. Nunca um quadrado colorido em volta (regra do usuário).
- **Tooltip**: "Lendário • Excelente • Anel", nome na cor da raridade. **Carta do baú**: a moldura da carta é a da raridade
  (`reward_card_common/rare/epic/legendary`). **Mapa**: chance de cada raridade.
- **Wiki**: página Visual com a tabela de chances por nível, os anéis e amuletos que faltavam e a raridade de cada peça.
- **Loja**: não vende nenhuma delas (as asas, que já não fazem parte da linha, são vendidas por dinheiro: ver abaixo). As abas ficaram em duas linhas.

## Loja: abas e paginação

O Centro Comercial passou de 11 abas de 70 px numa linha (o texto estourava o botão e as abas se sobrepunham) para
**duas linhas de abas de 128 px** (a última, Premium, ocupa o fim da linha), cartões de 188×214, paginação **centralizada**
embaixo (botões de 52×38, cinza nas pontas) e a mensagem da última compra no lugar da dica da coluna do provador (some no
próximo clique). Constantes em `ShopScreen` (`TAB_RECT`, `TAB_STEP`, `GRID_PANEL`, `CARD_*`, `PAGER_*`); testes em
`tests/gear_tests.gd` (`test_shop`).

## Asas (0.32): à venda por dinheiro

As oito asas (Pardal, Anjo, Fada, Demônio, Cristal, Fênix, Arcanas e Dragão) saíram do drop e da loja de ouro: **só se
compram por dinheiro** (carteira Steam, ou cartão e Pix em reais fora dela), **sem atributos**, e chegam vinculadas pelo
Correio, como as skins épicas e os mascotes. É a regra do ouro de `docs/SKINS.md`: o espaço `asas` passou de
`Armory.POWER_SLOTS` para `Armory.COSMETIC_SLOTS` (junto de skin e cabelo), então `PremiumStore.valid` aceita os
produtos, quem compra aparência não abre mão de nenhum equipamento forte, e `slot_rules_tests` falha se uma asa voltar a
ter atributo ou a ocupar um espaço de poder.

| Asas | Raridade (da arte) | Produto (`steam_item_id`) | Preço |
|---|---|---|---|
| Pardal | Comum | `asas_pardal` (2201) | R$ 14,90 |
| Anjo, Fada, Demônio, Cristal | Raro | `asas_anjo`, `asas_fada`, `asas_demonio`, `asas_cristal` (2202–2205) | R$ 24,90 |
| Fênix, Arcanas | Épico | `asas_fenix`, `asas_arcanas` (2206–2207) | R$ 39,90 |
| Dragão | Lendário | `asas_dragao` (2208) | R$ 59,90 |

Os degraus são os mesmos dos mascotes. A raridade deixou de dar poder: serve só para a cor do nome e do brilho, a
etiqueta do cartão da loja e o tooltip ("Lendário • Asas"). Os preços das outras moedas seguem a mesma tabela dos mascotes.

- **Loja**: a aba **Asas** lista os oito produtos (seção `asas` de `store.json`, com o provador de sempre), fora da aba
  Premium (`PremiumStore.is_wings_product`).
- **O que saiu**: o drop (`map_items.loot.gear_slots` tem seis espaços), os bônus aleatórios e a Brasa e a Coroa
  (`affixes.slots`), o leilão (a aba Asas) e a compra por moedas (`price` 0). Um save antigo lê uma asa como Normal e sem
  bônus (`valid_quality` e `Crafting.valid_mods` já seguem `affixes.slots`), sem mudar a versão do perfil.
- **Quem já tinha**: Anjo, Demônio, Fada e Fênix, comprados com moedas, ficam na mochila, sem atributos. As **Asas da
  Aurora** continuam exclusivas do Founder Pack (camada da skin).
- **Bots** usam qualquer asa, e o cupom `TESTARTUDO` dá as oito (`asas: true`).

## Para acrescentar uma peça

(As asas seguem outro caminho: um produto em `store.json` com a raridade no item, ver acima.)

1. Um PNG por vista do PixelLab em `tools/gear_src/` (ver os nomes em `tools/gear_art.py`) e a linha em `items.json`
   (`slot`, `art`, `rarity`, `pve`, `drop_only`, `attrs`, `hp` no amuleto).
2. `python tools/gear_art.py` instala os PNGs em `assets/cosmetics/<id>/` e o encaixe em `fit.json`; ajuste `FIT` olhando
   `tools/cosmetic_sheet.gd --set=pve_hats|pve_glasses` e `--screen=shop --tab=asas --try=<id>`.
3. `godot --headless --path . --editor --import --quit`, `python tools/i18n.py` (e o inglês), `python tools/build_site.py`,
   `tools/test.sh gear fit slot_rules`.

A captura `--demo=pve_lendario|pve_epico|pve_raro|pve_comum` equipa um conjunto inteiro de uma raridade.
