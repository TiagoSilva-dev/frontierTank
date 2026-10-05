# Mapas com chão indestrutível: China, Japão, Egito e espaço

Gerados pelo MCP do PixelLab em 2026-10-05, 25 gerações (restavam 811 até 2026-10-24 antes de começar).

## O que mudou no motor
- Peça de terreno com `"hard": true` em `shared/balance/combat.json`: `DestructibleTerrain.stamp` marca os pixels dela em `terrain.hard` e `crater` não toca neles. O resto do mapa continua destrutível. A máscara `hard` sai só da arte, então servidor e clientes calculam igual.
- Estes mapas têm um **chão de pedra de ponta a ponta** (ninguém cai no vazio) e **plataformas no alto** que dão altura e podem ser destruídas.
- Climas novos em `ambience.gd`: `petals`, `sand`, `stars`.
- O seletor de mapas da sala passa a 5 colunas quando há mais de 16 opções.

## Os mapas (2000×1150, chão em y = 970)
| id | Tema | Desenho |
|---|---|---|
| `pagode_dragoes` | China: picos de jade ao amanhecer | as duas equipes começam em palcos altos (y 690); um palco grande flutua no centro (y 400) |
| `jardim_sakura` | Japão: torii e Monte Fuji ao pôr do sol | equipes no chão; escada de ilhas (y 730 → 520) sobe até o centro |
| `vale_piramides` | Egito: pirâmides e esfinge ao entardecer | equipes no chão; degraus de arenito formam uma pirâmide de plataformas (y 720 → 640 → 470) |
| `estacao_orbital` | Universo: nebulosa e planeta anelado | equipes no convés da estação; dois asteroides e um alto central (y 600 / 430) |

## Como foi feita a arte
| O quê | Como | Onde |
|---|---|---|
| Fundos 680×380 | `create_image_pixen`, "panoramic landscape painting ... nothing close to the viewer, no characters, no platforms" (seeds 101–104, 1 geração cada, todos de primeira) | `assets/maps/bg/<id>.png` |
| Plataformas grandes (416×112) e pequenas (256×96) | `create_image_pixen` "side view cross-section of a wide floating island platform ... solid opaque body with no holes", `no_background` | `terrain_pieces.py --main` → `assets/maps/terrain/plat_*.png`, `small_*.png` |
| Chão | faixa 768×128 em formato "ilha larga" + `tools/floor_strip.py <fonte> <nome> 1000 --crop x0:x1 --extend n` (espelha a faixa até 1000 texels e empurra a base para baixo, o excedente sai do mundo) | `assets/maps/terrain/floor_*.png` |
| Miniaturas | `tools/map_thumbs.py` | `assets/maps/thumbs/<id>.png` |

## Lições
- Pedir "ground strip"/"courtyard" deu texturas de parede, castelos ou colunatas sem borda superior; o formato **"very wide floating island ... flat top"** voltou como laje útil. Para o chão da China a melhor fonte foi um estrado de três ilhas: recortei a ilha larga à mão e espelhei o miolo.
- O chão do Egito voltou sobre um cinza chapado (120,126,115) em vez de transparente: apaguei a cor exata antes do `floor_strip.py` (a detecção de `--key` exige cinza escuro).
- "Small ... island" às vezes vem em perspectiva isométrica (cubo) ou como parede de pedra; "strictly side view" ajudou, e duas sementes por mapa bastaram.
- Plataforma com árvore ou pavilhão por cima vira parede sólida na colisão: peça "flat top, nothing tall on top".
- O fundo do Egito veio com uma torre próxima na borda direita; com o `dim` e a câmera quase não aparece.
- Peças só dos fundos de 680×380 funcionam em 2× igual aos anteriores.
