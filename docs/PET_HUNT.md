# Caçada dos Mascotes (0.20)

Modo automático da Casa dos Mascotes, no estilo de um jogo idle de monstros: o time luta sozinho, o jogador coleta. **Desde a 0.30 é o único lugar onde o mascote sobe de nível** (não há mais alimentar nem estrelas) e não solta ovos; ver `docs/PETS.md`. Código em `client/systems/pet_hunt.gd` (regras, simulação, liquidação), `client/ui/hunt_tab.gd` e `hunt_arena.gd` (tela); números em `shared/balance/pets.json`, bloco `hunt`.

## Como se joga

1. Aba **Caçada**: escolha a **zona** (Ruínas do Sol, Portões de Brasa, Trilha Gelada, Ilhas Flutuantes, Praia dos Drakkar: uma por elemento), o **nível de caça** (1–8) e o **time** (1 a 5 mascotes), e toque em **INICIAR CAÇADA**.
2. O time encara um grupo de selvagens do elemento da zona a cada **12 s**, mesmo com o jogo fechado.
3. **COLETAR** recebe moedas, XP (cada mascote do time) e os mascotes capturados (só Comum e Raro). Mudar zona, nível ou time (**APLICAR E CAÇAR**) recolhe antes o que já rendeu.
4. O tempo só acumula até o limite: **2 h** (grátis) ou **8 h** com o **Passe do Caçador**. O que passa disso se perde; a sobra de um encontro em andamento é guardada. **O Passe rende mais moedas e XP, nunca mais capturas**: só os primeiros 600 encontros (2 h) de cada coleta rolam captura (`PetHunt.capture_slots`).
5. Cada nível abre depois de **60 vitórias** no nível abaixo, por zona.

## Regras

- **Luta** (por turnos, automática): a velocidade define a ordem; cada ação ataca um inimigo vivo sorteado; a cada 3ª ação o mascote usa a habilidade do elemento; crítico 8% (Máscara 33%) ×1,6; no máximo 24 rodadas (empate conta como derrota). O time se cura entre encontros.
- **Roda de elementos**: Sol > Gelo > Céu > Máscara > Runa > Sol; vantagem ×1,5, desvantagem ×0,7.
- **Habilidades**: Sol, Rajada Solar (golpe ×2); Máscara, Dupla Trapaça (dois golpes ×0,9); Gelo, Muralha Glacial (cura 12% da vida de todos); Céu, Tempestade (todos os inimigos ×0,8); Runa, Grito de Guerra (+25% de ataque ao time por 3 rodadas). Crescem 12% por raridade.
- **Atributos de luta**: raridade × nível (`hunt.stats`; as estrelas saíram na 0.30): vida, ataque, defesa, velocidade; Sol +12% ataque, Máscara +12% velocidade, Gelo +18% vida, Céu +15% velocidade, Runa +15% defesa. Os selvagens usam a mesma fórmula, no nível da zona (2 + 4 por nível de caça) e +26% de vida, ataque e defesa por nível de caça.
- **Encontros**: grupo de 1 a 3 selvagens (60/30/10); raridade 72/22/6 (Comum/Raro/Épico, o nível de caça empurra para raros e épicos). O **Lendário** da zona (vida ×2, ataque ×1,15, nível +2) aparece sozinho com 0,03% por encontro, **sem garantia nem contador**; vencê-lo rende só moedas e XP (raridade ×8 e ×12), nunca um mascote.
- **Recompensas por vitória**: XP por selvagem `(1,2 + 0,14 × nível) × [1; 1,5; 2,5; 8]`, para cada mascote do time; moedas `0,15 × nível × [1; 1,6; 3; 12]`; **captura** por selvagem: Comum 0,12% e Raro 0,03% (+8% por nível de caça). **Épico, Lendário e o chefe nunca são capturados.** Capturas entram no nível 1; com a Casa cheia (120) viram moedas. Não há ovos.
- **Determinismo**: o encontro `n` depende só da semente da caçada (`hunt.seed`) e de `n` então a tela mostra o encontro em andamento e a coleta entrega exatamente o mesmo. Estado no perfil: `hunt {active, zone, tier, team, since, n, seed, wins, report}` (o antigo `legend` é descartado ao ler).
- **Servidor**: `hunt_set`, `hunt_collect` e `hunt_stop` são operações de `PlayerProfile.apply_op`; o servidor usa o relógio dele (o espelho do cliente corrige a diferença pelo campo `clock`). Relógio para trás não rende nada.

## Campo (0.21): a Caçada vista de cima

Pedido: algo entre Tibia e Pokémon, com o mascote andando num campo e atacando com animações do elemento (o Charmander cospe fogo). As cinco zonas usam o campo (as três últimas vieram na 0.22, ver o fim deste arquivo); a arena lateral (`HuntArena`) fica só como reserva. Uma zona usa o campo quando existe `assets/field/<zona>/tiles.json` (`HuntField.available`).

- `client/ui/hunt_field.gd` (`HuntField`, herda de `HuntArena` e tem a mesma API) reproduz o log da simulação, sem decidir nada. A economia, o servidor e o offline não mudam.
- **Linha do tempo de 12 s:** 4,2 s de aproximação (o grupo selvagem entra pela borda e o time vai ao encontro, com a câmera acompanhando), a luta e 2,3 s de resultado.
- **Treinador:** anda de verdade. Entra pela esquerda no primeiro encontro, fica atrás do time durante a luta e, quando o resultado aparece, caminha até o meio do campo para "recolher o butim"; no encontro seguinte volta para trás do time. Usa a caminhada de 4 direções.
- **Selvagens vagando:** 7 criaturas da zona (sorteadas pela zona, mais comuns que raras) passeiam pelo campo entre os encontros, com nome e nível discretos e sem barra. Quando uma luta começa elas saem da área de combate (`_fight_area`) e não entram nela até o resultado.
- **Golpes por espécie:** `bolt` (flecha), `breath` (a baforada estica por toda a linha até o alvo), `orb` (orbe) e `slash` (garras), por espécie em `STYLES`. O dano só aparece quando o golpe chega. Cada elemento tem a sua versão recolorida dos três efeitos (`assets/field/fx/<estilo>_<elemento>.png`, geradas por `python tools/field_assets.py fx`): fogo laranja, gelo ciano, máscara violeta, céu amarelo, runa verde.
- **Sons:** cada golpe lançado emite `attack_played(estilo, elemento)` e a aba toca `hunt_claw` (garras), `hunt_ice` (gelo), `hunt_fire` (fogo do Sol) ou `hunt_zap` (os demais). Eles saem de `python tools/make_pet_audio.py field`.
- **Placas:** o time mostra só a barra e o nível (cinco placas com nome se empilhavam); os selvagens do encontro mostram nome, nível e barra.
- **Cenário:** `client/ui/field_map.gd` monta o chão uma vez por zona a partir de dois tilesets Wang (campo ↔ pedra/gelo, campo ↔ lago), com a decoração sorteada pela zona; o centro fica livre de árvores. O `tiles.json` aceita `"shade"` (cor que multiplica o chão): a neve usa um azul-acinzentado para os mascotes brancos não sumirem nela.
- **Sprites de cima:** `client/ui/field_sprites.gd`, uma folha por unidade em `assets/field/units/` (8 direções parado + caminhada em 4 direções). Quem não tem folha usa a arte do álbum, espelhada.
- **Arte:** `tools/field_assets.py` baixa os pacotes do PixelLab e monta folhas, efeitos e `tiles.json` (`units [id]`, `tiles [zona]`, `fx`). Sol: 4 espécies, o treinador, 2 tilesets, 6 objetos e 3 efeitos. Gelo: 4 espécies, 2 tilesets e 6 objetos (≈ 55 gerações).
- **Para estender a outra zona:** gerar o tileset (chão ↔ pedra e chão ↔ água) e a decoração do elemento, os personagens das 4 espécies com a caminhada de 4 direções; acrescentar a zona em `ZONES` e as espécies em `UNITS` do `tools/field_assets.py` (o treinador e os efeitos já servem).
- Teste: `tests/hunt_tests.gd` (`field_tests`) e capturas com `tests/hunt_visual_check.gd -- field|fieldboss [zona]` (`docs/screens/hunt_field_*.png`, `hunt_field_gelo_*.png`).

## Passe do Caçador

Item premium `passe_cacador` (slot "selo", sem atributos, vinculado, não vende), produto Steam `passe_cacador` (`steam_item_id` 3000, US$ 4,99, preços por moeda em `store.json`). Chega pelo Correio como os outros itens da loja Steam; quem o tem acumula 8 h. A tela mostra "VOCÊ TEM" e o botão de compra aparece na Caçada e na aba Premium da loja. Cupons de teste: `CACADA` (só o passe) e `TESTARTUDO`.
**Falta**: cadastrar o item 3000 na Steam e conferir os preços.

## Balanceamento (pontos de partida)

`tests/hunt_balance.gd` imprime vitórias e renda por hora por time e nível. Um time de 3 Raros nível 10 vence ~80% no nível 3 e ~0% a partir do 6; 5 Épicos nível 14 com 1 estrela vencem quase tudo até o 5 e ~50% no 8; 5 Lendários nível 30 com 5 estrelas vencem tudo. Renda: nível 1 ≈ 625 XP, 125 moedas e 1,1 ovo por hora; nível 8 (time forte) ≈ 3.000 XP, 2.700 moedas e 1,6 ovo por hora. Em 8 h o time forte captura cerca de 1 Lendário e de 5 a 8 mascotes menores. **Precisa de playtest**; os números estão todos no JSON.

## Testes e capturas

`tests/hunt_tests.gd`, `net_e2e_tests.gd` (a liquidação no servidor), `tests/hunt_balance.gd`, `tests/hunt_visual_check.gd -- fight|boss|picker|report|capture|idle` (imagens em `docs/screens/hunt_*.png`) e, no jogo, `--screen=pet --tab=Caçada --demo=1 --hunt=<segundos já caçados> --zone= --tier= --boss=1`.

## Em aberto

- Cadastrar o produto 3000 na Steam; ícone do Passe só em 64×64 (serve para a loja e a tela).
- Na batalha de tanque o mascote ativo tem uma habilidade por partida (0.22, ver `docs/PETS.md`); a Caçada em si continua automática.
- Mascotes não vão ao Leilão. Notificação fora do jogo (um e-mail ou Steam) quando a caçada enche não existe.
- Sons não foram ouvidos por uma pessoa; a taxa de captura precisa de playtest.

## Campo visto de cima nas cinco zonas (0.22)

Sol, Gelo, Brasa (Portões de Brasa), Céu (Ilhas Flutuantes) e Drakkar (Praia dos Drakkar) usam `HuntField`; uma zona entra assim que existe `assets/field/<zona>/tiles.json`. Brasa tem cinzas vulcânicas, lagos de lava e lajes de obsidiana; Céu, chão de nuvem, lagos de céu e mármore flutuante; Drakkar, costa rochosa, mar frio e lajes com runas. Os 12 mascotes novos andam nas quatro direções (8 quadros). Tudo é reconstruído por `tools/field_assets.py units|decor|tiles <id|zona>` (ids de personagens, tilesets e objetos estão no arquivo). Capturas: `tests/hunt_visual_check.gd -- field mascara|ceu|viking`. Ainda não foi jogado por ninguém.

**Acabamento das três zonas novas (04/10/2026).** A primeira versão tinha lajes que pareciam retângulos chapados, o chão de Brasa quase preto, tufos de Drakkar que pareciam cristais azuis e uma coluna de Céu branca sobre chão claro. O que mudou, tudo reproduzível pelo `tools/field_assets.py`:
- **Plataformas em ruínas** (`"ruined": true` no `tiles.json`, só Brasa, Céu e Drakkar; Sol e Gelo continuam com as lajes simples): `FieldMap._break_up` dá a cada laje uma ala em cima ou embaixo, cantos chanfrados ou mordidos e, nas grandes, um buraco; os tiles de canto do tileset Wang desenham as bordas novas. `_wear` clareia ou escurece cada laje e risca rachaduras, para o tile repetido não virar quadriculado. Itens com `"on_stone": true` (colunas e entulho) ficam só sobre as lajes, um por laje, e contam como cenário que respeita o centro livre.
- **Recolor das folhas** (`RECOLOR`, comando `field_assets.py recolor [zona]`, parte de `tools/field_src/` e é idempotente): em Brasa o chão violeta quase preto virou terra queimada e as lajes verde-acinzentadas viraram pedra clara de cinza; a folha da lava recebe a mesma regra, senão cada lago ganha um halo preto. O `shade` de Brasa saiu.
- **Cenário derivado** (`DERIVED`): o tufo de Drakkar é o capim do Sol em verde-mar (grátis, no lugar do cristal); a coluna de Céu foi gerada de novo (arenito claro com ouro e hera, 1 geração).
- `field_tests` ganhou 10 checagens (lajes, cenário sobre elas, centro livre, Sol e Gelo inalterados): `hunt_tests` com 162.

