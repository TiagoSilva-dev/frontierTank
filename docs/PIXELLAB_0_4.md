# PixelLab — entrega 0.4

O servidor MCP `pixellab` está configurado neste projeto (`claude mcp add pixellab https://api.pixellab.ai/mcp -t http -H "Authorization: Bearer …"`). Os prompts, IDs de trabalho e personagens estão em `assets/v04/pixellab_manifest.json`. Consumo nesta entrega: cerca de 410 gerações.

## Gerado e integrado
| O quê | Arquivos | Onde aparece |
|---|---|---|
| Praça da cidade (400×224) | `assets/city/city_bg.png` | Cidade, com o layout do DDTank |
| 6 prédios (Salão de Jogos em coliseu, Ferreiro, Namoro, Leilão, Centro Comercial, Instância) | `assets/city/buildings/*.png` | Cidade; brilham ao passar o mouse |
| Arte do VS | `assets/room/vs_art.png` | Sala |
| 21 ícones | `assets/ui/icons/*.png` | Barra inferior, chat, Salão, Sala, partida |
| 6 bots (ruivo, pirata, maga, ninja, robô, princesa) | `assets/characters/bot_*/` | Salão, Sala e partida (sorteados pelos bots) |
| **Pose deitada** dos 8 personagens (estado "Prone") | `assets/characters/*/prone/{east,west,south,north}.png` | Partida: como no DDTank, todos lutam deitados |
| Respirar e rastejar deitado (5 e 7 quadros) | `assets/characters/*/prone/{idle,crawl}/` | Partida: parado e ao se mover |
| Andar e idle em pé do Nilo e da Lia | `assets/characters/{nilo,lia}/{walk,idle,attack}/` | Reservado (usado só se faltar a pose deitada) |

Ajustes feitos na integração: prédios recortados da margem transparente; no robô a rotação "east" veio virada para a esquerda, então east/west foram trocados; o arremesso da Lia (modelo `throw-object`) virou o rosto para a câmera e mudou o cabelo, por isso foi apagado; os ícones "team" e "play" foram refeitos em 48×48.

## Ainda não gerado
- Cenários de batalha novos (ex.: jardim florido da referência): PNG 400×224 + entrada em `maps` de `shared/balance/combat.json`.
- Animação de disparo deitado (`prone/shoot/`); hoje o disparo usa um recuo curto.
- Arte das telas de Ferreiro, Loja e PET, que ainda não existem como sistemas.
