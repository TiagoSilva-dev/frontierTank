# Frontier Tank: Nova Era

## Entrega 0.4 — fluxo DDTank
Cidade → Salão de Jogos → Sala → Partida → Resultado → Cartas, contra bots. Combate por equipes (até 4v4) com ordem por Delay, energia 240 por turno, itens 1–8, ferramentas Z/X/C, POW por arma, avião de papel, PASS e Confiar. Instância do Templo do Sol com 4 dificuldades. Regras, fontes e interpretações em `docs/DDTANK_RESEARCH.md`; números em `shared/balance/combat.json`. As seções abaixo descrevem a entrega 0.1 e ficam como histórico.

## Entrega 0.1 — duelo na Ilha Celeste
Dois jogadores compartilham teclado ou mouse, alternando turnos de 20 segundos. Cada um começa com 150 PV, uma cura e um escudo. Vence quem eliminar o rival por dano ou queda. Empate se ambos caírem no mesmo impacto.

Mover custa a reserva do turno. Ângulo de 10 a 85 graus, orientação independente e potência carregada ao segurar espaço ou DISPARAR. Vento muda entre turnos. A previsão mostra somente o começo da trajetória; acertar à distância exige estimar potência e vento.

As cinco armas estão disponíveis desde a preparação. Alteram dano e raio da cratera; propriedades especiais de gelo/fogo ainda não fazem parte do protótipo. Mascotes são acompanhantes visuais. Não há economia ou conta simulada.

## Controles
A/D ou setas horizontais: andar. W/S ou setas verticais: ângulo. Q: inverter mira. Espaço: segurar e soltar para disparar. Esc: pausar. Controles equivalentes na interface. Cura e escudo podem ser usados uma vez por jogador, antes de carregar o tiro.

## Etapas seguintes
1. Validar diversão e balanceamento deste duelo local.
2. Servidor Go autoritativo, contrato versionado, autenticação e salas 1v1.
3. Persistência PostgreSQL, inventário, progressão e ferreiro transacional.
4. Campanha, mascotes com habilidades, grupos e ranqueamento.

Entrega atual não representa o jogo comercial completo descrito no documento de referência.

## 0.5 — Equipamento, armas e Ferreiro
- **Visual**: o personagem começa de camiseta e shorts. Slots visuais Roupa, Chapéu, Óculos, Cabelo e Asas; a arma equipada fica nas costas. Roupas são do gênero do personagem.
- **Armas**: 9 clássicas (Quebra Tijolos, Fogo Intenso, Canhão Arco-Íris, Vento de Deus, Cesto de Frutas de Newton, Kit Médico, Eletrodoméstico, Trovão, Desentupidor) em Normal, Excelente e Verdadeira, com ângulos dos guias do DDTank; 3 Super Verdadeiras (Cabeça de Boi, Bumerangue do Amor, Lança) só por drop da Instância. Cada arma tem projétil e POW próprios.
- **Fortalecimento** +1 a +12 com pedras (1, 5, 15, 35, 70, 150, 230, 330, 450, 600, 750 e 900 pontos por nível). Cada nível: mais dano na arma e +10% dos atributos do item. O ícone evolui no +9, +10 e +12. Aura da arma (atrás da cabeça e dos ombros): +1–5 verde, +6–8 azul, +9–11 roxa, +12 vermelha; a roupa fortalecida tem aura própria. Auras só fora das lutas; a arma nas costas só nas lutas.
- **Habilidades 1–9** como no DDTank: +2 ataques, três bolas (x3), +1 ataque, POW 50/40/30/20/10% de dano e POW máx (enche a barra de POW). Fusão (4 pedras → 1 do nível seguinte), Transferência e Composição (Cristal Dourado, +10 num atributo, até 5 vezes).
- **Atributos**: Ataque aumenta o dano, Defesa reduz o dano recebido, Agilidade reduz o Delay e dá energia, Sorte dá crítico (x1,5).
- **Auxiliar (V)**: Dom de Anjo cura; escudos reduzem o próximo dano; usos limitados por partida.
- **Cupons** para teste: TESTARTUDO, AURAS, PEDRAS.
