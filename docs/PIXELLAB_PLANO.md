# Plano de arte PixelLab — o que ainda é desenhado por código (26/09/2026)

Pedido: deixar o jogo mais bonito e atrativo, com a interface menos quadrada e um POW de jogo de luta, usando como referência a janela "Mochila" (bordas grossas e arredondadas, frisos dourados, relevo interno, sombras suaves) e a sequência de especial em 5 tempos (barra cheia, ativação com retrato grande e título, círculo mágico, mira e disparo, impacto com o número enorme).

**Estado:** a chave do PixelLab foi enviada, mas este ambiente não chega ao `api.pixellab.ai` (a política de rede bloqueia) e o MCP do PixelLab não tem a chave configurada (401). Por isso a parte de código já está pronta para receber a arte: **cada arquivo abaixo é carregado sozinho quando existir**, e até lá o jogo usa a versão desenhada por código. Para gerar, numa sessão com `PIXELLAB_API_TOKEN` configurado (ou com `api.pixellab.ai` liberado em Network access), é só seguir `assets/pixellab_plan.json`.

```
python tools/pixellab_plan.py            # quanto de cada grupo já foi feito
python tools/pixellab_plan.py --missing  # os trabalhos que faltam: arquivo, ferramenta e tamanho
python tools/pixellab_plan.py --write    # regrava o plano (guarda o hash dos arquivos feitos por código)
```

Um arquivo gerado por script que já ocupa o caminho (moedas, auras, tiers de armas) só conta como feito quando o conteúdo muda: o plano guarda o hash da versão feita por código.

## Inventário e onde a arte entra

| Grupo | Qtd. | Hoje (código) | Arquivo que o jogo procura | Ferramenta PixelLab |
|---|---|---|---|---|
| Molduras da interface (9-slice) | 23 | `UiKit.drawn_frame`: anéis, degradê, relevo e sombra desenhados em grade de 2 px | `assets/ui/frames/<tipo>.png` + margens em `assets/ui/frames/frames.json` (`UiKit.art_frame`) | `create_ui_asset` |
| Retratos do POW | 16 | `PowCutIn` mostra o personagem em pé (`AvatarView`) | `assets/portraits/<skin>.png` (`PowCutIn.portrait_path`) | `create_image_pro` com o `south.png` da skin como referência |
| Habilidades dos monstros | 22 | `AbilityFx` desenha cada efeito (lança, feixe, meteoro, pilar, tremor, garras, sopro, espinhos, corrente, dreno, chuvas) | `assets/effects/abilities/<fx>/frame_00.png…` (`AbilityFx.art_frames`, toca por cima do desenho) | `create_object_pro_flash` + `animate_object` |
| Moedas | 7 | `tools/currency_icons.py` | `assets/items/currency/<moeda>.png` | `create_image_pixflux` 32×32 |
| Auras das armas | 16 | `tools/aura_textures.py` (4 cores × disco, anel, raios, estrela) | `assets/effects/aura/<cor>_<camada>.png` | `create_image_pro` 256×256 |
| Ícones ainda procedurais | 5 | `PixelIcons` (masculino, feminino, setas, VIP) | `assets/ui/icons/<nome>.png` | `create_image_pixflux` |
| Tiers +9/+10/+12 das armas | 36 | `tools/weapon_tiers.py` (recolor por luminância) | `assets/weapons/<arma>/tier1..3.png` | `create_image_pro_flash` com o tier0 de referência (na 0.5 o img2img mudou o desenho; se mudar de novo, fica o recolor) |
| Lápide | 1 | retângulos em `TankFighter._draw` | `assets/effects/tombstone.png` | `create_image_pixflux` |

Continuam por código, de propósito: partículas (`FxParticles`), o corte de tela do POW (`PowCutIn`: faixa, linhas de velocidade, título), o número final do POW (`PowTotal`), a barra cheia (`PowGaugeGlow`) e os círculos mágicos da carga (`PowFx`) — são movimento e texto, não desenho parado, e já usam as cores de cada arma. Os sons também são gerados por código (`tools/make_sfx.py`), fora do PixelLab.

## Estilo pedido nos prompts
"high quality pixel art, warm fantasy adventure game, clean single colour outline, rounded shapes, gold trims, soft shading, vibrant". Molduras: centro vazio, fundo transparente, cantos redondos, friso dourado; botões em pílula com brilho em cima. Retratos: meio corpo, pose heroica, olhando para a direita (o lado rival espelha).
