# Arquitetura

Projeto Godot 4.7 na raiz (reutiliza `assets/`). Renderizador Compatibility, resolução lógica 1280×720, filtro nearest. Sem servidor: a autoridade da partida é local.

## Fluxo de telas (0.5)
`client/scripts/main.gd` é o app: carrega `shared/balance/combat.json`, o perfil e o `LobbyDirectory`, e troca as telas num `CanvasLayer`.

Cidade (`city_screen.gd`) → Salão de Jogos (`hall_screen.gd`) → Sala (`room_screen.gd`) → Partida (`battle_screen.gd` + `battle_hud.gd`) → Resultado/Cartas (`result_screen.gd`) → volta à Sala. A Mochila (`character_screen.gd`), o Ferreiro (`smith_screen.gd`), a Loja (`shop_screen.gd`) e o cupom (`coupon_dialog.gd`) abrem por cima de qualquer tela. Widgets comuns: `chat_box.gd`, `bottom_bar.gd`, `speaker_bar.gd`.

- `ui_kit.gd`: molduras pixel-art 9-slice geradas em 2× (madeira, papel, cartão, slot, botões), fonte Pixel Operator Bold (tamanho mínimo 16), helpers de widgets e de skins de personagem.
- `city_screen.gd`: praça com o Salão de Jogos no centro; o mar anima com `client/shaders/city_sea.gdshader` e os detalhes dos prédios (bandeiras, fumaça, corações, portal, brilhos, gaivotas) são desenhados por código.
- `pixel_icons.gd`: ícones procedurais com contorno automático; um PNG em `assets/ui/icons/<nome>.png` substitui o ícone.
- `lobby.gd`: substituto offline do servidor — bots, salas que entram/saem de jogo, chat do canal e alto-falante. Tudo marcado como IA.
- `profile.gd`: personagem único. Save v3 com inventário de instâncias (`{uid, id, quality, level, compose}`), mapa de equipados por slot, pedras e cristais em `items`, cupons usados; lê os saves v1/v2. Também faz as operações do Ferreiro (fortalecer, fundir, transferir, compor), compra/venda e cupons. `PlayerProfile.path_override` isola os testes.

## Armas, qualidades e visual (0.5)
- `shared/balance/items.json`: qualidades, regras de fortalecimento (pontos por nível, pedras, fusão, transferência, composição), cores das auras, as 12 armas (ângulo, dano, atributos, projétil, POW), itens auxiliares, cosméticos, drops e cupons.
- `armory.gd` (`Armory`): lê o catálogo; nomes no estilo DDTank, dano por qualidade e nível, tier do ícone (+9/+10/+12), cor da aura, atributos do personagem (`character_stats`) e o `look` usado para desenhar (`look_for`), além do equipamento aleatório dos bots.
- `look_rig.gd` (`LookRig`): camadas de boneco de papel em volta do sprite do corpo, com posições de `assets/characters/<skin>/anchors.json` (gerado por `tools/character_anchors.py`, que mede cabeça, olhos, costas e cores do cabelo, e rastreia a cabeça quadro a quadro nas animações). A parte `back` (aura, asas, arma nas costas) vai antes do corpo; o rig (chapéu, óculos, partículas da aura da roupa) vai depois. Na vista em pé (menus) mostra auras e esconde a arma; na vista deitada (partida) mostra a arma nas costas e esconde as auras. O corpo recebe `client/shaders/look.gdshader` (tintura de cabelo por paleta e brilho da roupa).
- `aura_ring.gd`: círculo mágico em camadas de alta resolução (`assets/effects/aura/<cor>_{disc,rays,ring,star}.png`, geradas por `tools/aura_textures.py`): disco pulsando, raios e anel de runas girando num sentido, estrela no outro, filtro linear com mipmaps e faíscas orbitando. Só aparece fora das lutas.
- `avatar_view.gd`: o personagem em pé com o rig, usado na Mochila, Loja, Sala, Salão, cidade e resultado.
- Roupas são estados PixelLab do mesmo personagem (`assets/characters/roupa_*/`, com `prone/` e animações), importados por `tools/import_pixellab_skin.py`.

## Partida
- `match.gd` (`LocalMatch`): arma de cada lutador montada por `Armory.weapon_for_entry`; especiais em `resolve_impact` (dividir, chuva, queda, raios, cura, puxar, empurrar, bumerangue com roubo de vida) e dano em `explode` com Ataque, Defesa e crítico pela Sorte; item auxiliar (V). Equipes 1v1–4v4; **Delay**: cada ação soma atraso (base − agilidade, itens, avião, movimento, ferramentas; PASS e tempo esgotado somam 55%) e joga quem tiver menos. Energia por turno 240 + agilidade/30. Itens 1–8 (um multi-tiro por turno; bônus de dano somam), ferramentas Z/X/C, POW por arma (bomba gigante, chuva de lava, gelo que faz perder a vez, trovão duplo, bênção com cura), avião de papel (teleporta, recarga 2 turnos), força que reinicia uma vez no máximo, Confiar (IA assume), congelamento, vitória por equipe e empate.
- `enemy_ai.gd`: escolhe o alvo (perto e ferido) e busca ângulo/força simulando a mesma balística a 30 Hz, com refinamento; o erro de força vem de `balance.bots`.
- `terrain.gd`: máscara RGBA (1 pixel = 2 unidades) gerada por mapa: ilhas com ruído, paletas (meadow, sand, frost, obsidian) e o piso do templo. A mesma máscara define apoio, colisão, crateras e o desenho. `slope_degrees` dá a inclinação usada no ângulo efetivo.
- `fighter.gd`: vida, energia, POW, inclinação, arco da faixa de ângulo e linha de mira, placa com nível/nome/patente, lápide ao morrer e o chefe com animações PixelLab. Como no DDTank, luta **deitado** quando existe `assets/characters/<skin>/prone/` (sprite, `idle/` em vai-e-volta, `crawl/` ao mover e `shoot/` ao disparar); a arma fica nas costas (LookRig) e o disparo sai à frente da cabeça. Atributos dos itens (`attrs`) e o item auxiliar vêm na entrada do lutador.
- `projectile.gd`: sprite, giro ou voo de ponta e rastro próprios de cada arma (fogo, arco-íris, vento, faíscas, corações, eletricidade, folhas, fumaça, bolhas, poeira, jade); `special`/`stage` guardam o POW e os projéteis secundários.
- `weapon_effect.gd`: efeitos dos especiais (raio arco-íris, raios, cura, corações, touro, tornado).
- `battle_screen.gd`: mundo num `SubViewport` com `Camera2D` que segue o jogador da vez, o projétil e o impacto; fundo com leve paralaxe; tremor nas explosões; arrastar com o botão direito e clicar no minimapa.
- Mapas, itens, ferramentas, PvE, bots e recompensas ficam em `shared/balance/combat.json`; armas e equipamentos em `shared/balance/items.json`.

## Rede (futuro)
Um adaptador de rede deve substituir `LobbyDirectory` e as intenções enviadas ao `LocalMatch`, reproduzindo eventos do servidor. Não aceitar dano, recompensas ou moedas calculados no cliente. Passo fixo não garante determinismo entre linguagens; o servidor Go precisará de testes de paridade.
