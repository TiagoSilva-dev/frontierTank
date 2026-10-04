# Desafio do Dia, replays e espectador (0.22)

Três peças que nascem da mesma ideia: como a simulação é **determinística** e só as intenções dos jogadores cruzam a rede (lockstep), uma batalha inteira é a sua **configuração** (mapa, semente, lutadores) mais a **lista de intenções com o tick de cada uma**. Isso dá, quase de graça, gravação, reprodução, conferência no servidor e transmissão ao vivo.

## Replays (`Replay`, `ReplayRunner`, `ReplayDriver`)

- **Formato** (`client/systems/replay.gd`): `{v, content, config, inputs: [[tick, lutador, ação, dados]...], ticks, winner, meta}`. A `config` é a que todas as cópias rodaram (semente e `lockstep` incluídos). `Replay.clean` valida a estrutura, limpa cada intenção (ação conhecida, só valores simples, as chaves de sempre) e **mantém a ordem das intenções do mesmo tick** (o `sort_custom` do GDScript não é estável, e `aim` antes de `charge` importa: já derrubou um replay na hora de escrever os testes).
- **Gravação no cliente**: o `LockstepDriver` guarda cada intenção que recebe (`history`); ao fim de uma batalha online de PvP (comum ou ranqueada) a `BattleScreen` salva o replay em `user://replays/` (as 12 últimas). O Desafio do Dia também grava o seu.
- **Reprodução**: `main.start_replay` abre uma `BattleScreen` em modo replay: `LocalMatch.spectator` (ninguém toma os controles, o teclado e a HUD ficam mudos), um `ReplayDriver` alimenta as intenções nos ticks certos e a `ReplayBar` dá PAUSAR, 1x/2x/4x, uma barra de progresso e SAIR. Nada é pago nem gravado no perfil.
- **Conferência** (`ReplayRunner`): roda um replay numa `LocalMatch` sem tela, em fatias de ticks (o servidor de jogo faz 250 por quadro para continuar atendendo os outros). Os testes provam que o replay chega ao **mesmo `checksum_text`**, posição por posição, e que mudar um tiro muda a batalha.
- **Onde assistir**: tela do Desafio → aba **REPLAYS** (as gravações locais, com ASSISTIR e APAGAR).

## Espectador ao vivo

- No Salão, clicar numa sala **em jogo** de PvP oferece **ASSISTIR**; na tela da Liga Ranqueada, a aba **AO VIVO** lista as partidas ranqueadas em andamento.
- **Servidor** (`MatchHost`): quem assiste recebe o mesmo fluxo de ticks dos jogadores, **atrasado** (20 s nas ranqueadas, 3 s nas outras: a transmissão não ajuda quem joga). Ao entrar, recebe a configuração e o histórico até o ponto que já foi liberado (`add_watcher`); depois, as mensagens `ticks` na hora certa (`deliver_watch`). No fim da partida recebe o que faltava de uma vez. Até 12 espectadores por partida; um jogador não assiste a própria batalha, nem enquanto está na fila ou numa sala.
- **Cliente**: a mesma `BattleScreen` online (`config.spectate`): `spectator` ligado, barra "AO VIVO", sem Confiar; ao terminar mostra o resultado e volta ao Salão. Nada é pago.

## Desafio do Dia (`Challenge`, `shared/balance/challenge.json`)

- **O mesmo duelo para todos, todo dia (UTC)**: a semente, o mapa PvP, a arma e o tipo de desafio saem do número do dia (`Challenge.spec_for`, `day_id` conta a partir de `epoch`). Ninguém usa o próprio equipamento: todos jogam com a arma do dia (Excelente +3), nível 10 e sem atributos extras. Tipos (`kinds`): **Tiro ao Alvo** (3 alvos em 6 turnos), **Duelo Relâmpago** (vencer o Rival do Dia, uma IA, em 10 turnos) e **Alvo Distante** (um alvo resistente, 5 turnos).
- **Pontuação** (`Challenge.score`, função pura do estado final): alvos derrubados, turnos que sobram, vida que sobra e dano; três medalhas por tipo (Bronze, Prata, Ouro).
- **Regras na simulação** (`LocalMatch`): `max_turns` (a partida acaba quando o desafiante joga o último turno; quem sobrou vence) e `totem_goal` (só termina quando todos os alvos caem). Os testes calibram as medalhas com o solucionador de tiro da IA, que joga sem erro.
- **Como roda**: uma batalha local em lockstep (`config.hosted`): um `LocalHost` faz o papel do servidor (carimba as intenções no tick e grava), e a IA (Confiar) e os emotes ficam recusados. Sair antes do fim não pontua.
- **Online, o servidor confere** (`GameServer.challenge_submit`): recebe só o replay, **refaz o desafio do dia a partir da própria configuração** (nada do que o jogador mandou na `config` vale), roda as intenções e pontua o resultado. Recusa dia errado, intenções que não sejam do desafiante, IA, replay inválido ou que não termina. Uma conferência por vez. A API (`server/api/challenge.go`, tabela `challenge_scores`, migração 007) guarda o melhor de cada jogador no dia com o replay daquela partida; o ranking do dia (`challenge_info`) e os replays dos melhores (`challenge_replay`, botão ASSISTIR) saem dali. Fica 30 dias.
- **Recompensa**: o primeiro resultado do dia paga 150 moedas e 100 EXP (`PlayerProfile.challenge_done`, que o servidor chama depois de conferir e o jogo offline chama pelo próprio placar); melhorar o resultado do dia não paga de novo. O desafio também move os contratos "Desafio do Dia" (diário) e "Constância" (semanal).
- **Offline** dá para jogar (o placar fica no perfil); o ranking e os replays dos outros só existem online.

## Testes

- `tests/replay_tests.gd` (35): intenções válidas e inválidas, ordem dentro do tick, duelo roteirizado, o replay dá o mesmo estado, fatias, arquivos, e a tela de replay (controles mudos, 4x, pausa, mesmo resultado, volta ao Salão).
- `tests/challenge_tests.gd` (41): dados, a definição do dia, os três tipos jogados pelo solucionador (e a pontuação igual no replay), o limite de turnos, ações recusadas, recompensa uma vez por dia e o desafio jogado de verdade pela `BattleScreen` com o cartão de resultado.
- `net_e2e_tests.gd`: o servidor refaz o replay e dá a mesma pontuação, paga uma vez, recusa trapaças, lista o dia, entrega o replay do melhor, dia seguinte; e três jogadores num ranqueado (o espectador acompanha, chega ao mesmo resultado, sem drift, e volta ao Salão).
- `server/api/challenge_test.go`: melhor pontuação por dia, ranking, replay do melhor, exportação LGPD e a limpeza dos dias velhos.

## Em aberto

- As medalhas e o atraso da transmissão são pontos de partida (calibrados com a IA, não com gente).
- Os replays só gravam partidas online de PvP e desafios; as partidas offline contra bots e as instâncias não são lockstep.
- Não há compartilhamento de replay por link.
