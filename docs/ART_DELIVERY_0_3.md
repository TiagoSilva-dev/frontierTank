# Arte e pesquisa — entrega 0.3

## Conteúdo

63 imagens estáticas novas para a primeira instância e interface, complementando o pacote anterior. 3 sequências do PixelLab workbench: efeito de revelação (8 quadros), chefe flutuando (4) e chefe lançando magia (6). Arquivos individuais, folhas de sprites, GIFs, receitas, metadados, prompts e IDs preservados.

19 referências de telas/localizações reunidas em `ddtank_references.html` e JSON. Há referências históricas, comunitárias e de relançamentos, identificadas individualmente. Alguns links externos falharam ao abrir; não foram tratados como imagens inspecionadas. O acervo não contém todas as telas de todas as versões do DDTank.

`DDTANK_RESEARCH.md` separa regras documentadas, diferenças entre edições, propostas próprias e lacunas. A pesquisa usa documentação da 7Road e de operadoras, além de capturas históricas para composição visual.

`frontier_visual_preview.html` apresenta cinco composições de demonstração: lobby, combate, cartas, mochila e ferreiro. Os valores e interações são ilustrativos. Não são capturas do jogo funcionando.

## Verificação

- 63/63 solicitações estáticas presentes, PNGs decodificados, dimensões esperadas e canal alpha conferidos.
- Inspeção visual das quatro páginas do catálogo; ícones ambíguos de vento, turno, POW, cristal, cartas, gelo, flechas e ovo foram corrigidos.
- Sequências exatas do workbench inspecionadas nas pranchas retornadas pelo MCP; quadros exportados sem redimensionamento.
- Importação no Godot executada com sucesso. Nenhum script de gameplay foi alterado nesta entrega.
- Caminhos estáticos da prévia HTML conferidos. A política do navegador bloqueou a abertura automática de arquivos locais; a navegação e o layout responsivo do HTML não foram validados no navegador.

## Limites e integração

Não estão implementados por esta entrega: lobby cooperativo, rede, novos stages, combos de energia, POW por arma, sorteio de cartas ou ferreiro. Os assets estão preparados para esses sistemas, que continuam sujeitos ao critério de conclusão do documento recebido.

Os fundos são ilustrativos e não contêm geometria de colisão. Barras, ângulo, tooltips, nomes, atalhos e quantidades precisam de estado dinâmico no Godot. O ferreiro gerado é uma vinheta de oficina em ilha; não é um cenário navegável completo. As animações novas usam deslocamento do sprite e efeitos desenhados; não incluem articulação de membros.

Tentativas do Pro Flash falharam no servidor ou foram canceladas. As imagens finais corrigidas usam Pixen e workbench. A tentativa de idle por IA também foi cancelada após a estimativa subir para 900 segundos; foi substituída pela sequência exata do workbench. Nenhuma geração fica intencionalmente pendente.

## Arquivos principais

- `assets/expansion/index.html`: catálogo de assets.
- `assets/expansion/godot_asset_registry.json`: texturas e animações para carregar no Godot.
- `assets/expansion/file_inventory.json`: dimensões e hashes.
- `assets/expansion/README.md`: contrato de integração.
- `frontier_tank_art_research_0_3.zip`: pacote portátil com arte atual e documentos.
