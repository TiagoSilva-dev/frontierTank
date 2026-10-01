# PixelLab: fundo novo da cidade (0.17+)

Só o fundo da cidade foi refeito (`assets/city/city_bg.png`, 640×360, mostrado em 2x); os prédios continuam os de `assets/city/buildings/`.

| O que | Como | Custo |
|---|---|---|
| Ilha, mar, praça com rosa-dos-ventos, seis lotes calçados, píer e barco | `create_image_pro` 640×360, `no_background: false`, com um **mapa de layout** como referência de composição | 40 por chamada |

- O mapa de layout é a cidade antiga reduzida a 160×90 e 8 cores (PNG indexado de 4 KB, 5,4 KB em base64; Pillow `quantize(8)` sobre a imagem reduzida) mandado como `reference_images` com `usage` "layout and composition: keep the island silhouette, the big circular plaza in the centre and the six rectangular lots around it in exactly the same positions; ignore the flat colours". Com ele a praça e os seis lotes voltam nos mesmos lugares (sem ele o pixen adiciona casas e deixa a praça fora do centro).
- Duas sementes: a primeira (seed 11) saiu fosca, com lotes de terra; a segunda (seed 21, prompt pedindo cores saturadas, luz de fim de tarde, mar com degradê de profundidade e lotes de pedra clara com borda decorativa) saiu como a imagem usada. 80 gerações no total (2228 → 2148 até 2026-10-24).
- Os prédios foram deslocados até 30 px (`CITY_LAYOUT` em `city_screen.gd`) para centrar nos lotes novos.
- `client/shaders/city_sea.gdshader` reconhece como água qualquer pixel dominado pelo azul (turquesa e o azul fundo), não só o ciano claro.
