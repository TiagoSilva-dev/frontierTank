/* "Try your aim": a small battle on the landing page with the game's own ballistics
 * (shared/balance/combat.json: gravity, launch speed, wind, charge rate, splash). */
(function () {
  "use strict";
  const GF = window.GF;
  const D = GF.data;
  const canvas = document.getElementById("play-canvas");
  if (!canvas || !D.combat) return;
  const ctx = canvas.getContext("2d");
  const W = canvas.width;
  const H = canvas.height;
  const C = D.combat;
  const FONT = '"Pixel Operator", monospace';
  const WEAPONS = ["quebra_tijolos", "vento_de_deus", "canhao_arco_iris"].map((id) => D.weapons.find((w) => w.id === id));
  const FOES = ["escaravelho_solar", "lobo_nevasca", "harpia_ruinas", "corvo_runico", "mascara_flamejante", "golem_gelo"];
  const FOE_SHOT = { escaravelho_solar: "fogo_intenso", mascara_flamejante: "fogo_intenso", harpia_ruinas: "canhao_arco_iris" };
  const $ = (id) => document.getElementById(id);

  const images = {};
  function load(key, src) {
    if (!src) return;
    const img = new Image();
    img.src = GF.img(src);
    images[key] = img;
  }
  load("bg", "img/game/maps/ilha_celeste.webp");
  ["a", "b", "c"].forEach((k) => load("t" + k, D.extras.terrain[k]));
  load("player", D.extras.hero.nilo_prone);
  D.extras.explosion.forEach((src, i) => load("boom" + i, src));
  WEAPONS.forEach((w) => load("p_" + w.id, w.projectile.img));
  D.weapons.forEach((w) => load("p_" + w.id, w.projectile.img));
  FOES.forEach((id) => load("e_" + id, D.enemies.find((e) => e.id === id).sprite));
  const ready = (img) => img && img.complete && img.naturalWidth > 0;

  // ---------- terrain (destructible, pixel mask) ----------

  const terrain = document.createElement("canvas");
  terrain.width = W;
  terrain.height = H;
  const tctx = terrain.getContext("2d", { willReadFrequently: true });
  let solid = new Uint8Array(W * H);
  const PIECES = [["ta", 40, 600, 2], ["tb", 650, 350, 2], ["tc", 900, 650, 2]];

  function buildTerrain() {
    tctx.clearRect(0, 0, W, H);
    tctx.imageSmoothingEnabled = false;
    PIECES.forEach(([key, x, y, s]) => {
      const img = images[key];
      if (ready(img)) tctx.drawImage(img, x, y, img.naturalWidth * s, img.naturalHeight * s);
    });
    refreshMask(0, 0, W, H);
  }

  function refreshMask(x0, y0, w, h) {
    x0 = Math.max(0, Math.floor(x0));
    y0 = Math.max(0, Math.floor(y0));
    w = Math.min(W - x0, Math.ceil(w));
    h = Math.min(H - y0, Math.ceil(h));
    if (w <= 0 || h <= 0) return;
    const data = tctx.getImageData(x0, y0, w, h);
    const px = data.data;
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4 + 3;
        // Keep the pixel look: no half-transparent edges.
        const on = px[i] > 110;
        px[i] = on ? 255 : 0;
        solid[(y0 + y) * W + x0 + x] = on ? 1 : 0;
      }
    }
    tctx.putImageData(data, x0, y0);
  }

  const isSolid = (x, y) => {
    x = Math.round(x);
    y = Math.round(y);
    return x >= 0 && y >= 0 && x < W && y < H && solid[y * W + x] === 1;
  };

  function crater(x, y, r) {
    tctx.save();
    tctx.globalCompositeOperation = "destination-out";
    tctx.beginPath();
    tctx.arc(x, y, r, 0, Math.PI * 2);
    tctx.fill();
    // Burnt rim, like the game's craters.
    tctx.globalCompositeOperation = "source-atop";
    tctx.strokeStyle = "rgba(58, 36, 24, 0.92)";
    tctx.lineWidth = 10;
    tctx.beginPath();
    tctx.arc(x, y, r + 4, 0, Math.PI * 2);
    tctx.stroke();
    tctx.restore();
    refreshMask(x - r - 12, y - r - 12, r * 2 + 24, r * 2 + 24);
  }

  function groundBelow(x, y) {
    for (let yy = Math.max(0, Math.round(y)); yy < H; yy++) if (isSolid(x, yy)) return yy;
    return H + 200;
  }

  // ---------- state ----------

  const state = {
    phase: "idle",
    weapon: 0,
    angle: 45,
    power: 0,
    lastPower: null,
    charging: false,
    wind: 0,
    foeIndex: 0,
    shots: 0,
    projectiles: [],
    booms: [],
    texts: [],
    trail: [],
    enemyTrail: [],
    shake: 0,
    timer: 0,
    aimDir: 0,
  };
  const player = { x: 250, y: 0, hp: C.base_hp, max: C.base_hp, vy: 0, hit: 20 };
  const foe = { x: 1310, y: 0, hp: 1, max: 1, vy: 0, def: null, alpha: 1, flash: 0 };

  function weapon() {
    return WEAPONS[state.weapon];
  }

  // Minions are small at 1x next to the whole map: show them a bit bigger (the hit
  // radius grows with them, so what you see is what you hit).
  function foeScale() {
    return foe.def && foe.def.rank === "minion" ? 1.5 : 1;
  }
  function foeHit() {
    return (foe.def.hit_radius || 20) * foeScale();
  }

  function rollWind() {
    const max = C.wind_max;
    state.wind = Math.round((Math.random() * 2 - 1) * max * 10) / 10;
  }

  function setupRound() {
    buildTerrain();
    const def = D.enemies.find((e) => e.id === FOES[state.foeIndex % FOES.length]);
    foe.def = def;
    foe.hp = foe.max = def.hp;
    foe.alpha = 1;
    foe.vy = 0;
    foe.y = groundBelow(foe.x, 0);
    player.y = groundBelow(player.x, 0);
    player.hp = player.max;
    player.vy = 0;
    state.projectiles = [];
    state.booms = [];
    state.texts = [];
    state.trail = [];
    state.enemyTrail = [];
    state.shots = 0;
    state.lastPower = null;
    state.power = 0;
    rollWind();
    clampAngle();
    updateHud();
  }

  function clampAngle() {
    const [lo, hi] = weapon().angle;
    state.angle = Math.min(hi, Math.max(lo, state.angle));
  }

  // ---------- physics (Ballistics.launch_velocity / acceleration) ----------

  function launch(from, angle, power, facing, windScale) {
    const speed = C.min_speed + (C.max_speed - C.min_speed) * Math.min(100, Math.max(0, power)) / 100;
    const rad = (angle * Math.PI) / 180;
    return {
      x: from.x, y: from.y,
      vx: Math.cos(rad) * speed * facing, vy: -Math.sin(rad) * speed,
      ax: state.wind * C.wind_accel * windScale, ay: C.gravity,
    };
  }

  function pivot(unit) {
    return { x: unit.x + (unit === player ? 18 : -10), y: unit.y - (unit === player ? 26 : 40) };
  }

  function fire() {
    if (state.phase !== "aim") return;
    const w = weapon();
    const shot = launch(pivot(player), state.angle, state.power, 1, w.projectile.wind_scale);
    Object.assign(shot, { owner: "player", img: "p_" + w.id, size: w.projectile.size * 1.5, spin: w.projectile.spin, align: w.projectile.align,
      damage: w.damage, radius: w.radius, rot: 0, path: [] });
    state.projectiles.push(shot);
    state.lastPower = state.power;
    state.power = 0;
    state.charging = false;
    state.shots += 1;
    state.phase = "flight";
    updateHud();
  }

  // Enemy AI: try the angles and powers, keep the one that lands closest, then miss a bit.
  function enemyShot() {
    const def = foe.def;
    const [lo, hi] = def.angle || [25, 70];
    const from = pivot(foe);
    const target = { x: player.x, y: player.y - 16 };
    let best = null;
    for (let a = lo; a <= hi; a += 5) {
      for (let p = 20; p <= 100; p += 2) {
        const land = simulate(launch(from, a, p, -1, 1));
        if (!land) continue;
        const d = Math.hypot(land.x - target.x, land.y - target.y);
        if (!best || d < best.d) best = { a, p, d };
      }
    }
    if (!best) best = { a: 45, p: 70 };
    const error = (Math.random() * 2 - 1) * 4.5;
    const shot = launch(from, best.a, best.p + error, -1, 1);
    const art = FOE_SHOT[def.id] || "trovao";
    Object.assign(shot, { owner: "foe", img: "p_" + art, size: 30, spin: 540, align: false, damage: def.damage, radius: def.radius || 32, rot: 0, path: [] });
    state.projectiles.push(shot);
    state.phase = "eflight";
  }

  function simulate(shot) {
    const dt = 1 / 60;
    for (let i = 0; i < 480; i++) {
      shot.vx += shot.ax * dt;
      shot.vy += shot.ay * dt;
      shot.x += shot.vx * dt;
      shot.y += shot.vy * dt;
      if (shot.x < -200 || shot.x > W + 200 || shot.y > H + 50) return null;
      if (isSolid(shot.x, shot.y) || Math.hypot(shot.x - player.x, shot.y - (player.y - 16)) < 24) return { x: shot.x, y: shot.y };
    }
    return null;
  }

  function splash(distance, radius, damage) {
    if (distance > radius) return 0;
    return Math.max(1, Math.round(damage * (1 - 0.65 * Math.min(1, distance / radius))));
  }

  function explode(shot) {
    const r = shot.radius;
    crater(shot.x, shot.y, r);
    state.booms.push({ x: shot.x, y: shot.y, t: 0, scale: (r * 2.4) / 96 });
    state.shake = Math.min(18, 6 + r / 5);
    const reach = r * C.splash_scale;
    const targets = shot.owner === "player" ? [foe] : [player];
    let hitSomething = false;
    targets.forEach((unit) => {
      if (unit.hp <= 0) return;
      const hitR = unit === foe ? foeHit() : player.hit;
      const cy = unit.y - (unit === foe ? 30 * foeScale() : 16);
      const distance = Math.max(0, Math.hypot(shot.x - unit.x, shot.y - cy) - hitR);
      let dmg = splash(distance, reach, shot.damage);
      if (!dmg) return;
      hitSomething = true;
      const crit = shot.owner === "player" && Math.random() < 0.12;
      if (crit) dmg = Math.round(dmg * 1.5);
      unit.hp = Math.max(0, unit.hp - dmg);
      if (unit === foe) foe.flash = 0.25;
      state.texts.push({ x: unit.x, y: cy - 50, text: (crit ? (GF.lang === "pt" ? "CRÍTICO " : "CRITICAL ") : "") + "-" + dmg,
        color: crit ? "#ff5aff" : shot.owner === "player" ? "#ffe95a" : "#ff9a7a", t: 0 });
    });
    if (!hitSomething && shot.owner === "player") state.texts.push({ x: shot.x, y: shot.y - 40, text: GF.t("try.miss"), color: "#ffffff", t: 0 });
  }

  // ---------- loop ----------

  let last = 0;
  let visible = false;
  let running = false;

  function step(dt) {
    // Charge: the power bar rises at charge_rate per second.
    if (state.phase === "aim" && state.charging) state.power = Math.min(100, state.power + C.charge_rate * dt);
    if (state.phase === "aim" && state.aimDir) {
      state.angle += state.aimDir * 30 * dt;
      clampAngle();
    }
    // Projectiles, in small steps so fast shots do not tunnel through thin ground.
    for (const shot of state.projectiles.slice()) {
      const sub = 4;
      for (let i = 0; i < sub; i++) {
        const h = dt / sub;
        shot.vx += shot.ax * h;
        shot.vy += shot.ay * h;
        shot.x += shot.vx * h;
        shot.y += shot.vy * h;
        shot.rot += (shot.spin || 0) * h;
        if (i === 0) shot.path.push([shot.x, shot.y]);
        const other = shot.owner === "player" ? foe : player;
        const hitR = other === foe ? foeHit() : player.hit;
        const cy = other.y - (other === foe ? 30 * foeScale() : 16);
        const touching = other.hp > 0 && Math.hypot(shot.x - other.x, shot.y - cy) < hitR + 6;
        const gone = shot.x < -300 || shot.x > W + 300 || shot.y > H + 60;
        if (isSolid(shot.x, shot.y) || touching || gone) {
          if (!gone) explode(shot);
          else if (shot.owner === "player") state.texts.push({ x: Math.min(W - 80, Math.max(80, shot.x)), y: H - 80, text: GF.t("try.miss"), color: "#fff", t: 0 });
          if (shot.owner === "player") state.trail = shot.path;
          else state.enemyTrail = shot.path;
          state.projectiles.splice(state.projectiles.indexOf(shot), 1);
          state.timer = 0.9;
          break;
        }
      }
    }
    // Units fall when the ground under them is blown away.
    [player, foe].forEach((unit) => {
      if (isSolid(unit.x, unit.y + 1) || isSolid(unit.x - 8, unit.y + 1) || isSolid(unit.x + 8, unit.y + 1)) {
        unit.vy = 0;
        while (isSolid(unit.x, unit.y) && unit.y > 0) unit.y -= 1;
      } else {
        unit.vy = Math.min(900, unit.vy + 1200 * dt);
        unit.y += unit.vy * dt;
        if (unit.y > H + 80 && unit.hp > 0) unit.hp = 0;
      }
    });
    if (foe.flash > 0) foe.flash -= dt;
    if (foe.hp <= 0) foe.alpha = Math.max(0, foe.alpha - dt * 1.4);
    state.booms.forEach((b) => (b.t += dt));
    state.booms = state.booms.filter((b) => b.t < 0.6);
    state.texts.forEach((t) => (t.t += dt));
    state.texts = state.texts.filter((t) => t.t < 1.4);
    state.shake = Math.max(0, state.shake - dt * 40);

    // Turns.
    if ((state.phase === "flight" || state.phase === "eflight") && state.projectiles.length === 0) {
      state.timer -= dt;
      if (state.timer <= 0) {
        if (foe.hp <= 0) return win();
        if (player.hp <= 0) return lose();
        if (state.phase === "flight") {
          state.phase = "enemy";
          state.timer = 0.8;
        } else {
          rollWind();
          state.phase = "aim";
          updateHud();
        }
      }
    }
    if (state.phase === "enemy") {
      state.timer -= dt;
      if (state.timer <= 0) enemyShot();
    }
  }

  function win() {
    state.phase = "won";
    const name = GF.L(foe.def.name);
    $("play-win-text").textContent = GF.t(state.shots === 1 ? "try.win_one" : "try.win_text", { name, shots: state.shots });
    $("play-win").hidden = false;
    $("play-win").querySelector("h3").textContent = GF.t("try.win");
  }

  function lose() {
    // The player can only fall off the map; start the same target again.
    state.phase = "aim";
    setupRound();
  }

  function draw() {
    ctx.save();
    ctx.imageSmoothingEnabled = false;
    if (state.shake > 0) ctx.translate((Math.random() - 0.5) * state.shake, (Math.random() - 0.5) * state.shake);
    if (ready(images.bg)) ctx.drawImage(images.bg, -20, -20, W + 40, H + 40);
    else {
      ctx.fillStyle = "#7ab8e8";
      ctx.fillRect(0, 0, W, H);
    }
    dashed(state.enemyTrail, "rgba(255, 150, 130, 0.85)");
    dashed(state.trail, "rgba(255, 255, 255, 0.95)");
    ctx.drawImage(terrain, 0, 0);

    // Player (prone, like in battle) and the aim arc.
    drawUnit(images.player, player.x, player.y, 1, false, 1);
    if (state.phase === "aim") drawAim();
    // The monster.
    if (foe.def) {
      const img = images["e_" + foe.def.id];
      const faceRight = foe.def.faces === "right";
      ctx.globalAlpha = foe.alpha;
      const scale = foeScale();
      drawUnit(img, foe.x, foe.y + (1 - foe.alpha) * 30, scale, faceRight, 1, foe.flash > 0);
      ctx.globalAlpha = 1;
      if (foe.hp > 0) drawBar(foe.x, foe.y - (img && img.naturalHeight ? img.naturalHeight * scale : 80) - 14, foe.hp / foe.max, GF.L(foe.def.name), "#ff5a5a");
    }
    drawBar(player.x, player.y - 64, player.hp / player.max, "Nilo", "#5ee27a");

    state.projectiles.forEach(drawProjectile);
    state.booms.forEach((b) => {
      const frame = Math.min(6, Math.floor((b.t / 0.6) * 7));
      const img = images["boom" + frame];
      if (!ready(img)) return;
      const s = 96 * Math.max(1.4, b.scale);
      ctx.drawImage(img, b.x - s / 2, b.y - s / 2, s, s);
    });
    ctx.textAlign = "center";
    state.texts.forEach((t) => {
      const a = Math.min(1, 2.4 - t.t * 1.7);
      ctx.globalAlpha = Math.max(0, a);
      ctx.font = `bold 40px ${FONT}`;
      ctx.lineWidth = 8;
      ctx.strokeStyle = "#1a0f2e";
      ctx.strokeText(t.text, t.x, t.y - t.t * 50);
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, t.x, t.y - t.t * 50);
      ctx.globalAlpha = 1;
    });
    ctx.restore();
    drawWind();
    drawTurn();
  }

  function drawUnit(img, x, y, scale, flip, alpha, flash) {
    if (!ready(img)) return;
    const w = img.naturalWidth * scale;
    const h = img.naturalHeight * scale;
    ctx.save();
    ctx.translate(Math.round(x), Math.round(y));
    if (flip) ctx.scale(-1, 1);
    if (flash) ctx.filter = "brightness(2.2)";
    ctx.drawImage(img, -w / 2, -h + 4, w, h);
    ctx.restore();
  }

  function drawAim() {
    const p = pivot(player);
    const [lo, hi] = weapon().angle;
    ctx.save();
    ctx.lineWidth = 6;
    ctx.strokeStyle = "rgba(242, 38, 26, 0.85)";
    ctx.beginPath();
    ctx.arc(p.x, p.y, 70, (-hi * Math.PI) / 180, (-lo * Math.PI) / 180);
    ctx.stroke();
    const rad = (state.angle * Math.PI) / 180;
    ctx.strokeStyle = "#ffe95a";
    ctx.lineWidth = 5;
    for (let i = 0; i < 7; i++) {
      ctx.beginPath();
      ctx.moveTo(p.x + Math.cos(rad) * (i * 14), p.y - Math.sin(rad) * (i * 14));
      ctx.lineTo(p.x + Math.cos(rad) * (i * 14 + 9), p.y - Math.sin(rad) * (i * 14 + 9));
      ctx.stroke();
    }
    ctx.restore();
  }

  function drawProjectile(shot) {
    const img = images[shot.img];
    if (!ready(img)) return;
    const s = shot.size;
    const ratio = img.naturalHeight / img.naturalWidth;
    ctx.save();
    ctx.translate(shot.x, shot.y);
    const angle = shot.align ? Math.atan2(shot.vy, shot.vx) + (shot.owner === "player" ? Math.PI / 4 : 0) : (shot.rot * Math.PI) / 180;
    ctx.rotate(angle);
    ctx.drawImage(img, -s / 2, (-s * ratio) / 2, s, s * ratio);
    ctx.restore();
  }

  function dashed(path, color) {
    if (!path || path.length < 2) return;
    ctx.save();
    ctx.setLineDash([14, 12]);
    ctx.lineCap = "butt";
    ctx.lineWidth = 7;
    ctx.strokeStyle = "rgba(26, 15, 46, 0.6)";
    ctx.beginPath();
    path.forEach(([x, y], i) => (i ? ctx.lineTo(x, y + 2) : ctx.moveTo(x, y + 2)));
    ctx.stroke();
    ctx.lineWidth = 4;
    ctx.strokeStyle = color;
    ctx.beginPath();
    path.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
    ctx.stroke();
    ctx.restore();
  }

  function drawBar(x, y, fraction, name, color) {
    const w = 120;
    ctx.save();
    ctx.fillStyle = "#1a0f2e";
    ctx.fillRect(x - w / 2 - 3, y - 3, w + 6, 16);
    ctx.fillStyle = "#3a2616";
    ctx.fillRect(x - w / 2, y, w, 10);
    ctx.fillStyle = color;
    ctx.fillRect(x - w / 2, y, Math.round(w * Math.max(0, fraction)), 10);
    ctx.font = `bold 24px ${FONT}`;
    ctx.textAlign = "center";
    ctx.lineWidth = 6;
    ctx.strokeStyle = "#1a0f2e";
    ctx.strokeText(name, x, y - 10);
    ctx.fillStyle = "#fff";
    ctx.fillText(name, x, y - 10);
    ctx.restore();
  }

  function drawWind() {
    const x = W / 2;
    const y = 58;
    ctx.save();
    ctx.fillStyle = "rgba(26, 15, 46, 0.78)";
    ctx.fillRect(x - 130, y - 36, 260, 72);
    ctx.strokeStyle = "#ffcf4a";
    ctx.lineWidth = 4;
    ctx.strokeRect(x - 130, y - 36, 260, 72);
    const dir = Math.sign(state.wind);
    const len = 16 + Math.abs(state.wind) * 16;
    ctx.strokeStyle = "#7fdcff";
    ctx.fillStyle = "#7fdcff";
    ctx.lineWidth = 8;
    if (dir !== 0) {
      const ax = x - 40;
      ctx.beginPath();
      ctx.moveTo(ax - (len / 2) * dir, y);
      ctx.lineTo(ax + (len / 2) * dir, y);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(ax + (len / 2 + 14) * dir, y);
      ctx.lineTo(ax + (len / 2 - 4) * dir, y - 14);
      ctx.lineTo(ax + (len / 2 - 4) * dir, y + 14);
      ctx.closePath();
      ctx.fill();
    }
    ctx.font = `bold 40px ${FONT}`;
    ctx.textAlign = "center";
    ctx.fillStyle = "#fff";
    ctx.fillText(dir === 0 ? "0" : Math.abs(state.wind).toFixed(1), x + 70, y + 14);
    ctx.restore();
  }

  function drawTurn() {
    if (state.phase !== "aim" && state.phase !== "enemy") return;
    const text = state.phase === "aim" ? (GF.lang === "pt" ? "SUA VEZ" : "YOUR TURN") : (GF.lang === "pt" ? "VEZ DO INIMIGO" : "ENEMY TURN");
    ctx.save();
    ctx.font = `bold 34px ${FONT}`;
    ctx.textAlign = "left";
    ctx.lineWidth = 8;
    ctx.strokeStyle = "#1a0f2e";
    ctx.strokeText(text, 30, 60);
    ctx.fillStyle = state.phase === "aim" ? "#ffe95a" : "#ff9a7a";
    ctx.fillText(text, 30, 60);
    ctx.restore();
  }

  function frame(now) {
    if (!visible) {
      running = false;
      return;
    }
    const dt = Math.min(1 / 30, (now - last) / 1000 || 0);
    last = now;
    if (state.phase !== "idle" && state.phase !== "won") step(dt);
    draw();
    updatePower();
    requestAnimationFrame(frame);
  }

  function wake() {
    if (running || !visible) return;
    running = true;
    last = performance.now();
    requestAnimationFrame(frame);
  }

  // ---------- HUD and input ----------

  function renderWeapons() {
    const box = $("play-weapons");
    box.innerHTML = WEAPONS.map((w, i) => `<button type="button" data-i="${i}" aria-pressed="${i === state.weapon}" title="${GF.esc(GF.L(w.name))} (${i + 1})"><img src="${GF.esc(GF.img(w.icon))}" alt="${GF.esc(GF.L(w.name))}"></button>`).join("");
    box.querySelectorAll("button").forEach((b) => b.addEventListener("click", () => pickWeapon(Number(b.dataset.i))));
  }

  function pickWeapon(i) {
    if (state.phase === "flight" || state.phase === "eflight") return;
    state.weapon = i;
    clampAngle();
    renderWeapons();
    updateHud();
  }

  function updateHud() {
    $("play-angle").textContent = Math.round(state.angle) + "°";
    const wind = state.wind;
    $("play-wind").textContent = wind === 0 ? GF.t("try.wind_calm") : (wind > 0 ? "→ " : "← ") + Math.abs(wind).toFixed(1);
  }

  function updatePower() {
    const bar = $("play-power");
    bar.querySelector("i").style.width = `calc(${state.power}% - ${state.power ? 6 : 0}px)`;
    const mark = bar.querySelector("em");
    if (state.lastPower != null) {
      mark.style.display = "block";
      mark.style.left = state.lastPower + "%";
    } else mark.style.display = "none";
    $("play-power-num").textContent = Math.round(state.power);
    $("play-angle").textContent = Math.round(state.angle) + "°";
  }

  function startCharge() {
    if (state.phase !== "aim") return;
    state.charging = true;
    state.power = 0;
  }
  function releaseCharge() {
    if (state.phase === "aim" && state.charging) fire();
  }

  function begin() {
    $("play-start").hidden = true;
    $("play-win").hidden = true;
    setupRound();
    state.phase = "aim";
    canvas.focus({ preventScroll: true });
  }

  function inView() {
    const r = canvas.getBoundingClientRect();
    return r.top < innerHeight * 0.75 && r.bottom > innerHeight * 0.25;
  }

  function setupInput() {
    $("play-go").addEventListener("click", begin);
    $("play-again").addEventListener("click", () => {
      state.foeIndex += 1;
      begin();
    });
    const fireBtn = $("play-fire");
    fireBtn.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      if (state.phase === "idle") begin();
      startCharge();
      fireBtn.setPointerCapture(e.pointerId);
    });
    fireBtn.addEventListener("pointerup", releaseCharge);
    fireBtn.addEventListener("pointercancel", releaseCharge);
    fireBtn.addEventListener("contextmenu", (e) => e.preventDefault());

    // Aim with the pointer: the angle points from the fighter to the pointer.
    const aimAt = (e) => {
      if (state.phase !== "aim") return;
      const r = canvas.getBoundingClientRect();
      const x = ((e.clientX - r.left) / r.width) * W;
      const y = ((e.clientY - r.top) / r.height) * H;
      const p = pivot(player);
      state.angle = (Math.atan2(p.y - y, x - p.x) * 180) / Math.PI;
      clampAngle();
      updateHud();
    };
    let dragging = false;
    canvas.addEventListener("pointerdown", (e) => {
      dragging = true;
      canvas.setPointerCapture(e.pointerId);
      aimAt(e);
    });
    canvas.addEventListener("pointermove", (e) => dragging && aimAt(e));
    canvas.addEventListener("pointerup", () => (dragging = false));
    canvas.tabIndex = 0;

    window.addEventListener("keydown", (e) => {
      if (state.phase === "idle" || state.phase === "won" || !inView()) return;
      if (e.target && /input|textarea|select/i.test(e.target.tagName)) return;
      if (e.code === "Space") {
        e.preventDefault();
        if (!e.repeat) startCharge();
      } else if (e.code === "ArrowUp" || e.code === "ArrowRight") {
        e.preventDefault();
        state.aimDir = 1;
      } else if (e.code === "ArrowDown" || e.code === "ArrowLeft") {
        e.preventDefault();
        state.aimDir = -1;
      } else if (["Digit1", "Digit2", "Digit3"].includes(e.code)) pickWeapon(Number(e.code.slice(-1)) - 1);
    });
    window.addEventListener("keyup", (e) => {
      if (e.code === "Space") releaseCharge();
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"].includes(e.code)) {
        state.aimDir = 0;
        updateHud();
      }
    });
  }

  function init() {
    renderWeapons();
    setupInput();
    const observer = new IntersectionObserver((entries) => {
      visible = entries[0].isIntersecting;
      wake();
    });
    observer.observe(canvas);
    // Draw the scene behind the start card as soon as the art is in.
    const preview = () => {
      buildTerrain();
      player.y = groundBelow(player.x, 0);
      const def = D.enemies.find((e) => e.id === FOES[0]);
      foe.def = def;
      foe.hp = foe.max = def.hp;
      foe.y = groundBelow(foe.x, 0);
      rollWind();
      updateHud();
      draw();
    };
    Promise.all(Object.values(images).map((img) => (img.complete ? Promise.resolve() : new Promise((ok) => { img.onload = img.onerror = ok; }))))
      .then(() => (document.fonts ? document.fonts.ready : null))
      .then(preview);
  }

  document.addEventListener("gf:lang", () => {
    renderWeapons();
    updateHud();
    if (state.phase === "won") win();
  });
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
