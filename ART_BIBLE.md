# Frontier Tank: Nova Era — pacote inicial PixelLab

## Direção visual
Fantasia medieval e tecnologia steampunk. Personagens chibi originais com cabeças grandes, roupas de aventureiro e armas exageradas. Ilhas flutuantes, ruínas e vegetação iluminadas por luz quente superior esquerda.

## Paleta de referência
Marinho `#182342`, azul `#327AC7`, ciano `#63D6EF`, creme `#FFF0C2`, ouro `#EAB34D`, cobre `#A86239`, coral `#E86A86`, violeta `#885BC7`, grama `#76AD48`. A geração usa orientação textual; a paleta final pode variar entre imagens.

## Escala e câmera
- Personagens: tamanho solicitado 96 × 96; o PixelLab expandiu ambos para canvas 136 × 136. Preservar os originais. Corpo inteiro, câmera lateral, quatro direções. Usar east/west no combate.
- Armas e mascotes: 64 × 64, perfil lateral, arma apontando à direita.
- Terreno: tiles 32 × 32, vista lateral.
- Fundo: 400 × 224, camada distante, sem colisão.
- Ícones: 32 × 32; explosão: 96 × 96.

## Acabamento
Pixels nítidos, contornos escuros, sombras em grupos de pixels e luz quente superior esquerda. Evitar suavização e escalas fracionárias. Personagens e armas são arquivos separados; ajustar ancoragem da arma na integração. Os personagens desta versão são sprites compostos, ainda sem separação de cabelo/roupas/corpo.

## Exportação e Godot
PNG RGBA com transparência nos sprites. Fundo opaco. Usar filtro Nearest no CanvasItem ou no projeto Godot, escala inteira e mipmaps desativados para sprites de interface. Manter dimensões originais e não aplicar suavização.

## Animação
Padrão planejado: idle 4 quadros a 6 fps; caminhada 6–8 quadros a 10 fps; disparo 4–6 quadros a 12 fps. Spritesheets devem manter canvas fixo e pivô estável nos pés. Registrar ordem, duração e dimensão dos quadros no manifesto; não inferir animações de imagens estáticas.

## Arquivos e rastreabilidade
Nomes em snake_case, categorias em assets/. `assets/pixellab_manifest.json` guarda prompts, IDs e resultados do MCP para rastreabilidade. Downloads originais preservados. Este pacote atende à criação de arte solicitada; o documento de referência descreve outros sistemas de jogo que não fazem parte desta entrega de assets.
