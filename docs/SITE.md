# Site oficial e wiki — Gustfire

O site fica em `website/`: uma página inicial para chamar jogadores e uma wiki no estilo do poedb, com todas as regras e números do jogo. É HTML, CSS e JavaScript puros, sem framework nem etapa de build no servidor: qualquer hospedagem estática serve, e abrir `website/index.html` direto no navegador também funciona.

## Nome e logotipo

- **Nome: Gustfire** (escolhido em 26/09/2026). *Gust* é rajada de vento e *fire* é disparo: o vento e o tiro, que são o centro do jogo. Na busca de 26/09/2026 não havia outro jogo com esse nome (Arcfall, Shellstorm, Skybrawl, Cloudbreaker e Arcblast já existem; Arcblast é inclusive um jogo de artilharia por turnos). **Antes de publicar, fazer uma busca de marca no INPI e no USPTO/EUIPO.**
- **Subtítulo**: *Artilharia nos céus* / *Sky Artillery* (a faixa vermelha do logotipo). Ele substitui o “Nova Era”, que era um risco de marca (ver `docs/ROADMAP.md`, revisão de nomes).
- **Logotipo** em pixel art, gerado por `tools/make_logo.py`: letras da fonte Titan One (SIL OFL, `tools/logo/TitanOne-OFL.txt`) num arco, pintadas como pixel art à mão (degradê em faixas com pontilhado, chanfro, brilho, contorno escuro, extrusão 3D e borda creme). “GUST” nas cores do vento e “FIRE” nas do fogo; rajadas de vento à esquerda, brasas saindo do FIRE, o tracejado do tiro e a bomba com asas no ápice (arte do PixelLab, `tools/logo/emblem_bomb.png`, 1 geração).
- Arquivos em `website/img/brand/`: `gustfire_logo_pt.png` e `_en.png` (663×207 em pixels nativos, transparente), as versões `@3x` (1989×621, para cápsulas e impressos), `gustfire_wordmark` (só as letras), `gustfire_icon_{32,64,180,512}` (ícone redondo com a bomba) e `og_pt.png` / `og_en.png` (1200×630, prévia de link em redes sociais).
- Para ampliar o logotipo, sempre em escala inteira com vizinho mais próximo (2×, 3×, 4×…), para os pixels continuarem quadrados.
- **O jogo inteiro usa o nome novo** (26/09/2026): o logotipo na tela de entrada (`assets/title/logo.png` e `logo_en.png`, gravados pelo `make_logo.py` em 1:1), o ícone do jogo (`icon.png`), o título da janela, os executáveis, os textos legais, a página e as cápsulas da Steam (padrão em inglês, `capsules/pt/` em português) e o servidor padrão **S1 · Ilha Celeste**. Os saves da pasta antiga (`app_userdata/Frontier Tank- Nova Era`) são copiados na primeira vez (`client/systems/legacy_data.gd`).

## Página inicial (`website/index.html`)

1. **Hero**: céu da Ilha Celeste com zoom lento, o logotipo com brilho passando, Lani e Nilo nas laterais, o Grifo da Tempestade atravessando o céu, **JOGAR GRÁTIS** e **Explorar a wiki**.
2. **Números**: armas, instâncias, monstros, níveis de mapa, fortalecimento e 4v4, todos lidos dos dados do jogo.
3. **Teste sua mira** (`js/playground.js`): uma mini batalha jogável no navegador com a **física do jogo** (velocidade de 190 a 900, gravidade 420, vento ×8, carga de 55%/s, dano em área com queda até 35%, ângulo preso à faixa da arma). Terreno destrutível com as peças da Ilha Celeste, tracejado dos tiros, três armas (Tijolaço, Cata-Vento, Prisma) e monstros que atiram de volta. Ao vencer, o botão chama para o jogo. Teclado (↑ ↓, Espaço, 1–3), mouse e toque.
4. **O jogo**: PvP, instâncias e POW com capturas de verdade, mais quatro cartões (loot, Ferreiro, leilão, visual).
5. **Arsenal**: as 12 armas com o especial, barras de dano/raio/ângulo e onde conseguir; troca sozinha até o jogador clicar.
6. **Expedições**: as 5 instâncias com o chefe na arena, fases, mecânicas e a Super Verdadeira.
7. **Galeria** com visualizador (setas do teclado), **compromisso “Grátis, sem vender poder”**, **FAQ** e a chamada final.

## Wiki (`website/wiki/`)

Página única com rotas no endereço (`wiki/#/armas/quebra_tijolos`, `wiki/#/monstros/rainha_nevasca`...), para dar para compartilhar o link de qualquer página. Tem busca instantânea (tecla `/`, acentos opcionais, nos dois idiomas), cartão do item ao passar o mouse em qualquer link, tabelas que ordenam ao clicar no cabeçalho e menu lateral que vira gaveta no celular.

- **Guias** (`js/wiki-guides.js`): primeiros passos, controles, turnos/Delay/energia/avião, mira/força/vento (com as fórmulas e uma tabela de alcance), dano e atributos (Ataque, Defesa, Sorte, Agilidade, Vida, com as fórmulas do `armory.gd`), POW, níveis e patentes.
- **Referência** (`js/wiki.js`): armas (lista e página de cada uma, com o especial em detalhe e o dano de +0 a +12 em cada qualidade), qualidades, fortalecimento, bônus aleatórios (faixas F1–F5), visual, habilidades 1–9, ferramentas, itens auxiliares, instâncias (fases, ondas, chefe, baú e escala por grupo), monstros (habilidades explicadas, com os efeitos que aplicam, e vida/dano por nível de mapa), efeitos de estado e elites (0.16: o que cada efeito faz, quem aplica e os afixos), mapas-item, arenas, moedas de criação, leilão, recompensas, loja e conquistas.

## Mascotes e Caçada (0.19–0.20)

- **Página inicial**: dois cartões novos (`#mascotes` e a Caçada) depois do POW, e as capturas de mascotes e da Caçada na galeria (`extras.hero.pet_*` e `hunt_*`, de `docs/screens/`).
- **Wiki**: grupo **Mascotes** com *Casa dos Mascotes* (`#/mascotes`: ovos e chances, garantia, raridades, elementos, níveis e estrelas, lista de espécies com filtro por elemento; `#/mascotes/<espécie>` com o poder por nível) e *Caçada dos Mascotes* (`#/cacada`: como se joga, zonas, regras da luta, roda de elementos, recompensas e o Passe do Caçador). Tudo sai de `shared/balance/pets.json` (bloco `pets` do `gamedata.js`) e entra na busca. A loja da wiki agrupa as seis Abas de Mochila numa linha.
- As fórmulas de poder do mascote estão repetidas em `petStats` (`website/js/wiki.js`), de `client/systems/pets.gd`: se mudarem lá, mudam aqui.

## Os números vêm do jogo

`tools/build_site.py` lê `shared/balance/*.json` e os nomes em inglês de `locale/en.po`, copia a arte usada (ícones, sprites, fundos em WebP sem perdas, capturas de `store/steam/screenshots`) e escreve `website/data/gamedata.js`. Também roda o `make_logo.py` e gera as prévias de link. **Depois de mudar o balanceamento, os itens ou as traduções, rode:**

```bash
python tools/build_site.py
```

(precisa de Pillow, numpy e scipy). Os textos à mão (guias, página inicial) usam os números dos dados, então quase nada precisa ser reescrito quando um valor muda. O que é texto fixo: as fórmulas que vêm do código (`armory.gd`, `match.gd`, `ballistics.gd`, `instance_run.gd`); se uma delas mudar, ajuste o guia correspondente em `js/wiki-guides.js`.

## Idiomas

Português e inglês. Na primeira visita segue o idioma do navegador; o botão PT/EN fica salvo. `?lang=en` força o inglês. O botão JOGAR passa o idioma para o jogo (`/jogar/?lang=en`). Os textos da página inicial em português ficam no próprio HTML; o inglês e os textos montados em JavaScript ficam em `js/i18n.js`; os nomes do jogo vêm dos dados.

## Onde o botão JOGAR leva

`website/js/config.js`: `playUrl` (padrão `/jogar/`) e `steamUrl` (vazio mostra “Steam em breve”). Nada mais precisa mudar ao hospedar em outro lugar.

## Rodar e publicar

- **Só olhar o site**: abra `website/index.html` no navegador, ou `python -m http.server -d website 8000`.
- **Site + jogo como na produção**: `python tools/web_build.py export` e depois `python tools/web_build.py serve --site --api http://localhost:8080` (site em `/`, jogo em `/jogar/`).
- **Docker** (`tools/local.sh`, `SubirLocal.cmd`): o serviço `web` agora serve o site em `http://localhost:8000` e o jogo em `http://localhost:8000/jogar/`, pelo mesmo nginx (`server/docker/web.nginx.conf`) que encaminha `/v1/` e `/ws`.
- **Com domínio**: troque `og:image` em `website/index.html` por um endereço absoluto (`https://seu-dominio/img/brand/og_pt.png`), senão WhatsApp, Discord e outros não mostram a prévia do link.

## Privacidade

O site não usa rastreadores, anúncios nem fontes do Google (as fontes vão junto, em `website/fonts/`): combina com a Política de Privacidade, que promete não usar rastreadores. O único dado guardado é a escolha de idioma, no `localStorage` do navegador.

## Pendências

- Busca de marca de “Gustfire” antes de registrar domínio e página da Steam.
- Links de **Termos de Uso** e **Política de Privacidade** no rodapé quando os textos de `legal/` tiverem os dados da empresa e a revisão jurídica.
- Endereço absoluto no `og:image` quando houver domínio.
