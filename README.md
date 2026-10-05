# Gustfire — 0.22

Abra **Jogar.cmd** para iniciar com o Godot instalado neste computador, ou importe **project.godot** no Godot 4.7 e pressione F5. Em outro computador, configure `GODOT_BIN` com o caminho do executável Godot.

Jogo de artilharia por turnos em pixel art, com cidade, salas, instâncias e economia de itens. Joga **online** (conta, servidor de jogo, salas, chat e batalhas com outros jogadores) ou no **modo offline** contra bots.

## Liga ranqueada (0.22)

- Botão **RANQUEADA** no Salão (online): partidas **1 contra 1 entre jogadores reais**, nunca com bots. Fila por rating (a janela de pontos abre com a espera), uma dupla só se enfrenta 3 vezes por hora. **Abandonar perde na hora** (3 turnos seguidos estourados pelo relógio também). Elo (K 48 nas 10 primeiras partidas, 32 depois), 5 partidas de avaliação por temporada e **seis divisões** (Bronze, Prata, Ouro, Platina, Diamante e Mestre, com três degraus cada) com um emblema desenhado por código.
- **Temporadas de 28 dias** (a primeira a partir de 05/10/2026): o rating volta à metade do caminho até 1000 e a divisão em que o jogador terminou vira um **título cosmético** ("Ouro · Temporada 1"), que aparece no perfil, na lista da liga e **no lugar da patente** sob o nome do lutador na batalha. Só aparência.
- A tela da liga mostra a divisão, o progresso até o próximo degrau, a fila, os 50 melhores da temporada, **AO VIVO** (as partidas ranqueadas em andamento, para assistir) e os títulos. Detalhes e números em [docs/RANKED.md](docs/RANKED.md).

## Desafio do Dia, replays e espectador (0.22)

- **Desafio diário** (botão no Salão): o mesmo duelo para todos todo dia, com a mesma arma, os mesmos atributos e o mesmo mapa e semente (o equipamento de ninguém conta): **Tiro ao Alvo**, **Duelo Relâmpago** ou **Alvo Distante**, com três medalhas. O primeiro resultado do dia paga uma recompensa. Online o servidor **refaz a sua partida a partir da gravação e confere a pontuação** antes de ela entrar no ranking do dia, e dá para assistir às partidas dos melhores.
- **Replays**: as últimas batalhas PvP online e os desafios ficam gravados no computador (aba REPLAYS do Desafio) e podem ser assistidos com pausa e 1x/2x/4x. Como a batalha é a configuração mais as intenções por tick, o replay chega exatamente ao mesmo estado.
- **Espectador ao vivo**: salas em jogo e partidas ranqueadas podem ser assistidas, com alguns segundos de atraso. Tudo em [docs/CHALLENGE.md](docs/CHALLENGE.md).

## Contratos, sequência de dias e habilidade do mascote (0.22)

- **Contratos diários e semanais sorteados**: 5 diários tirados de um conjunto de 16 (no máximo 2 do mesmo tipo) e 3 semanais de 9, iguais para todos, que mudam a cada dia e a cada semana (segunda a domingo, UTC), com bônus ao completar todos. Cobrem PvP, instâncias, mascotes, Ferreiro, Loja, o Desafio do Dia e a Liga. A aba **SEQUÊNCIA** é a escada de login de 7 dias: resgate uma vez por dia, dias seguidos sobem (o 7º dá um ovo), faltou um dia, volta ao começo. A bolinha do botão MISSÃO conta o que está pronto.
- **Habilidade do mascote em batalha** (tecla **G**, um uso por batalha, a partir do seu segundo turno): o mascote ativo empresta ao dono uma habilidade pelo elemento, mais forte com a raridade e as estrelas. **Sol**: Rajada Solar (o próximo tiro causa mais dano); **Máscara**: Truque da Máscara (crítico garantido); **Gelo**: Muralha Glacial (cura e corta o próximo golpe à metade); **Céu**: Corrente de Ar (zera o vento e devolve energia); **Runa**: Selo de Runa (enche parte da barra de POW). É uma intenção como outra qualquer, então vale no online e nos replays (`docs/PETS.md`).

## Treino e Primeiros passos (0.22)

- **Treino de artilharia** (`Tutorial`, `TutorialCoach`, `shared/balance/tutorial.json`): quem cria um personagem novo recebe na cidade o convite "Quer fazer um treino rápido?". O treino é uma batalha local (também online: só o fim chega ao servidor) contra um **Boneco de Treino** que não revida, com um cartão sob o retrato e uma moldura pulsando na parte da interface da lição: **andar**, **mirar**, **vento**, **disparar** (depois de dois erros o cartão sugere ângulo e força, calculados pelo mesmo solucionador da IA; o boneco se recompõe entre os turnos), **habilidades** (tecla 1, +2 ataques), **POW** (a barra já vem cheia) e **derrubar o boneco**. O relógio do turno não corre durante as lições, o terreno não se destrói e **PULAR TREINO** sai a qualquer hora. Recompensa uma vez só (200 moedas, 150 EXP, 3 pedras e 1 ovo de mascote). "Agora não" fica salvo; o botão **TREINO** em AJUDA repete a lição. Contas antigas que já jogaram não recebem o convite.
- **Primeiros passos** (aba da MISSÃO, `MissionsBoard`): um roteiro de seis passos que leva o novato pelo jogo (primeira batalha e vitória no PvP, tentar o Ferreiro, uma instância na entrada livre, chocar um ovo, iniciar uma Caçada), cada um com recompensa e um bônus ao completar todos (500 moedas, 300 EXP). Contas antigas ganham o que já fizeram. O botão MISSÃO mostra uma bolinha verde com quantos contratos podem ser resgatados.
- Testes: `tests/tutorial_tests.gd` (78) joga a lição inteira por script: passos, erros e dica, boneco que se recompõe, habilidade, POW, vitória, recompensa e o convite da cidade. Captura: `--screen=tutorial --step=<0..7>`.

## Mascotes e Caçada (0.19–0.21)

- **Casa dos Mascotes** (prédio da cidade, botão PET, espaço "Mascote" da Mochila; `docs/PETS.md`): cada instância solta o ovo do seu elemento (Sol, Máscara, Gelo, Céu, Runa), o jogador **choca** na cena do ovo que treme, racha e estoura na cor da raridade (58/28/11/3% com garantia de Épico no 10º ovo e de Lendário no 40º), e o mascote que nasce acompanha o lutador na batalha com bônus de verdade (atributos e talentos pelo elemento, nível e estrelas). 20 espécies (5 elementos × 4 raridades), álbum com bônus permanente ao completar um elemento. Na batalha o mascote anda ao lado do lutador com animação própria por espécie (`PetMotion`, `PetActor`) e, quando o dono cai, ele vira um **fantasma** flutuante enquanto os outros veem "X caiu!".
- **Caçada** (quarta aba da Casa dos Mascotes; `docs/PET_HUNT.md`): modo automático tipo idle. Escolha a zona (uma por elemento), o nível de caça (1–8) e um time de até 5 mascotes; a cada 12 s o time enfrenta selvagens do elemento, mesmo com o jogo fechado, e você **coleta** moedas, XP, ovos e mascotes capturados (o **Lendário** da zona é garantido depois de 2.000 encontros). O acúmulo vai até 2 h, ou 8 h com o **Passe do Caçador** (Steam). Simulação determinística (`PetHunt`), a mesma na tela e na coleta; online o servidor liquida com o relógio dele. **Campo visto de cima** (Ruínas do Sol e Trilha Gelada): o treinador anda, os selvagens vagam e cada espécie ataca com o golpe do seu elemento; as outras zonas ainda usam a arena lateral.
- Testes: `pet_tests` (65), `hunt_tests` (152), `pet_motion_tests`, `ghost_tests`; `tests/hunt_balance.gd` imprime renda e vitórias por time.

## Social, visual premium e Founder Pack (0.17–0.20)

- **Social**: a lista de jogadores do Salão tem abas Todos/Amigos e busca; clicar num nome abre **Ver perfil**, **Mensagem privada**, **Adicionar/Remover amigo** e, online, **Denunciar mensagem** (`PlayerList`, `PlayerMenu`, `FriendBook`).
- **Visual premium** (`PremiumUi`, `HudPaint`): molduras de bronze com vidro escuro em todas as telas, texto com contraste auditado (`tools/contrast_audit.gd`) e cosméticos encaixados na cabeça e nos olhos (`assets/cosmetics/fit.json`).
- **Founder Pack** (`docs/FOUNDER_PACK.md`): conjunto cosmético limitado "Paladino do Sol" (roupa, asas, a arma Solaris com POW próprio e efeitos), vendido pela loja Steam; só aparência. **Abas de Mochila** extras também são produtos premium (`store.json`), nunca poder.

## Casa de Câmbio (0.17)

Na cidade, a Casa de Câmbio substitui Namoro. Jogadores anunciam trocas entre as 7 moedas especiais e as 12 pedras de fortalecimento, com cotação própria, ofertas parciais, taxa em ouro e entrega pelo Correio. O PostgreSQL guarda as ofertas e o saldo reservado, inclusive com o vendedor offline. Regras, testes e publicação em [docs/CAMBIO.md](docs/CAMBIO.md).

## Site oficial e wiki — Gustfire
O jogo ganhou nome novo, **Gustfire** (*gust* = rajada de vento, *fire* = disparo), com logotipo em pixel art e site oficial em `website/`: página inicial com o botão **JOGAR**, uma mini batalha jogável com a física do jogo e uma **wiki** no estilo do poedb (armas, POW, instâncias, monstros, mapas, moedas, bônus, fortalecimento e as fórmulas do combate), em português e inglês. Os números da wiki saem dos arquivos de balanceamento: depois de mudar o jogo, rode `python tools/build_site.py`. Abra `website/index.html` ou suba o Docker (site em `/`, jogo em `/jogar/`). Tudo em [docs/SITE.md](docs/SITE.md). O jogo inteiro usa o nome e o logotipo novos: tela de entrada, janela, ícone, executáveis (`Gustfire.exe`, `Gustfire.x86_64`), textos legais, página e cápsulas da Steam e o servidor padrão (**S1 · Ilha Celeste**). O jogo se chamava *Frontier Tank: Nova Era*; na primeira vez que o Gustfire abre, o save offline, o idioma, o áudio e a conta lembrada da pasta antiga são copiados (`client/systems/legacy_data.gd`). Os nomes internos (pasta do projeto, projeto do Docker `frontier-tank`, banco `frontier`, identidade Steam `frontiertank`) ficaram iguais para não perder dados.

## Forja Celeste e drops de monstros

O Ferreiro ganhou cenário original do PixelLab, arma flutuante, interface de bronze e painéis escuros, efeitos e sons de sucesso/falha. Uma tentativa usa uma pedra do nível desejado (1–12); a chance aparece na tela. Se falhar, a pedra e a taxa são consumidas, mas o nível é mantido. Monstros das instâncias podem dar drops ao autor do golpe final e cópias de um drop para cada integrante do grupo. Mapas mais difíceis liberam pedras mais raras. Regras e testes em [docs/FORJA.md](docs/FORJA.md).

## Online (0.11)
- **Subir os servidores**: `cd server && cp .env.example .env && docker compose up --build -d` (PostgreSQL, API em Go e o servidor de jogo, que é este projeto rodando sem tela). Passo a passo, variáveis e produção em `server/README.md`.
- **Entrar**: a tela de entrada lista os servidores no ar; crie a conta (CRIAR CONTA) ou entre (ENTRAR). "Modo offline" continua lá.
- **Tudo decidido no servidor**: compras, Ferreiro, moedas, cupons, drops, EXP e cartas passam pelas regras do jogo no servidor; o perfil fica no PostgreSQL e cada operação vai para um registro de auditoria.
- **Batalhas em lockstep**: o servidor e cada jogador rodam a mesma partida a partir da mesma semente e só os comandos cruzam a rede. Mira e força saem exatamente como o jogador soltou.
- **Salão e salas de verdade**: jogadores online, chat com filtro, salas que outros jogadores veem e entram. **Início** procura uma sala rival do mesmo tamanho; sem ninguém, rivais de IA completam depois de alguns segundos.
- **Instância em grupo**: até 4 jogadores, com a escala por grupo valendo e loot pessoal (cada um com seus drops, baú e cartas).
- **Queda de conexão**: a IA joga por quem caiu e, ao entrar de novo, a batalha é reaberta onde estava; as recompensas não se perdem.

## Leilão e Correio (0.12)
O prédio do **Leilão** na cidade abre a casa de leilões (só online; `docs/screens/auction.png`, `auction_sell.png`, `auction_en.png`):
- **Comprar**: busca com filtros de tipo (armas, camisas, calças, chapéus, óculos, asas, anéis, amuletos ou mapas), qualidade, nível do item ou do mapa, fortalecimento, bônus, preço máximo em Solares e em Estrelas, e ordem (mais recentes, menor preço, maior nível). O anúncio mostra os bônus (ou as ameaças e recompensas do mapa), o vendedor, quanto tempo falta e as **vendas recentes** de itens parecidos. **COMPRAR** é compra imediata (lances ficam para depois) e o item vai direto para a Mochila.
- **Vender**: equipamentos que caíram nas instâncias e mapas, sem vínculo e sem estar equipados. Preço em Solares e/ou Estrelas, duração de 12, 24 ou 48 h. Anunciar custa uma **taxa em moedas de ouro** (30, 50 ou 80, pela duração) e a venda paga uma **comissão de 5%** de cada moeda (arredondada para baixo); a tela mostra quanto chega.
- **Meus anúncios**: até 10 à venda ao mesmo tempo, com **CANCELAR** (o item volta; a taxa não), e os últimos encerrados (vendidos, cancelados ou vencidos).
- **Correio** (barra de baixo, com o número de cartas; `mail.png`): chegam os Solares e Estrelas das vendas e os itens de anúncios cancelados ou vencidos. **RECEBER** ou **RECEBER TUDO**.
- **Vinculados** não vão ao leilão: itens da Loja, de cupons, cópias do Espelho Celeste, a arma inicial e as Super Verdadeiras depois de equipadas (sem equipar, dá para vender).
- **Custódia no servidor**: ao anunciar, o item sai da Mochila e fica no PostgreSQL; a venda, o pagamento e o item mudam de dono numa transação só, junto com o perfil de quem compra ou recebe. Nada é duplicado nem se perde, mesmo com dois compradores ao mesmo tempo ou a conexão caindo. Tudo fica no registro de auditoria.

| Tela | O que tem |
|---|---|
| **Entrada** (`docs/screens/title.png`, `title_en.png`) | Arte com os heróis e dirigíveis, logotipo **GUSTFIRE · ARTILHARIA NOS CÉUS** (em inglês, *SKY ARTILLERY*) com brilho passando, lista dos servidores online e o **Modo offline**, conta e senha (**CRIAR CONTA** / **ENTRAR**, ou Enter) e o idioma do jogo (**Português** ou **English**) no canto. |
| **Cidade** (`docs/screens/city.png`) | Ilha com o Salão de Jogos (coliseu) no centro da praça e seis prédios nos lotes em volta: Ferreiro, Instância, Leilão, Casa de Câmbio, Centro Comercial e Casa dos Mascotes. Mar em movimento, fumaça da chaminé e brilho da forja, faíscas no coliseu, portal girando, brilhos nas lojas e gaivotas. Todos os prédios abrem (**Leilão** e **Casa de Câmbio** só online). Botões **CUPOM**, **MOCHILA** e **FOUNDER PACK**, alto-falante, canal, chat e a barra SHOP · MOCHILA · PET · CORREIO · MISSÃO · AJUDA · SAIR (CORREIO e MISSÃO com bolinha de contagem). A cidade avisa "Caçada pronta para coletar" no prédio dos mascotes. |
| **Mochila** (`bag.png`, `bag_card.png`) | Informações Pessoais: o personagem num pedestal com holofote, vestindo tudo o que está equipado, com a aura da arma atrás da cabeça e dos ombros, e os espaços Chapéu, Óculos, Cabelo, Roupa, Asas, Arma e Auxiliar em volta (vazios mostram a silhueta do que vai ali). Ataque, Defesa, Agilidade, Sorte, Dano, Proteção, Vida e Força física com ícones. Inventário com Armas, Visual, Auxiliar, Materiais e **Mapas**: a qualidade é um brilho atrás do item; passar o mouse mostra o cartão do item (atributos, comparação com o equipado, bônus, nível, venda); arrastar organiza a mochila do seu jeito (**ORGANIZAR** volta à ordem padrão) e equipa soltando no personagem; clique duplo equipa; equipar, remover e vender. |
| **Ferreiro** (`smith.png`, `smith_moedas.png`) | **Fortalecer** até +12 com Pedras de Fortalecimento, **Transferência** do nível entre dois itens do mesmo tipo e **Moedas**: usar Brasa, Coroa, Estrela, Tormenta, Solar, Eclipse e Espelho Celeste em equipamentos e mapas. |
| **Centro Comercial** (`shop.png`) | Armas em Normal e Excelente (a Verdadeira só cai nas instâncias); skins, camisas, calças, chapéus, óculos, asas, anéis, amuletos, cabelos, itens auxiliares e pedras; **provador** que veste o item antes de comprar. Super armas não são vendidas. |
| **Salão de Jogos** (`hall.png`, online: `hall_online.png`) | Lista de salas, filtro, informações do usuário com o personagem equipado, lista de jogadores, **Equipe**, **Buscar** e **Jogar**. |
| **Sala** (`room.png`, `pve.png`, online: `room_online.png`) | 4 vagas com cada jogador vestido (roupa, chapéu, asas e auras), VS, modos, mapa, tempo do turno, ferramentas Z/X/C, Convide, Local e Início. Na Instância, **Local** escolhe uma das 5 instâncias e o **espaço de mapa** recebe um mapa da mochila (nível, qualidade e atributos) ou fica na entrada livre. |
| **Partida** (`battle.png`, `pve_battle.png`) | Personagens deitados, com a arma nas costas, asas, chapéu e óculos; as auras não aparecem em batalha. Habilidades **1–9**: +2, x3, +1, POW 50%, 40%, 30%, 20%, 10% e POW máx (enche a barra de POW). Cada arma tem projétil, rastro e especial (POW) próprios. Tudo da 0.4 continua: Delay, vento, Z/X/C, POW, avião, Confiar, terreno destrutível. Slot **V** para o item auxiliar. |
| **Som** | Música épica em loop para a entrada/cidade/salas, outra para as batalhas e outra para a Instância. Cada arma tem som de disparo e de impacto próprios; explosões em três tamanhos, POW, habilidades, ferramentas, contagem final do turno, "sua vez", vitória e derrota. **M** liga/desliga a música em qualquer tela; a pausa da partida liga/desliga música e efeitos. |
| **Leilão** (`auction.png`, `auction_sell.png`) | Online: abas Comprar (filtros, detalhes, vendas recentes e compra imediata), Vender (preço, duração, taxa e o que chega no Correio) e Meus anúncios. Botão do Correio com as cartas esperando. |
| **Correio** (`mail.png`) | Online: vendas do Leilão e itens que voltam; RECEBER e RECEBER TUDO. O ícone CORREIO da barra mostra quantas cartas esperam. |
| **Resultado e cartas** (`result.png`, `cards.png`) | Resultado com o personagem equipado; cartas de recompensa. Depois de uma instância: nível, fases vencidas, mapas encontrados e o **baú do chefe** (3 cartas ou mais, cartas de mapa, armas Verdadeiras e a Super Verdadeira, só por sorte). |

## Tudo no seu computador, no navegador
Um comando sobe o banco (PostgreSQL), a API, o servidor de jogo e o jogo web com o Docker, e o site oficial abre em **http://localhost:8000** (o jogo fica em **/jogar/**, no botão JOGAR do site):

- **Windows**: abra o Docker Desktop e dê dois cliques em **SubirLocal.cmd** (ou `powershell -File tools/local.ps1`).
- **Linux e macOS** (e depois a VM): `tools/local.sh`.

A primeira vez leva alguns minutos (baixa o Godot, importa os assets e exporta o jogo para o navegador); depois é rápido. O script cria `server/.env` com senha e chave aleatórias e os cupons de teste ligados, espera o servidor de jogo aparecer e abre o navegador. Crie a conta na própria página e jogue. Outros comandos: `status`, `logs [api|game|web|db]`, `stop` e `reset` (apaga o banco, pede confirmação). Detalhes, variáveis e o que muda numa VM em `server/README.md`.

Tudo passa por um endereço só: o nginx do serviço `web` entrega o site em `/` e o jogo em `/jogar/`, manda `/v1/...` para a API e `/ws` para o servidor de jogo. O jogo do computador (Jogar.cmd) continua entrando pelas portas 8080 e 7350, que ficam abertas só nesta máquina.

## Versão web para testes fechados
A versão web roda sem threads, então não precisa de `SharedArrayBuffer` nem dos cabeçalhos COOP/COEP: qualquer hospedagem estática serve (itch.io, GitHub Pages, Netlify, nginx). Preset **Web** em `export_presets.cfg` (os documentos, testes, ferramentas e metadados do PixelLab ficam de fora do pacote).

```bash
python tools/web_build.py templates   # baixa só os modelos web do Godot 4.7.2 (~20 MB, não o pacote de 1,2 GB)
python tools/web_build.py export      # importa e exporta para build/web (13,6 MB de .pck + 37,7 MB de .wasm; ~23 MB para baixar com gzip)
python tools/web_build.py serve --api http://localhost:8080   # http://localhost:8060, /v1/... vai para a API
node tools/web_bench.cjs --seconds 30 # FPS da batalha no Chromium (Playwright); --headed usa a placa de vídeo
```

- **No navegador**, o endereço aceita as mesmas opções da linha de comando: `?bench=30` (teste de desempenho), `?fps=1` (contador; **F3** liga e desliga em qualquer tela), `?lang=en`, `?api=https://...`.
- **Teste de desempenho** (`--bench=30` no computador, `?bench=30` na web): uma batalha 4 contra 4 jogada pela IA, 3 s de aquecimento e a medição: FPS médio e dos 1% mais lentos, tempo de quadro (média, 95%, 99%), tempo dos scripts separado do desenho, chamadas de desenho e nós. O resultado aparece na tela, no log (`BENCH {...}`) e em `window.ftBench`; usa um perfil de rascunho e nunca mexe no seu save.
- **API na web**: por padrão o jogo procura a API no próprio endereço da página (o proxy de produção manda `/v1/...` para a API, sem CORS). Numa página `https://`, o servidor de jogo precisa de `wss://` (`GAME_PUBLIC_URL`), senão o navegador bloqueia.
- No navegador não há botão SAIR na entrada; SAIR na cidade volta para a tela de entrada.
- O navegador não tem fontes do sistema: as setas e marcas que a fonte pixel não tem (← → ↑ ↓ ▶ ◀ ► ⇄ ↵ ✓) vêm de um recorte da DejaVu Sans Bold que vai no jogo (`assets/fonts/DejaVuSans-Bold-Symbols.ttf`, 2 KB).

### Celular e tablet (0.23)

O jogo tem **modo toque** (controles na tela, botões maiores, toque longo no lugar do hover) e roda em Android e iPhone sem loja: no navegador, num APK e como projeto Xcode. Guia completo, o roteiro do spike e o que ficou em aberto em `docs/MOBILE.md`.

```bash
tools/local.sh                                                 # a stack local; no celular: http://<ip>:8000/jogar/ (GAME_PUBLIC_URL com o IP da rede)
python tools/mobile_build.py android --api http://<ip>:8000    # APK em build/android/gustfire.apk
python tools/mobile_build.py ios --bundle com.voce.gustfire    # projeto Xcode zipado, para o Mac
python tools/mobile_build.py share                             # APK e zip em http://<ip>:8062/ (nginx em Docker)
```

No celular, **três dedos juntos** mostram o contador de FPS. No computador, `--touch=1` (`?touch=1` na web) liga o modo toque.

**Medição (25/09/2026, batalha 4v4, 8 lutadores, 1280×720):**

| Onde | FPS | Scripts por quadro a 60 FPS | Observação |
|---|---|---|---|
| Chromium sem placa de vídeo (SwiftShader, desenho na CPU, contêiner de testes) | 6,3 (1% mais lentos: 1) | 1,9 ms (95%: 3,6 ms) | ~154 ms por quadro são o desenho em software; 266 chamadas de desenho por quadro |
| Export Linux (preset da Steam) com OpenGL em software (llvmpipe) | 21 (1% mais lentos: 15,5) | 1,0 ms (95%: 1,4 ms) | o jogo exportado roda; o desenho em software ainda é o limite |
| Godot nativo sem tela (só lógica) | — | 0,9 ms (95%: 1,2 ms) | o mesmo código fora do navegador |

A lógica do jogo usa ~2 ms dos 16,7 ms de um quadro a 60 FPS dentro do navegador, então o limite é o desenho. O número que os testadores vão ver precisa ser medido numa máquina com placa de vídeo: `node tools/web_bench.cjs --headed` ou abrir `?bench=30` no navegador. Os picos isolados (1% mais lentos) vêm da primeira compilação de shaders de cada efeito (explosão, POW), comum no WebGL.

## Privacidade e contas (LGPD/GDPR)
- **Termos de Uso e Política de Privacidade** em português e inglês (`legal/`), dentro do jogo: links na tela de entrada, em **AJUDA** e no cadastro. Quem opera o jogo (razão social, CNPJ, e-mail, encarregado) é preenchido uma vez em `legal/controller.json`. São modelos escritos a partir do que o sistema guarda de verdade: **precisam de revisão jurídica antes de publicar**.
- **Consentimento**: CRIAR CONTA abre o aceite dos dois textos e a declaração de idade (13 anos ou mais; menores de 18 com o responsável). A API só cria a conta com a versão atual (`accept_terms`) e guarda a versão e o momento. Se os textos mudarem (`Legal.VERSION` no jogo e `LEGAL_VERSION` na API), o servidor de jogo recusa a entrada (`terms_required`) e o jogo mostra os textos novos para aceitar de novo.
- **AJUDA → Minha conta** (`docs/screens`: `--screen=account`): **Baixar meus dados** (um JSON com a conta, o perfil, as sessões, o Leilão, o Correio, os registros de acesso e o registro de atividades; na web é baixado pelo navegador) e **Excluir conta** com a senha. Online a exclusão passa pelo servidor de jogo, que para de gravar o perfil, pede a exclusão à API e fecha a conexão; na tela de entrada (conta lembrada, sem servidor) vai direto à API.
- **O que a exclusão apaga**: conta, personagem, itens, sessões, Correio, anúncios ativos, as mensagens de chat e o nome do personagem no registro de atividades; o resto do registro fica sem a conta até o prazo.
- **Prazos** (variáveis da API): registro de atividades 365 dias, chat 90 dias e **registros de acesso** (IP, data e hora do cadastro e dos logins) 6 meses, como exige o Marco Civil da Internet (art. 15).

## Denúncia no chat
- **Online**, o nome de outro jogador no chat é um link: abre **DENUNCIAR MENSAGEM** (`--screen=report`) com o motivo (ofensa, ódio, spam, golpe ou venda por dinheiro, dados pessoais, nome ofensivo, outro), detalhes opcionais e **Ocultar as mensagens deste jogador para mim**.
- O servidor de jogo guarda quem escreveu cada linha (as últimas 500), confere a denúncia (não dá para denunciar a própria linha nem a mesma linha duas vezes; 5 denúncias a cada 10 minutos) e manda à API a mensagem com as linhas em volta. Denúncias de **3 jogadores diferentes** em 10 minutos silenciam o autor por 10 minutos (`REPORT_MUTE`).
- A equipe analisa com `tools/moderate.py` (lista com o contexto e o histórico, decide descartar, avisar ou suspender). A suspensão desconecta o jogador em até 10 s. Detalhes em `server/README.md`.

## Steam (0.13)
Integração pronta, à espera do App ID e da extensão GodotSteam (passo a passo e checklist da Steamworks em [docs/STEAM.md](docs/STEAM.md)):
- **ENTRAR COM A STEAM**: rodando pela Steam, a entrada pede um ticket ao GodotSteam e a API confere com a Steam; um SteamID novo ganha conta depois do aceite dos Termos. Contas antigas se ligam em **Minha conta → Vincular à Steam**.
- **Loja Premium** (aba nova do Centro Comercial): pagamento pela carteira Steam (microtransações), com o overlay da Steam aprovando; o pedido pago e os itens no Correio ficam na mesma transação no PostgreSQL, e o que foi aprovado com o jogo fechado chega no próximo login. Só aparência: o catálogo (`shared/balance/store.json`) aceita apenas cosméticos `premium` sem atributos, vinculados e fora da loja de ouro. Hoje vende o Passe do Caçador, as abas da Mochila e o Pacote Fundador; **cabelo não se vende por dinheiro** (0.27: as tinturas saíram da loja paga e viraram itens de ouro) e as skins épicas chegam na 0.28.
- **Conquistas**: 11, liberadas pelo perfil online (`shared/balance/achievements.json`).
- **Builds**: presets Windows e Linux (Steam Deck); modelos do SteamPipe em `store/steam/steampipe/`.
- **Página "em breve"**: textos em pt e en, cápsulas em todos os tamanhos, capturas nos dois idiomas e ícones das conquistas em `store/steam/` (gerados por `tools/steam_store.py`). Sem o GodotSteam o jogo funciona como antes (conta e senha; a aba Premium avisa "Só na versão Steam").

## Armas
Nove armas clássicas em três qualidades, **Normal**, **Excelente** e **Verdadeira**: Tijolaço, Braseiro, Prisma, Cata-Vento, Pomar, Tônico, Bota-Fora, Para-Raios e Sugador. E três **Super Verdadeiras**, que só caem na Instância: Super Minotauro, Super Cupido e Super Lança de Jade (nomes da revisão de identidade de 25/09/2026; as ids internas e os saves não mudaram). Os especiais: tijolo que se parte, rajada tripla de fogo, raio prismático do céu, shuriken gigante que ignora o vento, chuva de frutas, cura em área, geladeira que cai do céu, três raios, ventosas que puxam, touro espectral que empurra, bumerangue que volta e cura, e chuva de lanças.

**Fortalecimento** até +12: cada tentativa usa uma pedra do nível de destino e moedas. A chance vai de 100% no +1 a 20% no +12; a falha preserva o nível. Cada nível deixa o item mais forte: a arma ganha dano e todos os itens fortalecidos ganham +10% dos seus atributos por nível (Ataque, Defesa, Agilidade, Sorte); camisa, calça e chapéu também dão Defesa e Vida. O ícone da arma evolui no +9, +10 e +12, e a **aura** atrás da cabeça e dos ombros muda de cor: +1–5 verde, +6–8 azul, +9–11 roxa, +12 vermelha. A camisa fortalecida ganha a própria aura: um brilho em volta do corpo e partículas subindo. As auras aparecem fora das lutas (Mochila, Sala, Salão, Loja, cidade); a arma nas costas aparece só nas lutas.

**Visual do personagem:** conta nova começa de camiseta e shorts. A **skin** troca o corpo inteiro (Explorador, Samurai, Ninja, Capitão; Exploradora, Princesa, Maga, Marinheira) e é só aparência, sem atributos; chapéu, óculos e asas vão por cima e o cabelo muda de cor; a opção **Só a skin** (na Mochila e no provador da loja) esconde tudo isso sem mexer nos atributos. **Camisa e calça** dão os atributos e a Defesa, mas não aparecem no boneco. Dois **anéis** (os dois espaços aceitam o mesmo catálogo, nunca o mesmo anel duas vezes) e o **amuleto**, que sempre dá **vida** (150 a 300 conforme a qualidade) além de um atributo, completam os 12 espaços; anel e amuleto não vão ao Ferreiro (`docs/SKINS.md`).

**Skins épicas (0.28):** a loja Premium vende **Tempestade Viva**, **Coroa de Gelo** e **Coração de Magma** (R$ 44,90 cada, ou as três no **Pacote da Temporada 1** por R$ 109,90). Cada uma é um item e um produto para os dois gêneros (uma pasta de arte por gênero), com as quatro direções em pé, a pose deitada e os 7 clipes de batalha (parado, andar, tiro, dano, vitória, derrota e POW), mais uma **camada própria** viva (`SkinFx`: arcos de raio, flocos de gelo, brasas) que reage ao que o personagem faz e tem um floreio no POW. Só aparência, sem atributos e sem caixa aleatória. O provador da loja ganhou **Em pé** (gira nas quatro direções) e **Batalha** (andar, atirar, POW e vitória). O cupom `TESTARTUDO` entrega as três.

**Item auxiliar** (tecla V): Bálsamo e Grande Bálsamo curam; Broquel de Latão e Égide de Aço reduzem o próximo dano.

## POW, habilidades e tracejado (0.7)
- **Consumir habilidade**: quem usa uma habilidade 1–9, ferramenta, item auxiliar, avião ou POW mostra o ícone saltando sobre a cabeça num clarão com raios e o nome embaixo; depois o ícone mergulha no personagem, que brilha na cor da habilidade. Vale para você e para os bots (os combos dos bots aparecem um por um).
- **POW**: ao armar (B), o personagem pega fogo: chamas douradas subindo, anel no chão e faíscas em volta até o disparo. No disparo: linhas de velocidade, estouro em quadrinho **POW!** com o nome do especial numa faixa, clarão, coluna de luz, duas ondas de choque, raios girando, zoom rápido da câmera e tremor. O projétil do POW voa com um halo dourado.
- **Tracejado**: todo disparo deixa uma linha branca tracejada ao longo do voo inteiro. A do seu último disparo fica no mapa até você atirar de novo, para corrigir a mira; as dos outros (azul claro aliados, vermelho claro inimigos) somem depois de cair. O projétil ainda deixa um rastro brilhante sob o efeito próprio de cada arma.

## POW (0.8)
- **Em fases**: ao armar (B) o personagem recua e a arma nas costas brilha; enquanto a força carrega, a aura cresce e partículas são puxadas para a arma; no disparo, clarão, recuo e a arte animada do POW de cada arma; o projétil voa maior, com halo e rastro de partículas nas cores da arma; no impacto, 80 ms de pausa (hit-stop), tremor, ondas de choque e fumaça.
- **Um impacto por arma**: entulho no Tijolaço, lava no Braseiro, anéis de arco-íris no Prisma, redemoinho no Cata-Vento, folhas e frutas, cruzes de cura, cristais de gelo na Geladeira, raios duplos no Trovão, bolhas, chifres de fogo do touro, corações no Bumerangue do Amor e cortes de jade na Lança.
- **Arma e projétil maiores**: a arma nas costas e os projéteis aparecem 1,5× maiores durante toda a batalha (o tiro de POW mais 1,6×). É só desenho: o acerto, o raio da cratera e o dano não mudam (há teste para isso). Os valores ficam em `items.json` → `visual`.

## POW em cut-in, Mochila nova e arma nas costas (0.15)
- **POW**: ao soltar o especial, a tela abre um *cut-in* como nos animes: corte branco, faixa inclinada nas cores da arma, o retrato do jogador (com o visual equipado) saindo por cima da faixa, o nome do especial letra por letra e a arte do especial. A faixa se fecha num corte e só então o tiro sai (a partida segura o tiro durante o *cut-in*, também online). `docs/screens/pow_cutin.png`.
- **Mochila**: pedestal com holofote, cartão do item ao passar o mouse, brilho de qualidade no lugar dos quadrados coloridos, arrastar para organizar e para equipar. Ver a tabela abaixo.
- **Batalha**: a arma nas costas fica apoiada no corpo em vez de flutuar (`docs/screens/back_weapons.png`).

## HUD da batalha novo (depois da 0.15)
- **Barra de força** com régua, degradê amarelo → vermelho, brilho, faíscas na ponta e a flâmula do último tiro; **habilidades** com ícones novos, tecla, brilho, cinza quando indisponíveis e moldura dourada no que foi armado; **POW** num orbe de vidro que enche; **relógio** com anel e números que tremem nos últimos segundos; **vento** em setas; **minimapa** com moldura, rodada e a visão da câmera; mostrador de ângulo, energia e vida redesenhados (`docs/screens/battle.png`, `battle_armed.png`).
- **Vitória e derrota** em tela cheia: emblemas novos, raios, letras caindo uma a uma, confete ou cinzas (`docs/screens/battle_victory.png`, `battle_defeat.png`).

## Especiais e monstros com habilidades (0.14)
- **Cada especial (POW) é único do começo ao fim**: a arte do especial entra na tela junto com o estouro **POW!** (um corte como no DDTank), o tiro voa com um projétil próprio desenhado no PixelLab (tijolo em chamas douradas, cometa, cristal-prisma, shuriken num vórtice, maçã dourada, cápsula de cura, TV elétrica, bola de raios, desentupidor gigante, cabeça de touro espectral, bumerangue de coração, lança de jade) e, onde cai, explode com a animação própria da arma (antes ela tocava escondida atrás do "POW!", no atirador). As capturas estão em `docs/screens/pow_specials.png`.
- **Os monstros das instâncias não atiram mais: usam habilidades.** Cada um tem 2 a 5, escolhidas pelo que faz sentido onde todos estão: **salto** (pula ao lado do alvo, golpeia com garras, machado ou lança e volta), **mergulho** (quem voa desce num rasante e volta), **golpe no chão** (onda de choque em volta de si), **magia do céu** (miras vermelhas sobre os alvos e, em seguida, lanças de sol, estalactites, raios, penas, machados, corvos ou meteoros caindo), **sopro** (fogo, gelo ou vento num cone até o alvo), **escudo** (aliados perto recebem metade do próximo dano), **grito de guerra** (o próximo ataque dos aliados é 30% mais forte) e **cura**. Algumas deixam o alvo **queimando** (dano no começo dos próximos turnos) e o Sopro Glacial da Rainha ainda congela. O nome e o ícone da habilidade aparecem sobre a cabeça do monstro, como as habilidades 1–9. Habilidades de fúria só vêm com o monstro enfurecido; com 3–4 jogadores, as magias do chefe caem em todos. O dano geral fica em `combat.json` → `pve.ability_damage` (1,08 desde a 0.16).
- **Fiorde dos Vikings**, a quinta instância: Praia dos Drakkars (Saqueadores Vikings e Corvos Rúnicos), Aldeia do Hidromel (Berserker Urso) e o Trono do Jarl, onde o **Jarl Barba-de-Ferro** chama o Martelo do Trovão, investe com o martelo, faz o chão tremer, ergue a Muralha de Escudos e chama reforços a cada 3 turnos. Mapas, inimigos e o ícone do mapa são arte nova do PixelLab (`docs/PIXELLAB_0_14.md`); capturas em `docs/screens/viking_*.png`.

## Instâncias mais difíceis: efeitos de estado e elites (0.16)
- **Efeitos de estado**: as habilidades dos monstros deixam efeitos que duram alguns turnos da vítima. **Queimação** (perde vida no começo do turno), **Envenenamento** (2% da vida máxima por dose, até 3 doses, e metade da cura), **Congelamento** (perde o turno; depois fica 1 turno imune ao gelo), **Exaustão** (andar, habilidades 1–9 e avião custam 50% mais energia), **Selo** (sem habilidades 1–9 nem POW), **Raízes** (não anda nem usa o avião), **Marca da Caça** (+30% de dano recebido; os monstros preferem o alvo marcado) e **Ofuscamento** (o vento vira "??" e a linha de mira some). Cada efeito tem ícone do PixelLab, som e desenho próprios sobre o lutador (chamas, bolhas, cristal de gelo, gotas de suor, anel de runas, raízes, mira vermelha, brilhos) (`docs/screens/status_turn.png`, `status_seal.png`, `status_frozen.png`).
- **Maldições** (`hex`): habilidade nova que fecha um círculo de runas na vítima e aplica o efeito sem dano — Julgamento Solar (Guardião do Templo, marca por 2 turnos), Riso Maldito (Máscara Flamejante, selo), Correntes de Gelo (Rainha da Nevasca, raízes e exaustão) e Grilhões de Ferro (Jarl, raízes e selo). A IA só amaldiçoa quem ainda não carrega o efeito.
- **Elites** (como os monstros mágicos do PoE): lacaios, e às vezes o guardião, podem vir como elite, com +50% de vida, +15% de dano, 15% maiores, uma aura no chão na cor do afixo e o afixo no lugar da patente: **Chamas**, **Veneno**, **Gelo** (exaustão e 25% de congelar), **Vampira** (recupera 35% do dano), **Encouraçada** (escudo que volta a cada 2 turnos), **Explosiva** (explode ao morrer e fere quem estiver perto) e **Veloz** (joga com muito mais frequência). Chance de 6% na entrada livre, +2% por nível de mapa (`docs/screens/elites.png`).
- **Mais monstros**: a fase 1 tem 2 + 3 lacaios, o guardião chama um reforço e o chefe vem com um lacaio (quando o chefe cai, a fase acaba e os lacaios fogem).
- **Contra-jogo**: a ferramenta **Elixir Purificador** (60 moedas, na sala) tira todos os efeitos; a IA do Confiar bebe quando os efeitos se acumulam. A vida recuperada entre as fases subiu de 30% para 35%.
- **Na HUD**: os efeitos do jogador ficam ao lado do retrato (ícone, turnos restantes, doses; passar o mouse explica), cada retrato da fila de turnos mostra os seus, correntes cobrem as habilidades quando selado, "x1.5" na energia quando exausto e "SUA VEZ!" lembra o que pesa no turno.
- **Ameaças novas nos mapas**: "+X% de inimigos de elite" e "Efeitos negativos duram +1 turno".
- **Balanceamento** (simulação `tests/instance_balance.gd`, IA jogando sem poções): um herói nível 6 com arma Normal vence ~47% da entrada livre (antes ~80%) e um nível 15 Excelente+6 ~73% (antes ~93%); nos mapas nível 5 o nível 15 vence ~43% (antes ~80%). Precisa de teste com jogadores.

## Instâncias e mapas (0.9)
Cinco instâncias (a quinta entrou na 0.14), cada uma com 3 fases e o chefão na última:

| Instância | Fase 1 | Fase 2 | Fase 3 (chefão) |
|---|---|---|---|
| Templo do Sol | Pátio do Templo: 2 ondas de Escaravelhos Solares (2 + 3) | Câmara do Guardião: Guardião do Templo, lacaio e reforço | Rei Hélio e um Escaravelho (Fúria Solar abaixo de 50%) |
| Trono das Máscaras | Portões de Brasa: 2 ondas de Máscaras Flamejantes (2 + 3) | Salão das Máscaras: Sentinela de Obsidiana, lacaio e reforço | Rei das Máscaras e uma Máscara (invoca máscaras a cada 3 turnos) |
| Picos Gelados | Trilha Congelada: Lobos da Nevasca (2 + 3) | Caverna de Cristal: destrua os 3 cristais | Rainha da Nevasca e um Lobo (o Sopro Glacial congela: a vítima perde a vez) |
| Ilha Celeste em Ruínas | Margem das Nuvens: Harpias (2 + 3) | Ruínas Flutuantes: sobreviva 5 turnos | Grifo da Tempestade e uma Harpia (voa para outro ponto depois de atacar) |
| Fiorde dos Vikings | Praia dos Drakkars: Saqueadores Vikings e Corvos Rúnicos (2 + 3) | Aldeia do Hidromel: Berserker Urso, lacaio e reforço | Jarl Barba-de-Ferro e um Corvo (Muralha de Escudos e reforços a cada 3 turnos) |

Entre as fases: tela de transição, +35% de vida, o POW continua e quem caiu volta com 20% de vida. Moedas e mapas caem em cada fase vencida e ficam mesmo se a equipe cair depois.

**Mapas** (como no PoE 2) substituem as dificuldades Normal, Difícil, Heroico e Pesadelo. Um mapa é um item ("Mapa: Templo do Sol — Nível 5") que abre aquela instância naquele nível e é consumido ao entrar. Níveis 1 a 16: por nível, vida dos inimigos ×1,12, dano ×1,07 e XP/ouro +10%; o nível do mapa vira o nível dos itens que caem. Qualidades Normal (sem atributos), Excelente (1–2) e Verdadeira (3–4), com **ameaças** (mais vida ou dano, lacaio extra, chefe em fúria, vento forte, menos energia, turno de 15 s, sem avião, escudo no primeiro golpe; cada uma dá +10% de quantidade) e **recompensas** (chance de mapa, XP, ouro, quantidade, raridade, carta extra no baú, chance de Super Verdadeira). Mapas caem de mapas: sem atributos, cerca de 0,9 por partida; o nível que cai é o mesmo (70%), +1 (25%) ou +2 (5%). A entrada livre (sem mapa) tem recompensa baixa e dá mapas de nível 1. Os mapas ficam na aba **Mapas** da Mochila.

**Grupo**: a escala por número de jogadores (vida 1,8×/2,5×/3,2×, dano, lacaios extras, recompensa e cartas; com 3–4 jogadores as magias do chefe caem em todos) está pronta e testada, e passa a valer quando houver grupos online; bots na sala não contam.

## Atributos aleatórios e moedas (0.10)
Como no PoE 2, armas, camisas, calças, chapéus, óculos, asas, anéis e amuletos têm **atributos bônus aleatórios**: Normal 0, Excelente 1–2, Verdadeira 3–4 e Super Verdadeira sempre 4 (`bag_bonus.png`).

| Peça | Bônus possíveis |
|---|---|
| Arma | +Ataque · +% dano · +% dano crítico · +% dano do POW · POW inicial · chance de não gastar a habilidade 1–9 |
| Anel | +Ataque · +Sorte · +% dano crítico · +% dano do POW |
| Amuleto | +vida máxima · +Defesa · +energia por turno · −Delay |
| Camisa, calça, chapéu, óculos e asas | +Defesa · +vida máxima · +Agilidade · +Sorte · +energia por turno · −Delay · −% efeito do vento (até 50%) · +% cura recebida |

Cada bônus tem faixas **F1** (melhor) a **F5**. O **nível do item** é o nível do mapa onde ele caiu e libera as faixas: F5 no nível 1, F4 no 4, F3 no 7, F2 no 10 e F1 no 13. Por isso mapas altos dão itens melhores, e não só mais itens. Nenhum bônus muda o raio da explosão ou o hitbox, e o fortalecimento continua aumentando só os atributos base.

**Moedas** (aba **Moedas** do Ferreiro, `smith_moedas.png` e `smith_moedas_mapas.png`). Usar gasta a moeda; se não der para usar, o botão fica apagado e a dica explica o motivo.

| Moeda | Uso em itens e mapas | Cai em |
|---|---|---|
| **Brasa** (Ember) | Normal → Excelente, com 1 bônus | qualquer mapa e a entrada livre; um pouco no PvP |
| **Coroa** (Crown) | Excelente → Verdadeira, com +1 bônus | mapas de nível 1+; um pouco no PvP |
| **Estrela** (Star) | Acrescenta 1 bônus (até o limite da qualidade) | nível 3+ |
| **Tormenta** (Storm) | Rerola todos os bônus | nível 3+ |
| **Solar** | Rerola só os valores, mantendo quais bônus são | nível 5+ (moeda principal do leilão) |
| **Eclipse** | Remove 1 bônus | nível 2+ |
| **Espelho Celeste** (Sky Mirror) | Duplica um equipamento; a cópia fica vinculada e não pode ser modificada | nível 10+, muito rara |

Cada fase vencida pode dar uma moeda (o chefão sempre dá) e o baú tem cartas de moeda e de equipamento (camisas, calças, chapéus, óculos, asas, anéis e amuletos, com nível do item). As moedas raras ficam mais comuns em mapas altos. As moedas de ouro continuam para NPC, Loja e Ferreiro. Itens da Loja e de cupons vêm sem bônus e **vinculados**: não vão ao leilão.

## Idiomas (português e inglês)
O jogo inteiro está em **português e inglês** (`title_en.png`, `city_en.png`, `bag_en.png`): telas, mensagens da partida, chat simulado, nomes de armas, itens, moedas, inimigos, instâncias, mapas e atributos. O idioma é escolhido na tela de entrada e fica salvo; na primeira vez, segue o idioma do sistema (português para quem usa o sistema em português, inglês para os demais). Os nomes em inglês têm versão própria (Tijolaço → *Bricklayer*, Cata-Vento → *Pinwheel*, Instância → *Dungeon*, Brasa → *Ember*, Espelho Celeste → *Sky Mirror*), não tradução literal.

Como funciona: o português é o idioma-fonte e cada texto é a própria chave (estilo gettext). O código usa `tr("...")` nas telas e `Lang.t("...")` nas regras; os nomes dos JSON de balanceamento também são chaves. `python tools/i18n.py` junta tudo em `locale/messages.pot` e atualiza `locale/en.po` (as chaves novas aparecem vazias para traduzir; `--missing` lista as que faltam, `--check` falha se algo ficou sem inglês). Para um terceiro idioma (espanhol, por exemplo), basta um `locale/es.po` com as mesmas chaves e o código em `Lang.LOCALES`; a fonte Pixel Operator já cobre os acentos de português, espanhol e francês.

## Cupons para teste
Na cidade (botão **CUPOM**), na Mochila ou na Loja (offline, ou num servidor com `TEST_COUPONS=1`):
- `TESTARTUDO`: todas as armas em todas as qualidades, as três super armas, auxiliares, todas as skins, camisas, calças, chapéus, óculos, asas, anéis, amuletos e cabelos, 200 pedras de cada nível, 50 cristais e 99.999 moedas.
- `AURAS`: quatro Tijolaços Verdadeiros em +3, +7, +10 e +12, para ver as quatro auras.
- `PEDRAS`: 50 pedras de cada nível.
- `MAPAS`: mapas de todas as instâncias nos níveis 1, 5, 10 e 16, de qualidades variadas (pode ser usado de novo).
- `MOEDAS`: 30 Brasas, 20 Coroas, 10 Estrelas, 10 Tormentas, 5 Solares, 10 Eclipses e 1 Espelho Celeste (pode ser usado de novo).
- `OVOS`: 10 ovos de cada elemento e 10 Ovos de Mascote para testar a Casa dos Mascotes (pode ser usado de novo).
- `CACADA`: o Passe do Caçador (acúmulo de 8 h) para testar a Caçada (pode ser usado de novo).

Os outros cupons valem uma vez por conta.

## Controles na partida
← → andar (gasta energia) · ↑ ↓ ângulo · segurar/soltar **Espaço** força · **1–9** habilidades · **Z X C** ferramentas · **B** POW · **F** avião · **V** item auxiliar · **P** passar · **Q** virar · **Esc** pausa · **M** música · botão direito arrasta a câmera · clique no minimapa move a câmera.

## Verificação
Execute: `powershell -File tools/run.ps1 -Test` — 563 verificações (combate 54, instâncias e mapas 66, interface 77, armas/Ferreiro/cupons/especiais 56, POW e escala visual 43, atributos aleatórios e moedas 64, idiomas 24, leilão 62, lançamento 117: web, identidade, textos legais, consentimento, Steam e página da loja), mais as de rede: 58 de lockstep e operações e 151 com um servidor e jogadores de verdade (inclui o Leilão, o Correio, a exclusão de conta, a denúncia no chat e a loja Steam com um GodotSteam falso). A API em Go (contas, leilão, privacidade, denúncias e Steam contra uma Steam falsa) e as verificações contra a pilha no ar: `server/README.md`, seção Testes.

Capturas: `godot --path . -- --screen=<title|city|hall|room|pve|battle|pve_battle|result|cards|bag|shop|smith|legal|consent|account|help|report> --out=arquivo.png` (`--lang=en` captura em inglês; `--profile=user://outro.json` evita mexer no seu save; `--demo=1` resgata o TESTARTUDO e o MOEDAS e veste um conjunto de vitrine com bônus; em `smith`, `--tab=Moedas` abre a aba de moedas e `--craft=map` mostra os mapas; em `bag`, `--tab=Atributos` abre os atributos; `--zoom=2` aproxima a câmera da partida; `--map=<id>` escolhe o mapa da partida; em `pve` e `pve_battle`, `--instance=<id>`, `--level=<1..16>` coloca um mapa daquele nível e `--phase=<1..3>` começa na fase pedida).

## Mapas
O chão de cada mapa é uma pintura: ilhas geradas no PixelLab cujo contorno é a colisão, destruídas pixel a pixel. **Ilha Celeste** (ilhas de grama sobre um mar de nuvens), **Pátio do Templo** (ruínas de areia), **Câmara do Guardião** (gelo, com neve caindo), **Trono das Máscaras** (rocha vulcânica, com brasas) e **Templo do Sol** (piso do templo, Instância). Na 0.9 entraram **Portões de Brasa**, **Salão das Máscaras**, **Trilha Congelada**, **Caverna de Cristal**, **Pico da Nevasca** (só na Instância), **Ruínas Flutuantes** e **Santuário dos Ventos**; na 0.14, **Praia dos Drakkars**, **Aldeia do Hidromel** e **Trono do Jarl** (só na Instância). As explosões têm fogo animado, clarão, onda de choque, fumaça e pedaços do chão voando; a cratera fica com a borda queimada.

## Arte
Toda a arte é do PixelLab: a entrada e o logotipo, a cidade e os prédios, os fundos e o chão dos mapas, a explosão, as cartas de recompensa, personagens, as roupas (estados do mesmo personagem, em pé e deitado, com respirar, rastejar e arremessar), armas, chapéus, óculos, asas, itens auxiliares, pedras, as sete moedas, projéteis, o touro espectral, a cidade e os prédios. Os tiers +9/+10/+12 das armas são recoloridos a partir do ícone do PixelLab (`tools/weapon_tiers.py`). A aura da arma é um círculo mágico em alta resolução com brilho, runas, estrela, raios e faíscas (`tools/aura_textures.py`); a aura da roupa é um brilho suave em volta do corpo com luz na borda e faíscas subindo. As asas são desenhadas uma de cada vez em 128×128 e batem a partir do ombro. Tintura de cabelo e brilhos são shaders. Fonte: **Pixel Operator Bold** (CC0, `assets/fonts/PixelOperator-LICENSE.txt`). Cenários aparecem em 2× exato e prédios, armas e cartas em 1×; o que precisa de escala quebrada usa um shader que mantém todos os pixels do mesmo tamanho. Inimigos das instâncias, POW animados, mapas e ícones de mapa da 0.8/0.9: [docs/PIXELLAB_0_9.md](docs/PIXELLAB_0_9.md); ícones das moedas: [docs/PIXELLAB_0_10.md](docs/PIXELLAB_0_10.md); projéteis dos especiais, ícones e artes das habilidades dos monstros e o Fiorde dos Vikings: [docs/PIXELLAB_0_14.md](docs/PIXELLAB_0_14.md). Detalhes anteriores em [docs/PIXELLAB_0_6.md](docs/PIXELLAB_0_6.md), [docs/PIXELLAB_0_5.md](docs/PIXELLAB_0_5.md) e [docs/PIXELLAB_0_4.md](docs/PIXELLAB_0_4.md).

## Som
Todo o áudio é original e gerado por código (`tools/synth.py`, um pequeno sintetizador em numpy): os efeitos por `tools/make_sfx.py` e as três músicas por `tools/make_music.py` (orquestra sintetizada: metais, cordas, coro, harpa, tímpanos e taikos, com reverb de sala). Arquivos em `assets/audio/sfx` e `assets/audio/music` (Ogg Vorbis, cerca de 6 MB no total). Para trocar por outra música, basta substituir `lobby.ogg`, `battle.ogg` ou `instance.ogg`. Detalhes em [docs/AUDIO_0_7.md](docs/AUDIO_0_7.md).

## Limites
No modo offline, salas, jogadores e chat do canal são simulados por IA e isso é avisado no chat; moedas e itens ficam em `user://profile.json` e não valem como economia online; Leilão, Casa de Câmbio e Correio só funcionam online. O leilão ainda não tem lances nem troca direta de moedas (Estrela ↔ Solar; o Câmbio cobre essa troca). Rosto e olhos ainda não são slots separados. A Steam precisa do App ID, da extensão GodotSteam e da configuração na Steamworks; estornos da Steam ainda não retiram o item (docs/STEAM.md, pendências). Pendências do lançamento fora do código: `docs/ROADMAP.md`, "Pendências externas".
