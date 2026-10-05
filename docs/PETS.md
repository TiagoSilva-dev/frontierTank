# Casa dos Mascotes (0.19, mascotes colecionáveis desde a 0.30)

Os mascotes são **só aparência**. Desde a 0.30 eles são vendidos na loja por dinheiro de verdade (aba **Mascotes** do Centro Comercial), não dão atributo nem poder, não têm habilidade em batalha e **não existem mais ovos nem "chocar"** (isso seria uma caixa de sorteio paga, que o Brasil não permite). Comuns e Raros também podem ser achados de graça (chefe de instância e Caçada), sempre com sorte e sem garantia.

A **Casa dos Mascotes** (prédio da cidade, botão PET da barra e o espaço "Mascote" da Mochila) guarda a coleção. Abas: **Mascotes** (a coleção, o companheiro de batalha e Libertar), **Álbum** (as 20 espécies, as que faltam em silhueta) e **Caçada** (o único lugar onde o mascote sobe de nível, ver `docs/PET_HUNT.md`). O botão **LOJA DE MASCOTES** abre o Centro Comercial já na aba Mascotes.

Tudo sai de `shared/balance/pets.json` e de `client/systems/pets.gd`; o perfil só guarda `{uid, species, level, xp}`. Offline o `PlayerProfile` aplica as operações, online o servidor de jogo aplica as mesmas (`pet_equip`, `pet_release` e as da Caçada estão em `PlayerProfile.OPS`), então não existe segunda cópia das regras.

## Loja

- **20 produtos** em `shared/balance/store.json` (`section: "mascotes"`, `pets: [espécie]`, `steam_item_id` 4001–4020, SKU `pet_<espécie>`), um por espécie, com preço por raridade:

| Raridade | BRL | USD |
|---|---|---|
| Comum | R$ 14,90 | 2,99 |
| Raro | R$ 24,90 | 4,99 |
| Épico | R$ 39,90 | 7,99 |
| Lendário | R$ 59,90 | 11,99 |

  Os outros preços (EUR, GBP, CAD, AUD, MXN, PLN) seguem a mesma proporção das skins. Cartão e Pix cobram em reais (Stripe), a Steam na moeda da carteira.
- **Entrega**: o pedido pago vira uma carta do Correio com `{"pet": espécie, "bound": true}` (`PremiumStore.mail_items`). `Auction.grant_mail` entrega o mascote na coleção (`grant_pet(espécie, paid: true)`, que **nunca é recusado por falta de lugar**) e `undo_mail` o devolve se a transação do servidor precisar voltar. A API em Go guarda o item como JSON opaco, então nada mudou lá.
- **Regras**: só espécies que existem (`PremiumStore.valid`), nada além do mascote na entrega, e quem já tem a espécie vê "VOCÊ TEM" e não consegue comprar de novo (`PremiumStore.owns_all` → `PlayerProfile.owns_species`), tanto na tela quanto no servidor (`store_buy` e `store_checkout`).
- **Provador**: clicar num mascote o põe ao lado do personagem (`ShopScreen.trying_pet`, `SkinStage.add_pet`); no modo Batalha ele aparece como companheiro. Captura: `--screen=shop --tab=pet --pet=<espécie>`.

## O que existe

| Coisa | Regra |
|---|---|
| **Espécies** | 20 (5 elementos × 4 raridades: Comum, Raro, Épico, Lendário). |
| **Nível** | Só sobe na Caçada (`PetHunt.settle`). Nível 1 ao 30, XP por nível = 50 × nível. |
| **Companheiro** | Um mascote ativo vai atrás do lutador em batalha (`PetCompanion`, `look.pet`). **Só visual**: sem bônus, sem habilidade, sem tecla. |
| **Libertar** | Devolve moedas pela raridade (40 / 120 / 400 / 1.500); não vale para o companheiro. |
| **Limite** | 120 mascotes por conta; um mascote **pago** nunca é recusado por isso. Mascotes não vão ao Leilão. |
| **Álbum** | Mostra as espécies que o jogador já teve. Não dá bônus. |

## De graça: só Comum e Raro, sem garantia

- **Chefe de instância**: chance de soltar o **Comum do elemento da instância** no baú: 2% + 0,25% por nível de mapa (máx. 6%; 1% na entrada livre) (`Pets.boss_pet_chance`, números em `pets.json → drops`). Sem garantia, sem contador. Monstros comuns, elites e guardiões **não** soltam mascote.
- **Caçada**: captura por selvagem derrotado, só **Comum (0,12%)** e **Raro (0,03%)**, +8% por nível de caça. Épico, Lendário e o chefe da zona nunca são capturados; só as primeiras 2 h de cada coleta rolam captura (o Passe do Caçador não dá mais sorteios).
- **Presente inicial**: a missão "Além da Ilha" (primeira Instância) dá um Escaravelho Solar, igual para todos, para quem não comprou nenhum poder usar a Caçada (`missions.json → s_instance.reward.pet`).
- Épico e Lendário só se compram.

## Migração (save v12)

Um save até a v11 é lido assim (`PlayerProfile.load_data`):

- cada ovo no inventário (`egg_*`) vira moedas: **150** o de elemento, **220** o genérico `pet_egg` (`pets.json → egg_refund`);
- uma espécie por conta: do que estiver repetido fica o de mais experiência, os outros viram as moedas de libertar;
- estrelas, contadores de garantia (`pity`) e ovos da Caçada são descartados; o nível limite passa a 30 para todos.

## Arquivos

`shared/balance/pets.json` (catálogo e drops) · `shared/balance/store.json` (os 20 produtos) · `client/systems/pets.gd` · `client/systems/premium_store.gd` · `client/systems/auction.gd` (`grant_mail`, `undo_mail`) · `client/systems/profile.gd` (campos, operações, migração, cupom `MASCOTES`) · `client/systems/instance_run.gd` (drop do baú) · `client/ui/shop_screen.gd` (aba Mascotes) · `client/ui/pet_screen.gd`, `pet_stage.gd`, `pet_widgets.gd` · `client/components/pet_companion.gd` · `tests/pet_tests.gd` e `tests/pet_shop_tests.gd`.

Cupons de teste: `MASCOTES` (um de cada espécie) e o `TESTARTUDO` (também dá os 20). `--demo=1` já traz cinco mascotes.

## O que saiu na 0.30

Ovos (seis tipos, `Pets.eggs/odds/roll_*`), a aba **Chocar** e a cena `HatchOutcome`, a garantia (pity) de Épico e Lendário, **alimentar** e **ganhar estrela** (e o XP de batalha), os atributos e talentos do mascote ativo (`Pets.attrs/talents/bonus`, `Armory.character_stats(…, pet_bonus)`), o bônus do álbum, a **habilidade em batalha** (tecla G, intenção `"pet"`, `battle` em `pets.json`) e as missões de chocar/alimentar. Os replays antigos que têm a intenção `"pet"` continuam abrindo: ela é aceita e não faz nada.

Os sons `pet_shake`, `pet_crack` e `pet_hatch_*` (de `tools/make_pet_audio.py`) e as artes dos ovos em `assets/pets/eggs/` ficaram no repositório sem uso.

## Arte (PixelLab, 139 gerações na 0.19)

- **20 espécies** em `assets/pets/<id>.png`, 128×128 (`create_image_pro_flash`, descrição "cute chibi … collectible monster-game pet sprite, three-quarter side view facing right, clean dark outline").
- **5 ícones de elemento** em `assets/pets/elements/` e o santuário `assets/ui/pets/sanctuary.png` (`PetStage`).
- Capturas: `docs/screens/pets_shop.png`, `pets_pets.png` e `pets_album.png`.

## Em aberto

- **A Caçada ainda usa a raridade nos números de luta** (`hunt.stats`): um Lendário comprado luta com o dobro de vida e ataque de um Comum. Isso rende mais moedas e XP na Caçada, então vale decidir se a luta deve ignorar a raridade (só nível e elemento).
- Cadastrar na Steam os itens 4001–4020 e conferir os preços; fazer uma compra real (cartão ou Pix) de um mascote.
- Playtest dos 2% de drop de chefe e das capturas da Caçada (`tests/hunt_balance.gd`).
- Uma página de mascotes (e dos preços) na wiki do site.
