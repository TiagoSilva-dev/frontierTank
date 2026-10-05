# Contratos: Primeiros passos, diários, semanais e sequência (0.21–0.22)

A tela **MISSÃO** (botão da barra e o prédio da cidade) tem quatro abas. Os números e as listas ficam em `shared/balance/missions.json` (versão 3); as regras em `client/systems/missions.gd` (`MissionsBoard`); a tela em `client/ui/mission_screen.gd`. O estado vai em `profile.missions` e muda só pela porta única do perfil (`mission_claim` e `streak_claim` em `PlayerProfile.OPS`), então offline e online usam o mesmo código e o servidor de jogo decide o que vale.

| Aba | O que é | Renovação |
|---|---|---|
| **Primeiros passos** | Checklist único de 6 passos para personagem novo (primeira batalha, primeira vitória, Ferreiro, instância, Caçada…) + bônus de 500 moedas e 300 EXP ao concluir tudo. | Nunca. Um save anterior ao v9 recebe crédito pelo que o personagem já fez (`credit_history`). |
| **Diários** | 5 contratos sorteados de um pool de 16, no máximo 2 da mesma categoria; bônus de 300 moedas e 250 EXP ao resgatar os cinco. | Todo dia à 00:00 UTC. |
| **Semanais** | 3 contratos de um pool de 9, metas e prêmios maiores; bônus de 900 moedas, 700 EXP e uma Pedra de Fortalecimento nível 2 ao resgatar os três. | Segunda a domingo, UTC. |
| **Sequência** | Resgate uma vez por dia; dias seguidos sobem uma escada de 7 prêmios (a do dia 7 traz Pedras de Fortalecimento) e ela se repete. | Perder um dia zera a contagem; o recorde fica guardado. |

## Como o sorteio funciona

`MissionsBoard.draw(kind, seed)` embaralha o pool com um gerador semeado pelo **dia** (ou pela **semana**), então todos os jogadores recebem os mesmos contratos no mesmo dia, sem o servidor sortear nada. A mistura respeita `per_category` (pvp, pve, general, pets, forge, economy, challenge, ranked). Um perfil **offline** não recebe contratos marcados `"online": true` (hoje a Liga ranqueada, diário e semanal).

Categorias do pool diário: PvP (vitórias, partidas), geral (dano, abates, usos de POW), PvE (expedição, chefe do Rei Hélio, qualquer chefe), mascotes (coletar a Caçada), Forja (fortalecer, fabricar), economia (comprar), Desafio do Dia e Liga.

## Como o progresso conta

Cada contrato espera um **evento** (`pvp_win`, `pvp_played`, `damage`, `kills`, `pow_uses`, `expedition_win`, `boss_any`, `boss:<id>`, `hunt`, `hunt_collect`, `strengthen`, `craft`, `buy`, `challenge`, `ranked_played`, ...). O mesmo evento anda **todas** as trilhas que têm um contrato para ele (um PvP vencido conta para o diário e o semanal ao mesmo tempo). Os eventos vêm de dois lugares, os dois rodando o mesmo código no cliente e no servidor:

- `progress_match`: no fim da partida liquidada (dano, abates, POW, vitória, chefes);
- `note_op`: depois de cada operação do perfil que muda o estado (Caçada, fortalecer, fabricar...).

O emblema com o número no botão MISSÃO soma os contratos prontos para resgatar e a recompensa da sequência quando ela está esperando (`MissionsBoard.claimable`).

## Compatibilidade

O save v6 criou os diários e o v9 o checklist inicial; os semanais e a sequência (0.22) moram dentro de `missions` e `MissionsBoard.clean_state` completa o que faltar em saves antigos, sem perder nada. Os testes movem o relógio com `MissionsBoard.clock_offset`.

## Testes e capturas

`tests/mission_tests.gd` (88 verificações): sorteio determinístico e sem repetição por categoria, virada do dia e da semana (domingo → segunda), escada da sequência (continuar, perder um dia, repetir no dia 8), resgate duplo recusado, bônus, eventos de mascote, Caçada, Desafio e Liga, e a leitura de saves antigos. Capturas: `--screen=missions [--tab=daily|weekly|streak]`.

## Em aberto

- Os prêmios são pontos de partida: falta ver no jogo se 5 diários + semanais dão ritmo ou sobrecarga.
- Não há contrato de Leilão nem de Câmbio (de propósito: só entram quando as duas economias tiverem jogadores).
- Fim de semana com prêmio dobrado e contratos sazonais da Liga ainda não existem.
