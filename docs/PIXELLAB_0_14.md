# Arte PixelLab — 0.14 (especiais, habilidades dos monstros e Fiorde dos Vikings)

Gerada pelo MCP do PixelLab em 2026-09-25/26. IDs de cada job e o destino de cada arquivo em `assets/v14/pixellab_manifest.json`. Custo: **68 gerações** (restam 164 até 2026-10-24).

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Projétil próprio de cada um dos 12 especiais (tijolo em chamas douradas, cometa, cristal-prisma, shuriken no vórtice, maçã dourada, cápsula de cura, TV elétrica, bola de raios, desentupidor gigante, cabeça de touro espectral, bumerangue de coração, lança de jade) | `create_image_pixen` 64×64; os que voam de bico (Braseiro, Sugador, Lança de Jade) apontam para a direita | `assets/effects/pow/<arma>/projectile.png` |
| Fiorde dos Vikings: 3 fundos (praia com drakkars e aurora, aldeia do hidromel à noite, trono do Jarl no penhasco em tempestade) | `create_image_pixen` 680×380 | `assets/maps/bg/praia_drakkar.png`, `aldeia_hidromel.png`, `trono_jarl.png` |
| Chão pintado: costa nevada com paliçada, aldeia com cerca e penhasco com runas | `create_image_pixen` 420×112 + `tools/terrain_pieces.py --main` | `assets/maps/terrain/viking_praia_a.png`, `viking_aldeia_a.png`, `viking_runas_a.png` |
| Saqueador Viking e Corvo Rúnico (lacaios, 64×64), Berserker Urso (guardião) e Jarl Barba-de-Ferro (chefe, 128×128) | `create_image_pro_flash` (lacaios com a Harpia como referência de estilo) | `assets/enemies/<id>/sprite.png` |
| Repouso (4 quadros) e ataque (8 quadros) dos 4 | `animate_image` a partir do sprite | `assets/enemies/<id>/idle/`, `attack/` |
| Ícone do mapa da instância (pergaminho com selo de elmo viking) | `create_image_pixen` 64×64 | `assets/items/maps/fiorde_viking.png` |
| Ícones dos tipos de habilidade (garras, garra de ave, punho no chão, meteoro na mira, sopro, escudo, trompa de guerra, cruz de cura) | `create_image_pixen` 48×48 | `assets/effects/abilities/icons/<tipo>.png` |
| O que cai do céu nas magias: lança de sol, estalactite, pena-lâmina, machado, corvo em mergulho, rocha de obsidiana, máscara em chamas | `create_image_pixen` 48×48, apontando para baixo | `assets/effects/abilities/drops/<fx>.png` |

Reaproveitado: o cometa do Braseiro, girado para baixo, é o meteoro (`drops/meteor.png`). As animações de impacto de cada especial são as da 0.9 (`assets/effects/pow/<arma>/frame_*.png`), que agora tocam onde o especial cai.

## Lições
- Pixen resolve projéteis e ícones de efeito por 1 geração; pedir "lying horizontally ... pointing to the right" deu a arte certa para girar na direção do voo.
- Chão: "one single solid opaque piece with no holes" ainda pode vir com buracos e pontilhado; "side view cross-section of a wide floating island for a 2D artillery game" deu uma faixa lateral limpa (com uma sombra preta embaixo, que foi apagada antes do `terrain_pieces.py`). Um pedido veio em perspectiva de cima e foi descartado.
- O primeiro pedido do Berserker falhou no servidor (502) e não foi cobrado; repetir com outra seed resolveu.
- `animate_image` pedindo "toward the right" para o Saqueador (a arte olha para a direita, `"faces": "right"`) manteve a direção.
