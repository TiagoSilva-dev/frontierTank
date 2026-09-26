# Arte PixelLab — 0.15 (Mochila nova)

Gerada pelo MCP do PixelLab em 2026-09-26. IDs de cada job em `assets/v15/pixellab_manifest.json`. Custo: **13 gerações** (restam 151 até 2026-10-24).

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Pedestal redondo de pedra com borda dourada e runas azuis, onde o personagem fica na Mochila | `create_image_pixen` 200×88, fundo transparente, "just the object alone" | `assets/ui/profile/pedestal.png` |
| Ícones dos atributos: espada (Ataque), escudo (Defesa), bota alada (Agilidade), trevo (Sorte), explosão (Dano), armadura (Proteção), coração (Vida) e raio (Força física) | `create_image_pixen` 32×32, "compact and centered with a small empty margin" | `assets/ui/stats/<atributo>.png` |

O fundo do palco (azul-noite, holofote, estrelas piscando e o brilho no chão) é desenhado no jogo (`hero_stage.gd`), e o *cut-in* do POW também (`pow_banner.gd`): usa o visual do próprio jogador, desenhado em 1× e ampliado 3×, e a arte do especial da 0.14.

## Descartado
- Dois cenários inteiros (holofote com pedestal; salão com cortinas): o pedestal ficava no meio da imagem e não sobrava altura para o personagem em 2×; o do salão tinha um hexagrama no pedestal que brigava com a aura da arma. Gerar o pedestal separado, sem fundo, deixou posicionar tudo.
- Um pedestal octogonal (o redondo lê melhor) e uma couraça que veio dentro de um quadrado escuro (ficou a armadura inteira).

## Lições
- Para peças de interface que precisam de posição exata, gerar o objeto sozinho com fundo transparente e desenhar o fundo no jogo: o pixen não respeita composição ("pedestal at the bottom") em cenas.
- Ícones 32×32 do pixen saem bons para interface; conferir se não vieram com moldura.
