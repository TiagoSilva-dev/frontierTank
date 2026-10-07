# PixelLab: cristais de energia e munição especial (0.33)

**27 gerações** (743 → 716 até 24/10/2026), tudo com `create_image_pixen` (1 geração por imagem, `no_background`, contorno `single color black outline` nas peças e `lineless` nos estouros de luz) e `animate_image` (1 a 3 gerações por clipe). Os quadros ficam em `assets/effects/ammo/<pasta>/frame_NN.png` e os ícones em `assets/ui/icons/`. Quem os carrega é `AmmoArt` (`client/components/ammo_art.gd`); o código só soma a luz, as faíscas e a poeira por cima.

**As URLs de download dos jobs expiram: a arte está no repositório.** Para refazer uma peça, gere de novo com o prompt e a semente da tabela e baixe com `https://api.pixellab.ai/mcp/images/<job>/download` (quadros de animação: `?index=N`, de 0 a N).

## Imagens-base

| Peça | Prompt (resumo) | Imagem | Semente |
|---|---|---|---|
| Cristal (duas variantes, vale a B) | "glowing cyan energy crystal, one tall faceted diamond-shaped gem shard floating, bright white-cyan core ... compact and centered with a small empty margin", `view: side` | 64×64 | 11 (A), 222 (B, `highly detailed`) |
| Estouro da coleta | "radial burst of cyan energy, shattering crystal shards flying outward, bright white flash in the center ..., symmetric, centered" | 128×128 | 31 |
| Clarão do laser | "magenta pink laser energy flare, four-pointed star lens flare with a blinding white center and thin radial rays, hot pink glow, symmetric, centered" | 96×96 | 41 |
| Míssil perfurante (em voo) | "armor-piercing missile pointing right, steel drill bit spiral nose cone, orange body, small red fins at the tail, side view of the missile alone", `direction: east` | 64×32 | 51 |
| Bomba-relógio | "round black time bomb with a white clock dial on the front and two red bands, short fuse with a burning orange spark on top ..." | 64×64 | 61 |
| Explosão da bomba | "big crimson and orange explosion fireball, blinding white-yellow core, thick expanding shockwave ring around it, flying fire sparks, symmetric, centered" | 128×128 | 71 |
| Ícone Perfurante | "one steel drill bit missile with orange body pointing diagonally up-right ... the missile alone" | 64×64 | 82 (a 81, com entulho, foi descartada) |
| Ícone Laser | "futuristic laser cannon pointing up-right firing a short bright pink laser beam ... wide empty transparent margin on every side" | 64×64 | 102 (a 101 saiu com o raio cortado na borda) |
| Ícone Bomba | a própria bomba (a imagem gerada para o ícone, semente 91, veio com a bomba dentro de um escudo e foi descartada) | 64×64 | 61 |
| Gema do medidor | "small cyan energy crystal gem icon, front-facing octagonal faceted gem with a bright glowing cyan-white core and dark blue outer facets ..." | 24×24 | 401 (402 também serviria) |
| Ícone `crystal` | o mesmo prompt em 32×32 | 32×32 | 302 |

## Animações (`animate_image`)

| Pasta | Origem | Ação pedida | Quadros usados |
|---|---|---|---|
| `crystal/` | cristal B | "the crystal slowly turns around its vertical axis like a rotating gem, light glints sliding over the facets, its inner glow pulsing" (semente 6, 8 quadros, 1 geração) | 9, em vai-e-volta (`ping_pong`) para fechar a volta |
| `pickup/` | estouro | "the energy burst expands outward fast, shards and sparkles fly away from the center and dissolve ..." (semente 7, 8 quadros, 2 gerações) | os 7 primeiros (os outros ficam quase vazios) |
| `flare/` | clarão do laser | "the star flare flickers: its rays grow long and bright then shrink ..." (semente 8, 8 quadros, 2 gerações) | 9; o piscar faz parte do brilho |
| `blast/` | explosão da bomba | "the explosion expands: the fireball grows huge, the shockwave ring races outward ..., then it fades into dark smoke and embers" (semente 9, 12 quadros, 3 gerações) | 10; os 3 últimos são espinhos pretos e não entram |
| `bomb/` | bomba | "the fuse spark flickers and throws tiny sparks, the red bands glow brighter and dimmer, the bomb trembles slightly" (semente 10, 4 quadros, 1 geração) | 5 |
| `drill/` | míssil | "the steel drill bit spins fast ..., a small jet flame flickers at the tail ..., the missile keeps pointing right" (semente 12, 4 quadros, 1 geração) | 5 |

A animação do cristal A ("pulsing") ficou só como pulsação clara e escura; a do B, que gira de verdade e mostra a faceta de cima, foi a escolhida.

## Como cada coisa aparece no jogo

| Efeito | Onde | O que o código soma |
|---|---|---|
| Cristal no mapa | `CrystalField` | halo suave, cone de luz até o chão e poça de luz no terreno (a posição fica legível), poeira de energia subindo, estrelas orbitando; ao surgir (início ou volta) cresce com sobra, com anel e clarão |
| Coleta | `AmmoFx` "crystal" + `CrystalMotes` | estouro, dois anéis, cruz de luz, estilhaços; oito partículas de luz voam em curvas até a gema nova do medidor do HUD, que incha e solta anéis |
| Disparo | `BattleScreen.dress_ammo_shot` | o projétil troca de sprite (broca girando com chama, bomba rolando com fumaça) e o cano ganha clarão e faíscas |
| Laser em voo | `TankProjectile.draw_laser_beam` | feixe em cinco camadas que afina até a cauda e cabeça com o clarão animado; no impacto, pulsos de energia correm pelo feixe, clarão, anel e `ShockwaveFx` |
| Túnel | `AmmoFx` "tunnel" | clarão a cada mordida, faíscas, pedaços do chão nas cores do terreno, poeira e brilho de brasa na parede |
| Bomba plantada | `CrystalField` | achata ao cair, anéis de poeira, placa com os turnos e o raio da explosão tracejado no chão; na última rodada treme, pisca vermelho e o raio se enche |
| Explosão da bomba | `AmmoFx` "bomb_blast" + `ShockwaveFx` | bola de fogo animada na escala do raio real, clarão, dois anéis, faíscas, brasas, fumaça, tremor, zoom e refração da tela (`shockwave.gdshader`); os quadros finais se dissolvem na fumaça; a explosão comum fica só com os pedaços do chão |

## Lições

- O PixelLab faz bem **estouros de luz e peças pequenas e isoladas**; o que falhou foi pedir ícone com "bomba + relógio" juntos (a bomba veio dentro de um escudo) e raios que encostam na borda da imagem (corte).
- Em efeitos aditivos, os pixels pretos que o modelo desenha somem sozinhos; é por isso que o estouro do cristal usa o modo aditivo e a explosão da bomba, com fogo escuro, usa o normal.
- Para ver o efeito em movimento sem GPU: rodar a cena a `Engine.time_scale = 0.2` e fotografar quadro a quadro; para o projétil em voo, parar a simulação (`set_physics_process(false)`) e andar com `game.step(1.0 / 60)`.
