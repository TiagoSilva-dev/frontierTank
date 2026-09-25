# Arte PixelLab — 0.6 (qualidade dos assets)

Gerada pelo MCP do PixelLab em 2026-09-24. IDs, prompts e destino de cada arquivo em `assets/v06/pixellab_manifest.json`. Custo: 217 gerações (restam 379 até 2026-10-24).

## Regra de escala
A arte antiga era esticada em escalas quebradas (a cidade de 400×224 aparecia em 3,2×, os mapas de 256×144 em 5×), o que deixava pixels de larguras diferentes. Agora:
- cenários são gerados em **640×360** (cidade, entrada) ou **680×380** (mapas) e aparecem em **2× exato**;
- prédios, armas e cartas são gerados no tamanho em que aparecem (**1×**);
- o que ainda precisa de escala quebrada (ícones em slots, personagens em 2,25× nos menus e 0,76× deitados na partida) passa pelo shader `client/shaders/pixel_smooth.gdshader` (e pela mesma amostragem dentro de `look.gdshader`): todo pixel da arte fica do mesmo tamanho e só a emenda entre dois pixels é suavizada.

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Tela de entrada: arte com os dois heróis, dirigíveis e nascer do sol | `create_image_pixen` 640×360 | `assets/title/title_bg.png` |
| Logotipo "FRONTIER TANK · NOVA ERA" | `create_image_pro_flash` 256×144 (em 2×, com brilho passando) | `assets/title/logo.png` |
| Cidade: ilha com a praça no centro, seis lotes, mar, píer e barco | `create_image_pro` 640×360 com a cidade antiga como referência de composição | `assets/city/city_bg.png` |
| Salão de Jogos (coliseu) e seis prédios: Ferreiro, Instância, Leilão, Namoro, Centro Comercial e a nova Casa dos Mascotes | `create_image_pro_flash` 256×256 e 192×192 | `assets/city/buildings/` |
| Fundos dos 5 mapas | `create_image_pixen` 680×380 | `assets/maps/bg/` |
| Terreno pintado (como no DDTank): ilhas de grama, ruínas de areia, gelo, rocha vulcânica e piso do templo | `create_image_pixen`, limpo por `tools/terrain_pieces.py` | `assets/maps/terrain/` |
| 12 armas em 96×96 (mesmo desenho da 0.5, mais detalhe) | `create_image_pro_flash` com o ícone antigo como estilo | `assets/weapons/<id>/tier0.png` (+9/+10/+12 por `tools/weapon_tiers.py`) |
| Explosão animada (12 quadros) | `create_image_pixen` 128×128 + `animate_image` 8 quadros | `assets/effects/explosion/` |
| Cartas de recompensa: verso e as quatro raridades | `create_image_pro_flash` 128×192 | `assets/expansion/rewards/` |

## Feito em código a partir da arte
- **Terreno**: cada mapa lista peças em `shared/balance/combat.json` (`terrain`: arte, posição, espelhar). O alfa da pintura é a colisão; as crateras ganham borda queimada e jogam pedaços com as cores do chão arrancado.
- **Explosão** (`client/components/impact_fx.gd`): fogo animado, clarão, onda de choque, fumaça e estilhaços.
- **Clima** (`client/components/ambience.gd`): neve na Câmara do Guardião, brasas no Trono das Máscaras, poeira de luz nos templos e pólen na Ilha Celeste; `dim` escurece o fundo de cada mapa para o chão se destacar.
- **Miniaturas dos mapas** para a escolha de local: `tools/map_thumbs.py` → `assets/maps/thumbs/`.
- **Cidade viva**: fumaça da chaminé e brilho da forja do Ferreiro, faíscas no coliseu, portal da Instância girando, corações da capela, brilhos nas lojas, gaivotas e mar animado.
- O céu da Ilha Celeste veio com uma faixa escura no topo; foi recolorida para azul só na região ligada à borda superior.

## Descartes
- Cidades em Pixen: vinham com casas desenhadas e a praça fora do centro; a versão Pro com a cidade antiga como referência manteve a composição.
- Fundos de céu com tanque ou personagens no primeiro plano, e um que virou um mapa de plataformas.
- A primeira arte da entrada veio com letras sem sentido.
- Pisos de templo com tijolos vazados (só contorno) e uma ilha de gelo fina demais.

## Como fazer um mapa novo
1. Fundo: `create_image_pixen` 680×380 descrevendo só o cenário distante ("no foreground, no characters, no vehicles").
2. Chão: uma ilha por vez, `no_background`, largura = metade da largura da ilha no mundo (1 texel = 2 unidades), pedindo "solid opaque body with no holes".
3. `python tools/terrain_pieces.py origem.png nome [--flip] [--key] [--main]` (use `--key` se vier com fundo xadrez ou preto).
4. Registrar em `combat.json` com `terrain`, `spawns` dentro das peças, `rim` (cor da borda da cratera), `dim` e `ambience`; depois `python tools/map_thumbs.py`.
