# Arte PixelLab — HUD da batalha

Gerada pelo MCP do PixelLab em 2026-09-27. IDs de cada job em `assets/ui/battle/pixellab_manifest.json`. Custo: **15 gerações** (restam 82 até 2026-10-24).

O resto do HUD novo é desenhado no jogo (`client/ui/hud_paint.gd` e as telas que o usam): molduras de bronze, poços de vidro, barras, relógio, bússola de ângulo, minimapa, orbe do POW e as letras em relevo do *cut-in*. Só o que precisava ser pintado veio do PixelLab.

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Emblema da vitória: escudo dourado com estrela de rubi, asas de anjo, coroa, louros e fita vermelha | `create_image_pixen` 192×144, fundo transparente, contorno preto; 2 sementes | `assets/ui/battle/victory_emblem.png` |
| Emblema da derrota: escudo de aço rachado com caveira, espada partida e asas de morcego rasgadas | `create_image_pixen` 192×144, fundo transparente; 2 sementes | `assets/ui/battle/defeat_emblem.png` |
| Habilidade 1 (+2): duas flechas de fogo | `create_image_pixen` 64×64, "compact and centered with a small empty margin" | `assets/ui/skills/item_1.png` |
| Habilidade 2 (x3): três flechas de gelo em leque | idem (3 tentativas) | `assets/ui/skills/item_2.png` |
| Habilidade 3 (+1): uma flecha de fogo | idem | `assets/ui/skills/item_3.png` |
| Habilidades 4–8 (+50% … +10%): espada em chamas | idem; uma arte só, com o matiz deslocado por nível (−0,075, −0,04, 0, +0,035, +0,07 — do magenta ao amarelo) nos pixels com saturação ≥ 0,25 | `assets/ui/skills/item_4.png` … `item_8.png` |
| Habilidade 9 (POW Máx): orbe dourado com raios roxos | idem | `assets/ui/skills/item_9.png` |

Os ícones antigos das habilidades tinham o texto desenhado na arte ("POW 50%", "+2"). Os novos não têm texto: o botão (`SkillSlot`) escreve +2, x3, +1, 50%…10% e MAX no canto, e o ícone é cortado na parte usada (`SkillSlot.trim`) para encher o botão. Os mesmos ícones aparecem sobre a cabeça ao consumir a habilidade (`SkillFx`).

Os emblemas antigos (`assets/expansion/ui/victory_emblem.png` e `defeat_emblem.png`, 128×64, ampliados 4×) não são mais usados.

## Descartado
- Um emblema de vitória com o escudo marrom por dentro e um de derrota sem a espada partida.
- Para o x3: três canhões num anel de gelo e uma "máquina" com espinhos — "cannonballs" virou canhões. "Three blue ice arrows ... in a fan" acertou de primeira.
- Uma flecha +1 apontando para baixo, uma espada borrada e um orbe cujos raios encostavam na borda.

## Lições
- Para ícones que se diferenciam só pelo número (4–8), uma arte e variações de matiz por código custam 1 geração em vez de 5 e ficam coerentes entre si.
- Emblemas 192×144 do pixen com "symmetric, centered, no text" saem limpos e sem fundo; desenhados em 2× ficam nítidos.
