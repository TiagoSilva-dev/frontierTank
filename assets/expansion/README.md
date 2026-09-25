# Expansão visual — Frontier Tank

Arte original gerada pelo MCP PixelLab a partir do documento de instâncias PvE. Esta pasta complementa os personagens, armas, pets, tiles e animações existentes em `assets/`; não substitui o pacote anterior.

Abra `index.html` para navegar pelos PNGs ou `catalog_1.png` e páginas seguintes para inspeção. `generation_manifest.json` registra cada prompt, ID e URL. `file_inventory.json` registra dimensões, transparência e SHA-256 dos arquivos recebidos. `asset_requests.json` é a lista planejada de imagens fixas.

## Cobertura

- Lobby: moldura de jogador, pronto, líder, quatro dificuldades, prévia da instância, slots de loot e ferramentas.
- Combate: energia, POW, ângulo, força, vento, turno, boss HP, minimapa, oito habilidades e ferramentas. Escudo reutiliza `assets/ui/icone_escudo.png`.
- Recompensas: verso, quatro raridades, baú e animação de virada em pacote separado.
- Progressão: pedras II/III/IV, cristal, fragmento, ovo e pet do Rei das Máscaras; moeda e pedra I já existem no pacote inicial.
- Conteúdo: guardião, Rei das Máscaras, cristal a defender, arco mecânico, três cenários de templo, interiores de ferreiro e inventário.
- Feedback: efeitos visuais de quatro POWs, vitória, derrota, stage clear, botão, fechar e cadeado.

Três sequências adicionais foram montadas no `pixelart_workbench` do MCP: revelação de carta (8 quadros), flutuação do chefe (4) e lançamento de magia (6). São animações por deslocamento do sprite e composição exata de efeitos, não animação esquelética. Spritesheets, quadros individuais, GIFs, duração e eventos estão em `animations/` e `animations_manifest.json`.

O efeito `card_flip_effect` é uma sobreposição de brilhos: a UI deve girar a carta via escala horizontal e trocar o verso pela frente quando a largura atingir zero. O evento `reveal` ocorre no quadro 4 do efeito. A animação de ataque tem evento `cast` no quadro 4; o projétil real deve ser criado pelo combate, não inferido do GIF.

## Contrato de integração

Godot 4: filtro Nearest, sem mipmaps na interface, escala inteira quando possível. Cenas de fundo são imagens opacas; sprites e molduras usam RGBA. Os números devem ser consultados no inventário, não deduzidos pelo tamanho solicitado.

As barras são arte estática: a implementação deve usar máscara/recorte para preenchimento e texto independente para valores. O indicador de ângulo é decoração; desenhar agulha dinâmica e valor no código. Estados normal/hover/pressed/disabled/selected usam modulação de cor e contorno no Theme; não exigem duplicação de texturas. Não esticar molduras ornamentadas indiscriminadamente: usar NinePatchRect com margens verificadas no PNG.

Ícones de dano precisam de rótulos +10% a +50% no jogo; a silhueta sozinha não diferencia valores com precisão. Dificuldades também precisam de nome, evitando depender exclusivamente de cor. Não rasterizar nomes de jogadores, atalhos ou quantidades.

Os cenários contêm chão ilustrado, sem colisão: renderizar o terreno físico destrutível em camada separada. Chefe e guardião são novos personagens; suas hitboxes e pivôs devem ser configurados após integração.

## Limites

Assets produzidos não equivalem a sistemas implementados. Lobby cooperativo, múltiplos stages, combos, cartas e ferreiro ainda precisam da programação descrita no documento. Este pacote cobre o conteúdo visual especificado para a primeira instância, não todas as futuras armas, campanhas, skins ou telas de todos os serviços do DDTank. Áudio e música não são gerados pelas ferramentas gráficas do PixelLab usadas aqui.

Reexecutar `python tools/collect_expansion.py` a partir da raiz baixa apenas as imagens concluídas faltantes e recria inventário e catálogo.

`python tools/collect_workbench_animations.py` exporta os quadros das animações sem redimensionamento. `godot_asset_registry.json` contém os caminhos `res://` para integração. Resultados descartados permanecem em `superseded/` e nos manifestos para rastreabilidade; não são arte recomendada.
