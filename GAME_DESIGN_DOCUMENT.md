# Gustfire (antes Frontier Tank: Nova Era)

> **Este documento é o histórico das decisões de design por entrega** (as seções mais antigas descrevem o duelo da 0.1 e ficam como registro). O estado atual do jogo está em `README.md` (o que o jogador vê), `ARCHITECTURE.md` (como é feito), `docs/PROGRESS.md` (o que mudou em cada versão) e `docs/ROADMAP.md` (decisões e o que falta).

## Entrega 0.22 — treino e primeiros passos
Quem cria um personagem faz um **treino de artilharia** guiado (andar, mirar, vento, força, habilidades e POW contra um Boneco de Treino) e segue um roteiro de seis **Primeiros passos** com recompensas, na aba nova da MISSÃO. A ideia é que ninguém precise ler a wiki para jogar a primeira partida. Regras e números em `shared/balance/tutorial.json`, `missions.json` e `combat.json` (`tutorial`, `boneco_treino`).

## Entregas 0.19 a 0.21 — mascotes e Caçada
A **Casa dos Mascotes** guarda uma coleção de 20 espécies (5 elementos × 4 raridades) que acompanham o lutador **só como aparência**: desde a 0.30 os mascotes são vendidos na loja por dinheiro (de R$ 14,90 a R$ 59,90 pela raridade), não dão atributos nem habilidade e não há ovos nem sorteio pago. Comuns e Raros também podem cair de chefes e ser capturados na **Caçada**, um modo automático, tipo idle, em que um time de até 5 mascotes luta sozinho (até 2 h acumuladas, 8 h com o Passe do Caçador) e o jogador coleta moedas, XP e capturas; é o único lugar onde o mascote sobe de nível. Regras em `docs/PETS.md` e `docs/PET_HUNT.md`.

## Idiomas (roadmap 4.3)
Português e inglês desde já, com versão própria dos nomes em cada idioma. O português é o idioma-fonte; o inglês fica em `locale/en.po`. Detalhes no `README.md` (seção Idiomas).

## Entrega 0.12 — Leilão e Correio
O **Leilão** da cidade (online) é onde os jogadores vendem uns para os outros os equipamentos que caíram nas instâncias e os mapas, por **Solares** e/ou **Estrelas**, com compra imediata e anúncios de 12, 24 ou 48 h. Anunciar custa ouro e a venda paga 5% de comissão: as duas saídas seguram a inflação das moedas. O item fica guardado no servidor enquanto está à venda e o pagamento chega pelo **Correio**. Itens vinculados (Loja, cupons, cópias do Espelho, arma inicial e Super Verdadeiras equipadas) não vão ao leilão. Regras e números em `docs/ROADMAP.md` (item 3.3) e `shared/balance/items.json` (`auction`).

## Entrega 0.10 — atributos aleatórios e moedas
Armas, roupas, chapéus, óculos e asas têm **atributos bônus aleatórios** (Normal 0, Excelente 1–2, Verdadeira 3–4, Super Verdadeira 4) em faixas F1 a F5; as melhores faixas só aparecem em itens de nível alto, e o nível do item é o nível do mapa onde caiu. Sete **moedas** com nomes próprios (Brasa, Coroa, Estrela, Tormenta, Solar, Eclipse e Espelho Celeste) caem nas instâncias e mudam a qualidade e os bônus de itens e mapas na aba **Moedas** do Ferreiro. Usar gasta a moeda: é isso que mantém o valor delas no leilão. Regras e números em `docs/ROADMAP.md` (item 3) e `shared/balance/items.json` (`affixes`, `currencies`).

## Entregas 0.8 e 0.9 — POW e instâncias
POW em fases com impacto próprio por arma, arma e projétil maiores só no desenho. Quatro instâncias de 3 fases (lacaios, guardião ou objetivo, chefão com mecânica própria); a dificuldade vem de **mapas** de nível 1 a 16 com atributos aleatórios, no lugar das dificuldades. Regras e números em `docs/ROADMAP.md` (itens 1 e 2) e `shared/balance/combat.json` (`enemies`, `instances`, `map_items`, `party_scaling`).

## Entrega 0.4 — fluxo DDTank
Cidade → Salão de Jogos → Sala → Partida → Resultado → Cartas, contra bots. Combate por equipes (até 4v4) com ordem por Delay, energia 240 por turno, itens 1–8, ferramentas Z/X/C, POW por arma, avião de papel, PASS e Confiar. Instância do Templo do Sol com 4 dificuldades (substituídas pelos mapas na 0.9). Regras, fontes e interpretações em `docs/DDTANK_RESEARCH.md`; números em `shared/balance/combat.json`. As seções abaixo descrevem a entrega 0.1 e ficam como histórico.

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
- **Armas**: 9 clássicas (Tijolaço, Braseiro, Prisma, Cata-Vento, Pomar, Tônico, Bota-Fora, Para-Raios, Sugador) em Normal, Excelente e Verdadeira, com ângulos dos guias do DDTank; 3 Super Verdadeiras (Super Minotauro, Super Cupido, Super Lança de Jade) só por drop da Instância. Nomes da revisão de identidade (25/09/2026, `docs/ROADMAP.md`, item 4); as ids internas continuam as antigas. Cada arma tem projétil e POW próprios.
- **Fortalecimento** +1 a +12 com pedras (1, 5, 15, 35, 70, 150, 230, 330, 450, 600, 750 e 900 pontos por nível). Cada nível: mais dano na arma e +10% dos atributos do item. O ícone evolui no +9, +10 e +12. Aura da arma (atrás da cabeça e dos ombros): +1–5 verde, +6–8 azul, +9–11 roxa, +12 vermelha; a roupa fortalecida tem aura própria. Auras só fora das lutas; a arma nas costas só nas lutas.
- **Habilidades 1–9** como no DDTank: +2 ataques, três bolas (x3), +1 ataque, POW 50/40/30/20/10% de dano e POW máx (enche a barra de POW). Transferência do nível de fortalecimento. Composição e Fusão do DDTank foram retiradas: os atributos extras dos itens vêm das moedas (Brasa, Coroa, Estrela…) e as pedras de todos os níveis são vendidas na Loja.
- **Atributos**: Ataque aumenta o dano, Defesa reduz o dano recebido, Agilidade reduz o Delay e dá energia, Sorte dá crítico (x1,5).
- **Auxiliar (V)**: Dom de Anjo cura; escudos reduzem o próximo dano; usos limitados por partida.
- **Cupons** para teste: TESTARTUDO, AURAS, PEDRAS.
