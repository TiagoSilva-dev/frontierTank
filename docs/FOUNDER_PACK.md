# Founder Pack — Edição Paladino do Sol

Pacote cosmético limitado do Gustfire, feito para um único efeito: alguém olha o Paladino do Sol e pensa **"esse jogador estava aqui desde o começo"**, e quando ele usa **Julgamento do Sol** todos na partida percebem que é um Fundador.

Regras que valem para tudo abaixo:

- **Só cosmético.** Nada aqui dá vantagem permanente. A Solaris tem os mesmos números de uma arma de loja (dano 255, raio 46, sem atributos bônus); o POW dela fica abaixo do Raio Prismático. Os itens são `premium`, vinculados, sem atributos e fora do leilão (mesmas regras do `PremiumStore`).
- **Leitura de jogo em primeiro lugar.** Nenhum efeito cobre a trajetória, o vento ou os inimigos. A explosão nunca parece maior que a área de dano real.
- **Pixel art.** Paleta fechada, contorno, rampas de 4–6 tons, partículas em grade de 2 px (como o resto do jogo). Nada de HD, vetor, 3D ou anime.
- **Identidade própria.** Sol, halo, estrelas, mandala, asas, fogo dourado. Não é cavaleiro medieval genérico e não copia Athena, Artemis nem outro jogo; as imagens de referência só deram a régua de quantidade e prestígio.

## Estado da implementação (30/09/2026)

Feito e testado (`tests/founder_tests.gd`, 94 checagens; as outras suítes e o `net_e2e` seguem passando, exceto o que já falhava antes: `ability_tests` "a magia de fúria do Jarl quebra o chão"):

- **Itens** em `items.json`: arma `solaris`, roupa `roupa_paladino_sol`, asas `asas_aurora` e o `selo_fundador` (o selo é o que faz de alguém um Fundador; não se equipa, não se vende, vem pelo Correio com o pacote). O produto `founder_pack` está em `store.json` (preço, `steam_item_id` 2000 e `sale_until` vazio: **você decide a data final da venda**; o servidor recusa a compra depois dela e quem comprou fica com tudo).
- **Skin** com 7 clipes deitado (idle, crawl, shoot, hit, victory, defeat, pow) e o **Halo Solar** como camada própria (`FounderFx`): gira, solta faíscas ao andar, acende no ataque, apaga no dano, cresce na vitória e vira a mandala no POW.
- **Solaris** com 4 formas (+0, +6, +10, +12; `Armory.tier_for_level` lê `tiers` da arma), projétil **Estrela do Amanhecer** (gira, rastro dourado com estrelas), **explosão** de 5 quadros (`SunBlast`, raio real = metade da largura) e o POW **Julgamento do Sol** (`FounderPow` + `FounderImpact`): vinheta só nas bordas, mandala, carga com tremor de 2 px, lança com anéis, ondulação de calor numa área pequena em volta dela, símbolo no chão a 0,97 R, feixe de 0,22 R, anéis que morrem em R, estrelas, pena que cai. A música baixa 9 dB durante a sequência.
- **Aura**, **Pet Solis**, **Footstep**, **Asas da Aurora** (fecham ao rastejar, abrem na vitória e no POW), **emote** Paladino Approved (tecla **E** em batalha; online viaja como intenção no lockstep e o servidor só aceita de quem tem o selo), **entrada no lobby** (1,4 s, uma vez por sessão, no Salão de Jogos, só com o conjunto completo).
- **Badge, título e moldura** no perfil, na cidade, no Salão, nas salas e no chat (o servidor marca `founder` na linha do chat e no `look` dos membros). A **tela do Founder Pack** (botão ✦ FOUNDER PACK ✦ na cidade) tem o Paladino, o conjunto com a evolução da Solaris, o preview do POW em laço e o botão TORNE-SE UM FUNDADOR; para quem já é Fundador mostra as chaves dos efeitos.
- **Sons** novos (`tools/make_sfx.py`): `fire_solaris`, `impact_solaris`, `pow_solaris_awaken/charge/lance/impact`, `founder_reveal`, `founder_emote`. Inglês completo e wiki (`website/`, Solaris com a marca Founder).

Decisões que mudaram o conceito acima:

1. **Aura, pet, footstep e entrada no lobby são chaves na tela do Founder, não espaços de equipamento.** Os espaços do Mochila são os da tela do DDTank; três novos exigiriam refazê-la. As chaves vão no perfil (`founder_fx`, operação `founder_fx`) e no `look.founder`, então todos na partida veem o mesmo.
2. **O símbolo solar enorme do impacto mora no céu** (rodada 3 do Jev, `docs/founder/jev_round3.json`): mandala de 8 R de largura, vertical, centrada 6 R acima do impacto, nunca toca o chão. O que toca o chão fica dentro de R. As "ondas douradas atravessando o cenário" são três faixas finas no céu e um pulso de luz na tela, não anéis no chão.
3. **A Solaris não tem atributos** (regra do `PremiumStore`) e tem o dano e a área do piso da loja: quem a usa abre mão dos bônus de uma arma de loja, e em troca ganha o visual. Se preferir paridade (por exemplo 30/30/30/30, o mesmo total do Tijolaço), é só mudar `attrs` e relaxar a validação do `PremiumStore.valid` para itens `founder`.
4. A **mandala** ficou com 192 px (não 160) e a moldura com 128×104 (as asas saem do quadrado).
5. O halo é o mesmo em batalha e no menu; em batalha a aura é só um anel fino a 35%, como combinado.

Ainda não feito / precisa de olhos e ouvidos seus: ouvir os sons; jogar o POW numa partida real (cronometrei só em captura de tela); conferir o preço e a data; definir o `steam_item_id` real na Steam; badge no ranking e na lista de amigos (o jogo ainda não tem essas listas: o ranking é só um número no perfil e o botão de amigos é um ícone); o pet só aparece em batalha.

## Como o Jev entrou nas decisões

O Jev (TypeSafe System One) não escreve texto: devolve notas e probabilidades tipadas. Usei-o como **portão de design** sobre descrições das opções, com `tools/jev_review.py` e o plano em `docs/founder/jev_plan.json` (respostas brutas em `docs/founder/jev_round1.json` e `jev_round2.json`; dá para rodar de novo quando uma opção mudar). A nota total de cada opção é uma soma ponderada de perguntas pequenas (Score/Noul); riscos pesam ao contrário.

| Decisão | Opções testadas | Escolhida | Por quê (Jev) |
|---|---|---|---|
| Silhueta da skin | A chibi + halo em camada própria · B asas e halo pintados no sprite · C sacerdote de túnica · D halo gigante permanente | **A** (6,22 vs 5,89 / 5,15 / 5,04) | Melhor equilíbrio: leitura 0,77, identidade 0,83, prestígio 0,95, viabilidade 0,67. B falha em viabilidade (0,08: halo e asas refeitos em todo quadro); D lê bem mas pesa na poluição (0,75). |
| Duração do POW | rodada 1: 2,0 s · 3,0 s · 4,0 s · 3,0 s comprimindo para o adversário | rodada 1 mostrou que **toda sequência forçada** custa ritmo e legibilidade (3 s: legibilidade 0,20; 4 s: 0,34) | Em vez de escolher o menos ruim, refinei. |
| Duração do POW, rodada 2 | 2,0 s · **2,4 s legível** · 2,2 s apertado · 2,4 s com tiro segurado | **2,4 s legível** (4,91 vs 4,03 / 3,67 / 2,95) | Legibilidade 0,98 e epicidade 0,94: sem escurecer a tela inteira (só vinheta nas bordas), câmera acompanha a lança, tremor de no máximo 2 px, anel dentro do raio real. |
| Política do raio da explosão | anel exato · anel 1,5× · estrelas até 2× · anel exato + brilho fraco a 1,4× | **anel exato em R** (engana 0,16; as outras 0,62–0,86) | Decalque do sol a 0,8 R, anel termina em R, pilar estreito, estrelas minúsculas que somem antes de R. Nada de "anel decorativo" além do raio. |
| Prioridade de produção | 15 elementos | ver tabela de prioridades | Nota = quanto o elemento faz os outros perceberem o Fundador × frequência com que aparece. |

Ordem que o Jev deu (maior a menor): skin 2,56 · moldura 2,24 · título 2,22 · badge 2,18 · pet 2,06 · explosão 2,04 · POW 2,02 · arma 2,01 · projétil 1,85 · asas 1,81 · entrada no lobby 1,62 · emote 1,39 · footstep 1,33 · aura 1,23 · tela comercial 1,12. O pedido diz que o POW é o elemento **mais importante**, então ele sobe para P0 junto da skin, apesar de aparecer pouco por partida.

## Paleta

Uma rampa por material, todas com o mesmo contorno quente. Mantém o Paladino reconhecível em 80 px de altura: dourado forte nas bordas, branco no volume, azul só em pontos focais.

| Material | Tons (escuro → claro) |
|---|---|
| Ouro | `7a4a12` `b9791c` `f0a62c` `ffd25a` `fff0a8` |
| Branco celestial | `8e93b8` `c4c8e4` `e8ebfa` `ffffff` |
| Azul real | `16206e` `2a3fc0` `4a78ff` `9ad0ff` |
| Sol (laranja/amarelo, só detalhe) | `c8300f` `ff6a1a` `ffb02e` `fff26a` |
| Contorno | `2a1c30` (roxo quase preto, não preto puro) |

## Mapa dos 19 entregáveis

Legenda de prioridade: **P0** identidade do pacote · **P1** completa o conjunto · **P2** acabamento.

| # | Elemento | Prio. | Resolução | Quadros | Como é feito |
|---|---|---|---|---|---|
| 1 | Paladino do Sol (conceito) | P0 | — | — | seção abaixo |
| 2 | Paleta | P0 | — | — | acima |
| 3 | Silhueta | P0 | — | — | seção abaixo |
| 4 | Sprite sheets | P0 | ver lista | ver lista | seção abaixo |
| 5 | Animações | P0 | 136×136 | 5–8 por clipe | seção abaixo |
| 6 | Arma Solaris | P0 | 96×96 | 1 por estágio | PixelLab + acabamento |
| 7 | Evoluções +0/+6/+10/+12 | P0 | 96×96 (+12 com camadas) | 4 | PixelLab + código |
| 8 | Projétil Estrela do Amanhecer | P0 | 32×32 | 8 (giro) | Python (pixel a pixel) |
| 9 | Explosão | P0 | 128×128 | 5 | Python + partículas |
| 10 | POW Julgamento do Sol | P0 | tela cheia | 6 fases | código + arte |
| 11 | Aura do Primeiro Sol | P1 | 96×48 | 8 | Python |
| 12 | Asas da Aurora | P1 | 128×128 (uma asa) | 1 + flap em código | PixelLab |
| 13 | Pet Solis | P1 | 64×64 | 4 clipes | PixelLab |
| 14 | Footstep | P2 | 32×16 | 6 | Python |
| 15 | Badge Founder | P0 | 16/24/32 | 1 | Python |
| 16 | Moldura Founder | P1 | 96×96 (9-slice) | 1 | Python |
| 17 | Emote Paladino Approved | P2 | 64×64 | 6 | PixelLab + Python |
| 18 | Entrada no lobby | P2 | — | — | código |
| 19 | Tela do Founder Pack | P1 | 640×360 | — | código (Godot) |

---

## 1. Paladino do Sol — conceito

Um guerreiro celestial pequeno e denso, ligado ao sol e às estrelas. Armadura branca com filetes dourados, **coroa-elmo alada com um cristal azul no centro**, ombreiras largas em forma de raios, luvas e botas douradas, capa curta branca forrada de azul real. Nas costas, fora do sprite, a **Asa da Aurora** (seção 12). Atrás da cabeça e dos ombros gira o **Halo Solar**, o elemento principal.

O que o separa de um cavaleiro medieval: não há viseira fechada nem espada, o elmo é uma coroa de raios com asas pequenas, o peito leva um sol em relevo e o ouro é luz (brilho, não metal fosco). Em 80 px, o que lê é a **mancha dourada redonda atrás da cabeça** e as duas asas brancas.

### Silhueta (opção A do Jev)
Corpo compacto deitado (mesma pose prone de todos os lutadores, ver `ddtank-prone-pose`), cabeça grande com coroa-elmo em três pontas, ombreira em raio. O halo e as asas **não estão pintados no corpo**: são camadas à parte no `LookRig`, por isso animam sozinhos (idle gira, andar solta partículas, ataque acende, POW vira mandala) sem redesenhar quadro nenhum.

### Halo Solar (camada própria, `SunHalo`)
Anel duplo com 8 raios e 8 runas, desenhado pixel a pixel em 64×64 e gerado em **passos de rotação exatos** (simetria de 8 lados: só 6 quadros cobrem 45°, sem serrilhado de girar pixel art).

| Estado | Halo |
|---|---|
| Idle | gira 1 volta em 12 s, brilho respirando ±10% |
| Andar | gira 2× mais rápido e solta 1 faísca a cada 0,12 s (vida 0,5 s) |
| Mirar | brilho +25%, raios alongam 1 px |
| Atacar | clarão de 0,18 s (+80%) e recuo de escala 1,0→1,12→1,0 |
| Levar dano | apaga 0,1 s e volta |
| Vitória | cresce para 1,6× por 2,5 s com raios em leque |
| Derrota | apaga devagar, anel trinca em 3 pedaços |
| POW | vira a **mandala solar** (seção 10) |

## 5. Lista de animações (skin)

O `Fighter` já toca `idle`, `crawl` (andar) e `shoot` (atacar). Ganha três clipes opcionais (`hit`, `victory`, `defeat`); a skin que não os tiver continua como hoje.

| Animação | Quadros | Tempo | Roupa e corpo | Halo | Luz e partículas |
|---|---|---|---|---|---|
| IDLE | 5 (pingpong) | 5 fps | capa respira, cristal pulsa | gira lento | 1 fagulha subindo a cada 0,8 s |
| WALK (rastejar) | 7 | 12 fps | capa balança para trás, ombreira sobe | gira rápido, solta faíscas | footstep (seção 14), brilho nas botas |
| AIM | pose do idle com a arma erguida (ângulo do jogo) | contínuo | capa parada | brilho +25% | energia entra no núcleo da Solaris |
| ATTACK | 5 | 14 fps | recuo do ombro, capa estala | clarão | clarão no cano, anel dourado de 0,15 s |
| HIT | 3 | 12 fps | corpo encolhe, capa ao contrário | apaga 0,1 s | 4 estrelas pequenas caem |
| VICTORY | 6 | 8 fps | levanta a cabeça, punho com a arma para cima | 1,6× | asas abertas, chuva de estrelas, aura cresce |
| DEFEAT | 5 | 6 fps | cai de lado, cristal escurece | trinca e apaga | 3 fagulhas sobem e somem |
| POW | pose especial de 4 quadros (seção 10) | 12 fps | cabeça erguida, capa ao vento | mandala | fragmentos subindo |
| EMOTE | 6 (seção 17) | 10 fps | cabeça com sorriso de canto | — | estrela brilhando |

## 4. Sprite sheets necessários

```
assets/characters/roupa_paladino_sol/          south/east/north/west.png   136×136 (em pé, menus)
  prone/{east,west,south,north}.png                                        136×136 (batalha)
  prone/idle/frame_00..04   prone/crawl/frame_00..06   prone/shoot/frame_00..04
  prone/hit/frame_00..02    prone/victory/frame_00..05  prone/defeat/frame_00..04
  anchors.json                                        (cabeça, olhos, costas, cores do cabelo)
assets/founder/halo/halo_00..05.png  halo_pow_00..05.png  halo_small.png   64×64 / 128×128
assets/founder/mandala/mandala_00..05.png                                  160×160
assets/weapons/solaris/tier0..3.png                                        96×96
assets/projectiles/estrela_amanhecer.png + effects/pow/solaris/projectile.png (lança)
assets/effects/founder/explosion/frame_00..04.png   lance.png   feather.png   sun_sigil.png
assets/cosmetics/asas_aurora/wing.png (+ ícone)     pet/solis/{idle,fly,scared,victory}/
assets/founder/{badge_16,badge_24,badge_32,frame,aura_00..07,footstep_00..05,emote_00..05}.png
```

---

## 6. Arma Solaris

**Aparência.** Canhão-relíquia: corpo branco, filetes dourados, **núcleo solar laranja no centro**, cristal azul na culatra, duas pequenas asas de metal dobradas ao lado do cano. Continua sendo um canhão (cano, recuo, boca), não uma espada.

**Animação.** Equipada: núcleo pulsa devagar (brilho aditivo 0,6→1,0 em 2,4 s). Mirando: pontos de energia entram no núcleo (`FxParticles` com `radial` negativo). Disparo: as asas e o anel do cano **abrem** (2 quadros sobrepostos ao sprite, 0,15 s) e fecham.

**Números.** Dano 255, raio 46, ângulo 20–60°, sem atributos. É o piso das armas de loja: o Fundador nunca sai na frente por causa dela.

**VFX.** Brilho aditivo do núcleo (`weapon_shine` do `LookRig` já existe), partículas de entrada de energia, clarão de 0,1 s no cano.
**SFX.** `fire_solaris` (sino agudo + estouro quente), `impact_solaris` (acorde que sobe e abre), pulso do núcleo em 0,3 de volume.
**Implementação.** Entrada `solaris` em `weapons` (premium, `tiers: [0,6,10,12]`), `Armory.tier_for_level` passa a ler `tiers` da arma, sons no `tools/make_sfx.py`, efeitos de mirar/abrir em `weapon_effect.gd`.

## 7. Evolução visual

| Nível | Forma | Mudanças |
|---|---|---|
| +0 | Forma inicial | arma branca simples, poucos filetes, núcleo pequeno |
| +6 | Núcleo ativado | mais ouro, runas no cano, núcleo maior |
| +10 | Asas celestiais | cristal maior, asas de metal abertas, 4 partículas orbitando |
| +12 | Forma suprema | asas de **energia** nas laterais, núcleo solar flutuando à frente, 6 partículas em órbita |

Só a aparência muda; a força vem do Ferreiro como em qualquer arma. +12 é desenhado em camadas (corpo + asas de energia + núcleo flutuante + órbita) para animar sem quadro extra.

## 8. Projétil — Estrela do Amanhecer

**Aparência.** Esfera solar pequena (amarelo-branca com anel laranja e 4 pontas de estrela). **Animação.** gira (8 quadros), rastro dourado de 10 pontos que encolhe, estrelas de 2 px e fragmentos que caem e somem em 0,4 s. **Leitura.** O sprite tem no máximo 32 px e o rastro fica atrás dele; a linha tracejada de mira continua por cima. Sem distorção no tiro normal. **Implementação.** `projectile.sprite = estrela_amanhecer`, `trail = "sun"` em `projectile.gd`. **SFX.** `fire_solaris`.

## 9. Explosão exclusiva (raio R = raio de dano real)

| Quadro | Tempo | O que aparece |
|---|---|---|
| 1 | 0,00 s | flash dourado pequeno (≤ 0,3 R) |
| 2 | 0,06 s | símbolo solar no chão a **0,8 R** |
| 3 | 0,12 s | explosão vertical de luz, estreita (< 0,25 R de largura) |
| 4 | 0,20 s | anel de energia cresce até **exatamente R** e some |
| 5 | 0,32 s | estrelinhas (2 px) sobem e se apagam, nenhuma passa de R no chão |

O teste `tests/founder_tests.gd` confere por código que o maior raio desenhado é ≤ R.

## 10. POW — Julgamento do Sol (cut-in de anime + carga, ~2,5 s até o disparo)

**Revisão (2026-10-01).** A primeira versão (só vinheta e mandala no mundo) ficou sem o "especial de anime" que as outras armas têm. Agora o Julgamento do Sol abre com seu **próprio cut-in** (`FounderCutin`, `client/ui/founder_cutin.gd`), da mesma família do `PowBanner` (a partida segura o tiro, o retrato do próprio jogador, o nome entrando letra por letra), mas uma cena inteira e diferente: céu noturno com um sol atrás do Paladino, **mandala solar gigante** girando (mesma arte da mandala do jogo, ×3, com uma cópia maior contra-girando), **linhas de foco** que piscam a 20 quadros por segundo, **dois cortes brancos** em X que abrem a cena, **onda de choque** quando o Paladino pousa (0,30 s) com tremor de tela, título em duas linhas ("JULGAMENTO / DO SOL") sobre uma faixa azul real com bordas douradas e brilho que varre as letras, selo de Fundador + nome do jogador em cima e "✦ SOLARIS ✦" embaixo, poeira dourada subindo. Nos últimos 0,3 s a **tensão sobe** (linhas mais longas, tudo treme em pixels inteiros) e o sol implode num **clarão branco** que devolve a tela ao mundo. O cut-in cobre a tela de propósito: a partida está parada nesse momento, então nada do jogo some. A mandala **é** a aura da cena (o anel de arma de +12, vermelho, é desligado no retrato com `look.no_aura`).

A leitura do jogo continua protegida: depois do clarão a **vinheta** só nas bordas volta, o terreno, os inimigos, o vento e a linha de tiro ficam no brilho normal, e a **carga** e o **disparo** acontecem no mundo, vistos de verdade.

| Fase | Tempo | O que acontece |
|---|---|---|
| 1 Ativação | 0,00–0,30 | clarão, céu, dois cortes, o halo cresce por baixo; o Paladino desce com ecos dourados e **pousa** (onda de choque, tremor) |
| 2 Despertar | 0,30–1,15 | mandala gigante, título letra por letra, faixa azul, poeira; sob o cut-in o halo já é a mandala do mundo |
| 3 Tensão | 1,15–1,45 | linhas de foco longas, tudo treme, vinheta das bordas entra por baixo, o sol implode no clarão branco |
| 4 Carga | 1,35–1,85 | a Solaris abre as partes mecânicas, energia entra no núcleo (partículas puxadas), fragmentos sobem, tremor ≤ 2 px |
| 5 Disparo | 1,85–2,5 | o projétil vira a **Lança Celestial Solar**, cruza o cenário com anéis solares, estrelas, fragmentos e uma leve distorção de calor que **nunca cobre a trajetória** |
| 6 Impacto | ao acertar | símbolo solar dentro do raio real, feixe de luz estreito do céu, explosão, ondas douradas (não passam do raio real) |
| 7 Final | +0,15 s | partículas somem, uma **pena celestial** cai; o jogo volta ao normal |

A partida segura o tiro por `visual.founder_cutin` (1,95 s, igual em todas as cópias; as outras armas usam `pow_cutin`, 1,15 s); `founder_cutin_close` (1,45 s) é quando o cut-in se fecha.

**Dados.** `kind: "judgment"`, `damage_scale 1.3`, `radius_scale 1.15` (o Raio Prismático faz 1,6 / 1,5). **SFX.** `pow_solaris_cutin` (dois cortes, taiko e sino no pouso, coro, subida e clarão), `pow_solaris_awaken` (pad que sobe), `pow_solaris_charge`, `pow_solaris_lance` (varredura), `pow_solaris_impact` (sino + explosão), `pow_solaris_feather`. **Rede.** Tudo é visual local depois do tiro; a simulação (dano, raio, acerto) é a mesma em todos os clientes (lockstep).

## 11. Aura do Primeiro Sol
Círculo mágico de 96×48 no chão sob o personagem: anel duplo e 8 pontos de sol. **Em batalha** só um anel fino a 35% de opacidade, 4 partículas subindo devagar. **No lobby** mais elaborado: runas girando, 14 partículas. **Vitória:** cresce 1,0→1,8× por 2,5 s. 8 quadros de giro, `assets/founder/aura_*`. Convenção do jogo: aura de arma só fora da batalha; esta é cosmética da conta e segue a mesma regra, com o anel fino permitido em batalha por ser um pedido explícito do pacote.

## 12. Asas da Aurora
Uma asa (128×128) espelhada para a outra, como as demais, penas brancas com borda dourada e ponta azul. Idle: bate devagar (±0,13 rad em 3,4 rad/s, já no `LookRig`). Movimento: fecham em parte (rotação +0,25). Vitória: abrem por completo (escala 1,35× e 0,6 rad). Uma asa ocupa ≤ 1× a largura da cabeça, não cobre o tiro. Entrada `asas_aurora` em `cosmetics` (slot `asas`, premium).

## 13. Pet Solis
Guardião celestial fofo: corpo redondo branco, duas asinhas douradas, cristal solar na testa, cauda de energia que termina em faísca. 64×64, clipes **idle voando** (4), **feliz** (4), **assustado** (3, quando o dono leva dano) e **vitória** (6, giro e estrelas). Segue o personagem com atraso suave (mola) **sempre acima e atrás**, sem sombra no terreno nem colisão, e fica a ≥ 40 px da linha de tiro; em batalha fica a 75% de opacidade. Novo slot `pet` no equipamento.

## 14. Footstep
Ao rastejar aparece, a cada 28 px, um símbolo solar de 32×16 no chão (6 quadros: surge, brilha, desfaz), vida 0,4 s. É marca visual, sem colisão; some quando o terreno muda sob ele. Novo slot `rastro`.

## 15. Badge Founder
Sol de 8 raios, ouro sobre azul real, em 16/24/32 px. Aparece em **perfil, ranking, lobby, lista de amigos e chat**, sempre à esquerda do nome, também para jogadores online (sai do servidor como `founder: true` no perfil público; o cliente não decide). Quem tem o badge também mostra o título **✦ FUNDADOR ✦**.

## 16. Moldura Founder
Moldura 96×96 (9-slice) de ouro com duas asinhas nos cantos superiores e cristal azul embaixo, usada no retrato do perfil e no cartão de jogador.

## 17. Emote — Paladino Approved
Cabeça em pixel art do Paladino, expressão confiante (sobrancelha erguida, sorriso de canto), com uma estrela brilhando na lateral (6 quadros, balança e pisca). Aparece sobre o personagem por 1,6 s com a tecla de emote.

## 18. Entrada no lobby
Quando o conjunto completo está equipado: o halo surge (0,3 s), partículas solares sobem, o personagem aterrissa (queda de 40 px com quique) e as asas fecham. Total **1,4 s**, só na **primeira vez que entra no lobby por sessão**.

## 19. Tela do Founder Pack
640×360, três colunas: à esquerda o Paladino grande com halo animado; no centro a grade **Skin · Arma · Asas · Pet · Aura**; à direita o **preview animado do POW** em laço. Título *GUSTFIRE FOUNDER PACK*, subtítulo *EDIÇÃO PALADINO DO SOL*, botão **TORNE-SE UM FUNDADOR**, texto *Itens exclusivos disponíveis somente durante o período Founder.* e a lista ✓ de 12 itens. O botão usa o fluxo existente do `PremiumStore` (Steam Wallet); o pacote entra em `store.json` como `founder_pack` e tem prazo de venda configurável.

---

## Implementação: o que muda no código

| Área | Mudança |
|---|---|
| `shared/balance/items.json` | weapon `solaris`; cosmetics `roupa_paladino_sol`, `asas_aurora`; novos slots `pet`, `rastro`, `aura_fundador` |
| `shared/balance/store.json` | produto `founder_pack` |
| `Armory` | `tiers` por arma, slots novos, `founder_items()` |
| `PlayerProfile` | `founder: bool` derivado de possuir o pacote; ações `equip` dos novos slots |
| `LookRig` / `Fighter` | `SunHalo` (camada), clipes opcionais hit/victory/defeat/pow, aura, pet, footstep |
| `projectile.gd`, `match.gd` | trail `sun`, kind `judgment` |
| `pow_fx.gd` / novo `founder_pow.gd` | as 6 fases, vinheta, câmera |
| `impact_fx.gd` | explosão do sol (raio exato) |
| UI | `FounderBadge`, `FounderScreen`, moldura e título em perfil, ranking, lobby, amigos, chat |
| Servidor | `founder` no perfil público (Go) e na presença |
| Testes | `tests/founder_tests.gd` (números da Solaris, raio da explosão, lockstep igual, itens cosméticos) |
