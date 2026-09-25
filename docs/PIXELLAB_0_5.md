# Arte PixelLab — 0.5 (visual do personagem, armas e cidade)

Gerada pelo MCP do PixelLab em 2026-09-24. IDs, prompts e destino de cada arquivo em `assets/v05/pixellab_manifest.json`. Custo: 784 gerações (restam 605 até 2026-10-24).

## Gerado e em uso
| O quê | Como | Onde |
|---|---|---|
| Personagem base de camiseta e shorts (ele e ela), em pé e deitado, com respirar, rastejar e arremessar | `create_character_state` a partir de Nilo/Lia + `animate_character` v3 | `assets/characters/base_m`, `base_f` |
| Roupas: Samurai, Ninja, Capitão; Princesa, Maga, Marinheira (mesmo rosto e cabelo) | estados do personagem base, em pé e deitado, com as três animações | `assets/characters/roupa_*` |
| 12 armas do DDTank (9 clássicas + 3 super) | `create_image_pixen` 64×64 | `assets/weapons/<id>/tier0.png` |
| 6 chapéus (frente e lado), 4 óculos | `create_image_pixen` | `assets/cosmetics/<id>/front.png`, `side.png` |
| 4 asas (anjo, demônio, fada, fênix): uma asa por imagem em 128×128; a outra é espelhada e cada uma bate a partir do ombro (`root` em `items.json`) | `create_image_pixen` | `assets/cosmetics/asas_*/wing.png` (par e ícone montados a partir dela) |
| Itens auxiliares, ícone de cabelo, 4 pedras de fortalecimento | `create_image_pixen` | `assets/aux/`, `assets/cosmetics/cabelo/`, `assets/items/pedra_*.png` |
| Projéteis (tijolo, bala de fogo, orbe arco-íris, maçã, laranja, cápsula, TV, orbe elétrico, geladeira) e o touro espectral | `create_image_pixen` | `assets/projectiles/` |
| Praça sem o chafariz, para o Salão de Jogos ir ao centro | `inpaint_image` num recorte de 112×80 | `assets/city/city_bg.png` |

## Feito em código a partir da arte
- **Tiers das armas** +9 (azul), +10 (roxo) e +12 (dourado): recoloração por luminância com brilho em volta (`tools/weapon_tiers.py`). A variação feita pelo PixelLab (img2img) saiu inconsistente e foi descartada.
- **Óculos de lado** (para a pose deitada): recorte de uma lente da vista de frente.
- **Aura da arma**: camadas em alta resolução desenhadas por `tools/aura_textures.py` (disco, raios, anel de runas, estrela).
- **Âncoras** de cabeça, olhos, costas e cores do cabelo de cada personagem, e a posição da cabeça em cada quadro das animações: `tools/character_anchors.py` → `assets/characters/<skin>/anchors.json`.
- **Aura** (círculo mágico girando), **tintura de cabelo**, **brilho da roupa**, **mar animado** e animações dos prédios.

## Descartes
- Vários chapéus vieram com rosto ou cabeça desenhados junto; foram refeitos pedindo só o objeto.
- Os primeiros pares de asas (128×64, com corpo de morcego, borboleta e pássaro no meio) foram trocados por asas avulsas em 128×128. Na asa de fada foi apagado o corpo da borboleta e, na de anjo, um toco amarelo na raiz.
- Tijolo (parecia um baú) e os primeiros Super Cabeça de Boi, Super Lança e Super Bumerangue refeitos.
- Ícones antigos das pedras II e IV (um tanque e um baú, vindos de uma leva anterior) trocados.

## Como fazer mais roupas
1. `create_character_state` no estado em pé do personagem base (`73eea963…` ele, `fe830c5c…` ela) com a roupa, sem chapéu.
2. O mesmo texto no estado deitado (`7c9b210c…` ele, `afe5ef83…` ela), começando por "same prone pose lying on the belly, now wearing…".
3. `animate_character` v3, direção east: respirar (4 quadros), rastejar (6) e arremessar (4), com os textos do manifesto.
4. Baixar o zip do grupo e rodar `python tools/import_pixellab_skin.py grupo.zip Roupa_X Roupa_X_Prone roupa_x`, depois `python tools/character_anchors.py roupa_x`.
5. Registrar a roupa em `shared/balance/items.json` (`cosmetics`, `slot: "roupa"`, `skin: "roupa_x"`).

## Ainda não gerado
Rosto e olhos como slots separados, mais roupas e cenários de batalha novos.
