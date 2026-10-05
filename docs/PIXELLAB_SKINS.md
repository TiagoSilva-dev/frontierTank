# Arte — skins épicas (PixelLab)

Registro da arte gerada para as skins épicas (`docs/SKINS.md`). A receita é a do Paladino do Sol (`docs/PIXELLAB_FOUNDER.md`), com uma lição nova: **a pose deitada sai de mãos vazias**.

## Receita (uma versão, masculina ou feminina)
| Passo | Chamada | Custo |
|---|---|---|
| Em pé, 4 direções | `create_character` padrão, `view` side, 4 direções, `size` 96 (tela 136), chibi, `detail` high, `shading` detailed, outline preta | 1 |
| Deitado | `create_character_state` "lying flat on the belly in a prone pose, big head raised, both arms stretched forward on the ground with open empty hands, no weapon, no cannon, side view facing right, same …" | 20–40 (cerca de 30) |
| 7 clipes | `animate_character` v3, `directions: ["east"]`, `keep_first_frame: false`, nomes `prone_idle` (6 quadros), `prone_crawl` (8), `prone_shoot` (6), `prone_hit` (4), `prone_victory` (6), `prone_defeat` (6), `prone_pow` (4) | 2–5 cada (cerca de 21 no total) |
| Importar | `python tools/import_pixellab_skin.py <grupo.zip> Idle ProneB epica_<tema>_<m|f>` e `python tools/character_anchors.py epica_<tema>_<m|f>` | 0 |

O leste já vem virado para a direita; o importador não espelha. Baixar o grupo (todos os estados) em `https://api.pixellab.ai/mcp/characters/<id>/download`.

## O que saiu
| Skin | Masculina | Feminina | Em pé (id) | Deitado, versão final (id) |
|---|---|---|---|---|
| Tempestade Viva | Senhor da Tempestade: armadura azul-escura com detalhes brancos, capa rasgada, cabelo branco espetado, olhos de raio | Senhora da Tempestade: armadura de aço com saia de placas, capa, cabelo longo branco-azulado | M `1c5bae97-cf03-43dd-b857-6a1866acfa14`, F `77c397c6-74b3-4967-9242-fef7329713d3` | M `2c527112-61b9-4fbe-82a1-dd1b8c382ed0`, F `b52e439b-b10d-4e8e-930d-d062f04a05b9` |
| Coroa de Gelo | Rei do Gelo: armadura de cristal azul-claro, capa branca, coroa de estilhaços | Rainha do Gelo: vestido de cristal branco e azul, coroa de estilhaços, cabelo longo azul-claro | M `d51fcb0b-5173-4910-b63e-7a8ea8a619c6`, F `9f6dac9c-a7a2-4729-af68-201c13c9a4a6` | M `45ae7995-bb98-45b4-b6db-27e117d337d8`, F `f5b32add-d4de-4b93-a52f-e4c9b461a994` |
| Coração de Magma | Lorde do Magma: obsidiana escura com rachaduras laranja, elmo com chifres, olhos de brasa | Lady do Magma: armadura de obsidiana, saia, cabelo longo vinho com pontas de brasa, chifres | M `8a1469fd-51ed-4c00-a3c5-7cca20daa46a`, F `f73affa4-2129-4dc6-918e-f03de9fee1a4` | M `b7bef12d-3a55-47c0-ad04-a4fadf8101bc`, F `9e9e233b-c79d-4fda-bab5-22e6f3e2249b` |

Cada personagem em pé saiu bom **na primeira geração** (uma variação por versão, sem descartes).

## Custo
- Saldo antes: 1.690; depois: **953** (737 gerações, contando o POW refeito do Gelo).
- **Cerca de 310 foram desperdiçadas** na primeira passada: o estado deitado foi pedido com "arms forward holding a small cannon in front" e saiu com um canhão fixo nas mãos, o que briga com a regra do jogo (a arma equipada vai nas costas, e as outras skins deitam de mãos vazias). O estado "Prone" e os clipes dele (todos os do Magma e do Gelo e parte dos da Tempestade) foram descartados; o estado final é o "ProneB".
- Sem o desperdício, as três skins para os dois gêneros custam cerca de 320 gerações (6 em pé, cerca de 180 deitados e cerca de 126 de clipes).

## Lições
- Pedir "no weapon, no cannon, open empty hands" no estado deitado funcionou nas seis versões. Conferir a imagem `east` **antes** de animar.
- Vestido e saia longos (Rainha do Gelo) aumentam a tela do clipe e o custo (4 a 5 por clipe em vez de 3).
- O clipe `pow` com "body shuddering with glowing energy" deu clarões amarelo-brancos no Magma e na Tempestade (bom, lê como carga de poder); no Gelo mudou pouco na primeira vez; refeito (apagado com `delete_animation` e gerado de novo, 5 gerações) com "releasing a huge power blast while lying prone: the chest arches up, head thrown back, both arms thrown wide, body glowing bright white-blue with a burst of ice light", que deu clarão branco e redemoinho de gelo.
- Os personagens saem dentro de uma tela de 136 px com margem; o `anchors.json` mede cabeça, olhos e costas. `epica_*` não tem tintura de cabelo.
- Camada própria: nada de PixelLab. `SkinFx` desenha em código.
