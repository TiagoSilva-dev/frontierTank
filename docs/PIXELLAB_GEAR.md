# PixelLab: equipamentos de instância (0.31)

28 peças (7 espaços × 4 raridades; as 4 asas deixaram de ser drop na 0.32 e são vendidas por dinheiro, ver `docs/GEAR.md`), **38 gerações** (781 → 743 até 24/10/2026). Tudo com `create_image_pixen`, sempre
`no_background`, contorno `single color black outline`, descrição terminando em "compact and centered with a small
empty margin". Os PNGs originais estão em `tools/gear_src/` e `python tools/gear_art.py` os instala (`docs/GEAR.md`).

## Receita por raridade (a mesma linguagem em todos os espaços)

| Raridade | Descrição que se repete | `detail` |
|---|---|---|
| Comum | couro/osso/latão fosco, "plain, dull muted colors, no gems, no decoration" | medium |
| Raro | aço azul polido, detalhes de prata, uma safira, "cool blue highlights" | highly detailed |
| Épico | violeta e prata, runas roxas brilhando, ametistas, "faint magical purple glow" | highly detailed |
| Lendário | ouro maciço com vermelho, escamas de dragão, rubi brilhante, "tiny flames and sparkles", "masterwork legendary" | highly detailed |

## Tamanhos e sementes

| Espaço | Imagem | Sementes (Comum, Raro, Épico, Lendário) | Observações |
|---|---|---|---|
| Camisa | 96×96, "front view" | 101, 102, 103, 104 | colete de couro, couraça azul, túnica arcana, armadura com cabeças de dragão nos ombros |
| Anel | 96×96 | 201, 202, 203, 204 | aro de ferro, prata com safira e asinhas, prata com ametista e runas, dragão dourado enrolado com rubi |
| Calça | 96×96, "front view" | 301, 302, 303, 304 | |
| Amuleto | 96×96 | 401, 402, 403, 404 | osso e couro, medalhão com asinhas, cristal rúnico, dragão enrolado num coração de rubi |
| Chapéu (frente) | 64×64, "just the object alone ... no face, no head" | 501, 502, 503, 504 | capacete de couro, elmo azul com asas, chapéu de mago, elmo de dragão com chifres |
| Chapéu (lado) | 64×64, `direction: west`, `view: side`, "seen from the side in profile facing left" | 511, 512, 513, 514 | gerados do zero com a mesma descrição (a edição de imagem não gira a peça) |
| Óculos (frente) | 64×32 | 601, 602, 603, 604 | googles de latão, lentes de cristal com asinhas, visor arcano, olhos de dragão |
| Óculos (lado) | 32×32, `direction: west`, `view: side`, "a single ... lens" | 611, 612, 613, 614 | uma lente só, como os óculos antigos |
| Asas | 128×128, "a single wing seen from the side ... the root ... is at the lower right corner, just the wing alone" | 701, **722**, 703, 704 | a asa de cristal do Raro saiu "uma pena gigante" nas sementes 702 e 712 com "translucent crystal feathers"; com "many layered feathers in rows like an angel wing, translucent light blue crystal" a semente 722 deu uma asa de verdade |

## Encaixe

- **Chapéus e óculos**: `tools/gear_art.py` corta cada PNG ao seu retângulo opaco (+1 px) e escreve a entrada em
  `assets/cosmetics/fit.json` (`width`, `drop`, `dx`; o corte e a base padrão servem). Ajustados olhando
  `godot --path . --rendering-driver opengl3 --script tools/cosmetic_sheet.gd -- --set=pve_hats --view=front|prone --bodies=lani --scale=3`.
  O visor arcano e as googles são altos: ficaram com largura menor (0,62 e 0,70) para não cobrir a boca.
- **Asas**: `root` em `items.json` é o ombro dentro dos 128×128 (aviso: a asa precisa subir do ombro, então fica no
  terço de baixo): Pardal `[92, 112]`, Cristal `[112, 80]`, Arcanas `[104, 84]`, Dragão `[112, 92]`. `front.png` (o par,
  espelhado nas raízes) e `icon.png` (64 px de largura) são montados em código; `side.png` é a própria asa.

## Lições

- Uma peça de cada raridade com a **mesma descrição de base e só o material trocado** deu uma progressão legível
  de graça (Comum fosco → Lendário radiante); mudar a forma entre raridades (como o aro simples do Comum) não atrapalhou.
- O pixen acertou os 28 ícones de 96×96 e as vistas laterais na primeira tentativa: 36 das 38 gerações viraram
  peça; as duas descartadas foram as asas Raras 702 (pena gigante) e 712 (boa, mas com ruído escuro). A frente de
  chapéu e óculos serve de peça vestida sem edição.
- Nenhuma peça precisou de `create_object_pro_flash` (5 gerações cada).
