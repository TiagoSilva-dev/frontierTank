/* Wiki guides (how the game works). Numbers come from the game data (D), so they follow
 * the balance files; the prose is written by hand in both languages. */
(function () {
  "use strict";
  const GF = window.GF;

  function rangeTable(D, h) {
    // Flat ground, no wind: R = v² · sin(2θ) / g, with v from the power bar.
    const C = D.combat;
    const powers = [40, 50, 60, 70, 80, 90, 100];
    const angles = [30, 45, 60, 70];
    const speed = (p) => C.min_speed + (C.max_speed - C.min_speed) * p / 100;
    const rows = powers.map((p) => `<tr>${h.td(`<b>${p}</b>`)}${h.tdn(Math.round(speed(p)))}${angles.map((a) => h.tdn(Math.round(speed(p) ** 2 * Math.sin((2 * a * Math.PI) / 180) / C.gravity))).join("")}</tr>`);
    return h.table([h.T("Força", "Power"), [h.T("Velocidade", "Speed"), "num"]].concat(angles.map((a) => [`${a}°`, "num"])), rows);
  }

  function expTable(D, h) {
    const levels = [2, 5, 10, 15, 20, 25, 30, 40, 50, 60];
    const exp = (l) => 60 * l * (l - 1);
    const rank = (l) => h.L(D.ranks[Math.min(D.ranks.length - 1, Math.floor((l - 1) / 4))]);
    return h.table([[h.T("Nível", "Level"), "num"], [h.T("EXP total", "Total EXP"), "num"], [h.T("Vida", "HP"), "num"], [h.T("Agilidade base", "Base agility"), "num"], h.T("Patente", "Rank")],
      levels.map((l) => `<tr>${h.td(`<b>${l}</b>`, l, "num")}${h.tdn(exp(l))}${h.tdn(D.combat.base_hp + l * D.combat.hp_per_level)}${h.tdn(D.combat.base_agility + l * D.combat.agility_per_level)}${h.td(h.esc(rank(l)))}</tr>`));
  }

  GF.GUIDES = {
    "primeiros-passos": {
      title: { pt: "Primeiros passos", en: "First steps" },
      intro: { pt: "Do primeiro login à primeira arma Verdadeira: o caminho de quem está começando.", en: "From your first login to your first True weapon: the path for newcomers." },
      icon: (D) => D.icons.play,
      keywords: "comecar começar iniciante tutorial conta cidade start beginner account city new",
      body: (D, h) => ({
        pt: `
          <h2>1. Entre no jogo</h2>
          <p>Clique em <b>Jogar</b> no site. Na tela de entrada, escolha o servidor, digite um nome de conta e uma senha e aperte <b>CRIAR CONTA</b> (na primeira vez você aceita os Termos de Uso e a Política de Privacidade). Nas próximas vezes, é só <b>ENTRAR</b>. O idioma fica no canto da tela. Sem internet? O <b>Modo offline</b> joga contra a IA.</p>
          <h2>2. Conheça a cidade</h2>
          <ul>
            <li><b>Salão de Jogos</b> (o coliseu no centro): salas de PvP, de 1 contra 1 até 4 contra 4.</li>
            <li><b>Instância</b> (o portal): expedições cooperativas contra chefes. Veja <a href="#/instancias">Instâncias</a>.</li>
            <li><b>Ferreiro</b>: fortalecer até +${D.strengthen.max}, transferir o nível entre itens e usar <a href="#/moedas">moedas de criação</a>.</li>
            <li><b>Centro Comercial</b>: armas, visuais, itens auxiliares, ferramentas e pedras, com provador.</li>
            <li><b>Leilão</b>: compra e venda entre jogadores (online). <b>Correio</b>: pagamentos e itens que chegam para você.</li>
            <li><b>Mochila</b>: seu personagem, equipamentos, atributos e inventário.</li>
          </ul>
          <h2>3. Sua primeira batalha</h2>
          <p>No Salão de Jogos, crie uma sala e aperte <b>Início</b>: o jogo procura uma equipe rival do mesmo tamanho; se ninguém aparecer, a IA completa a sala em alguns segundos. Na sua vez, ajuste o ângulo com <b>↑ ↓</b>, olhe o vento no alto da tela, segure <b>Espaço</b> e solte na força certa. Veja <a href="#/guia/mira">Mira, força e vento</a>.</p>
          <h2>4. Fique mais forte</h2>
          <ol>
            <li>Equipe a melhor arma, a camisa e a calça na Mochila (clique duplo, ou arraste até o personagem).</li>
            <li>Fortaleça a arma no Ferreiro: cada nível aumenta o dano e os atributos (<a href="#/fortalecimento">Fortalecimento</a>).</li>
            <li>Entre nas instâncias: lá caem armas Verdadeiras, <a href="#/mapas">mapas</a> e moedas de criação.</li>
            <li>Use as moedas para melhorar os <a href="#/bonus">bônus</a> dos itens, ou venda o que sobrar no <a href="#/leilao">Leilão</a>.</li>
          </ol>
          <h2>Dicas de artilheiro</h2>
          <ul>
            <li>Olhe o vento <b>antes</b> de cada disparo: ele muda a cada turno.</li>
            <li>Tiros altos ficam mais tempo no ar e sentem mais o vento.</li>
            <li>O tracejado do último disparo fica na tela: use-o para corrigir a força.</li>
            <li>Guarde o <a href="#/guia/pow">POW</a> para quando vários inimigos estiverem juntos e combine com a habilidade de +50% de dano.</li>
            <li>Às vezes <b>Passar</b> (P) é a melhor jogada: soma menos Delay e você volta mais cedo.</li>
            <li>Cuidado com a beirada: quem cai do mapa é eliminado na hora. A explosão também fere aliados.</li>
          </ul>`,
        en: `
          <h2>1. Get in</h2>
          <p>Click <b>Play</b> on the site. On the login screen, pick the server, type an account name and a password and press <b>CREATE ACCOUNT</b> (the first time you accept the Terms of Use and the Privacy Policy). After that, just <b>LOG IN</b>. The language switch is in the corner. No internet? <b>Offline mode</b> plays against the AI.</p>
          <h2>2. Meet the city</h2>
          <ul>
            <li><b>Game Hall</b> (the colosseum in the middle): PvP rooms, from 1v1 up to 4v4.</li>
            <li><b>Dungeon</b> (the portal): co-op expeditions against bosses. See <a href="#/instancias">Dungeons</a>.</li>
            <li><b>Blacksmith</b>: strengthen up to +${D.strengthen.max}, transfer levels between items and use <a href="#/moedas">crafting currencies</a>.</li>
            <li><b>Shopping Center</b>: weapons, cosmetics, support items, tools and stones, with a fitting room.</li>
            <li><b>Auction</b>: trading between players (online). <b>Mail</b>: payments and items sent to you.</li>
            <li><b>Bag</b>: your character, gear, attributes and inventory.</li>
          </ul>
          <h2>3. Your first battle</h2>
          <p>In the Game Hall, create a room and press <b>Start</b>: the game looks for a rival team of the same size; if nobody shows up, the AI fills the room in a few seconds. On your turn, set the angle with <b>↑ ↓</b>, check the wind at the top of the screen, hold <b>Space</b> and let go at the right power. See <a href="#/guia/mira">Aim, power and wind</a>.</p>
          <h2>4. Get stronger</h2>
          <ol>
            <li>Equip your best weapon and clothes in the Bag (double-click, or drag onto your character).</li>
            <li>Strengthen your weapon at the Blacksmith: each level raises damage and attributes (<a href="#/fortalecimento">Strengthening</a>).</li>
            <li>Run dungeons: True weapons, <a href="#/mapas">maps</a> and crafting currencies drop there.</li>
            <li>Use currencies to improve your items' <a href="#/bonus">bonuses</a>, or sell what you don't need at the <a href="#/leilao">Auction</a>.</li>
          </ol>
          <h2>Gunner tips</h2>
          <ul>
            <li>Check the wind <b>before</b> every shot: it changes each turn.</li>
            <li>High shots stay longer in the air and feel the wind more.</li>
            <li>The dashed line of your last shot stays on screen: use it to correct your power.</li>
            <li>Save your <a href="#/guia/pow">POW</a> for when several enemies stand together, and stack it with the +50% damage skill.</li>
            <li>Sometimes <b>Pass</b> (P) is the best move: it adds less Delay, so you come back sooner.</li>
            <li>Mind the edges: falling off the map knocks you out at once. Blasts hurt allies too.</li>
          </ul>`,
      }),
    },

    controles: {
      title: { pt: "Controles", en: "Controls" },
      intro: { pt: "Todas as teclas da batalha e os botões do celular.", en: "Every battle key and the phone's buttons." },
      icon: (D) => D.icons.power,
      keywords: "teclas teclado atalhos keys keyboard shortcuts celular toque touch mobile phone android iphone botoes buttons",
      body: (D, h) => {
        const keys = [
          ["← →", "Andar (gasta energia)", "Walk (spends energy)"],
          ["↑ ↓", "Mudar o ângulo", "Change the angle"],
          ["Espaço / Space", "Segurar para carregar a força, soltar para disparar", "Hold to charge power, release to fire"],
          ["1 – 9", "Habilidades do turno", "Skills for this turn"],
          ["Z X C", "Ferramentas", "Tools"],
          ["B", "Soltar o POW (com a barra cheia)", "Unleash the POW (full gauge)"],
          ["F", "Avião de papel", "Paper plane"],
          ["V", "Item auxiliar", "Support item"],
          ["P", "Passar a vez", "Pass the turn"],
          ["Q", "Virar para o outro lado", "Turn around"],
          ["Esc", "Pausa (música e efeitos)", "Pause (music and effects)"],
          ["M", "Liga e desliga a música", "Toggle music"],
          [h.T("Botão direito", "Right mouse"), "Arrastar a câmera", "Drag the camera"],
          [h.T("Clique no minimapa", "Minimap click"), "Mover a câmera até ali", "Move the camera there"],
          ["F3", "Contador de FPS", "FPS counter"],
        ];
        const rows = keys.map(([k, pt, en]) => `<tr>${h.td(`<b style="font:700 18px var(--pixel)">${h.esc(k)}</b>`)}${h.td(h.esc(h.T(pt, en)))}</tr>`);
        const table = h.table([h.T("Tecla", "Key"), h.T("Ação", "Action")], rows);
        // The phone (a browser on Android or iPhone): the battle gets its own buttons, which
        // press the same keys, so the rules are the same as on the computer.
        const touch = [
          ["◀ ▶", "Andar (gasta energia); tocar no lado oposto vira o personagem", "Walk (spends energy); tapping the opposite side turns the fighter around"],
          ["↑ ↓", "Mudar o ângulo (segure para mover)", "Change the angle (hold to keep moving)"],
          [h.T("FOGO", "FIRE"), "Segurar para carregar a força, soltar para disparar", "Hold to charge power, release to fire"],
          [h.T("HAB.", "SKILLS"), "Abre a gaveta com as habilidades 1–9 do turno", "Opens the drawer with skills 1–9 for this turn"],
          ["Z X C · G · V · F", "Ferramentas, mascote, item auxiliar e avião de papel: um toque em cada botão da fileira", "Tools, pet, support item and paper plane: one tap on each button of the row"],
          ["POW", "Toque no círculo roxo, no canto, com a barra cheia", "Tap the purple orb in the corner when the gauge is full"],
          ["PASS", "Passar a vez", "Pass the turn"],
          [h.T("Arrastar", "Drag"), "Com um dedo no campo de batalha, move a câmera; tocar no minimapa leva a câmera até ali", "One finger on the battlefield moves the camera; tapping the minimap takes it there"],
          [h.T("Segurar", "Press and hold"), "Em qualquer item ou habilidade, mostra a descrição (no lugar do mouse parado em cima)", "On any item or skill, shows the description (instead of hovering with a mouse)"],
          [h.T("3 dedos", "3 fingers"), "Contador de FPS (como o F3)", "FPS counter (like F3)"],
        ];
        const touchRows = touch.map(([k, pt, en]) => `<tr>${h.td(`<b style="font:700 18px var(--pixel)">${h.esc(k)}</b>`)}${h.td(h.esc(h.T(pt, en)))}</tr>`);
        const touchTable = h.table([h.T("Botão", "Button"), h.T("Ação", "Action")], touchRows);
        return {
          pt: `${table}<p class="note">O botão <b>Confiar</b> deixa a IA jogar os seus turnos (bom se você precisar sair um instante). No navegador, o endereço aceita <code>?lang=en</code> e <code>?fps=1</code>.</p>
            <h2>No celular</h2>
            <p>No Android e no iPhone, abra o jogo no navegador, com o aparelho na horizontal. A batalha ganha botões na tela, feitos para o polegar, e eles apertam as mesmas teclas do computador: as regras são as mesmas. No iPhone, <b>Compartilhar → Adicionar à Tela de Início</b> abre o jogo em tela cheia.</p>
            ${touchTable}`,
          en: `${table}<p class="note">The <b>Trust</b> button lets the AI play your turns (handy if you need to step away). In the browser, the address accepts <code>?lang=en</code> and <code>?fps=1</code>.</p>
            <h2>On a phone</h2>
            <p>On Android and iPhone, open the game in the browser with the device held sideways. The battle gets on-screen buttons made for your thumb, and they press the same keys as the computer: the rules are the same. On iPhone, <b>Share → Add to Home Screen</b> opens the game full screen.</p>
            ${touchTable}`,
        };
      },
    },

    combate: {
      title: { pt: "Turnos, Delay e energia", en: "Turns, Delay and energy" },
      intro: { pt: "Quem joga quando, quanto dá para andar e como o avião de papel funciona.", en: "Who plays when, how far you can move and how the paper plane works." },
      icon: (D) => D.icons.team,
      keywords: "delay turno ordem energia agilidade aviao avião passar confiar turn order energy agility plane pass",
      body: (D, h) => {
        const C = D.combat;
        const d = C.delay;
        return {
          pt: `
            <h2>Tempo do turno</h2>
            <p>No PvP o turno dura <b>${C.turn_seconds} s</b> (a sala pode escolher ${C.turn_seconds_options.join(", ")} s); nas instâncias, <b>${D.pve.turn_seconds} s</b>. Se o tempo acabar, a vez passa.</p>
            <h2>Delay: a ordem dos turnos</h2>
            <p>Não existe fila fixa. Cada ação soma <b>Delay</b> e quem tiver o menor Delay acumulado joga em seguida. Por isso um jogador ágil ou que usa poucas habilidades pode jogar duas vezes antes de um rival lento.</p>
            <code class="formula">Delay do turno = ${d.base} − Agilidade
              + Delay das habilidades usadas
              + ${d.move_per_px} × pixels andados
              + ${d.tool} × ferramentas usadas
              + ${C.fly.delay} se usou o avião
Passar a vez: o total × ${d.pass_scale}      Congelado: ${d.frozen}</code>
            <p>O bônus <b>−Delay por turno</b> dos equipamentos desconta desse total (cada turno soma no mínimo 100). A partida começa com um Delay aleatório pequeno, menor para quem tem mais Agilidade.</p>
            <h2>Energia</h2>
            <p>Todo turno começa com <b>${C.energy} + Agilidade ÷ 30</b> de energia (mais o bônus de energia dos equipamentos). Andar gasta <b>${C.move_energy_per_px}</b> por pixel e cada <a href="#/habilidades">habilidade</a> tem o seu custo. A energia não acumula de um turno para o outro.</p>
            <h2>Avião de papel (F)</h2>
            <p>No lugar do tiro, você é lançado junto com o avião e pousa onde ele cair. Custa <b>${C.fly.energy}</b> de energia, soma <b>${C.fly.delay}</b> de Delay e recarrega em <b>${C.fly.cooldown}</b> turnos. Não combina com habilidades nem com o POW, e alguns mapas de instância proíbem (“Sem avião de papel”).</p>
            <h2>Terreno e quedas</h2>
            <p>Cada explosão abre uma cratera. Quem fica sem chão cai, e quem cai para fora do mapa é eliminado na hora. Andar é também uma forma de fugir de um buraco ou de subir numa ilha melhor.</p>`,
          en: `
            <h2>Turn timer</h2>
            <p>In PvP a turn lasts <b>${C.turn_seconds} s</b> (rooms can pick ${C.turn_seconds_options.join(", ")} s); in dungeons, <b>${D.pve.turn_seconds} s</b>. When time runs out, the turn passes.</p>
            <h2>Delay: turn order</h2>
            <p>There is no fixed queue. Every action adds <b>Delay</b>, and whoever has the lowest total Delay plays next. That is why an agile player, or one using few skills, can play twice before a slow rival.</p>
            <code class="formula">Turn Delay = ${d.base} − Agility
           + Delay of the skills used
           + ${d.move_per_px} × pixels walked
           + ${d.tool} × tools used
           + ${C.fly.delay} if you used the plane
Pass: the total × ${d.pass_scale}      Frozen: ${d.frozen}</code>
            <p>The gear bonus <b>−Delay per turn</b> is taken off that total (a turn always adds at least 100). Matches start with a small random Delay, lower for higher Agility.</p>
            <h2>Energy</h2>
            <p>Every turn starts with <b>${C.energy} + Agility ÷ 30</b> energy (plus the energy bonus from gear). Walking costs <b>${C.move_energy_per_px}</b> per pixel and each <a href="#/habilidades">skill</a> has its own cost. Energy does not carry over between turns.</p>
            <h2>Paper plane (F)</h2>
            <p>Instead of a shot, you are launched with the plane and land where it falls. It costs <b>${C.fly.energy}</b> energy, adds <b>${C.fly.delay}</b> Delay and recharges in <b>${C.fly.cooldown}</b> turns. It cannot be combined with skills or the POW, and some dungeon maps forbid it (“No paper plane”).</p>
            <h2>Terrain and falls</h2>
            <p>Every blast opens a crater. Whoever loses their footing falls, and falling off the map knocks you out at once. Walking is also how you escape a hole or climb onto a better island.</p>`,
        };
      },
    },

    mira: {
      title: { pt: "Mira, força e vento", en: "Aim, power and wind" },
      intro: { pt: "A física do disparo, com as mesmas fórmulas e números do jogo.", en: "Shot physics, with the game's own formulas and numbers." },
      icon: (D) => D.icons.plane,
      keywords: "mira angulo ângulo forca força vento gravidade balistica alcance aim angle power wind gravity ballistics range",
      body: (D, h) => {
        const C = D.combat;
        const slow = D.weapons.filter((w) => w.projectile.wind_scale < 1);
        return {
          pt: `
            <h2>Ângulo</h2>
            <p>Cada arma tem uma faixa de ângulo (o arco vermelho em volta do personagem), por exemplo ${h.ref("weapon", "quebra_tijolos")} de ${D.weapons[0].angle[0]}° a ${D.weapons[0].angle[1]}°. As setas ↑ ↓ giram a mira a 30° por segundo. O ângulo é medido a partir do chão onde você está: numa ladeira, a mira inclina junto.</p>
            <h2>Força</h2>
            <p>Segure <b>Espaço</b>: a barra enche <b>${C.charge_rate}%</b> por segundo (cerca de ${h.n(100 / C.charge_rate, 1)} s até 100). Solte para disparar. A marca vermelha na barra mostra a força do seu último tiro.</p>
            <code class="formula">velocidade = ${C.min_speed} + (${C.max_speed} − ${C.min_speed}) × força ÷ 100   (px/s)
x(t) = x₀ + v·cos(θ)·t + ½·(${C.wind_accel}·vento)·t²
y(t) = y₀ − v·sin(θ)·t + ½·${C.gravity}·t²</code>
            <h2>Vento</h2>
            <p>O vento vai de <b>−${C.wind_max}</b> a <b>+${C.wind_max}</b> e é sorteado a cada turno. Ele empurra o projétil de lado com aceleração de <b>${C.wind_accel} × vento</b> px/s²: quanto mais tempo no ar, maior o desvio. Um mapa com a ameaça “Vento sempre forte” nunca deixa o vento abaixo de 70% do máximo.</p>
            <ul>
              ${slow.map((w) => `<li>${h.ref("weapon", w.id, true)} sente só ${h.pct(w.projectile.wind_scale)} do vento.</li>`).join("")}
              <li>O POW ${h.ref("weapon", "vento_de_deus")} (Olho do Furacão) ignora o vento.</li>
              <li>O bônus “−% de efeito do vento” dos equipamentos reduz o vento até ${D.affixes.limits.vento}%.</li>
            </ul>
            <h2>Alcance sem vento, em terreno plano</h2>
            <p>Distância horizontal em pixels (a tela do jogo tem 1280 de largura). Use como ponto de partida e corrija pelo vento.</p>
            ${rangeTable(D, h)}`,
          en: `
            <h2>Angle</h2>
            <p>Each weapon has an angle range (the red arc around your character), for example ${h.ref("weapon", "quebra_tijolos")} from ${D.weapons[0].angle[0]}° to ${D.weapons[0].angle[1]}°. The ↑ ↓ keys turn your aim at 30° per second. The angle is measured from the ground you stand on: on a slope, your aim tilts with it.</p>
            <h2>Power</h2>
            <p>Hold <b>Space</b>: the bar fills at <b>${C.charge_rate}%</b> per second (about ${h.n(100 / C.charge_rate, 1)} s to 100). Release to fire. The red mark on the bar shows your last shot's power.</p>
            <code class="formula">speed = ${C.min_speed} + (${C.max_speed} − ${C.min_speed}) × power ÷ 100   (px/s)
x(t) = x₀ + v·cos(θ)·t + ½·(${C.wind_accel}·wind)·t²
y(t) = y₀ − v·sin(θ)·t + ½·${C.gravity}·t²</code>
            <h2>Wind</h2>
            <p>Wind ranges from <b>−${C.wind_max}</b> to <b>+${C.wind_max}</b> and is rolled every turn. It pushes the projectile sideways with an acceleration of <b>${C.wind_accel} × wind</b> px/s²: the longer it flies, the bigger the drift. A map with the “Wind always strong” threat never lets the wind drop below 70% of the maximum.</p>
            <ul>
              ${slow.map((w) => `<li>${h.ref("weapon", w.id, true)} only feels ${h.pct(w.projectile.wind_scale)} of the wind.</li>`).join("")}
              <li>The ${h.ref("weapon", "vento_de_deus")} POW (Eye of the Storm) ignores the wind.</li>
              <li>The gear bonus “−% wind effect” cuts the wind by up to ${D.affixes.limits.vento}%.</li>
            </ul>
            <h2>Range with no wind, on flat ground</h2>
            <p>Horizontal distance in pixels (the game screen is 1280 wide). Use it as a starting point and correct for the wind.</p>
            ${rangeTable(D, h)}`,
        };
      },
    },

    dano: {
      title: { pt: "Dano e atributos", en: "Damage and attributes" },
      intro: { pt: "Como o dano é calculado e o que Ataque, Defesa, Agilidade e Sorte fazem de verdade.", en: "How damage is worked out and what Attack, Defence, Agility and Luck really do." },
      icon: (D) => D.icons.shield,
      keywords: "dano ataque defesa agilidade sorte critico crítico vida explosao explosão raio damage attack defence defense agility luck critical hp splash",
      body: (D, h) => {
        const C = D.combat;
        const defRows = [50, 100, 200, 300, 400, 600].map((d) => `<tr>${h.tdn(d)}${h.tdn(d / (d + 800), "−" + h.pct(d / (d + 800), 1))}</tr>`);
        const w = D.weapons[0];
        const falloff = [0, 0.25, 0.5, 0.75, 1].map((f) => `<tr>${h.td(h.pct(f))}${h.tdn(Math.round(w.damage * (1 - 0.65 * f)))}</tr>`);
        return {
          pt: `
            <h2>Dano da arma</h2>
            <code class="formula">dano = dano base × qualidade × (1 + fortalecimento) × (1 + bônus “% de dano”)</code>
            <p>Os multiplicadores estão em <a href="#/qualidades">Qualidades</a> e <a href="#/fortalecimento">Fortalecimento</a>. As habilidades 4 a 8 somam +10% a +50% no turno; a 1, 2 e 3 disparam mais vezes com menos dano cada.</p>
            <h2>Explosão</h2>
            <p>O dano alcança <b>${C.splash_scale} ×</b> o raio da arma e cai de 100% no centro para 35% na borda. A distância é medida até a borda do corpo do alvo, então acertar perto já vale quase tudo.</p>
            <div class="twrap" style="max-width:420px">${h.table([h.T("Distância (fração do alcance)", "Distance (share of reach)"), [h.T("Dano do " + h.L(w.name), h.L(w.name) + " damage"), "num"]], falloff).replace('<div class="twrap">', "").replace(/<\/div>$/, "")}</div>
            <p class="note fire">A explosão também atinge aliados (sem crítico). Cuidado com tiros perto do seu time.</p>
            <h2>Atributos</h2>
            <p>Na batalha contam os atributos que vêm dos <b>equipamentos</b> (arma, camisa, calça, chapéu, óculos, asas e bônus). A Mochila mostra também a base do nível.</p>
            <ul>
              <li><b>Ataque</b>: +0,1% de dano por ponto. <code>dano × (1 + Ataque ÷ 1000)</code></li>
              <li><b>Defesa</b>: reduz o dano recebido com retorno decrescente. <code>dano × (1 − Defesa ÷ (Defesa + 800))</code></li>
              <li><b>Sorte</b>: chance de crítico de Sorte ÷ 1500, até 25%. O crítico causa ×1,5 (mais o bônus “% de dano crítico”).</li>
              <li><b>Agilidade</b>: ${C.base_agility} + ${C.agility_per_level} por nível + metade da Agilidade dos equipamentos. Cada ponto tira 1 de Delay por turno, e cada 30 pontos dão +1 de energia.</li>
              <li><b>Vida</b>: ${h.n(C.base_hp)} + ${C.hp_per_level} por nível, +${D.strengthen.hp_per_level} por nível de fortalecimento na camisa, na calça e no chapéu, mais o bônus de vida.</li>
            </ul>
            <h3>Defesa na prática</h3>
            <div class="twrap" style="max-width:420px">${h.table([[h.T("Defesa", "Defence"), "num"], [h.T("Dano recebido", "Damage taken"), "num"]], defRows).replace('<div class="twrap">', "").replace(/<\/div>$/, "")}</div>
            <h2>Escudos</h2>
            <p>O Escudo (ferramenta), o ${h.ref("aux", "escudo_bugou")} e a ${h.ref("aux", "escudo_barao")} reduzem só o <b>próximo</b> dano recebido.</p>`,
          en: `
            <h2>Weapon damage</h2>
            <code class="formula">damage = base damage × quality × (1 + strengthening) × (1 + “% damage” bonus)</code>
            <p>The multipliers are in <a href="#/qualidades">Qualities</a> and <a href="#/fortalecimento">Strengthening</a>. Skills 4 to 8 add +10% to +50% for the turn; 1, 2 and 3 fire more shots with less damage each.</p>
            <h2>Blast</h2>
            <p>Damage reaches <b>${C.splash_scale} ×</b> the weapon radius and falls from 100% at the centre to 35% at the edge. Distance is measured to the edge of the target's body, so a near hit is worth almost everything.</p>
            <div class="twrap" style="max-width:420px">${h.table([h.T("Distância (fração do alcance)", "Distance (share of reach)"), [h.T("Dano do " + h.L(w.name), h.L(w.name) + " damage"), "num"]], falloff).replace('<div class="twrap">', "").replace(/<\/div>$/, "")}</div>
            <p class="note fire">Blasts hit allies too (never critically). Careful with shots near your team.</p>
            <h2>Attributes</h2>
            <p>In battle, the attributes that count are the ones from your <b>gear</b> (weapon, shirt, trousers, hat, glasses, wings and bonuses). The Bag also shows your level base.</p>
            <ul>
              <li><b>Attack</b>: +0.1% damage per point. <code>damage × (1 + Attack ÷ 1000)</code></li>
              <li><b>Defence</b>: reduces damage taken, with diminishing returns. <code>damage × (1 − Defence ÷ (Defence + 800))</code></li>
              <li><b>Luck</b>: critical chance of Luck ÷ 1500, up to 25%. Criticals deal ×1.5 (plus the “% critical damage” bonus).</li>
              <li><b>Agility</b>: ${C.base_agility} + ${C.agility_per_level} per level + half the Agility from gear. Each point removes 1 Delay per turn, and every 30 points give +1 energy.</li>
              <li><b>HP</b>: ${h.n(C.base_hp)} + ${C.hp_per_level} per level, +${D.strengthen.hp_per_level} per strengthening level on shirt, trousers and hat, plus the HP bonus.</li>
            </ul>
            <h3>Defence in practice</h3>
            <div class="twrap" style="max-width:420px">${h.table([[h.T("Defesa", "Defence"), "num"], [h.T("Dano recebido", "Damage taken"), "num"]], defRows).replace('<div class="twrap">', "").replace(/<\/div>$/, "")}</div>
            <h2>Shields</h2>
            <p>The Shield tool, the ${h.ref("aux", "escudo_bugou")} and the ${h.ref("aux", "escudo_barao")} only reduce the <b>next</b> hit you take.</p>`,
        };
      },
    },

    pow: {
      title: { pt: "POW", en: "POW" },
      intro: { pt: "O especial de cada arma: como encher a barra e o que cada um faz.", en: "Every weapon's special: how to fill the gauge and what each one does." },
      icon: (D) => D.icons.pow,
      keywords: "pow especial especiais barra gauge special specials",
      body: (D, h) => {
        const C = D.combat;
        const rows = D.weapons.map((w) => `<tr>${h.td(`<span class="name">${h.icon(w.pow.art || w.icon)}${h.ref("weapon", w.id)}</span>`, h.L(w.name))}${h.td(`<b>${h.esc(h.L(w.pow.name))}</b>`, h.L(w.pow.name))}${h.td(h.esc(h.L(w.pow.desc)))}${h.tdn(w.pow.damage_scale || 1, h.mult(w.pow.damage_scale || 1))}</tr>`);
        const table = h.table([[h.T("Arma", "Weapon"), "text"], ["POW", "text"], h.T("Efeito", "Effect"), [h.T("Dano", "Damage"), "num"]], rows, { sortable: true });
        return {
          pt: `
            <h2>A barra de POW</h2>
            <ul>
              <li>+<b>${C.pow_per_turn}</b> no começo de cada turno seu;</li>
              <li>+<b>${C.pow_per_damage_dealt}</b> por ponto de dano que você causa (1.000 de dano = +${h.n(1000 * C.pow_per_damage_dealt)});</li>
              <li>+<b>${C.pow_per_damage_taken}</b> por ponto de dano que você recebe;</li>
              <li>a habilidade 9 (<a href="#/habilidades">POW Máx</a>) enche a barra na hora; o bônus de arma “Começa a batalha com X de POW” adianta o começo.</li>
            </ul>
            <p>Com a barra em <b>${C.pow_max}</b>, aperte <b>B</b> para armar o especial no tiro do turno. O especial não combina com o avião de papel nem com a habilidade Três Bolas. O bônus “+% de dano do POW” aumenta só o especial.</p>
            <p>Na hora do disparo a partida para um instante: entra o <i>cut-in</i> com o seu personagem e o nome do especial, e o impacto tem um pequeno congelamento de quadro para pesar mais.</p>
            <h2>Todos os especiais</h2>${table}`,
          en: `
            <h2>The POW gauge</h2>
            <ul>
              <li>+<b>${C.pow_per_turn}</b> at the start of each of your turns;</li>
              <li>+<b>${C.pow_per_damage_dealt}</b> per point of damage you deal (1,000 damage = +${h.n(1000 * C.pow_per_damage_dealt)});</li>
              <li>+<b>${C.pow_per_damage_taken}</b> per point of damage you take;</li>
              <li>skill 9 (<a href="#/habilidades">POW Max</a>) fills it instantly; the weapon bonus “Starts the battle with X POW” gives you a head start.</li>
            </ul>
            <p>With the gauge at <b>${C.pow_max}</b>, press <b>B</b> to arm the special for this turn's shot. It cannot be combined with the paper plane or the Three Balls skill. The “+% POW damage” bonus only boosts the special.</p>
            <p>When you fire, the match holds for a moment: an anime cut-in shows your character and the special's name, and the impact gets a short hit-stop so it lands heavier.</p>
            <h2>Every special</h2>${table}`,
        };
      },
    },

    progresso: {
      title: { pt: "Níveis e patentes", en: "Levels and ranks" },
      intro: { pt: "Experiência, níveis e a patente que aparece embaixo do seu nome.", en: "Experience, levels and the rank shown under your name." },
      icon: (D) => D.icons.star,
      keywords: "nivel nível exp experiencia experiência patente recruta marechal level xp experience rank",
      body: (D, h) => {
        const R = D.rewards;
        const ranks = D.ranks.map((r, i) => `<span class="pill">${h.esc(h.L(r))} · ${i * 4 + 1}${i === D.ranks.length - 1 ? "+" : "–" + (i * 4 + 4)}</span>`).join("");
        return {
          pt: `
            <h2>Experiência</h2>
            <p>Uma vitória dá <b>${R.win_exp}</b> EXP e uma derrota <b>${R.loss_exp}</b>, mais <b>${R.exp_per_damage}</b> por ponto de dano causado e <b>${R.exp_per_kill}</b> por abate. Nas instâncias, o nível do mapa e o bônus “+% de XP” multiplicam tudo. O nível máximo é <b>${D.max_level}</b>.</p>
            <code class="formula">EXP total para o nível N = 60 × N × (N − 1)</code>
            ${expTable(D, h)}
            <h2>Patentes</h2>
            <p>A patente sobe a cada 4 níveis:</p>
            <div class="pills">${ranks}</div>
            <h2>Mérito</h2>
            <p>Cada partida também dá mérito (${R.merit_win} na vitória, ${R.merit_loss} na derrota, +${R.merit_per_kill} por abate), que entra no ranking junto com as vitórias.</p>`,
          en: `
            <h2>Experience</h2>
            <p>A win gives <b>${R.win_exp}</b> EXP and a loss <b>${R.loss_exp}</b>, plus <b>${R.exp_per_damage}</b> per point of damage dealt and <b>${R.exp_per_kill}</b> per kill. In dungeons, the map level and the “+% XP” bonus multiply it all. The level cap is <b>${D.max_level}</b>.</p>
            <code class="formula">Total EXP for level N = 60 × N × (N − 1)</code>
            ${expTable(D, h)}
            <h2>Ranks</h2>
            <p>Your rank goes up every 4 levels:</p>
            <div class="pills">${ranks}</div>
            <h2>Merit</h2>
            <p>Every match also gives merit (${R.merit_win} on a win, ${R.merit_loss} on a loss, +${R.merit_per_kill} per kill), which counts toward the ranking together with your wins.</p>`,
        };
      },
    },
  };
})();
