/* Landing page: the parts built from the game data (stats, arsenal, dungeons, gallery). */
(function () {
  "use strict";
  const GF = window.GF;
  const D = GF.data;
  const $ = (id) => document.getElementById(id);
  const esc = GF.esc;
  let selectedWeapon = 0;
  let weaponTimer = null;
  let userPicked = false;

  const byId = (list, id) => list.find((item) => item.id === id);

  function renderStats() {
    const box = $("stats");
    if (!box) return;
    const stats = [
      [D.weapons.length, "stat.weapons"],
      [D.instances.length, "stat.dungeons"],
      [D.enemies.filter((e) => e.rank !== "totem").length, "stat.monsters"],
      [D.map_items.max_level, "stat.maplevels"],
      ["+" + D.strengthen.max, "stat.forge"],
      ["4v4", "stat.online"],
    ];
    box.innerHTML = stats.map(([value, key]) => `<div class="stat"><b>${esc(value)}</b><span>${esc(GF.t(key))}</span></div>`).join("");
  }

  function renderCardIcons() {
    const sets = {
      currencies: D.currencies.slice(0, 4).map((c) => c.icon),
      stones: D.strengthen.stones.map((s) => s.icon).concat([byId(D.weapons, "quebra_tijolos").tiers[3]]),
      auction: [byId(D.currencies, "solar").icon, byId(D.currencies, "estrela").icon, D.icons.mail],
      looks: ["asas_fenix", "chapeu_kabuto", "oculos_coracao", "chapeu_coroa"].map((id) => byId(D.cosmetics, id).icon),
    };
    document.querySelectorAll("[data-icons]").forEach((box) => {
      const list = sets[box.dataset.icons] || [];
      box.innerHTML = list.filter(Boolean).map((src) => `<img src="${esc(GF.img(src))}" alt="" loading="lazy">`).join("");
    });
  }

  // ---------- arsenal ----------

  function instanceNames(ids) {
    return ids.map((id) => GF.L(byId(D.instances, id).name)).join(", ");
  }

  function renderArsenalGrid() {
    const grid = $("arsenal-grid");
    if (!grid) return;
    grid.innerHTML = D.weapons.map((w, i) => `
      <button class="slot" role="tab" type="button" data-index="${i}" aria-selected="${i === selectedWeapon}" style="--wc:#${esc(w.color)}" title="${esc(GF.L(w.name))}">
        <img src="${esc(GF.img(w.super ? w.tiers[3] : w.icon))}" alt="${esc(GF.L(w.name))}">
        ${w.super ? `<span class="tag">${esc(GF.t("arsenal.super"))}</span>` : ""}
      </button>`).join("");
    grid.querySelectorAll(".slot").forEach((slot) => slot.addEventListener("click", () => {
      userPicked = true;
      selectWeapon(Number(slot.dataset.index));
    }));
  }

  function selectWeapon(index) {
    selectedWeapon = index;
    document.querySelectorAll("#arsenal-grid .slot").forEach((slot, i) => slot.setAttribute("aria-selected", String(i === index)));
    renderWeapon();
  }

  function renderWeapon() {
    const box = $("weapon-show");
    if (!box) return;
    const w = D.weapons[selectedWeapon];
    const maxDamage = Math.max(...D.weapons.map((x) => x.damage));
    const maxRadius = Math.max(...D.weapons.map((x) => x.radius));
    const where = w.super
      ? GF.t("arsenal.bossonly", { list: instanceNames(w.drops) })
      : GF.t("arsenal.shop") + (w.drops.length ? " · " + GF.t("arsenal.drops", { list: instanceNames(w.drops) }) : "");
    const sub = GF.t(w.super ? "arsenal.subsuper" : "arsenal.sub", { a: w.angle[0], b: w.angle[1] });
    box.style.setProperty("--wc", "#" + w.color);
    box.innerHTML = `
      <div class="weapon-stage">
        <span class="aura"></span>
        <img class="big" src="${esc(GF.img(w.super ? w.tiers[3] : w.icon))}" alt="${esc(GF.L(w.name))}">
        ${w.pow.art ? `<img class="pow-art" src="${esc(GF.img(w.pow.art))}" alt="">` : ""}
      </div>
      <div class="weapon-info">
        <h3>${esc(GF.L(w.name))}</h3>
        <div class="sub">${esc(sub)}</div>
        <div class="pow-box"><b><small>${esc(GF.t("arsenal.pow"))}</small>${esc(GF.L(w.pow.name))}</b><p>${esc(GF.L(w.pow.desc))}</p></div>
        <div class="bars">
          ${bar(GF.t("arsenal.damage"), w.damage, maxDamage)}
          ${bar(GF.t("arsenal.radius"), w.radius, maxRadius)}
          ${bar(GF.t("arsenal.angle"), w.angle[1] - w.angle[0], 55, `${w.angle[0]}–${w.angle[1]}°`)}
        </div>
        <div class="foot">
          <span><b style="color:var(--ink)">${esc(GF.t("arsenal.where"))}:</b> ${esc(where)}</span>
          <a href="wiki/#/armas/${esc(w.id)}">${esc(GF.t("arsenal.wiki"))}</a>
        </div>
      </div>`;
  }

  function bar(label, value, max, text) {
    const pct = Math.max(6, Math.round((value / max) * 100));
    return `<div class="bar"><span>${esc(label)}</span><span class="track"><i style="width:${pct}%"></i></span><b>${esc(text || value)}</b></div>`;
  }

  function startWeaponCycle() {
    clearInterval(weaponTimer);
    weaponTimer = setInterval(() => {
      if (userPicked || document.hidden) return;
      const box = $("arsenal");
      const rect = box.getBoundingClientRect();
      if (rect.bottom < 0 || rect.top > innerHeight) return;
      selectWeapon((selectedWeapon + 1) % D.weapons.length);
    }, 4500);
  }

  // ---------- dungeons ----------

  function renderDungeons() {
    const box = $("dungeons");
    if (!box) return;
    box.innerHTML = D.instances.map((inst) => {
      const boss = byId(D.enemies, inst.boss);
      const arena = byId(D.arenas, inst.phases[inst.phases.length - 1].map);
      const sup = byId(D.weapons, inst.loot.super);
      const mechs = (boss.mechanics || []).map((m) => `<span class="mech">${esc(GF.t("mech." + m))}</span>`);
      inst.phases.forEach((phase) => {
        if (phase.objective) mechs.push(`<span class="mech">${esc(GF.t("mech." + phase.objective))}</span>`);
      });
      return `
        <a class="dungeon" href="wiki/#/instancias/${esc(inst.id)}" style="--ic:#${esc(inst.color)}">
          <div class="scene">
            <img src="${esc(GF.img(arena.bg))}" alt="" loading="lazy">
            <img class="boss" src="${esc(GF.img(boss.sprite))}" alt="${esc(GF.L(boss.name))}" loading="lazy">
          </div>
          <div class="body">
            <h3>${esc(GF.L(inst.name))}</h3>
            <span class="boss-name">${esc(GF.t("dungeon.boss", { name: GF.L(boss.name) }))}</span>
            <p>${esc(GF.L(inst.desc))}</p>
            <div class="phases">${inst.phases.map((p, i) => `<span>${i + 1}. ${esc(GF.L(p.name))}</span>`).join("")}</div>
            <div class="mechs">${mechs.join("")}</div>
            <div class="loot"><img src="${esc(GF.img(sup.tiers[3]))}" alt="">${esc(GF.t("dungeon.loot", { name: GF.L(sup.name) }))}</div>
          </div>
        </a>`;
    }).join("");
  }

  // ---------- gallery ----------

  let shots = [];
  let current = 0;

  function renderGallery() {
    const box = $("gallery");
    if (!box) return;
    const list = (D.extras.shots[GF.lang] || D.extras.shots.pt).slice();
    // The POW cut-in first: it is the most striking picture.
    const pow = list.findIndex((src) => src.includes("02_pow"));
    if (pow > 0) list.unshift(list.splice(pow, 1)[0]);
    shots = list.map((src) => ({ src, key: "shot." + src.split("/").pop().replace(".webp", "") }));
    box.innerHTML = shots.map((shot, i) => `
      <button type="button" data-i="${i}"><img src="${esc(GF.img(shot.src))}" alt="${esc(GF.t(shot.key))}" loading="lazy"><span>${esc(GF.t(shot.key))}</span></button>`).join("");
    box.querySelectorAll("button").forEach((button) => button.addEventListener("click", () => openShot(Number(button.dataset.i))));
  }

  function openShot(index) {
    current = (index + shots.length) % shots.length;
    const box = $("lightbox");
    $("lightbox-img").src = GF.img(shots[current].src);
    $("lightbox-img").alt = GF.t(shots[current].key);
    $("lightbox-cap").textContent = `${current + 1} / ${shots.length} · ${GF.t(shots[current].key)}`;
    if (box.hidden) {
      box.hidden = false;
      box.querySelector(".close").focus();
      document.body.style.overflow = "hidden";
    }
  }

  function closeShot() {
    $("lightbox").hidden = true;
    document.body.style.overflow = "";
  }

  function setupLightbox() {
    const box = $("lightbox");
    if (!box) return;
    box.addEventListener("click", (event) => {
      const action = event.target.closest("[data-lb]");
      if (action) {
        const what = action.dataset.lb;
        if (what === "close") closeShot();
        else openShot(current + (what === "next" ? 1 : -1));
      } else if (event.target === box) closeShot();
    });
    document.addEventListener("keydown", (event) => {
      if (box.hidden) return;
      if (event.key === "Escape") closeShot();
      if (event.key === "ArrowRight") openShot(current + 1);
      if (event.key === "ArrowLeft") openShot(current - 1);
    });
  }

  // ---------- language-dependent art ----------

  function swapArt() {
    const logo = $("hero-logo");
    if (logo) {
      logo.src = `img/brand/gustfire_logo_${GF.lang}@3x.png`;
      logo.alt = GF.lang === "pt" ? "Gustfire: Artilharia nos céus" : "Gustfire: Sky Artillery";
      const shine = logo.parentElement.querySelector(".shine");
      if (shine) shine.style.setProperty("--logo", `url('${logo.src}')`);
    }
    document.querySelectorAll("img[data-shot]").forEach((img) => {
      img.src = `img/shots/${GF.lang}/${img.dataset.shot}.webp`;
    });
    document.title = GF.lang === "pt" ? "Gustfire · Artilharia nos céus" : "Gustfire · Sky Artillery";
  }

  function render() {
    renderStats();
    renderCardIcons();
    renderArsenalGrid();
    renderWeapon();
    renderDungeons();
    renderGallery();
    swapArt();
  }

  function setupRail() {
    const rail = $("dungeons");
    const prev = $("rail-prev");
    const next = $("rail-next");
    if (!rail || !prev) return;
    const update = () => {
      prev.disabled = rail.scrollLeft < 8;
      next.disabled = rail.scrollLeft + rail.clientWidth > rail.scrollWidth - 8;
    };
    const step = (dir) => {
      const card = rail.querySelector(".dungeon");
      rail.scrollBy({ left: dir * (card ? card.offsetWidth + 26 : 400), behavior: "smooth" });
    };
    prev.addEventListener("click", () => step(-1));
    next.addEventListener("click", () => step(1));
    rail.addEventListener("scroll", update, { passive: true });
    window.addEventListener("resize", update);
    update();
  }

  document.addEventListener("gf:lang", render);
  document.addEventListener("DOMContentLoaded", () => {
    setupLightbox();
    setupRail();
    startWeaponCycle();
  });
})();
