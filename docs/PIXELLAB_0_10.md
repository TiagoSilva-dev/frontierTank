# Arte PixelLab — 0.10 (moedas)

Gerada pelo MCP do PixelLab em 2026-09-25. IDs, seeds, prompts e destino de cada arquivo em `assets/v10/pixellab_manifest.json`. Custo: **17 gerações** (restam 232 até 2026-10-24).

Na entrega da 0.10 o MCP não estava autenticado (erro 401), então os ícones saíram provisórios, desenhados por código em `tools/currency_icons.py` (32×32). Agora os sete são arte PixelLab em 64×64, com o mesmo nome de arquivo; o jogo não mudou. O script ficou como reserva: só cria um ícone que não existe (moeda nova) e não sobrescreve os atuais sem `--force`.

## Gerado e em uso
Todos com `create_image_pixen`, 64×64, fundo transparente, contorno preto de 1 pixel, `highly detailed`, vista lateral. Ficam em `assets/items/currency/<id>.png`.

| Moeda | O que é | Tentativas |
|---|---|---|
| Brasa | carvão em brasa com rachaduras de lava e chamas em cima | 1 |
| Coroa | coroa dourada de três pontas com gemas vermelhas e azuis | 1 |
| Estrela | estrela dourada facetada como gema, com brilhos | 1 |
| Tormenta | orbe roxo com nuvens de tempestade e um raio amarelo | 1 |
| Solar | medalhão de sol com doze raios e núcleo branco | 3 |
| Eclipse | disco escuro na frente do sol com chamas douradas na borda | 5 |
| Espelho Celeste | espelho de mão dourado com estrelas e gemas, vidro azul-céu | 5 |

Capturas da aba Moedas do Ferreiro com os ícones novos: `docs/screens/smith_moedas.png` e `smith_moedas_mapas.png`.

## Lições
- Pixen em 64×64 tende a encher o quadro inteiro: Solar, Eclipse e Espelho vieram com raios, coroa ou cabo cortados na borda. Pedir "in the middle of the canvas with empty transparent margin" resolveu o Solar, mas encolheu demais o espelho (28 px de largura); "compact and centered with a small empty margin" (Eclipse) e "large ... filling most of the canvas" com a forma descrita (Espelho) deram o tamanho certo com 1 a 2 px de folga.
- Conferir a caixa de conteúdo (pixels opacos na coluna 0/63 e linha 0/63) antes de aceitar; se só o contorno escuro encosta na borda (Tormenta), o ícone está completo.
- A palavra "ring" no eclipse gerou planetas com anel; "flames radiating all around its rim ... not a planet" deu o eclipse certo.
- Rodar a mesma descrição com duas seeds por 1 geração cada sai mais barato que o Pro Flash (5 gerações) para ícones de item.
