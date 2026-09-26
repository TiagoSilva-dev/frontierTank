# Arte PixelLab — Lani (nova personagem feminina)

Gerada pelo MCP do PixelLab em 2026-09-26 a partir de uma foto de referência enviada pelo usuário. A Lani substitui a Lia como personagem feminina padrão (`assets/characters/lani`, no lugar de `base_f`). IDs em `assets/characters/manifest.json`. Custo: **52 gerações** (restam 99 até 2026-10-24).

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Lani em pé, 4 direções (pele morena escura, cabelo preto ondulado na altura dos ombros, brincos e colar dourados, body preto de frente única, short de couro preto com cinto, pulseiras douradas, tatuagem no braço, sandálias pretas) | `create_character` padrão, chibi, `side`, 96 px (tela de 136), mesmos parâmetros de estilo da Lia | `south/east/west/north.png` |
| Lani deitada (pose de batalha) | `create_character_state` com o texto de pose deitada da Lia + "one-piece black bodysuit that covers the belly" | `prone/*.png` |
| Respirar (4), rastejar (6) e arremessar (4) deitada | `animate_character` v3, direção east | `prone/idle`, `prone/crawl`, `prone/shoot` |

Importado com `tools/import_pixellab_skin.py` (a vista east deitada veio virada para a esquerda; o script troca east/west e espelha as animações) e âncoras de `tools/character_anchors.py lani`.

## Ajustes feitos à mão
- **Barriga coberta:** a vista em pé veio com top cropped; na foto é um body inteiro. Os ~3 pixels de altura de pele entre o top e o cinto foram pintados com o preto do próprio tecido (south, east, west; a north não é usada pelo jogo e ficou como veio).
- **Cabelo azul-escuro para a tintura:** o cabelo, os olhos e a roupa usavam os mesmos pretos, então a tintura de cabelo pintava também os olhos e as alças do body. Os pixels da massa de cabelo das vistas em pé (menos o contorno externo) ganharam +2 no verde e +8 no azul: continuam pretos, mas agora são cores só do cabelo. `character_anchors.py` passou a reconhecer cabelo quase preto (tom dominante com brilho < 0.13) seguindo esse tom na cabeça inteira; as outras skins dão exatamente as mesmas cores de antes.

## Descartado
- Uma segunda variação (1 geração): rosto de anime com dentes à mostra e tatuagens azuis que pareciam hematomas.

## Pendente
As roupas femininas (Exploradora = pasta `lia`, Princesa, Maga e Marinheira) foram feitas como estados da Lia e ainda mostram o rosto e o cabelo rosa dela. Para trocar, refazer cada uma como estado da Lani seguindo "Como fazer mais roupas" em `PIXELLAB_0_5.md` (em pé `9973d592…`, deitada `48019c16…`); custa ~50–90 gerações por roupa.
