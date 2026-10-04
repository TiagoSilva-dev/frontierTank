# Liga ranqueada (0.22)

Partidas **1 contra 1 entre jogadores reais**, com um rating por temporada, divisões e títulos cosméticos. Só online; nunca completa com bots. Código em `client/systems/ranked.gd` (regras puras), `server/game/game_server.gd` e `match_host.gd` (fila, partida, rating), `server/api/ladder.go` (a lista dos melhores) e `client/ui/ranked_screen.gd`, `rank_badge.gd` (telas). Números em `shared/balance/ranked.json`, que entra no hash de conteúdo (`NetClient.content_version`): mudou um número, reimplante o servidor.

## Como se joga

1. No Salão, **LIGA RANQUEADA** abre a tela da liga: o emblema da divisão, os pontos, o tempo que falta para a temporada acabar, os melhores da temporada e os títulos.
2. **BUSCAR PARTIDA** põe o jogador na fila (nível 3 ou mais, fora de salas e de batalhas). O servidor une dois jogadores de rating parecido: a janela começa em ±120 pontos e abre 30 a cada 10 s de espera (até ±900). A mesma dupla só se enfrenta 3 vezes por hora (anti combinação de resultados).
3. A partida é 1v1 de 15 s por turno, em mapa sorteado, com o equipamento de cada um. **Abandonar perde na hora** (o outro vence e ganha os pontos); **3 turnos seguidos estourados pelo relógio** também perdem. Queda de conexão não perde: a IA joga e o jogador pode voltar.
4. No fim, a tela de resultado mostra a linha **RANQUEADA** com os pontos ganhos ou perdidos, a divisão e "SUBIU!" ou "DESCEU".

## Rating e divisões

- **Elo**: começa em 1000, K = 48 nas 10 primeiras partidas da carreira e 32 depois; uma vitória sempre dá pelo menos 1 ponto e uma derrota sempre custa pelo menos 1; o piso é 700.
- **Avaliação**: nas 5 primeiras partidas da temporada o emblema é um escudo cinza com "?" (os pontos já andam; a divisão aparece depois).
- **Divisões** (cada uma com 3 degraus, III o mais baixo e I o mais alto; o Mestre não tem degraus): Bronze 700, Prata 1000, Ouro 1150, Platina 1300, Diamante 1450, Mestre 1600. O emblema é desenhado por código (`RankBadge`): um escudo na cor da divisão, uma estrela com um bico a mais a cada divisão e um ponto por degrau.

## Temporadas e títulos

- **28 dias**, a primeira a partir de **05/10/2026** (`season.epoch`). Ao entrar numa temporada nova, o rating da anterior é arquivado (com pelo menos 5 partidas) e puxado para a metade do caminho até 1000 (reset suave); a avaliação recomeça.
- Cada temporada arquivada dá um **título** da divisão em que terminou ("Ouro · Temporada 1"). É **só visual**: aparece na janela do perfil, na lista da liga e **no lugar da patente** sob o nome do lutador na batalha. Resgata-se na tela da liga (operação `season_claim`) e equipa-se com `title_set`. O perfil guarda os 12 últimos fechamentos.
- Nada na liga vende ou dá poder: só títulos e emblemas.

## O que vive onde

| Peça | O que faz |
|---|---|
| `Ranked` | Divisões, Elo, temporadas (`season_of`, `sync`), títulos. Funções puras do rating e do relógio; `Ranked.clock_offset` deixa os testes mover o relógio. |
| Perfil (v10) | `rating` (`season`, `mmr`, `games`, `wins`, `losses`, `career`, `peak`, `streak`, `log`), `titles` e `title`. **Nenhuma operação muda o rating**: só o servidor, em `MatchHost.settle_ranked`, antes das recompensas (o perfil gravado já vem com o rating novo). As operações `season_claim` e `title_set` só mexem nos títulos. |
| Servidor de jogo | Mensagens `ranked_info` (temporada, relógio, melhores, posição e a fila) e `ranked_queue` (`on`); aviso `ranked_state` (quantos na fila). `ranked_matchmaking` roda a cada segundo junto com a busca de salas. `MatchHost.ranked` guarda o rating de cada um antes da partida; a configuração da partida leva `ranked: true` para todas as cópias (o abandono e os 3 estouros de relógio são regras da simulação, em `LocalMatch.forfeit_fighter`, e valem igual para todas as cópias). Cada resultado vai para a auditoria (`ranked`). |
| API (Go) | `GET /internal/ladder?season=&limit=&account=` (`ladder.go`): consulta sobre o JSON dos perfis (não há tabela nova, então não existe uma segunda cópia que possa discordar); lista quem jogou pelo menos uma partida da temporada, por pontos, vitórias e conta, e devolve a posição de quem perguntou. |
| Cliente | `RankedScreen`, `RankBadge`, o botão no Salão, a linha na tela de resultado, o emblema e o título no perfil de outro jogador. |

## Testes

- `tests/ranked_tests.gd` (60): divisões e degraus, Elo, avaliação, piso, promoção, temporadas (arquivo, reset, ausência longa, limite do histórico), títulos nos dois idiomas, operações do perfil, salvamento v10 e leitura de v9, placa do lutador, abandono e estouros de relógio na simulação.
- `tests/net_e2e_tests.gd` (`ranked_tests`): fila com nível mínimo, uma partida entre dois jogadores de verdade com os pontos nos dois perfis e nos espelhos, a linha na tela de resultado, a lista dos melhores, abandono (quem ficou ganha, quem saiu perde), o limite de reencontros, a tela da liga (fila e cancelamento) e o fim de uma temporada com o título resgatado.
- `server/api/ladder_test.go`: ordem, posição, outras temporadas e ratings quebrados (PostgreSQL descartável em `TEST_DATABASE_URL`).

## Em aberto

- Os números (K, janela da fila, divisões, 28 dias) são pontos de partida: faltam partidas de verdade. O que mais pode pedir ajuste é a janela da fila com pouca gente online.
- Sem ligas por região nem fila de equipes (2v2): só 1v1.
- Os títulos são o único prêmio; outros cosméticos (moldura de nome, emblema na batalha) cabem em `titles` no mesmo formato.
