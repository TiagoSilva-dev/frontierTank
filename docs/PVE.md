# PvE 0.2 — Templo do Sol

A entrada principal agora é uma cidade celeste. O portal e o botão de expedição iniciam a primeira missão solo contra Rei Hélio. Um único herói pertence ao perfil; o chefe é um inimigo, sem perfil de jogador.

## Arte PixelLab incorporada
- Cinco imagens fixas: cidade, templo, piso de pedra, portal e chefe original.
- Herói em repouso: 5 quadros, 7 fps.
- Rei Hélio em repouso: 5 quadros, 7 fps.
- Rei Hélio lançando magia: 9 quadros, 7 fps, acionados pelo disparo real.

Os quadros incluem a imagem inicial devolvida pelo PixelLab. PNGs originais em `assets/pve/`, prompts e IDs nos dois manifestos. GIFs de inspeção em `docs/`. Nenhum sprite foi extraído das duas referências de DDtank; a terceira referência orientou temas, cores e composição. O resultado é uma primeira interpretação pixel art, não uma reprodução visual exata.

## Combate
Herói: 150 PV. Chefe: 240 PV. IA busca ângulo e potência com a mesma gravidade e vento, verifica o terreno e aplica pequena dispersão de mira. O jogador não controla ações no turno inimigo. Aviso de 2,2 segundos antes do ataque. Abaixo de metade da vida, o dano do chefe passa de 32 para 42, com aviso de Fúria Solar. Todos os parâmetros em `shared/balance/combat.json`.

Terreno destrutível usa a imagem PixelLab como textura da máscara real de colisão. Vitória, derrota, cura, escudo, pausa e nova tentativa funcionam. Recompensas permanecem exclusivamente locais.

## Validação
27 verificações de regressão de combate, 8 de navegação e 17 específicas de PvE. O teste da precisão da IA desliga a dispersão intencional para isolar o cálculo balístico. Inspeção da prancha de animação e capturas reais do Godot.

Escopo atual: uma missão solo contra um chefe. Ainda sem ondas de lacaios, campanha de várias fases, cooperativo ou ferreiro. As animações de ataque do herói e caminhada ainda não foram geradas.
