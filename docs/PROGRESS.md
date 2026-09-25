# Progresso

## Atual — 0.5: armas, visual e Ferreiro
- Visual do personagem montado pelo equipamento: começa de camiseta e shorts; roupa, chapéu, óculos, asas, cor do cabelo e arma nas costas aparecem na Mochila, Loja, Sala, Salão, cidade, resultado e na partida (deitado).
- 12 armas do DDTank: 9 clássicas em Normal, Excelente e Verdadeira, e 3 Super Verdadeiras só por drop na Instância. Cada uma com projétil, rastro e POW próprios.
- Fortalecimento +1 a +12 com pedras (tabela do TechTudo), ícone que evolui no +9/+10/+12, aura da arma (verde, azul, roxa, vermelha) e aura da roupa. Ferreiro com Fortalecer, Composição, Fusão e Transferência. Loja com provador. Item auxiliar na tecla V.
- Atributos Ataque, Defesa, Agilidade e Sorte (crítico) vindos dos itens; bots com equipamento e auras.
- Cidade: Salão de Jogos no centro, mar animado e prédios com animação. Fonte trocada por Pixel Operator Bold.
- Cupons de teste: TESTARTUDO, AURAS e PEDRAS.
- Ajustes pedidos: aura mais alta (atrás da cabeça e ombros) e mais viva; auras só fora das lutas e arma nas costas só nas lutas; habilidades 1–9 com os ícones e o item POW máx do DDTank; fortalecer aumenta também os atributos do item.

## 0.4: fluxo DDTank
Implementadas as telas da referência: Cidade, Salão de Jogos, Sala, Partida e Resultado com cartas, mais a Mochila adaptada. O combate foi refeito no estilo DDTank: mapas maiores com câmera e minimapa, equipes até 4v4 com bots, ordem por Delay, energia 240, itens 1–8, ferramentas Z/X/C compradas na sala, POW por arma, avião de papel, PASS, Confiar, inclinação do terreno e barra de força com uma nova tentativa. O PvE do Templo do Sol virou a Instância, com 4 dificuldades e grupo de até 4.

Balanceamento medido com partidas automáticas: 1v1 ≈ 10 turnos, 2v2 ≈ 23, 4v4 ≈ 38.

Arte PixelLab da 0.4 gerada e integrada: cidade e prédios, VS, ícones, seis bots e a pose deitada de batalha (com respirar e rastejar) para os oito personagens. Detalhes em `PIXELLAB_0_4.md`.

## PvE 0.2
Cidade e templo PixelLab, chefe Rei Hélio com IA, fúria e três animações de quadros.

## Protótipo 0.1
Fundação Godot e combate local: física, vento, destruição, queda, turnos, vitória e perfil local.

## Regra de identidade
Uma conta corresponde a um personagem. Sem lista de personagens nem troca. No futuro banco, `characters.account_id` terá restrição UNIQUE; criação de conta e personagem será transacional.

## Próxima entrega
1. Slots de rosto e olhos, mais roupas e novos cenários de batalha no PixelLab.
2. PET, Leilão e missões.
3. Backend Go com protocolo versionado, autenticação e salas reais substituindo `LobbyDirectory`; PostgreSQL como autoridade de progresso e economia.
