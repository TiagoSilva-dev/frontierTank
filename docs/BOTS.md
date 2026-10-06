# Jogadores simulados (bots)

Antes do lançamento o Salão online fica vazio e quem chega acha que o jogo está morto. Os jogadores simulados dão vida ao Salão e às partidas sem enganar ninguém sobre o que vale de verdade: nome de gente, jogo melhor ou pior conforme o nível, e um teste de carga que mostra quantas batalhas o servidor aguenta.

## O que existe

| Peça | Onde | O que faz |
|---|---|---|
| Apelidos | `client/systems/bot_roster.gd` + `shared/balance/bot_names.json` | Nomes de pessoa (`Lucas07`, `xBruna`, `Fenix_SP`, `Gabi_BR`...), com as mesmas regras de um jogador (2–14 caracteres, letras, números, `_ - .`). Nunca contêm `bot`, `cpu`, `npc`, `robo`, `_ia` e afins, nem uma palavra que o filtro do chat esconde. Sem repetir dentro da lista. Mais nomes: é só acrescentar ao JSON. |
| Habilidade | `BotRoster.skill_for`, `LocalMatch.plan_ai`, `combat.json` → `bots.skill` | Cada simulado tem `skill` de 0 a 1 (cresce com o nível, com sorteio em volta). Quanto maior: pensa mais rápido, erra menos a força e o ângulo, lê melhor o vento, escolhe melhor a presa e usa mais itens. Os números são `[novato, craque]` e a habilidade mistura os dois. Quem não tem `skill` (treino, desafio diário, jogador que perdeu a conexão) joga como antes, com as mesmas chamadas ao `rng`. |
| População do Salão | `GameServer.lobby_snapshot`, `simulated_people`, `simulate_population` | O Salão mostra `POPULATION` pessoas (padrão 36), jogadores reais incluídos. Com ninguém online são 36 simulados e 14 salas; chegaram 5 jogadores, são 5 reais e 31 simulados; a partir de 36 reais não há nenhum. Eles entram e saem sozinhos (um a cada 20–60 s) e as salas que esperam abrem e fecham. As partidas são outra peça (abaixo). O contador de "online" continua o número real. |
| Partidas de bots | `server/game/bot_arena.gd` (`BotArena`), `GameServer.simulate_population`, `lobby_snapshot` | O servidor mantém `BOT_BATTLES` partidas de verdade entre os simulados (padrão 6: 4 PvP e 2 PvE). Aparecem no Salão como salas em jogo; as de PvP têm **ASSISTIR**. Ver a seção abaixo. |
| Entrar numa sala simulada | `GameServer.room_join`, `adopt_sim_room` | Clicar numa sala simulada (ou em **Jogar**) cria uma sala de verdade com os mesmos jogadores e o visitante como dono; o Salão ganha outra sala simulada no lugar. Uma sala simulada "em jogo" não abre. |
| Rivais da partida | `GameServer.start_pvp`, `LobbyDirectory.bot_near` | Sem rival de verdade depois de `BOT_FILL_SECONDS`, os rivais saem da mesma lista (nível parecido, sem repetir nome, com `skill`). |
| Perfil | `GameServer.player_profile`, `PlayerProfileDialog` | Abre como o de qualquer jogador (visual, arma, atributos, vitórias) e traz a nota "Personagem controlado pela IA do jogo.". Não há mensagem privada nem amizade com eles. |

## Partidas de bots

O Salão não mostra só nomes: o servidor roda partidas de verdade entre os simulados, para o canal parecer vivo.

- **PvP**: duas equipes de 1 a 4 (mesmo nível, mapa sorteado pela semente da partida), cada uma numa sala "em jogo" no Salão, com o botão **ASSISTIR** (o mesmo espectador das salas de jogadores: transmissão com 3 s de atraso, até 12 espectadores). Nas medições, as partidas duram em média uns 4 minutos (PvP e PvE juntos).
- **PvE**: um grupo de 1 a 4 numa das cinco instâncias (nível do mapa = nível ÷ 3), jogando as três fases. A sala aparece "em jogo" com o nome da instância, **sem** ASSISTIR: o espectador só acompanha uma fase, e o grupo muda de fase sozinho (3,5 a 8 minutos de jogo; nas medições o grupo vence em 14 de 15 tentativas).
- **Quem joga** são os mesmos nomes da lista de jogadores, nunca em duas partidas ao mesmo tempo, e as salas ganham números que não repetem os de salas reais nem os das salas que esperam. Entrar numa sala em batalha dá "A sala está em batalha".
- **Ninguém está nos controles**: o `MatchHost` roda a partida com a IA de habilidade em cada lutador e fecha sem pagar a ninguém (não há conta, EXP, carta nem ranking). Quando termina, as salas saem do Salão e, passados 3 a 10 s, outra começa.
- **Somem com a chegada de gente de verdade**: o número de partidas segue a mesma conta da lista (`BOT_BATTLES × (POPULATION − reais) ÷ POPULATION`). Com 18 jogadores de verdade de 36, ficam 3 (2 PvP e 1 PvE); a partir de 36, nenhuma começa e as que estavam acabam sozinhas em alguns minutos.
- **Não atrapalham quem joga**: uma partida só começa se o quadro de física do servidor estiver abaixo de 10 ms (`BotArena.LOAD_LIMIT`), e uma por vez, com 2 a 8 s entre elas.

### Desligar

| Quero | Faço |
|---|---|
| Parar só as partidas, mantendo a lista e as salas | `BOT_BATTLES=0` |
| Desligar os bots por inteiro (lista, salas e partidas) | `POPULATION=0` |
| Deixar sumirem sozinhos | nada: a lista e as partidas já diminuem a cada jogador que entra |

Mudar a variável pede reiniciar o servidor de jogo (na Railway, aplicar a variável reimplanta o serviço, e quem está jogando reconecta); as partidas de bots recomeçam do zero.

### Custo medido

Uma hora de jogo virtual com o servidor de verdade (36 pessoas, 6 partidas, 85 partidas iniciadas e encerradas):

- 1,3% de um núcleo em média (0,21 ms por tick de todas as partidas juntas); o pior tick foi de 30 ms, o plano de tiro de um ou dois bots no mesmo instante (ver abaixo).
- Memória estável (~150 MB no total, +55 MB das partidas) e nós estáveis (350 a 550): sem vazamento.
- **Construir uma partida custa 20 a 60 ms** num único quadro (o terreno e a simulação inicial). Acontece uma vez a cada ~40 s com o canal cheio e uma vez por segundo no primeiro minuto, enquanto as 6 sobem. Se algum dia incomodar, o caminho é o mesmo do plano de tiro: espalhar o trabalho por vários quadros.

## O que não foi feito, de propósito

- **Sem chat nem alto-falante falsos online.** No modo offline o canal simula conversa e anúncios (e avisa que é simulado). Online, uma linha de chat ou um "Fulano ganhou um Cristal Dourado" inventados seriam mentira dita a gente de verdade, que pode responder, comprar ou vender achando que há alguém do outro lado.
- **O contador de online é o real**, e a **Ranqueada, o ranking, o desafio diário, o Leilão, o Câmbio, o Correio e a lista de amigos nunca têm simulados** (eles não têm conta).
- Os termos de uso (`legal/terms_*.md`) não falam de jogadores controlados pela IA. Vale uma frase como "salas e partidas podem incluir personagens controlados pela IA do jogo". Mudar o texto exige subir `LEGAL_VERSION` (todo mundo aceita de novo), por isso não mexi.
- Quem olha com atenção percebe: o perfil diz que é IA, o nome de um jogador de verdade aparece em dourado na sala e o espaço vazio da sala oferece "um jogador de IA". Para esconder mais que isso, o preço é enganar o jogador; decida com isso na mesa.

## Ajuste

| Quero | Mexo em |
|---|---|
| Mais ou menos gente no Salão | `POPULATION` (variável de ambiente `FT_POPULATION`, `--population`); `0` desliga |
| Bots mais fáceis ou mais difíceis | `combat.json` → `bots.skill` (`[novato, craque]` de `think`, `power_error`, `angle_error`, `wind_misread`, `blunder`, `item_chance`) |
| Esperar menos por um rival | `BOT_FILL_SECONDS` (padrão 20) |
| Mais nomes | `shared/balance/bot_names.json` |
| Mais ou menos partidas de bots | `BOT_BATTLES` (variável de ambiente `FT_BOT_BATTLES`, `--bot-battles`; no máximo 40; um terço é PvE); `0` desliga só as partidas |

`combat.json` entra no hash de conteúdo: depois de mudar um número, reimplante servidor e cliente juntos.

Quanto vale a habilidade (duelos 1v1 de IA contra IA, mesmo nível e arma, 48 partidas por linha, lados trocados): a de 0,9 vence a de 0,5 em 67%, a de 0,25 em 77% e a de 0,1 em 88%. É uma diferença que se sente e que não decide sozinha, por causa do vento e do terreno.

## Teste de carga

```bash
godot --headless --path . --script tests/bot_load.gd -- --pvp=40 --pve=20 --seconds=300
# --watchers=N (espectadores por batalha PvP, 4), --seed, --level (nível fixo dos bots)
```

Sobe um `GameServer` de verdade (API em memória) e roda batalhas só de simulados, PvP de 1 a 4 de cada lado e grupos de PvE nas cinco instâncias. O tempo é virtual: cada varredura avança todas as batalhas um tick de 60 Hz com o mesmo `MatchHost` do servidor, e o tempo gasto na varredura é o que a CPU pagaria. Abaixo de 16,7 ms o servidor acompanha 60 ticks por segundo. Quando uma batalha termina outra começa, então a carga fica igual o tempo todo. Não faz parte da suíte (os números dependem da máquina). Imprime média, p95, p99, pior tick, carga de um núcleo, custo por batalha, memória e nós a cada minuto, e uma linha `LOAD {json}`.

Medido em 06/10/2026 (AMD Ryzen 5 5600, um núcleo; o servidor de jogo do Godot roda numa thread só), 4 espectadores por batalha PvP:

| Batalhas ao mesmo tempo | Tick médio | p95 | p99 | Pior | Ticks acima de 16,7 ms | Memória |
|---|---|---|---|---|---|---|
| 60 (40 PvP + 20 PvE) | 2,5 ms | 7,0 | 14,0 | 38 | 0,6% | 440 MB |
| 150 (100 + 50) | 6,4 ms | 13,9 | 21,4 | 34 | 2,7% | 910 MB |
| 300 (200 + 100) | 13,9 ms | 25,2 | 33,2 | 53 | 25,6% | 1,7 GB |

- **Custo médio**: 0,047 ms por batalha PvP e 0,033 por batalha PvE a cada tick, ou seja, cerca de 2,6 ms de CPU por batalha por segundo. Um núcleo a 70% de carga segura umas 250 batalhas.
- **Os picos vêm do plano do bot**: `EnemyAI.choose_shot` simula mais de 300 trajetórias e leva 3 a 8 ms (média de 6) uma vez por turno de bot. Com poucas batalhas passa despercebido; a partir de ~150 simultâneas dois planos no mesmo tick estouram o orçamento. Se esse dia chegar, o caminho é espalhar a busca pelos ticks do tempo de "pensar" do bot (1–3 s), contando candidatos por tick, nunca o relógio, para continuar determinístico.
- **Memória**: ~6 MB por batalha em andamento (a máscara de terreno de cada mapa é a maior parte). Estável: 5 minutos de rodízio de partidas não aumentaram nós nem memória.
- **Tráfego**: ~1 KB/s por jogador ou espectador (as mensagens `ticks`).
- **O servidor tem capacidade para 500 contas** (`GAME_CAPACITY`). Mesmo todos em 4v4 seriam ~125 batalhas, uns 40% de um núcleo.

Isto mede a simulação. Não entram os sockets e o JSON dos jogadores de verdade, nem a API e o banco, nem o desenho no cliente (esse está em `--bench=` e `F3`, `PerfProbe`). Antes de um pico de lançamento vale um teste com clientes de verdade pelo WebSocket.

## Testes

`tests/bot_tests.gd` (apelidos, habilidade, a IA aposta melhor com habilidade maior, duas cópias da mesma partida ficam idênticas) e `tests/population_tests.gd` (Salão, desaparecimento conforme chegam jogadores reais, entrar numa sala simulada, rivais, perfil). Os dois entram na suíte (`tools/test.sh`).
