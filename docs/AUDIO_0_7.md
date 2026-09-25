# Áudio 0.7

Todo o som do Frontier Tank é original e gerado por código, como receita reproduzível:

```
python tools/make_sfx.py            # todos os efeitos -> assets/audio/sfx/*.ogg
python tools/make_sfx.py fire_trovao impact_trovao   # só alguns
python tools/make_music.py          # lobby, battle e instance -> assets/audio/music/*.ogg
python tools/make_music.py battle   # só uma
```

Dependências: Python 3 com `numpy` e `scipy`, e `ffmpeg` com libvorbis no PATH. Depois de gerar, abra o editor ou rode `tools/run.ps1` (ele reimporta quando os arquivos mudam). O jogo também lê um `.ogg` ainda não importado.

`tools/synth.py` é o sintetizador: osciladores sem aliasing (PolyBLEP), ruído branco e rosa, filtros Butterworth fixos e com varredura, ressonadores de formantes (vogais do coro), reverb estéreo por convolução, limitador com antecipação e gravação em Ogg Vorbis que decodifica o arquivo e reduz o ganho se a compressão passar do teto (−0,8 dBFS). Instrumentos: cordas (legato e spiccato), trompa, trompete, trombone, tuba, coro, harpa/alaúde (cordas pinçadas aditivas), sinos, tímpanos, taiko, caixa, tambor de moldura, prato, prato invertido, contrabaixos e o "braam" épico.

## Armas
Cada arma tem `fire_<id>` (disparo) e `impact_<id>` (camada tocada junto com a explosão).

| Arma | Disparo | Impacto |
|---|---|---|
| Quebra Tijolos | pancada seca de pedra, cascalho e o tijolo girando no ar | desmoronamento de entulho |
| Fogo Intenso | ignição "fwoosh" com varredura, rugido de fogo e estalos | labareda |
| Canhão Arco-Íris | disparo de canhão com arpejo mágico de sinos subindo e brilhos | sinos descendo e brilhos |
| Vento de Deus | rajada girando (a shuriken) e o "shing" metálico | lufada de vento |
| Cesto de Frutas de Newton | "pop" do arremesso, folhas e apito subindo | fruta esmagando |
| Kit Médico | "pssht" pneumático e sino de cura | vidro, efervescência e sino |
| Eletrodoméstico | baque, zumbido de 60 Hz, chiado de TV e o apito do tubo | vidro estilhaçando e faísca |
| Trovão | arco elétrico, estalos e trovão rolando | estalo elétrico |
| Desentupidor | sucção "thwop", "plop", mola e bolhas | "splash" com bolhas |
| Super Cabeça de Boi | bufada e mugido/rugido do touro com estrondo | pisadas pesadas |
| Super Bumerangue do Amor | "vup-vup" girando e sininhos de amor | sininhos |
| Super Lança | lança cortando o ar, anel de bronze e brilho de jade | metal batendo na terra |
| Rei Hélio (chefe) | fogo solar, braam grave e estrondo | — |

Outros projéteis: `fire_plane` (avião de papel), `drop_whistle` (o que cai do céu), `split_pop` (tijolos que se partem), `boomerang_return`.

## Batalha
- Explosões `explosion_small`, `explosion_medium`, `explosion_big` pelo raio (estalo, corpo, sub-grave e detritos).
- POW: `pow_activate` (subida ao armar com B) e `pow_fire` (braam, taiko, coro "AH" e prato). Especiais: `special_beam`, `special_lightning`, `special_bull`, `special_heal`, `special_hearts`, `special_tornado`, `special_freeze`.
- Habilidades: `skill_multi` (+2, x3, +1), `skill_power` (POW 50%…10%), `skill_powmax`; ferramentas `tool_heal`, `tool_energy`, `tool_shield`; `aux_angel` (Dom de Anjo).
- Partida: `battle_start`, `your_turn`, `tick` (3 últimos segundos), `charge_loop` (zumbido da força, tom sobe com a barra), `critical`, `fighter_down`, `victory`, `defeat`.
- Interface: `ui_click`, `ui_open`, `ui_confirm`, `ui_error`, `ui_coin`, `ui_forge`, `ui_card`.

## Músicas
Loops sem emenda (a cauda do reverb do fim volta para o começo). Tocam no barramento `Music` a −8 dB.

| Faixa | Onde | Tom e andamento | Forma |
|---|---|---|---|
| `lobby.ogg` (80 s) | entrada, cidade, salão, salas, resultado | Ré maior, 96 BPM | A: harpa e trompa com o tema · B: orquestra, trompetes e coro · C: ponte em Si menor com cordas pulsando · D: clímax e volta suave |
| `battle.ogg` (69 s) | partidas PvP | Ré menor, 140 BPM | A: cordas galopando, taikos, metais · B: tema na trompa · C: trompetes agudos e coro · D: pausa grave e subida · E: tema de novo, uma oitava acima |
| `instance.ogg` (74 s) | Instância (Templo do Sol) | Lá menor com o dominante frígio (Mi–Fá–Sol#), 104 BPM | A: alaúde e coro distante · B: marcha do Rei Sol · C: fúria com o Si♭ napolitano e metais · D: clímax com coro |

Para usar outra música, troque o arquivo mantendo o nome (Ogg Vorbis). O volume de cada barramento fica em `client/components/audio.gd` (`MUSIC_DB`, `SFX_DB`).

Observação: é uma orquestra sintetizada (timbre de videogame), não gravada. As músicas e os efeitos foram conferidos por medições (níveis, espectro, emendas e picos), não por audição.
