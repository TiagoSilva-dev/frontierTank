# Progresso

## Atual — 0.16: instâncias mais difíceis (efeitos de estado, maldições e elites)
- **8 efeitos de estado** vindos das habilidades dos monstros: Queimação, Envenenamento (doses que acumulam e cortam a cura), Congelamento (perde o turno e depois fica imune 1 turno, para ninguém ficar preso), Exaustão (tudo custa 50% mais energia), Selo (sem habilidades 1–9 e POW), Raízes (não anda nem voa), Marca da Caça (+30% de dano recebido, os monstros focam o marcado) e Ofuscamento (vento e linha de mira escondidos). Duram turnos da vítima; o dano por turno bate no começo do turno e todos contam quando o turno termina. Regras em `LocalMatch` (`add_status`, `tick_statuses`, `expire_statuses`), dados em `combat.json` → `statuses`, consultas em `client/systems/status_rules.gd`. A antiga queimadura (`burn`) virou o efeito Queimação.
- **Habilidades**: 30 habilidades dos 16 monstros ganharam efeitos (por tema: sol ofusca, gelo cansa e prende, runas selam, veneno nas picadas) e 4 **maldições** novas (`kind: "hex"`): Julgamento Solar, Riso Maldito, Correntes de Gelo e Grilhões de Ferro. Um mesmo ataque aplica cada efeito uma vez só, mesmo com várias magias caindo.
- **Elites** com 7 afixos (Chamas, Veneno, Gelo, Vampira, Encouraçada, Explosiva, Veloz): +50% de vida, +15% de dano, maiores, aura no chão e o afixo no lugar da patente. Sorteados pelo `InstanceRun` (6% + 2% por nível de mapa; guardião pela metade; nunca o chefe; até 2 por onda). Ameaças novas de mapa: "+X% de inimigos de elite" e "efeitos duram +1 turno".
- **Mais monstros por fase** (fase 1: 2 + 3; reforço na fase do guardião; o chefe vem com um lacaio). Derrubar o chefe vence a fase mesmo com lacaios de pé.
- **Elixir Purificador** (ferramenta nova, 60 moedas): remove todos os efeitos; a IA usa quando os efeitos se acumulam. Vida entre fases 30% → 35%; `pve.ability_damage` 1,15 → 1,08.
- **HUD**: efeitos do jogador ao lado do retrato com turnos/doses e explicação ao passar o mouse; ícones na fila de turnos (e borda na cor do afixo nos elites); correntes sobre as habilidades quando selado; "x1.5" na energia; vento "??" ofuscado; "SUA VEZ!" com o que pesa no turno e "CONGELADO!" quando perde a vez. Sobre os lutadores: chamas, bolhas, cristal de gelo, gotas de suor, anel de runas, raízes, mira, brilhos e a fila de ícones embaixo do nome. Efeitos novos no `MonsterFx`: círculo da maldição, ícone do efeito que salta e entra no alvo, veneno, purificação e a explosão do elite.
- **Barra de força do adversário escondida**: a barra só enche com a força do próprio jogador (antes mostrava a de qualquer um que carregasse). O zumbido de carga dos outros não sobe mais de tom e a aura do POW deles só pulsa, para não entregar a força pelo som ou pela aura (`BattleHUD.visible_force`).
- Sons novos: `status_poison`, `status_seal`, `status_root`, `status_mark`, `status_blind`, `status_exhaust`, `status_hex`, `status_cleanse` (gerados, ainda não ouvidos por um humano).
- Arte: 16 gerações do PixelLab (`docs/PIXELLAB_0_16.md`). Versão **0.16** (cliente e servidor precisam da mesma: a simulação em lockstep mudou).
- **Balanceamento** (`tests/instance_balance.gd`, a IA joga sem poções nem elixir): entrada livre nv6 ~47% (antes ~80%), nv15 ~73% (antes ~93%); mapa nível 5: nv15 ~43% (antes ~80%), nv6 praticamente não vence. Precisa de teste com jogadores.
- Consertado: um brilho do *cut-in* do POW nascia com tamanho zero e gerava "triangulation failed" (aparecia ao voltar para uma batalha online).
- **Testes**: `tests/status_tests.gd` (47) e ajustes em `pve_tests.gd` e `ability_tests.gd`; todas as suítes e `net_e2e_tests.gd` (151) passam.

## 0.15: POW em cut-in, Mochila nova e arma presa nas costas
- **POW épico**: o balão "POW!" virou um *cut-in* de anime. Um corte branco atravessa a tela e se abre numa faixa inclinada nas cores da arma; o retrato do próprio jogador (com roupa, chapéu, óculos, asas e a aura da arma) entra deslizando e sai por cima da faixa; o nome do especial cai letra por letra, em letras grandes com relevo e um brilho que passa; a arte do especial aparece à direita com raios; faíscas e riscos correm pela faixa. No fim a faixa se fecha num corte e o tiro sai. A partida segura o tiro enquanto o *cut-in* toca (`items.json` → `visual.pow_cutin`, 1,15 s; igual em todas as cópias, então o online continua em lockstep). Sons novos `pow_cutin` e `pow_slash`; o som da arma toca quando o especial sai de verdade (`docs/screens/pow_cutin.png`).
- **Mochila nova** (`docs/screens/bag.png`, `bag_card.png`): o personagem fica num pedestal com holofote e estrelas; células quadradas em que a qualidade é um brilho atrás do item (com uma pedrinha da cor no canto) em vez dos quadrados coloridos; marca de equipado; seleção com cantos dourados; ícones nos atributos.
- **Cartão do item ao passar o mouse**: nome e qualidade, tipo, fortalecimento e aura, dano, cratera, ângulo e POW, os quatro atributos com a diferença para o item equipado naquele espaço (verde/vermelho), os bônus com a faixa, nível do item, vínculo e quanto vale na venda. Mapas mostram ameaças (vermelho) e recompensas (verde); moedas, pedras e ferramentas dizem para que servem.
- **Organizar a mochila arrastando**: arrastar um item para uma célula vazia ou trocar com outro (na aba Todos pode deixar espaços; nas outras abas troca na mesma ordem), segurar sobre as setas vira a página, **ORGANIZAR** volta à ordem padrão (armas, visual, auxiliar, moedas, pedras, ferramentas e mapas, o equipado e as melhores primeiro). Itens vendidos deixam o espaço vazio e itens novos ocupam o primeiro espaço vazio. A arrumação fica no perfil (online, pela operação `bag_layout` do servidor, sem registro de auditoria).
- **Equipar arrastando**: soltar um item no personagem ou no espaço dele equipa; arrastar do espaço para a mochila remove; clique duplo ou botão direito também equipam.
- **Arma nas costas**: ela flutuava atrás e acima do personagem na batalha. Agora cada arma é medida (a parte visível da arte) e fica apoiada nas costas, inclinada para as pernas, com a base escondida atrás do corpo (`docs/screens/back_weapons.png`).
- Arte: 13 gerações do PixelLab (`docs/PIXELLAB_0_15.md`). Versão 0.15 (cliente e servidor precisam da mesma).
- **Testes**: `tests/bag_tests.gd` (27, com arrastar de verdade pelo mouse), mais 5 em `pow_tests.gd` (tiro seguro durante o *cut-in*, retrato, todas as armas apoiadas nas costas). `net_e2e_tests.gd` rodado de novo depois da 0.14: 151 verificações.
- **Depois da 0.15 — Composição e Fusão retiradas do Ferreiro**: os atributos extras dos itens vêm só das moedas (Brasa, Coroa, Estrela…); o Ferreiro ficou com Fortalecer, Transferência e Moedas (`docs/screens/smith.png`). As pedras de todos os níveis continuam na Loja. O Cristal Dourado saiu das cartas de recompensa, da Mochila e do cupom TESTARTUDO; saves antigos perdem o bônus de composição e os cristais ao carregar, e as operações `fuse` e `compose` não existem mais (nem no servidor).

- **Depois da 0.15 — HUD da batalha novo** (`docs/screens/battle.png`, `battle_armed.png`, `battle_victory.png`, `battle_defeat.png`, `pve_battle.png`): a interface da partida ficou no nível do *cut-in* do POW. Tudo com molduras de bronze com rebites, vidro escuro e as letras em relevo do *cut-in* (`hud_paint.gd`).
  - **Força**: placa "Força", régua 10…100 (o número mais perto da força acende), barra com degradê amarelo → vermelho em segmentos, brilho que passa, ponta luminosa que solta faíscas enquanto carrega e a flâmula vermelha do último tiro com linha tracejada.
  - **Habilidades 1–9, F, V e Z/X/C** (`skill_slot.gd`): ícones novos do PixelLab sem texto (o botão escreve +2, x3, +1, 50%…10%, MAX), tecla numa plaquinha, brilho ao passar o mouse, afunda ao clicar, cinza quando não dá para usar, moldura dourada pulsando no que foi armado no turno (com x2, x3 quando repete) e um brilho que passa por todos quando a sua vez começa. Os usados aparecem também em fichas acima da força.
  - **POW** (`pow_orb.gd`): botão redondo como no DDTank, um orbe de vidro que enche de líquido roxo com ondas e bolhas (mostra a %); cheio vira dourado com um anel de respingo; pronto para soltar, gira raios e faíscas.
  - **Tempo e vento**: relógio com anel que esvazia no sentido horário na cor de quem joga (dourado para você), números que caem a cada turno e ficam vermelhos, pulando e tremendo nos 3 últimos segundos; vento com 5 setas de cada lado que acendem na direção e força do vento, com uma onda correndo.
  - **Minimapa**: moldura com o nome do mapa e a **rodada**, céu, grade de 1/10 de tela, marcador do jogador em losango, anel pulsando em quem joga, tiros com rastro e a visão da câmera em cantoneiras.
  - **Ângulo, energia e vida**: mostrador de bronze com escala em graus, faixa permitida, ponteiro dourado com ponta brilhante; barras com brilho, segmentos e o que acabou de ser perdido ficando para trás um instante; a vida pisca em vermelho abaixo de 25%. Fila de turnos com molduras e o painel da fase da instância no mesmo estilo; o retrato do jogador num medalhão.
  - **Vitória, derrota e empate** (`battle_outcome.gd`): tela cheia como o *cut-in*. Vitória: clarão, raios dourados, emblema alado novo (PixelLab), "VITÓRIA!" letra por letra com brilho, confete. Derrota: tela fria, o escudo partido cai e treme tudo, poeira, "DERROTA" cai letra por letra e fica torto, cinzas. Empate: raios prateados. Uma faixa embaixo diz o que aconteceu. O resultado abre depois de 3,4 s (antes 2,6).
  - "SUA VEZ!" e "FASE CONCLUÍDA!" com as letras do *cut-in* sobre uma faixa de luz.
  - Arte: 15 gerações do PixelLab (`docs/PIXELLAB_HUD.md`). Só o cliente mudou (nada do lockstep); `GAME_VERSION` continua 0.15. Todos os testes passam, incluindo `net_e2e_tests.gd` (151).

## 0.14: especiais, monstros com habilidades e Fiorde dos Vikings
- **Especiais (POW) únicos**: cada arma tem um projétil de especial próprio (arte PixelLab), a arte entra na tela junto com o "POW!" e a animação da arma toca grande onde o especial cai (antes ela tocava atrás do banner, no atirador, e os impactos pareciam iguais).
- **Monstros usam habilidades em vez de atirar**: salto com golpe (e volta), mergulho, golpe no chão, magias do céu com mira, sopro, escudo, grito de guerra e cura; queimadura e congelamento; habilidades de fúria; nome e ícone sobre a cabeça. Determinístico para o online (lockstep). Todos os 16 monstros que agem ganharam 2 a 5 habilidades.
- **Fiorde dos Vikings**: quinta instância, com 3 mapas novos (Praia dos Drakkars, Aldeia do Hidromel, Trono do Jarl), Saqueador Viking, Corvo Rúnico, Berserker Urso e o chefe Jarl Barba-de-Ferro, e o ícone de mapa próprio.
- Balanceamento: sem crateras nas magias (cavavam um poço sob o jogador parado), empurrões até 50 px e `pve.ability_damage` 1,15 para a entrada livre ficar como antes na simulação (`tests/instance_balance.gd`); precisa de teste com jogadores.
- Sons novos: `mob_cast`, `mob_leap`, `mob_strike`, `mob_slam`, `mob_roar`, `mob_breath`, `mob_burn`. Versão 0.14 (cliente e servidor precisam da mesma).
- Arte: 68 gerações do PixelLab (`docs/PIXELLAB_0_14.md`). Ícones das moedas da 0.10 também feitos no PixelLab (`docs/PIXELLAB_0_10.md`).
- **Testes**: `tests/ability_tests.gd` (30).

## 0.12: Leilão e Correio
- **Leilão** (prédio da cidade, online): busca com filtros (tipo, qualidade, nível do item ou do mapa, fortalecimento, bônus, preço máximo em Solares e Estrelas, ordem), detalhes do anúncio com os bônus, o vendedor, o tempo que falta e as vendas recentes de itens parecidos, e compra imediata. Aba **Vender** com preço em Solares e/ou Estrelas, duração de 12, 24 ou 48 h, a taxa em ouro, a comissão de 5% e quanto chega no Correio. Aba **Meus anúncios** (até 10 à venda; cancelar devolve o item).
- **Correio**: vendas e itens que voltam (cancelados ou vencidos), com RECEBER e RECEBER TUDO; o ícone CORREIO mostra quantas cartas esperam.
- **Custódia e transações** na API em Go e no PostgreSQL: o item fica guardado no banco enquanto está à venda; anunciar, comprar e receber gravam o perfil na mesma transação. Operações com id único (repetir não duplica), dois compradores ao mesmo tempo resolvidos pelo banco, vencimento automático, histórico de preços e auditoria de tudo.
- **Vinculados**: a arma inicial e as Super Verdadeiras equipadas passam a ser vinculadas (como os itens da Loja, dos cupons e as cópias do Espelho Celeste).
- **Testes**: `auction_tests.gd` (62), o Leilão no `net_e2e_tests.gd` (108 no total), `auction_test.go` na API e `auction_stack_check.gd` contra a API e o PostgreSQL de verdade.

## 0.11: backend e jogo online
- **API em Go + PostgreSQL** (`server/api/`): contas com senha PBKDF2, sessões por token, perfis com versão (nenhuma gravação sobrescreve outra), nomes de personagem únicos, auditoria de toda operação da economia, lista de servidores de jogo, presença (uma conta num servidor por vez) e exclusão da conta pela LGPD. Porta interna separada para os servidores de jogo.
- **Servidor de jogo** (`server/game/`): o próprio projeto Godot sem tela. Canal com jogadores online e chat (filtro de palavrões e limite de mensagens), salas reais, busca de sala rival com rivais de IA de reserva, batalhas PvP e instâncias em grupo, cartas sorteadas e entregues pelo servidor, e as regras da economia com o mesmo código do jogo (`PlayerProfile.apply_op`, `Rewards`, `InstanceRun`). Desliga com calma (salva todos) no `docker stop`.
- **Batalha em lockstep**: a mesma `LocalMatch` no servidor e em cada jogador, com intenções carimbadas por tick; força e ângulo exatos; checksum a cada segundo. Consertado no caminho: o mapa aleatório era sorteado antes de aplicar a semente da partida.
- **Cliente**: tela de entrada com a lista de servidores, conta e senha (criar conta, lembrar, trocar de conta) e o "Modo offline"; perfil espelhado do servidor; Salão, Sala (cada jogador prepara, configurações vão ao servidor), batalha, fases e cartas online; volta automática a uma batalha depois de cair.
- **Docker**: `server/docker-compose.yml` (PostgreSQL, API e servidor de jogo).
- **Testes**: `net_tests.gd` (58), `net_e2e_tests.gd` (66: servidor e dois jogadores reais jogando PvP até o fim, queda e volta, instância em grupo), testes da API em Go e `online_stack_check.gd` contra a pilha Docker. Os cupons de teste agora só valem online num servidor de testes (`TEST_COUPONS=1`).

## 0.10: atributos aleatórios, moedas, craft e inglês
- **Português e inglês** (item 4.3, que faltava da 0.8): todas as telas, mensagens, chat simulado e nomes (armas, roupas, moedas, inimigos, instâncias, mapas, atributos) nos dois idiomas, com nomes próprios em inglês. Escolha na tela de entrada, salva em `user://settings.cfg`; a primeira abertura segue o idioma do sistema. `locale/en.po` com 717 textos, extrator `tools/i18n.py` e teste que falha se faltar tradução, se um texto em português ficar fora de `tr()` ou se a fonte não tiver uma letra. A fonte cobre português, espanhol e francês.
- **Atributos bônus aleatórios**: Normal 0, Excelente 1–2, Verdadeira 3–4 e Super Verdadeira sempre 4. Arma: +Ataque, +% dano, +% dano crítico, +% dano do POW, POW inicial e chance de não gastar a habilidade 1–9. Roupa, chapéu, óculos e asas: +Defesa, +vida máxima, +Agilidade, +Sorte, +energia por turno, −Delay, −% efeito do vento e +% cura recebida. Cada bônus tem faixas F1 (melhor) a F5; F1 só em itens de nível 13+, e o nível do item é o nível do mapa. Nada muda o raio da explosão ou o hitbox. O fortalecimento continua aumentando só os atributos base.
- **Moedas** (Brasa, Coroa, Estrela, Tormenta, Solar, Eclipse e Espelho Celeste) com a mesma função das do PoE 2, em itens e em mapas, na nova aba **Moedas** do Ferreiro. A Coroa é o outro caminho para a Verdadeira (a Loja vende só Normal e Excelente). O Espelho Celeste cria uma cópia vinculada que não pode ser modificada.
- **Drops**: cada fase vencida pode dar uma moeda e o chefão sempre dá; cartas de moeda e de equipamento (chapéus, óculos, asas e roupas do seu gênero) no baú; Solar só a partir do mapa nível 5 e Espelho do 10; a entrada livre dá só Brasas; um pouco de Brasa e Coroa no PvP.
- Itens da Loja e de cupons vêm sem bônus e **vinculados** (não irão ao leilão). Save v5; armas que caíram antes da 0.10 ganham seus bônus uma vez ao carregar.
- Mochila mostra bônus, faixa, nível do item e o resumo dos bônus em Atributos; moedas ficam em Materiais. Cupom de teste `MOEDAS`.

## 0.9: instâncias de 3 fases e mapas
- **Quatro instâncias** com 3 fases e o chefão na última: Templo do Sol, Trono das Máscaras, Picos Gelados e Ilha Celeste em Ruínas. Fase 1 com ondas de lacaios (a segunda onda cai do céu), fase 2 com guardião ou objetivo (destruir cristais, sobreviver 5 turnos), fase 3 com o chefe e mecânica própria (fúria, invocar máscaras, congelar a vez, trocar de posição).
- Entre as fases: tela de transição, +30% de vida, POW mantido e quem caiu volta com 20%. Moedas e mapas das fases ficam mesmo se a equipe cair.
- **Mapas no lugar das dificuldades**: itens de nível 1 a 16 com qualidade (Normal, Excelente, Verdadeira) e atributos de ameaça e recompensa, consumidos ao entrar. Caem das fases (cerca de 0,9 por partida sem atributos). Espaço de mapa na sala, aba Mapas na Mochila, cupom `MAPAS`.
- **Loot**: baú do chefe com 3+ cartas, armas da instância em Normal/Excelente/Verdadeira com nível do item, cartas de mapa (carta esmeralda) e a Super Verdadeira com garantia depois de 20 chefões. A Loja agora vende só Normal e Excelente.
- Escala por grupo pronta e testada (vale quando houver grupos online).
- Arte PixelLab: 9 inimigos com repouso e ataque, animação do Guardião do Templo, 7 mapas novos e ícones de mapa (`PIXELLAB_0_9.md`).

## 0.8: POW em fases, arma e projétil maiores
- POW em fases: preparação (recuo e arma brilhando), carga (aura cresce, partículas puxadas para a arma), disparo (clarão, recuo e arte animada do POW de cada arma), voo (halo e rastro de partículas) e impacto (hit-stop de 80 ms, tremor, ondas e fumaça).
- Impacto próprio para cada uma das 12 armas e partículas de verdade (`CPUParticles2D`).
- Arma nas costas e projéteis 1,5× maiores em toda a batalha (POW mais 1,6×), sem mudar acerto, cratera ou dano (teste de regressão em `tests/pow_tests.gd`).

## 0.7: sons, POW, habilidades e tracejado
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
Lista completa e decisões em aberto em `ROADMAP.md`. Backend (0.11) e Leilão (0.12) prontos; o próximo passo é o lançamento (item 4): testes fechados na web, página da Steam e acesso antecipado.

1. Troca de moedas (Estrela ↔ Solar) e lances no leilão.
2. Slots de rosto e olhos e mais roupas no PixelLab; mais mapas seguindo a receita de `PIXELLAB_0_6.md`.
3. PET e missões.
