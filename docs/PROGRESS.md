# Progresso

## Atual — 0.7: sons, POW, habilidades e tracejado
- **Som de disparo próprio para cada uma das 12 armas** (tijolo girando, bola de fogo, canhão com arpejo mágico, shuriken e vento, maçã com apito, cápsula com sino de cura, TV com chiado, orbe elétrico com trovão, desentupidor com "plop" e bolhas, mugido do touro, bumerangue girando com sininhos, lança de bronze) e uma camada de impacto por arma; explosões em três tamanhos.
- **Músicas épicas** em loop: tema heroico da entrada/cidade/salas, tema de batalha (taikos e cordas galopando) e tema sombrio da Instância (coro, alaúde e escala "egípcia"). Fanfarra de vitória e tema de derrota. Tecla **M** e botões na pausa ligam/desligam música e efeitos.
- **Consumir habilidade como no DDTank**: ícone da habilidade salta sobre a cabeça de quem usou (você ou bots), mostra o nome e mergulha no personagem, que brilha na cor da habilidade. Vale para 1–9, ferramentas, item auxiliar, avião e POW.
- **POW novo**: aura de fogo dourado enquanto está armado; no disparo, estouro em quadrinho "POW!" com o nome do especial, linhas de velocidade, coluna de luz, ondas de choque, zoom e tremor; projétil com halo dourado.
- **Tracejado**: linha branca tracejada ao longo de todo o voo; a do seu último tiro fica no mapa até o próximo para corrigir a mira. Rastro brilhante sob o efeito de cada arma.
- Sons da interface (clique, confirmar, erro, moedas, forja, cartas), tique dos 3 últimos segundos, "sua vez", crítico e queda de personagem.

## 0.6: qualidade da arte
- Nova **tela de entrada** (arte, logotipo com brilho, escolha de servidor e ENTRAR) antes da cidade.
- **Cidade** refeita em 640×360 (2× exato) com o Salão de Jogos no centro e seis prédios novos em 1× nos lotes, incluindo a Casa dos Mascotes.
- **Mapas**: fundos novos em 680×380 (2×) com leve paralaxe e o **chão pintado** como no DDTank (a pintura é a colisão); clima por mapa (neve, brasas, poeira de luz, pólen).
- **Armas** redesenhadas em 96×96 com o mesmo visual e mais detalhe; tiers +9/+10/+12 refeitos.
- **Efeitos**: explosão animada com clarão, onda de choque, fumaça e estilhaços do chão; cratera com borda queimada; brilho de POW.
- **Cartas de recompensa** novas (verso e quatro raridades) e miniaturas reais dos mapas na escolha de local.
- Pixels iguais em qualquer escala: shader de amostragem nítida nos ícones, na interface e nos personagens (inclusive deitados na partida).

## 0.5: armas, visual e Ferreiro
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
1. Slots de rosto e olhos e mais roupas no PixelLab; mais mapas seguindo a receita de `PIXELLAB_0_6.md`.
2. PET, Leilão e missões.
3. Backend Go com protocolo versionado, autenticação e salas reais substituindo `LobbyDirectory`; PostgreSQL como autoridade de progresso e economia.
