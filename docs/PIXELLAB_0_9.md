# Arte PixelLab — 0.8 e 0.9 (POW e instâncias)

Gerada pelo MCP do PixelLab em 2026-09-25. IDs de cada job e o destino de cada arquivo em `assets/v09/pixellab_manifest.json`. Custo: **130 gerações** (restam 249 até 2026-10-24).

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| 9 inimigos novos: Escaravelho Solar, Máscara Flamejante, Lobo da Nevasca, Harpia das Ruínas (lacaios, 64×64); Sentinela de Obsidiana, Golem de Gelo, Cavaleiro Celeste (guardiões, 128×128); Rainha da Nevasca e Grifo da Tempestade (chefes, 128×128) | `create_image_pro_flash`, vista lateral virada para a esquerda | `assets/enemies/<id>/sprite.png` |
| Repouso (4 quadros) e ataque (8 quadros) dos 9 inimigos e do Guardião do Templo (arte antiga `temple_guard.png`) | `animate_image` a partir do sprite (o quadro 0 é o próprio sprite) | `assets/enemies/<id>/idle/`, `attack/` |
| Arte animada do POW de cada uma das 12 armas | `create_image_pixen` 128×128 + `animate_image` 8 quadros | `assets/effects/pow/<arma>/` |
| 7 fundos de mapa: Portões de Brasa, Salão das Máscaras, Trilha Congelada, Caverna de Cristal, Pico da Nevasca, Ruínas Flutuantes, Santuário dos Ventos | `create_image_pixen` 680×380 (2×) | `assets/maps/bg/` |
| 7 peças de chão pintado | `create_image_pixen` + `tools/terrain_pieces.py --main` | `assets/maps/terrain/` |
| Ícones dos mapas das 4 instâncias (pergaminhos com selo de sol, máscara, floco de neve e asa) | `create_image_pixen` 64×64 | `assets/items/maps/<instância>.png` |

Reaproveitados: Rei Hélio (`assets/pve/`), Rei das Máscaras (`assets/expansion/animations/mask_king_*`), Guardião do Templo (`assets/expansion/enemies/temple_guard.png`), o Cristal de Proteção como totem da Caverna de Cristal e os mapas antigos nas fases (Pátio do Templo, Câmara do Guardião, Templo do Sol, Trono das Máscaras, Ilha Celeste). A carta de recompensa de mapa (`reward_card_map.png`) é a carta épica recolorida para esmeralda por código.

## Lições
- Pixen resolve bem efeitos radiais (POW) e fundos por 1 geração; para criaturas com identidade o Pro Flash foi melhor.
- `animate_image` a 128×128 com 8 quadros custa 2 gerações; 4 quadros custa 1. Pedir "toward the left" no ataque manteve a direção; a Rainha vira o cajado ao contrário no golpe, mas continua atacando para a esquerda.
- Arte que só existe no disco pode ser animada com um `data:` URL (o PNG do guardião tinha 35 cores e ficou com 2,5 KB); o quadro 0 do job vira uma URL para os pedidos seguintes.
- Nos POW, os últimos quadros às vezes enchem o fundo (Bumerangue do Amor): esses quadros foram descartados.
- Peças de chão: pedir "very wide ... spanning the full width of the image", senão a ilha ocupa só o meio do quadro.
