# Celular e tablet (0.23)

O Gustfire roda em Android e iPhone de três jeitos, **sem loja**: no navegador (e instalado na tela inicial), num APK instalado à mão e como projeto Xcode rodado no seu iPhone. Tudo usa o mesmo código do jogo; só a entrada e o desenho dos controles mudam (o **modo toque**). As regras, o servidor e o lockstep não mudam.

> **Estado**: o modo toque foi testado em um navegador de verdade com toque emulado (Chromium: o treino jogado só com toques) e nos testes `tests/touch_tests.gd` e `tests/net_e2e_tests.gd`. **Nada foi jogado ainda num aparelho de verdade**: desempenho, tamanho dos botões e teclado virtual dependem do seu teste. O roteiro está no fim.

## Testar agora

### 1. No navegador (Android e iPhone), o mais rápido

O caminho mais simples é a stack local (Docker Desktop): ela serve o jogo já com o shell de celular, o modo online e o servidor de jogo.

```bash
# server/.env: GAME_PUBLIC_URL=ws://<IP do PC na rede>:8000/ws   (o celular não alcança "localhost")
tools/local.sh            # ou SubirLocal.cmd; o Docker Desktop publica a porta 8000 na rede sozinho
```

No celular, na mesma rede (o PC pode estar no cabo e o celular no Wi-Fi: o que importa é o roteador não isolar os dois), abra `http://<IP do PC>:8000/jogar/`:

- **Android (Chrome)**: vai para tela cheia e trava a horizontal no primeiro toque.
- **iPhone (Safari)**: o Safari não tem tela cheia para páginas. Toque em Compartilhar → **Adicionar à Tela de Início** e abra pelo ícone: abre em tela cheia, sem barras. Em retrato, uma tela pede para girar o aparelho.
- O jogo detecta sozinho (`pointer: coarse`). Num computador, `?touch=1` (web) ou `--touch=1` liga o modo toque para olhar e capturar; `touch=0` desliga.
- O modo offline não precisa do servidor de jogo.

Sem Docker, só para ver o build web: `python tools/web_build.py export` e `python tools/web_build.py serve --lan` (porta 8060). Dentro do **WSL2** essa porta fica atrás de NAT: dê dois cliques em `Celular.cmd` no Windows (pede administrador; encaminha a 8060 para o WSL e libera 8060 e 8000 no firewall só para a sub-rede local; `Celular.cmd -Remove` desfaz). A 8000 o Docker Desktop já encaminha, então o script só abre o firewall nela.

**Se o celular não abre o endereço**: confira que ele está na mesma faixa de IP do PC (`192.168.0.x`), que não é uma rede de convidados e que o roteador não tem "isolamento de clientes/AP" ligado; teste `http://<IP>:8000/v1/servers` no celular (deve mostrar o servidor em JSON).

### 2. APK no Android

```bash
python tools/mobile_build.py templates                        # uma vez (~400 MB: Android e iOS)
python tools/mobile_build.py setup-android --accept-licenses  # uma vez: SDK em ~/Android/Sdk, chave de debug
python tools/mobile_build.py android --api http://<IP do PC>:8000
python tools/mobile_build.py share                            # nginx em Docker na porta 8062 (sem passo de administrador)
```

No celular abra `http://<IP>:8062/gustfire.apk` e instale (o Android pede, uma vez, "instalar apps desconhecidos" para o navegador). Ou, com depuração USB/Wi-Fi ligada, `python tools/mobile_build.py install`. `--api` grava o endereço da API no app (`api_default.txt`, fora do git): sem ele o app só joga offline, porque `localhost` num celular é o próprio celular.

`--accept-licenses` aceita por você as licenças do SDK do Android (https://developer.android.com/studio/terms); a ferramenta nova do Google coleta métricas de uso por padrão (o script passa `--no-metrics`).

O APK é de **debug**, assinado com a chave de debug. Pacote `com.gustfire.game`, Android 7 ou mais novo (minSdk 24), só arm64, só horizontal (por sensor).

### 3. iPhone via Xcode (precisa do Mac)

```bash
python tools/mobile_build.py ios --bundle com.<seunome>.gustfire --api http://<IP do PC>:8000
python tools/mobile_build.py share        # o zip sai em http://<IP>:8062/Gustfire-xcode.zip
```

No Mac: baixe o zip, descompacte, abra `Gustfire.xcodeproj`, em **Signing & Capabilities** escolha o seu Team (um Apple ID gratuito basta), ligue o iPhone, escolha-o como destino e Run. No iPhone, **Ajustes → Geral → VPN e Gerenciamento de Dispositivo** para confiar no seu perfil. Com Apple ID gratuito o app vence em 7 dias.

O identificador precisa ser um que ninguém mais registrou na Apple: se o Xcode reclamar de `com.gustfire.game`, use `--bundle`. O Godot não monta o `.ipa` fora do macOS; o projeto sai pronto para o Xcode.

## Vídeo para as redes sociais

`tools/make_mobile_trailer.py` faz o vídeo vertical (9:16, ~29 s, português e inglês) do jogo **jogado por toque**. Não é uma simulação: o diretor (`tools/trailer/director.gd`, `--seg=pilot`) manda ao jogo os mesmos `ScreenTouch` que um celular manda, nos botões da tela (andar, mirar, FOGO, gaveta HAB., orbe POW), com um marcador de dedo desenhado por cima; o tiro vem do solver dos bots (`EnemyAI.choose_shot`), então o piloto acerta. A montagem (ffmpeg + Pillow) tem o celular que gira de pé para deitado, o jogo dentro da moldura com um zoom embaixo (gaveta, botões, força), câmera acelerada no voo e lenta no impacto, um "tec" a cada toque, o cartão final com o endereço sendo digitado e a música da batalha.

```bash
GODOT=/caminho/godot python tools/make_mobile_trailer.py --lang pt_BR     # grava e monta
GODOT=... python tools/make_mobile_trailer.py --lang en
python tools/make_mobile_trailer.py --lang pt_BR --skip-record             # só remonta (ajustar texto e cortes)
python tools/make_mobile_trailer.py --lang en --record-only --scene boss   # regrava uma cena
```

- As cenas usam `--seed=7` (opção de captura do `main.gd`): as duas línguas gravam o **mesmo** roteiro, e os cortes (`EDIT`) valem para as duas. Se mudar uma cena ou a semente, confira os tempos em `build/trailer/mobile/<lang>/<cena>_taps.json`.
- Saída: `store/trailer/gustfire_mobile_{pt,en}_9x16.mp4` e a cópia leve com pôster em `website/video/` (a seção **Celular** do site; `--no-web` não escreve lá).
- O vídeo diz "gustfire.online" e "Google Play e App Store: em breve". Troque o `end4` em `TEXT` quando as lojas abrirem.
- Não ouvi o áudio (só medi: ~-15 LUFS); confira o som antes de postar.

## O que medir no spike

O contador de FPS liga **tocando com três dedos ao mesmo tempo** (é o F3 do computador); na web também `?fps=1`, e `?bench=30` joga uma batalha 4 contra 4 pela IA e mostra a média e os 1% mais lentos na tela.

| Medir | Como | O que decide |
|---|---|---|
| FPS na batalha | 3 dedos, ou `?bench=30` | se precisa de uma opção "qualidade baixa" (renderizar menor) |
| Carga inicial | contar o tempo até o título (o build web tem ~57 MB; ~25 MB com gzip) | compressão e cache no servidor |
| Memória e calor | 10 minutos de batalhas seguidas | Safari do iPhone mata abas pesadas |
| Controles | andar, mirar, segurar FOGO, habilidades pela gaveta, os dois polegares ao mesmo tempo | tamanho e posição dos botões (`touch_controls.gd`, constantes no topo) |
| Texto | ler o treino, a Mochila, a loja | se a fonte mínima precisa subir no modo toque |
| Teclado | digitar conta e senha na entrada | teclado virtual da web (experimental) e do app |
| Sair e voltar | trocar de app no meio de uma batalha online | reconexão automática |

## Como funciona

- **`client/systems/touch_mode.gd`** (`TouchMode`): decide se é modo toque (app Android/iOS, ou navegador com ponteiro grosso; notebook com tela de toque continua com o mouse) e guarda o tamanho mínimo dos alvos. `TouchMode.pointer(node)` é a posição do dedo: o cartão do item, o menu do jogador e o "virar página arrastando" leem ela no lugar de `get_global_mouse_position()`.
- **`client/systems/touch_assist.gd`** (`TouchAssist`): no modo toque o Godot deixa de transformar o primeiro dedo em mouse (`emulate_mouse_from_touch` desligado) e este nó faz isso: (1) o segundo dedo continua livre (os botões do Godot 4.7 já aceitam qualquer dedo); (2) um toque no vão ao lado de um botão cai no botão mais próximo, a até 22 px, se nada o cobrir (um diálogo, por exemplo); (3) segurar parado mostra o tooltip (não há hover) e soltar não clica; (4) um toque que deslizou (rolar, arrastar) não clica no que estava embaixo, a não ser que carregue um arrastar-e-soltar (a Mochila); (5) listas (`ScrollContainer`, `RichTextLabel`) seguem o dedo e continuam deslizando depois do arremesso (a rolagem por toque do Godot só acorda com `is_touchscreen_available()` e não dá para testar; ela fica desligada com `scroll_deadzone` alto); (6) três dedos juntos ligam o contador de FPS.
- **`client/ui/touch_controls.gd`** (`TouchControls`): os controles da batalha, no lugar do teclado. Direcionais ◀ ▶ (andar) e ↑ ↓ (mirar), botão **FOGO** (segurar enche a força, soltar atira) e a gaveta **HAB.** com as habilidades 1–9. Os botões leem os toques crus (dois polegares ao mesmo tempo) e **apertam e soltam as mesmas teclas do teclado** (`Input.parse_input_event`: A/D, W/S, ESPAÇO): a partida offline, as intenções online e o lockstep não distinguem um polegar de um teclado. Ferramentas, avião, item auxiliar, mascote, POW e PASS continuam sendo os botões do HUD, movidos e aumentados. Na batalha, um dedo no campo vazio arrasta a câmera.
- **Tamanhos**: numa tela de 6" os 1280×720 lógicos ficam com ~110 px/cm, então 72 px são ~6,5 mm. Os direcionais têm ~92 px, o FOGO 176 px, e todo botão do `UiKit` ganha pelo menos 48 px de altura (ícones, 56 px de área de toque sem mudar o desenho).
- **Voltar do Android** (`main.go_back`): fecha o que estiver por cima (Mochila, loja, diálogo), senão volta uma etapa como o SAIR; na batalha é o ESC (pausa).
- **Reconexão** (`main.reconnect`): no celular, uma conexão que cai sem o servidor dizer o motivo (app em segundo plano, sinal perdido) tenta voltar sozinha por até ~1 minuto, com um aviso, e uma batalha em andamento reabre com o histórico. Motivos dados pelo servidor (outro login, banido, versão velha) vão direto para a entrada.
- **Web**: `tools/web/shell_head.html` entra no `index.html` na exportação: viewport sem zoom, tela cheia no Android, tela de "gire o aparelho", `manifest.webmanifest` (instalável, horizontal), bloqueio do zoom de pinça do Safari e teclado virtual (`html/experimental_virtual_keyboard`).
- **Projeto**: orientação horizontal por sensor, o botão voltar não fecha o app, tela sempre acesa no app, textos do treino e da AJUDA sem teclas (`text_touch` no `tutorial.json`).

## Fora do escopo (decisões antes das lojas)

- **Compras**: o Passe da Caçada e o Pacote Fundador passam pela Steam, que não existe no celular. Bem digital nas lojas exige Google Play Billing e Apple IAP (comissão de 15–30%).
- **Ovos e drops aleatórios** exigem divulgar as probabilidades nas duas lojas.
- **Conta**: sem Steam o login é e-mail/senha; a Apple cobra a exclusão da conta dentro do app (existe em AJUDA → Minha conta).
- Exportar os dados da conta grava um arquivo em `user://exports` fora da web; no celular não há como abri-lo (funciona no navegador e no computador).
- Safari/iPhone: o áudio da web respeita o botão de silêncio do aparelho; o teclado virtual da web é experimental.
- Os triângulos ▲ ▼ não existem nas fontes do jogo: os textos usam ↑ ↓ (os botões são desenhados).
- O ícone do app é o ícone do projeto (256 px); falta o ícone adaptativo do Android e os tamanhos do iOS.
- Arrastar e soltar na Mochila e rolar listas funcionam por toque nos testes; confira no aparelho.

## Testes

`tests/touch_tests.gd` (61 verificações): detecção, teclas sintéticas dos botões, andar/mirar/atirar, dois polegares, gaveta de habilidades, o toque no vão ao lado do botão, toque longo, rolagem com inércia, `CheckBox` sem clique duplo, Mochila por dedo, FPS por três dedos, botão voltar e a câmera. A reconexão está em `tests/net_e2e_tests.gd`. Capturas: `godot --path . -- --touch=1 --screen=battle --demo=1 --out=x.png`.
