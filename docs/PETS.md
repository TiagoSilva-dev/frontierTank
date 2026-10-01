# Casa dos Mascotes (0.19)

Os ovos caem nas instâncias, o jogador os abre na **Casa dos Mascotes** (prédio da cidade, botão PET da barra e o espaço "Mascote" da Mochila) e o mascote que nasce acompanha o personagem nas batalhas com bônus de verdade. A tela segue o layout da Forja Celeste: abas **Chocar**, **Mascotes** e **Álbum**, painéis de bronze com vidro escuro e o cenário de santuário no meio.

Tudo sai de `shared/balance/pets.json` e de `client/systems/pets.gd`; o perfil só guarda `{uid, species, level, xp, stars}`. Offline o `PlayerProfile` aplica as operações, online o servidor de jogo aplica as mesmas (`pet_hatch`, `pet_equip`, `pet_feed`, `pet_evolve`, `pet_release` estão em `PlayerProfile.OPS`), então não existe segunda cópia das regras.

## O que o jogador vê

| Aba | O que faz |
|---|---|
| **Chocar** | Seis tipos de ovo (cinco elementos + o Ovo de Mascote genérico), cada um com contagem, as **chances** de raridade, as **garantias** (quantos ovos faltam para um Épico e um Lendário), os mascotes que podem nascer (silhueta se ainda não descobertos) e o botão **CHOCAR OVO**. Embaixo, o progresso do álbum por elemento. |
| **Mascotes** | Coleção (25 por página, ordenada por raridade, estrelas e nível), cartão do mascote com arte grande, nível e barra de XP, estrelas, o **poder** (atributos e talentos), **ATIVAR/DESATIVAR**, **ALIMENTAR**, **GANHAR ESTRELA** e **LIBERTAR**. |
| **Álbum** | As 20 espécies por elemento; as que faltam aparecem como silhueta "???". Completar um elemento dá um bônus permanente; completar todos dá o final. |

**A cena de chocar** (`HatchOutcome`): o ovo balança cada vez mais forte, racha, e estoura numa luz da cor da raridade; o mascote cresce no centro com o nome, a raridade, o elemento, os dois primeiros bônus e "NOVO NO ÁLBUM!" quando é uma espécie nova. Raridade maior = mais raios, anéis, faíscas, clarão e, de Épico para cima, a janela treme. Um clique depois da revelação fecha. Cada fase tem som próprio (`pet_shake`, `pet_crack`, `pet_hatch_<raridade>`).

**Em batalha** (`PetCompanion`): o mascote ativo fica atrás do lutador, flutua, vira junto, pula quando o dono apanha e comemora na vitória. É só visual (vai no `look.pet`); os bônus vêm do perfil. Na tela de resultado há uma linha com o XP que o mascote ganhou.

## Regras

- **Ovos**: contadores em `profile.items` (`egg_sol`, `egg_mascara`, `egg_gelo`, `egg_ceu`, `egg_viking`, e `pet_egg`, o antigo Ovo de Mascote do baú, agora o "genérico": sorteia o elemento e tem chances melhores). Cada instância solta o ovo do seu elemento: Templo do Sol → Sol, Trono das Máscaras → Máscara, Picos Gelados → Gelo, Ilha Celeste → Céu, Fiorde dos Vikings → Runa.
- **De onde caem**: o chefe, ao ser vencido, tem 14% + 2% por nível de mapa (máx. 45%; 10% na entrada livre) de soltar o ovo no baú; elites, guardiões e o golpe final do chefe têm 6% dos "drops de monstro" para ovo (antes: 75% pedra, 20% moeda, 5% arma; agora 69/20/6/5); o ovo genérico continua entre as cartas de recompensa.
- **Chances** (`odds`, por ovo): elemento 58 / 28 / 11 / 3 (Comum / Raro / Épico / Lendário); genérico 40 / 36 / 18 / 6. **Garantia**: o 10º ovo sem Épico ou melhor é um Épico+; o 40º sem Lendário é Lendário (`profile.pity["egg_epico"/"egg_lendario"]`, zeram ao sair a raridade).
- **Espécies**: 20 (5 elementos × 4 raridades), uma por raridade em cada elemento.
- **Níveis e estrelas**: nível máximo 10 sem estrelas, +4 por estrela (até 30 com 5). XP por nível = 50 × nível. **Ganhar estrela** consome 1 duplicata da mesma espécie (nunca a ativa) e moedas (150, 300, 600, 1.200, 2.400) e passa metade do XP total da duplicata. **Alimentar**: 100 moedas = 100 XP. **Batalha**: o mascote ativo ganha 20 + 20% da EXP da partida (×1,5 em instâncias). **Libertar** devolve moedas (40 / 120 / 400 / 1.500) e não vale para o ativo.
- **Poder** (`Pets.attrs/talents`): atributos = valor da raridade (14 / 26 / 42 / 64) × peso do elemento × `power(nível)` (30% no nível 1 → 100% no 30) × (1 + 0,15 por estrela). Talentos (Raro 1, Épico 2, Lendário 3, na ordem do elemento) usam os mesmos bônus de combate do Crafting (dano %, dano do POW, POW inicial, crítico, poupar habilidade, vida, cura, vento, energia, delay) com valor máximo × fator da raridade (0,35 / 0,65 / 1,0) × poder × (1 + 0,10 por estrela). Um Lendário no nível 30 com 5 estrelas dá cerca de +112 de atributo principal e +21% de dano: comparável a duas boas afixações de item, não mais.
- **Elementos**: Sol (Ataque e Sorte; dano, POW, POW inicial), Máscara (Sorte e Ataque; crítico, poupar, dano), Gelo (Defesa e Agilidade; vida, cura, vento), Céu (Agilidade e Sorte; vento, energia, delay), Runa (Defesa e Ataque; vida, POW inicial, crítico).
- **Álbum**: elemento completo = +24 de um atributo (Ataque, Sorte, Defesa, Agilidade) ou +150 de vida (Runa); os cinco = +5% de dano.
- **Limites**: 120 mascotes por conta. Ovos e mascotes não vão ao Leilão.

O bônus entra por `Armory.character_stats(..., pet_bonus)`: atributos somam aos do equipamento e os talentos aos "bônus de batalha", então servidor, bots e a tela de atributos usam o mesmo número.

## Arquivos

`shared/balance/pets.json` (catálogo e números) · `client/systems/pets.gd` · `client/systems/profile.gd` (campos, operações, `pet_bonus`, cupom `OVOS`) · `client/systems/instance_run.gd` (drops) · `client/systems/rewards.gd` (XP de batalha) · `client/ui/pet_screen.gd`, `pet_stage.gd`, `pet_widgets.gd`, `hatch_outcome.gd` · `client/components/pet_companion.gd` · `tools/make_pet_audio.py` · `tests/pet_tests.gd` (65) e `tests/pet_visual_check.gd`.

Salvamento versão 7 (`pets`, `pet_active`, `pet_album`); saves antigos carregam sem mascotes. `GAME_VERSION` 0.19 e `pets.json` entra no hash de conteúdo: o servidor precisa ser reimplantado. Cupons de teste: `OVOS` (10 de cada ovo) e o `TESTARTUDO` agora dá 20 de cada; `--demo=1` já traz cinco mascotes.

## Arte (PixelLab, 139 gerações; sobraram 2.003 até 24/10/2026)

- **20 espécies** em `assets/pets/<id>.png`, 128×128: `create_image_pro_flash` (6 gerações cada), descrição "cute chibi … collectible monster-game pet sprite, three-quarter side view facing right, clean dark outline" + o que a espécie tem de característico; sementes 11–38. As três artes antigas de 64 px (Fênix, Raposa Glacial, Rei Máscara) foram refeitas no mesmo estilo. A Raposa Glacial falhou na primeira tentativa (job 52cfb88b) e foi repetida com a semente 129.
- **6 ovos** em `assets/pets/eggs/` (pixen 64×64, 1 geração): sol, máscara, gelo, céu, runa + o genérico que já existia. Gelo e céu foram refeitos com "smooth oval egg … plain egg shape, no face" (a primeira versão do céu saiu como uma criatura e a do gelo como uma bola de espinhos).
- **5 ícones de elemento** em `assets/pets/elements/` (pixen 32×32 "bold simple icon").
- **Santuário** `assets/ui/pets/sanctuary.png` (pixen 580×392, 1 geração): arcos de pedra, feixe de luz e um altar de ninho embaixo, onde o ovo/mascote pousa (`PetStage`).
- **Sons** gerados por `tools/make_pet_audio.py` (numpy + scipy + ffmpeg): `pet_shake`, `pet_crack`, `pet_hatch_comum/raro/epico/lendario`, `pet_levelup`. Não foram ouvidos por uma pessoa.

Capturas: `docs/screens/pets_hatch.png`, `pets_pets.png`, `pets_album.png`, `pets_shake.png`, `pets_common.png`, `pets_legend.png`.

## Em aberto

- Os números (chances, bônus, custos) são pontos de partida: falta jogar e ver se o ovo cai com a frequência certa e se um Lendário não desequilibra.
- Mascotes ainda não têm habilidade própria na batalha (só bônus passivos). Uma habilidade por elemento é o passo seguinte natural, mas entra na simulação em lockstep e precisa de teste de sincronia.
- Troca e venda de ovos no Leilão, e uma página de mascotes na wiki do site (`tools/build_site.py`).
