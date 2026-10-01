# Arte — Founder Pack (Paladino do Sol)

Gerada em 2026-09-30. Custo no PixelLab: **102 gerações** (restam 2.228 até 2026-10-24). O resto da arte é desenhado em código (`tools/founder_art.py`) e os sons saem de `tools/make_sfx.py`.

## PixelLab
| O quê | Como | Onde |
|---|---|---|
| Paladino do Sol, em pé (4 direções) | `create_character` padrão, chibi, `side`, 96 px (tela 136). Duas variações (A: capa azul, B: capa branca forrada de azul, cristal grande, coroa de raios); **B** ficou. A sobrou como descarte e foi apagada. Id `cbd14985-bb6e-4ac9-82e7-b5a683f558ca` | `assets/characters/roupa_paladino_sol/` |
| Paladino deitado | `create_character_state` "lying flat on the belly… prone shooting position", id `820934f7-6610-4ba7-baa3-7bcade8dc3d1` | `…/prone/` |
| 7 clipes deitado (idle 6, crawl 8, shoot 6, hit 4, victory 6, defeat 6, pow 4 quadros) | `animate_character` v3, direção east (o leste já veio virado para a direita, o import não espelha) | `…/prone/<clipe>/` |
| Solaris +0 | `create_object_pro_flash` 96×96, 3 sementes, ficou a de seed 5 (id `95a4f21a-23eb-4553-ab6f-1fb8b7c9438d`); 3 candidatas do `create_image_pixen` descartadas | `assets/weapons/solaris/tier0.png` |
| Solaris +6, +10, +12 | `edit_image_pixen` sobre a +0, duas sementes cada, ficaram `6bdd31db…` (+6), `691e8ba0…` (+10) e `3fed389e…` (+12) | `tier1/2/3.png` |
| Asas da Aurora | `create_image_pixen` 128×128, uma asa, 3 sementes (ficou a seed 2, raiz em `[118, 100]`); a outra asa é espelhada, `front.png` e `icon.png` montados em código | `assets/cosmetics/asas_aurora/` |
| Pet Solis | `create_character_pro_flash` 64×64, id `c400a561-50ff-4f64-91d4-60d913daffc9`; clipes `pet_fly` (8), `pet_happy` (6), `pet_scared` (4), `pet_victory` (8) | `assets/founder/pet/<clipe>/` |

Importação: `python tools/import_pixellab_skin.py grupo.zip Idle Prone roupa_paladino_sol` (agora aceita `hit`, `victory`, `defeat` e `pow`) e `python tools/character_anchors.py roupa_paladino_sol`. O capacete dourado é lido como cabelo pela análise de cores; a skin está em `NO_DYE` para a tintura de cabelo não pintar o elmo.

## Em código (`python tools/founder_art.py [halo|mandala|sigil|aura|foot|proj|lance|feather|boom|badge|frame|emote|all]`)
Tudo é desenhado pixel a pixel numa paleta fechada (ouro, branco, azul real, sol e um contorno roxo escuro), sem antisserrilhado, com sombreamento facetado (metade clara e espinha brilhante) e rotação em passos exatos (a mandala de 8 lados só precisa de 45° de giro).

| Peça | Arquivo | Notas |
|---|---|---|
| Halo Solar | `halo/halo_00..07`, `halo_power_00..07`, `glow.png` | 128×128, 16 raios, anel azul com 8 gemas e 8 runas |
| Mandala (POW) | `mandala/mandala_00..11` | 192×192, 24 raios, 16 pétalas, gemas contra-rotativas, núcleo solar |
| Estrela do Amanhecer | `projectile/frame_00..07` | 32×32, gira |
| Lança Celestial | `lance/frame_00..03` | 128×40, penas na cauda, cristal azul na ponta |
| Explosão | `explosion/frame_00..04` | 192×140; **metade da largura é o raio real** |
| Símbolo solar no chão | `sigil/sun_sigil.png` | 160×64 já em perspectiva |
| Aura do Primeiro Sol | `aura/aura_00..07`, `aura_thin.png` | 96×40 em perspectiva |
| Footstep | `foot/footstep_00..05` | 32×16 |
| Pena celestial | `feather.png` | 16×40 |
| Badge | `badge/badge_16/24/32/64.png` | sol de 8 raios, ouro sobre azul real |
| Moldura | `frame/founder_frame.png` | 128×104: borda de 88×88 no meio, duas asas, sol em cima, cristal embaixo |
| Emote | `emote/frame_00..05` | a cabeça do próprio Paladino (recorte da vista de frente) com sorriso de canto, sobrancelha erguida e uma estrela que pisca |

## Descartes
- Paladino A (capa azul, elmo mais liso, cabelo dourado aparecendo).
- Solaris em formato de rolo/tubo (seeds 11 e 22 do pixen) e de canhão com rodas (seed 33): bonitas, mas não liam como relíquia solar.
- Emote feito pelo pixen (cabeça de bronze com pluma vermelha): saiu fora da paleta do Paladino; trocado pela cabeça da própria skin.
- A primeira Moldura (asas de 4 px) e o primeiro projétil sem penas.

## Pendências de arte
- O brilho das asas de energia da Solaris +12 vem do ícone; as partículas orbitando a arma em batalha não são camadas separadas (o ícone já traz as estrelas).
- Clipe `pow` do Paladino é discreto (a mudança vem do halo, das asas e da mandala); dá para refazer com mais gerações se quiser uma pose mais dramática.
- Nenhum som foi ouvido (só medido, como nos anteriores): `fire_solaris`, `impact_solaris`, `pow_solaris_*`, `founder_reveal`, `founder_emote`.
