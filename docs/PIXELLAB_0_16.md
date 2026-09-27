# Arte PixelLab — 0.16 (efeitos de estado e elites)

Gerada pelo MCP do PixelLab em 2026-09-27. IDs de cada job em `assets/ui/status/pixellab_manifest.json`. Custo: **16 gerações** (restam 66 até 2026-10-24).

Os efeitos em cima dos lutadores (chamas, bolhas de veneno, cristal de gelo, gotas de suor, anel do selo, raízes, mira da marca, brilho do ofuscamento), a aura dos elites, o círculo da maldição e as correntes do selo no HUD são desenhados no jogo, na grade de 2 px (`fighter.gd` → `draw_overlay` e `draw_elite_aura`, `monster_fx.gd`, `battle_hud.gd`). Só os ícones e o projétil de veneno vieram do PixelLab.

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Ícones dos 8 efeitos: chama (Queimação), frasco verde com caveira (Envenenamento), floco de neve (Congelamento), raio com gotas de suor (Exaustão), cadeado roxo com runas (Selo), nó de raízes (Raízes), mira vermelha (Marca da Caça), olho ofuscado numa estrela (Ofuscamento) | `create_image_pixen` 32×32, fundo transparente, contorno preto, "bold simple shape, compact and centered with a small empty margin"; 1 tentativa cada | `assets/ui/status/<id>.png` |
| Exaustão | o raio veio amarelo e se confundia com o ícone da energia: os pixels amarelos foram levados para um cinza-violeta "sem força" por código (matiz 0,7, saturação ×0,22) | `assets/ui/status/exaustao.png` |
| Maldição (habilidade `hex`) | `create_image_pixen` 48×48: círculo mágico roxo com um sigilo | `assets/effects/abilities/icons/hex.png` |
| Afixos de elite sem ícone de efeito: gota de sangue com presas (Vampira), bomba com pavio aceso (Explosiva), bota com linhas de velocidade (Veloz) | `create_image_pixen` 32×32; a Vampira na 2ª tentativa | `assets/ui/status/vampira.png`, `explosiva.png`, `veloz.png` |
| Elixir Purificador (ferramenta) | `create_image_pixen` 32×32: frasco redondo com líquido dourado e brilhos | `assets/expansion/combat/tool_cleanse.png` |
| Ferrão Venenoso (o que cai do céu) | `create_image_pixen` 48×48: ferrão verde pingando veneno; virado de cabeça para baixo para cair de ponta | `assets/effects/abilities/drops/poison.png` |

Os elites das Chamas, do Veneno e do Gelo usam o ícone do próprio efeito; a Encouraçada usa o escudo que já existia (`assets/ui/icone_escudo.png`).

## Descartado
- Vampira: um rosto de vampiro com a língua de fora (ficou cômico). "Big glossy dark red blood drop with two sharp white vampire fangs" acertou.
- Veneno que cai: um frasco verde com cauda ("falling glob of venom") parecia uma poção arremessada. "Venom stinger spike pointing straight down" acertou (e foi virado).

## Lições
- Ícones de 32×32 do pixen com "bold simple shape, compact and centered with a small empty margin" saem legíveis mesmo desenhados a 13–16 px (fila de turnos e embaixo do nome).
- Quando um ícone novo lembra outro do jogo (o raio da exaustão × o da energia), trocar a cor por código resolve sem gastar geração.
