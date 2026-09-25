# Frontier Tank: Nova Era — 0.5 (armas, visual e Ferreiro)

Abra **Jogar.cmd** para iniciar com o Godot instalado neste computador, ou importe **project.godot** no Godot 4.7 e pressione F5. Em outro computador, configure `GODOT_BIN` com o caminho do executável Godot.

Réplica em pixel art do fluxo clássico do DDTank, contra bots (modo offline):

| Tela | O que tem |
|---|---|
| **Cidade** (`docs/screens/city.png`) | Salão de Jogos no centro da praça, mar em movimento, bandeiras, fumaça do Ferreiro, corações do Namoro, portal da Instância, brilhos nas lojas e gaivotas. Prédios clicáveis: **Ferreiro** e **Centro Comercial** abrem de verdade. Botões **CUPOM** e **MOCHILA**, alto-falante, canal, chat e barra SHOP · MOCHILA · PET · CORREIO · MISSÃO · AJUDA · SAIR. |
| **Mochila** (`bag.png`) | Informações Pessoais como no DDTank: slots Chapéu, Óculos, Cabelo, Roupa, Asas, Arma e Auxiliar em volta do personagem, que veste tudo o que está equipado, com a aura da arma atrás da cabeça e dos ombros. Ataque, Agilidade, Defesa, Sorte, Dano, Proteção, Vida e Força física. Inventário com Armas, Visual, Auxiliar e Materiais; equipar, remover e vender. |
| **Ferreiro** (`smith.png`) | **Fortalecer** até +12 com Pedras de Fortalecimento, **Composição** com Cristal Dourado, **Fusão** de 4 pedras iguais e **Transferência** do nível entre dois itens do mesmo tipo. |
| **Centro Comercial** (`shop.png`) | Armas em Normal, Excelente e Verdadeira; roupas, chapéus, óculos, asas, cabelos, itens auxiliares e pedras; **provador** que veste o item antes de comprar. Super armas não são vendidas. |
| **Salão de Jogos** (`hall.png`) | Lista de salas, filtro, informações do usuário com o personagem equipado, lista de jogadores, **Equipe**, **Buscar** e **Jogar**. |
| **Sala** (`room.png`, `pve.png`) | 4 vagas com cada jogador vestido (roupa, chapéu, asas e auras), VS, modos, mapa, tempo do turno, ferramentas Z/X/C, Convide, Local e Início. Instância com 4 dificuldades. |
| **Partida** (`battle.png`, `pve_battle.png`) | Personagens deitados, com a arma nas costas, asas, chapéu e óculos; como no DDTank, as auras não aparecem em batalha. Habilidades **1–9** iguais às do DDTank: +2, x3, +1, POW 50%, 40%, 30%, 20%, 10% e POW máx (enche a barra de POW). Cada arma tem projétil, rastro e especial (POW) próprios. Tudo da 0.4 continua: Delay, vento, Z/X/C, POW, avião, Confiar, terreno destrutível. Slot **V** para o item auxiliar. |
| **Resultado e cartas** (`result.png`, `cards.png`) | Resultado com o personagem equipado; cartas de recompensa. Na Instância vencida, uma carta pode ser uma **Super arma** (mais chance em dificuldades altas). |

## Armas (como no DDTank)
Nove armas clássicas em três qualidades, **Normal**, **Excelente** e **Verdadeira**: Quebra Tijolos, Fogo Intenso, Canhão Arco-Íris, Vento de Deus, Cesto de Frutas de Newton, Kit Médico, Eletrodoméstico, Trovão e Desentupidor. E três **Super Verdadeiras**, que só caem na Instância: Super Cabeça de Boi, Super Bumerangue do Amor e Super Lança. Ângulos e tipo de POW seguem os guias do DDTank; os especiais: tijolo que se parte, rajada tripla de fogo, raio arco-íris do céu, shuriken gigante que ignora o vento, chuva de frutas, cura em área, geladeira que cai do céu, três raios, desentupidores que puxam, touro espectral que empurra, bumerangue que volta e cura, e chuva de lanças.

**Fortalecimento** até +12 (pedras: +1 = 1 ponto … +12 = 900 pontos, como no artigo do TechTudo). Cada nível deixa o item mais forte: a arma ganha dano e todos os itens fortalecidos ganham +10% dos seus atributos por nível (Ataque, Defesa, Agilidade, Sorte); roupa e chapéu também dão Defesa e Vida. O ícone da arma evolui no +9, +10 e +12, e a **aura** atrás da cabeça e dos ombros muda de cor: +1–5 verde, +6–8 azul, +9–11 roxa, +12 vermelha. A roupa fortalecida ganha a própria aura: um brilho em volta do corpo e partículas subindo. As auras aparecem fora das lutas (Mochila, Sala, Salão, Loja, cidade); a arma nas costas aparece só nas lutas.

**Visual do personagem:** conta nova começa de camiseta e shorts. Roupa troca o corpo inteiro (Explorador, Samurai, Ninja, Capitão; Exploradora, Princesa, Maga, Marinheira), chapéu, óculos e asas vão por cima e o cabelo muda de cor.

**Item auxiliar** (tecla V): Dom de Anjo e Verdadeiro Dom de Anjo curam; Escudo de Bugou e Escudo do Barão reduzem o próximo dano.

## Cupons para teste
Na cidade (botão **CUPOM**), na Mochila ou na Loja:
- `TESTARTUDO`: todas as armas em todas as qualidades, as três super armas, auxiliares, todas as roupas, chapéus, óculos, asas e cabelos, 200 pedras de cada nível, 50 cristais e 99.999 moedas.
- `AURAS`: quatro Quebra Tijolos Verdadeiros em +3, +7, +10 e +12, para ver as quatro auras.
- `PEDRAS`: 50 pedras de cada nível.

Cada cupom vale uma vez por conta.

## Controles na partida
← → andar (gasta energia) · ↑ ↓ ângulo · segurar/soltar **Espaço** força · **1–9** habilidades · **Z X C** ferramentas · **B** POW · **F** avião · **V** item auxiliar · **P** passar · **Q** virar · **Esc** pausa · botão direito arrasta a câmera · clique no minimapa move a câmera.

## Verificação
Execute: `powershell -File tools/run.ps1 -Test` — 168 verificações (combate 49, instância 20, interface 44, armas/Ferreiro/cupons/especiais 55).

Capturas: `godot --path . -- --screen=<city|hall|room|pve|battle|pve_battle|result|cards|bag|shop|smith> --out=arquivo.png` (`--profile=user://outro.json` evita mexer no seu save; `--demo=1` resgata o TESTARTUDO e veste um conjunto de vitrine; `--zoom=2` aproxima a câmera da partida).

## Arte
Toda a arte é do PixelLab: personagens, as roupas (estados do mesmo personagem, em pé e deitado, com respirar, rastejar e arremessar), armas, chapéus, óculos, asas, itens auxiliares, pedras, projéteis, o touro espectral, a cidade e os prédios. Os tiers +9/+10/+12 das armas são recoloridos a partir do ícone do PixelLab (`tools/weapon_tiers.py`). A aura da arma é um círculo mágico em alta resolução com brilho, runas, estrela, raios e faíscas (`tools/aura_textures.py`); a aura da roupa é um brilho suave em volta do corpo com luz na borda e faíscas subindo. As asas são desenhadas uma de cada vez em 128×128 e batem a partir do ombro. Tintura de cabelo e brilhos são shaders. Fonte: **Pixel Operator Bold** (CC0, `assets/fonts/PixelOperator-LICENSE.txt`). Detalhes em [docs/PIXELLAB_0_5.md](docs/PIXELLAB_0_5.md) e [docs/PIXELLAB_0_4.md](docs/PIXELLAB_0_4.md).

## Limites
Não há servidor: salas, jogadores e chat do canal são simulados por IA e isso é avisado no chat. Leilão, Namoro, PET, Correio e Missão mostram aviso de "ainda não disponível". Moedas e itens ficam em `user://profile.json` e não valem como economia online. Rosto e olhos ainda não são slots separados.
