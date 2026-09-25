# Assets PixelLab — Frontier Tank

Arte original gerada pelo MCP PixelLab a partir da direção visual do projeto.

Pastas: `characters`, `weapons`, `pets`, `maps`, `tilesets`, `effects`, `ui`, `items`. `enemies` está reservada para expansão.

Os PNGs de armas são artes de inventário com orientação diagonal; precisam de ajuste de rotação e pivô ao serem usados na mão de um personagem. Os personagens são compostos, com equipamento em arquivo separado. O fundo é uma única camada distante.

Consulte `../ART_BIBLE.md` e `pixellab_manifest.json`. O manifesto registra prompts e IDs de geração. As URLs remotas podem expirar; os arquivos locais são a entrega preservada.

Não há implementação de gameplay neste pacote. A arte não inclui ainda todas as animações, roupas em camadas, biomas ou telas descritas no documento de referência.

## Revisão visual
24 PNGs de arte: oito vistas de dois personagens, cinco armas, dois mascotes, um fundo, dois tilesets, dois efeitos e quatro ícones/itens. `preview.png` é a prancha de contato adicional.

A versão final da Lia usa preset chibi, mas continua com proporções um pouco mais altas que Nilo. Os dois tilesets retornados pelo modelo representam pedra/ruínas; a superfície de grama solicitada não foi reproduzida. Os nomes preservam a intenção do prompt e os JSONs contêm a disposição dos tiles. A explosão é um quadro estático. Antes de produção, revisar uniformidade de proporções, pontos de ancoragem, terreno e animações.
