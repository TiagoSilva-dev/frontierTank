# Frontier Tank: Nova Era — 0.12 (Leilão e Correio online)

Abra **Jogar.cmd** para iniciar com o Godot instalado neste computador, ou importe **project.godot** no Godot 4.7 e pressione F5. Em outro computador, configure `GODOT_BIN` com o caminho do executável Godot.

Réplica em pixel art do fluxo clássico do DDTank. Joga **online** (conta, servidor de jogo, salas, chat e batalhas com outros jogadores) ou no **modo offline** contra bots.

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
- **Comprar**: busca com filtros de tipo (armas, roupas, chapéus, óculos, asas ou mapas), qualidade, nível do item ou do mapa, fortalecimento, bônus, preço máximo em Solares e em Estrelas, e ordem (mais recentes, menor preço, maior nível). O anúncio mostra os bônus (ou as ameaças e recompensas do mapa), o vendedor, quanto tempo falta e as **vendas recentes** de itens parecidos. **COMPRAR** é compra imediata (lances ficam para depois) e o item vai direto para a Mochila.
- **Vender**: equipamentos que caíram nas instâncias e mapas, sem vínculo e sem estar equipados. Preço em Solares e/ou Estrelas, duração de 12, 24 ou 48 h. Anunciar custa uma **taxa em moedas de ouro** (30, 50 ou 80, pela duração) e a venda paga uma **comissão de 5%** de cada moeda (arredondada para baixo); a tela mostra quanto chega.
- **Meus anúncios**: até 10 à venda ao mesmo tempo, com **CANCELAR** (o item volta; a taxa não), e os últimos encerrados (vendidos, cancelados ou vencidos).
- **Correio** (barra de baixo, com o número de cartas; `mail.png`): chegam os Solares e Estrelas das vendas e os itens de anúncios cancelados ou vencidos. **RECEBER** ou **RECEBER TUDO**.
- **Vinculados** não vão ao leilão: itens da Loja, de cupons, cópias do Espelho Celeste, a arma inicial e as Super Verdadeiras depois de equipadas (sem equipar, dá para vender).
- **Custódia no servidor**: ao anunciar, o item sai da Mochila e fica no PostgreSQL; a venda, o pagamento e o item mudam de dono numa transação só, junto com o perfil de quem compra ou recebe. Nada é duplicado nem se perde, mesmo com dois compradores ao mesmo tempo ou a conexão caindo. Tudo fica no registro de auditoria.

| Tela | O que tem |
|---|---|
| **Entrada** (`docs/screens/title.png`, `title_en.png`) | Como o login do DDTank: arte com os heróis e dirigíveis, logotipo **FRONTIER TANK · NOVA ERA** com brilho passando, lista dos servidores online e o **Modo offline**, conta e senha (**CRIAR CONTA** / **ENTRAR**, ou Enter) e o idioma do jogo (**Português** ou **English**) no canto. |
| **Cidade** (`docs/screens/city.png`) | Ilha com o Salão de Jogos (coliseu) no centro da praça e seis prédios nos lotes em volta: Ferreiro, Instância, Leilão, Namoro, Centro Comercial e Casa dos Mascotes. Mar em movimento, fumaça da chaminé e brilho da forja, faíscas no coliseu, portal girando, corações da capela, brilhos nas lojas e gaivotas. Prédios clicáveis: **Ferreiro**, **Centro Comercial** e, online, **Leilão** abrem de verdade. Botões **CUPOM** e **MOCHILA**, alto-falante, canal, chat e barra SHOP · MOCHILA · PET · CORREIO · MISSÃO · AJUDA · SAIR. |
| **Mochila** (`bag.png`) | Informações Pessoais como no DDTank: slots Chapéu, Óculos, Cabelo, Roupa, Asas, Arma e Auxiliar em volta do personagem, que veste tudo o que está equipado, com a aura da arma atrás da cabeça e dos ombros. Ataque, Agilidade, Defesa, Sorte, Dano, Proteção, Vida e Força física. Inventário com Armas, Visual, Auxiliar, Materiais e **Mapas**; equipar, remover e vender. |
| **Ferreiro** (`smith.png`, `smith_moedas.png`) | **Fortalecer** até +12 com Pedras de Fortalecimento, **Composição** com Cristal Dourado, **Fusão** de 4 pedras iguais, **Transferência** do nível entre dois itens do mesmo tipo e **Moedas**: usar Brasa, Coroa, Estrela, Tormenta, Solar, Eclipse e Espelho Celeste em equipamentos e mapas. |
| **Centro Comercial** (`shop.png`) | Armas em Normal e Excelente (a Verdadeira só cai nas instâncias); roupas, chapéus, óculos, asas, cabelos, itens auxiliares e pedras; **provador** que veste o item antes de comprar. Super armas não são vendidas. |
| **Salão de Jogos** (`hall.png`, online: `hall_online.png`) | Lista de salas, filtro, informações do usuário com o personagem equipado, lista de jogadores, **Equipe**, **Buscar** e **Jogar**. |
| **Sala** (`room.png`, `pve.png`, online: `room_online.png`) | 4 vagas com cada jogador vestido (roupa, chapéu, asas e auras), VS, modos, mapa, tempo do turno, ferramentas Z/X/C, Convide, Local e Início. Na Instância, **Local** escolhe uma das 4 instâncias e o **espaço de mapa** recebe um mapa da mochila (nível, qualidade e atributos) ou fica na entrada livre. |
| **Partida** (`battle.png`, `pve_battle.png`) | Personagens deitados, com a arma nas costas, asas, chapéu e óculos; como no DDTank, as auras não aparecem em batalha. Habilidades **1–9** iguais às do DDTank: +2, x3, +1, POW 50%, 40%, 30%, 20%, 10% e POW máx (enche a barra de POW). Cada arma tem projétil, rastro e especial (POW) próprios. Tudo da 0.4 continua: Delay, vento, Z/X/C, POW, avião, Confiar, terreno destrutível. Slot **V** para o item auxiliar. |
| **Som** | Música épica em loop para a entrada/cidade/salas, outra para as batalhas e outra para a Instância. Cada arma tem som de disparo e de impacto próprios; explosões em três tamanhos, POW, habilidades, ferramentas, contagem final do turno, "sua vez", vitória e derrota. **M** liga/desliga a música em qualquer tela; a pausa da partida liga/desliga música e efeitos. |
| **Leilão** (`auction.png`, `auction_sell.png`) | Online: abas Comprar (filtros, detalhes, vendas recentes e compra imediata), Vender (preço, duração, taxa e o que chega no Correio) e Meus anúncios. Botão do Correio com as cartas esperando. |
| **Correio** (`mail.png`) | Online: vendas do Leilão e itens que voltam; RECEBER e RECEBER TUDO. O ícone CORREIO da barra mostra quantas cartas esperam. |
| **Resultado e cartas** (`result.png`, `cards.png`) | Resultado com o personagem equipado; cartas de recompensa. Depois de uma instância: nível, fases vencidas, mapas encontrados e o **baú do chefe** (3 cartas ou mais, cartas de mapa, armas Verdadeiras e a Super Verdadeira com garantia). |

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

**Medição (25/09/2026, batalha 4v4, 8 lutadores, 1280×720):**

| Onde | FPS | Scripts por quadro a 60 FPS | Observação |
|---|---|---|---|
| Chromium sem placa de vídeo (SwiftShader, desenho na CPU, contêiner de testes) | 6,3 (1% mais lentos: 1) | 1,9 ms (95%: 3,6 ms) | ~154 ms por quadro são o desenho em software; 266 chamadas de desenho por quadro |
| Godot nativo sem tela (só lógica) | — | 0,9 ms (95%: 1,2 ms) | o mesmo código fora do navegador |

A lógica do jogo usa ~2 ms dos 16,7 ms de um quadro a 60 FPS dentro do navegador, então o limite é o desenho. O número que os testadores vão ver precisa ser medido numa máquina com placa de vídeo: `node tools/web_bench.cjs --headed` ou abrir `?bench=30` no navegador. Os picos isolados (1% mais lentos) vêm da primeira compilação de shaders de cada efeito (explosão, POW), comum no WebGL.

## Armas (como no DDTank)
Nove armas clássicas em três qualidades, **Normal**, **Excelente** e **Verdadeira**: Quebra Tijolos, Fogo Intenso, Canhão Arco-Íris, Vento de Deus, Cesto de Frutas de Newton, Kit Médico, Eletrodoméstico, Trovão e Desentupidor. E três **Super Verdadeiras**, que só caem na Instância: Super Cabeça de Boi, Super Bumerangue do Amor e Super Lança. Ângulos e tipo de POW seguem os guias do DDTank; os especiais: tijolo que se parte, rajada tripla de fogo, raio arco-íris do céu, shuriken gigante que ignora o vento, chuva de frutas, cura em área, geladeira que cai do céu, três raios, desentupidores que puxam, touro espectral que empurra, bumerangue que volta e cura, e chuva de lanças.

**Fortalecimento** até +12 (pedras: +1 = 1 ponto … +12 = 900 pontos, como no artigo do TechTudo). Cada nível deixa o item mais forte: a arma ganha dano e todos os itens fortalecidos ganham +10% dos seus atributos por nível (Ataque, Defesa, Agilidade, Sorte); roupa e chapéu também dão Defesa e Vida. O ícone da arma evolui no +9, +10 e +12, e a **aura** atrás da cabeça e dos ombros muda de cor: +1–5 verde, +6–8 azul, +9–11 roxa, +12 vermelha. A roupa fortalecida ganha a própria aura: um brilho em volta do corpo e partículas subindo. As auras aparecem fora das lutas (Mochila, Sala, Salão, Loja, cidade); a arma nas costas aparece só nas lutas.

**Visual do personagem:** conta nova começa de camiseta e shorts. Roupa troca o corpo inteiro (Explorador, Samurai, Ninja, Capitão; Exploradora, Princesa, Maga, Marinheira), chapéu, óculos e asas vão por cima e o cabelo muda de cor.

**Item auxiliar** (tecla V): Dom de Anjo e Verdadeiro Dom de Anjo curam; Escudo de Bugou e Escudo do Barão reduzem o próximo dano.

## POW, habilidades e tracejado (0.7)
- **Consumir habilidade**: como no DDTank, quem usa uma habilidade 1–9, ferramenta, item auxiliar, avião ou POW mostra o ícone saltando sobre a cabeça num clarão com raios e o nome embaixo; depois o ícone mergulha no personagem, que brilha na cor da habilidade. Vale para você e para os bots (os combos dos bots aparecem um por um).
- **POW**: ao armar (B), o personagem pega fogo: chamas douradas subindo, anel no chão e faíscas em volta até o disparo. No disparo: linhas de velocidade, estouro em quadrinho **POW!** com o nome do especial numa faixa, clarão, coluna de luz, duas ondas de choque, raios girando, zoom rápido da câmera e tremor. O projétil do POW voa com um halo dourado.
- **Tracejado**: todo disparo deixa uma linha branca tracejada ao longo do voo inteiro. A do seu último disparo fica no mapa até você atirar de novo, para corrigir a mira; as dos outros (azul claro aliados, vermelho claro inimigos) somem depois de cair. O projétil ainda deixa um rastro brilhante sob o efeito próprio de cada arma.

## POW (0.8)
- **Em fases**: ao armar (B) o personagem recua e a arma nas costas brilha; enquanto a força carrega, a aura cresce e partículas são puxadas para a arma; no disparo, clarão, recuo e a arte animada do POW de cada arma; o projétil voa maior, com halo e rastro de partículas nas cores da arma; no impacto, 80 ms de pausa (hit-stop), tremor, ondas de choque e fumaça.
- **Um impacto por arma**: entulho no Quebra Tijolos, lava no Fogo Intenso, anéis de arco-íris, redemoinho no Vento de Deus, folhas e frutas, cruzes de cura, cristais de gelo na Geladeira, raios duplos no Trovão, bolhas, chifres de fogo do touro, corações no Bumerangue do Amor e cortes de jade na Lança.
- **Arma e projétil maiores**: a arma nas costas e os projéteis aparecem 1,5× maiores durante toda a batalha (o tiro de POW mais 1,6×). É só desenho: o acerto, o raio da cratera e o dano não mudam (há teste para isso). Os valores ficam em `items.json` → `visual`.

## Instâncias e mapas (0.9)
Quatro instâncias, cada uma com 3 fases e o chefão na última:

| Instância | Fase 1 | Fase 2 | Fase 3 (chefão) |
|---|---|---|---|
| Templo do Sol | Pátio do Templo: 2 ondas de Escaravelhos Solares | Câmara do Guardião: Guardião do Templo e lacaio | Rei Hélio (Fúria Solar abaixo de 50%) |
| Trono das Máscaras | Portões de Brasa: 2 ondas de Máscaras Flamejantes | Salão das Máscaras: Sentinela de Obsidiana | Rei das Máscaras (invoca máscaras a cada 3 turnos) |
| Picos Gelados | Trilha Congelada: Lobos da Nevasca | Caverna de Cristal: destrua os 3 cristais | Rainha da Nevasca (o Sopro Glacial congela: a vítima perde a vez) |
| Ilha Celeste em Ruínas | Margem das Nuvens: Harpias | Ruínas Flutuantes: sobreviva 5 turnos | Grifo da Tempestade (voa para outro ponto depois de atacar) |

Entre as fases: tela de transição, +30% de vida, o POW continua e quem caiu volta com 20% de vida. Moedas e mapas caem em cada fase vencida e ficam mesmo se a equipe cair depois.

**Mapas** (como no PoE 2) substituem as dificuldades Normal, Difícil, Heroico e Pesadelo. Um mapa é um item ("Mapa: Templo do Sol — Nível 5") que abre aquela instância naquele nível e é consumido ao entrar. Níveis 1 a 16: por nível, vida dos inimigos ×1,12, dano ×1,07 e XP/ouro +10%; o nível do mapa vira o nível dos itens que caem. Qualidades Normal (sem atributos), Excelente (1–2) e Verdadeira (3–4), com **ameaças** (mais vida ou dano, lacaio extra, chefe em fúria, vento forte, menos energia, turno de 15 s, sem avião, escudo no primeiro golpe; cada uma dá +10% de quantidade) e **recompensas** (chance de mapa, XP, ouro, quantidade, raridade, carta extra no baú, chance de Super Verdadeira). Mapas caem de mapas: sem atributos, cerca de 0,9 por partida; o nível que cai é o mesmo (70%), +1 (25%) ou +2 (5%). A entrada livre (sem mapa) tem recompensa baixa e dá mapas de nível 1. Os mapas ficam na aba **Mapas** da Mochila.

**Grupo**: a escala por número de jogadores (vida 1,8×/2,5×/3,2×, dano, lacaios extras, recompensa e cartas; ataque em área do chefe com 3–4 jogadores) está pronta e testada, e passa a valer quando houver grupos online; bots na sala não contam.

## Atributos aleatórios e moedas (0.10)
Como no PoE 2, armas, roupas, chapéus, óculos e asas têm **atributos bônus aleatórios**: Normal 0, Excelente 1–2, Verdadeira 3–4 e Super Verdadeira sempre 4 (`bag_bonus.png`).

| Peça | Bônus possíveis |
|---|---|
| Arma | +Ataque · +% dano · +% dano crítico · +% dano do POW · POW inicial · chance de não gastar a habilidade 1–9 |
| Roupa, chapéu, óculos e asas | +Defesa · +vida máxima · +Agilidade · +Sorte · +energia por turno · −Delay · −% efeito do vento (até 50%) · +% cura recebida |

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

Cada fase vencida pode dar uma moeda (o chefão sempre dá) e o baú tem cartas de moeda e de equipamento (chapéus, óculos, asas e roupas do seu gênero, com nível do item). As moedas raras ficam mais comuns em mapas altos. As moedas de ouro continuam para NPC, Loja e Ferreiro. Itens da Loja e de cupons vêm sem bônus e **vinculados**: não vão ao leilão.

## Idiomas (português e inglês)
O jogo inteiro está em **português e inglês** (`title_en.png`, `city_en.png`, `bag_en.png`): telas, mensagens da partida, chat simulado, nomes de armas, itens, moedas, inimigos, instâncias, mapas e atributos. O idioma é escolhido na tela de entrada e fica salvo; na primeira vez, segue o idioma do sistema (português para quem usa o sistema em português, inglês para os demais). Os nomes em inglês têm versão própria (Quebra Tijolos → *Brickbreaker*, Instância → *Dungeon*, Brasa → *Ember*, Espelho Celeste → *Sky Mirror*), não tradução literal.

Como funciona: o português é o idioma-fonte e cada texto é a própria chave (estilo gettext). O código usa `tr("...")` nas telas e `Lang.t("...")` nas regras; os nomes dos JSON de balanceamento também são chaves. `python tools/i18n.py` junta tudo em `locale/messages.pot` e atualiza `locale/en.po` (as chaves novas aparecem vazias para traduzir; `--missing` lista as que faltam, `--check` falha se algo ficou sem inglês). Para um terceiro idioma (espanhol, por exemplo), basta um `locale/es.po` com as mesmas chaves e o código em `Lang.LOCALES`; a fonte Pixel Operator já cobre os acentos de português, espanhol e francês.

## Cupons para teste
Na cidade (botão **CUPOM**), na Mochila ou na Loja:
- `TESTARTUDO`: todas as armas em todas as qualidades, as três super armas, auxiliares, todas as roupas, chapéus, óculos, asas e cabelos, 200 pedras de cada nível, 50 cristais e 99.999 moedas.
- `AURAS`: quatro Quebra Tijolos Verdadeiros em +3, +7, +10 e +12, para ver as quatro auras.
- `PEDRAS`: 50 pedras de cada nível.
- `MAPAS`: mapas de todas as instâncias nos níveis 1, 5, 10 e 16, de qualidades variadas (pode ser usado de novo).
- `MOEDAS`: 30 Brasas, 20 Coroas, 10 Estrelas, 10 Tormentas, 5 Solares, 10 Eclipses e 1 Espelho Celeste (pode ser usado de novo).

Os outros cupons valem uma vez por conta.

## Controles na partida
← → andar (gasta energia) · ↑ ↓ ângulo · segurar/soltar **Espaço** força · **1–9** habilidades · **Z X C** ferramentas · **B** POW · **F** avião · **V** item auxiliar · **P** passar · **Q** virar · **Esc** pausa · **M** música · botão direito arrasta a câmera · clique no minimapa move a câmera.

## Verificação
Execute: `powershell -File tools/run.ps1 -Test` — 446 verificações (combate 54, instâncias e mapas 66, interface 77, armas/Ferreiro/cupons/especiais 56, POW e escala visual 43, atributos aleatórios e moedas 64, idiomas 24, leilão 62), mais as de rede: 58 de lockstep e operações e 108 com um servidor e dois jogadores de verdade (inclui o Leilão e o Correio). O leilão contra a API em Go e o PostgreSQL: `server/README.md`, seção Testes.

Capturas: `godot --path . -- --screen=<title|city|hall|room|pve|battle|pve_battle|result|cards|bag|shop|smith> --out=arquivo.png` (`--lang=en` captura em inglês; `--profile=user://outro.json` evita mexer no seu save; `--demo=1` resgata o TESTARTUDO e o MOEDAS e veste um conjunto de vitrine com bônus; em `smith`, `--tab=Moedas` abre a aba de moedas e `--craft=map` mostra os mapas; em `bag`, `--tab=Atributos` abre os atributos; `--zoom=2` aproxima a câmera da partida; `--map=<id>` escolhe o mapa da partida; em `pve` e `pve_battle`, `--instance=<id>`, `--level=<1..16>` coloca um mapa daquele nível e `--phase=<1..3>` começa na fase pedida).

## Mapas
Como no DDTank, o chão de cada mapa é uma pintura: ilhas geradas no PixelLab cujo contorno é a colisão, destruídas pixel a pixel. **Ilha Celeste** (ilhas de grama sobre um mar de nuvens), **Pátio do Templo** (ruínas de areia), **Câmara do Guardião** (gelo, com neve caindo), **Trono das Máscaras** (rocha vulcânica, com brasas) e **Templo do Sol** (piso do templo, Instância). Na 0.9 entraram **Portões de Brasa**, **Salão das Máscaras**, **Trilha Congelada**, **Caverna de Cristal**, **Pico da Nevasca** (só na Instância), **Ruínas Flutuantes** e **Santuário dos Ventos**. As explosões têm fogo animado, clarão, onda de choque, fumaça e pedaços do chão voando; a cratera fica com a borda queimada.

## Arte
Toda a arte é do PixelLab: a entrada e o logotipo, a cidade e os prédios, os fundos e o chão dos mapas, a explosão, as cartas de recompensa, personagens, as roupas (estados do mesmo personagem, em pé e deitado, com respirar, rastejar e arremessar), armas, chapéus, óculos, asas, itens auxiliares, pedras, projéteis, o touro espectral, a cidade e os prédios. Os tiers +9/+10/+12 das armas são recoloridos a partir do ícone do PixelLab (`tools/weapon_tiers.py`). A aura da arma é um círculo mágico em alta resolução com brilho, runas, estrela, raios e faíscas (`tools/aura_textures.py`); a aura da roupa é um brilho suave em volta do corpo com luz na borda e faíscas subindo. As asas são desenhadas uma de cada vez em 128×128 e batem a partir do ombro. Tintura de cabelo e brilhos são shaders. Fonte: **Pixel Operator Bold** (CC0, `assets/fonts/PixelOperator-LICENSE.txt`). Cenários aparecem em 2× exato e prédios, armas e cartas em 1×; o que precisa de escala quebrada usa um shader que mantém todos os pixels do mesmo tamanho. Inimigos das instâncias, POW animados, mapas e ícones de mapa da 0.8/0.9: [docs/PIXELLAB_0_9.md](docs/PIXELLAB_0_9.md). Detalhes anteriores em [docs/PIXELLAB_0_6.md](docs/PIXELLAB_0_6.md), [docs/PIXELLAB_0_5.md](docs/PIXELLAB_0_5.md) e [docs/PIXELLAB_0_4.md](docs/PIXELLAB_0_4.md).

## Som
Todo o áudio é original e gerado por código (`tools/synth.py`, um pequeno sintetizador em numpy): os efeitos por `tools/make_sfx.py` e as três músicas por `tools/make_music.py` (orquestra sintetizada: metais, cordas, coro, harpa, tímpanos e taikos, com reverb de sala). Arquivos em `assets/audio/sfx` e `assets/audio/music` (Ogg Vorbis, cerca de 6 MB no total). Para trocar por outra música, basta substituir `lobby.ogg`, `battle.ogg` ou `instance.ogg`. Detalhes em [docs/AUDIO_0_7.md](docs/AUDIO_0_7.md).

## Limites
No modo offline, salas, jogadores e chat do canal são simulados por IA e isso é avisado no chat; moedas e itens ficam em `user://profile.json` e não valem como economia online; Leilão e Correio só funcionam online. Namoro, PET (e a Casa dos Mascotes) e Missão mostram aviso de "ainda não disponível". O leilão ainda não tem lances nem troca direta de moedas (Estrela ↔ Solar). Rosto e olhos ainda não são slots separados. Os ícones das sete moedas da 0.10 são provisórios, desenhados por `tools/currency_icons.py`, até a arte PixelLab (`docs/PIXELLAB_0_10.md`).
