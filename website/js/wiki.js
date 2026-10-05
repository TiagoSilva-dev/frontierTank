/* Gustfire wiki: every page is built from the game data (data/gamedata.js). */
(function () {
  "use strict";
  const GF = window.GF;
  const D = GF.data;
  const L = GF.L;
  const esc = GF.esc;
  const img = GF.img;
  const $ = (id) => document.getElementById(id);
  const T = (pt, en) => (GF.lang === "pt" ? pt : en);
  const n = (value, digits) => GF.num(value, digits);
  const pct = (value, digits) => GF.num(value * 100, digits == null ? 0 : digits) + "%";
  const mult = (value) => "×" + GF.num(value, 2);
  const byId = (list, id) => list.find((item) => item.id === id);
  const attrName = (key) => L(D.attr_names[key]) || key;
  const qual = (id) => byId(D.qualities, id);

  // ---------- entities (links, icons, tooltips) ----------

  const ENT = {
    weapon: { list: () => D.weapons, href: (e) => `#/armas/${e.id}`, icon: (e) => (e.super ? e.tiers[3] : e.icon), cls: (e) => (e.super ? "q-super" : "") },
    enemy: { list: () => D.enemies, href: (e) => `#/monstros/${e.id}`, icon: (e) => e.sprite, cls: (e) => (e.rank === "boss" ? "m-boss" : e.rank === "guardian" ? "m-guardian" : "") },
    instance: { list: () => D.instances, href: (e) => `#/instancias/${e.id}`, icon: (e) => e.map_icon, cls: () => "" },
    currency: { list: () => D.currencies, href: (e) => `#/moedas/${e.id}`, icon: (e) => e.icon, cls: () => "" },
    cosmetic: { list: () => D.cosmetics, href: (e) => `#/visual/${e.id}`, icon: (e) => e.icon, cls: () => "" },
    arena: { list: () => D.arenas, href: (e) => `#/arenas/${e.id}`, icon: (e) => e.thumb, cls: () => "" },
    skill: { list: () => D.skills, href: (e) => `#/habilidades/${e.id}`, icon: (e) => e.icon, cls: () => "" },
    tool: { list: () => D.tools, href: (e) => `#/ferramentas/${e.id}`, icon: (e) => e.icon, cls: () => "" },
    aux: { list: () => D.auxiliary, href: (e) => `#/auxiliares/${e.id}`, icon: (e) => e.icon, cls: () => "" },
    pet: { list: () => D.pets.species, href: (e) => `#/mascotes/${e.id}`, icon: (e) => e.art, cls: (e) => "pet-" + e.rarity },
    status: { list: () => D.statuses, href: (e) => `#/efeitos/${e.id}`, icon: (e) => e.icon, cls: () => "" },
  };

  function ref(kind, id, withIcon) {
    const def = ENT[kind];
    const entity = def && byId(def.list(), id);
    if (!entity) return esc(id);
    const icon = withIcon && def.icon(entity) ? `<img class="inline-ico" src="${esc(img(def.icon(entity)))}" alt="">` : "";
    return `<a class="ref ${def.cls(entity)}" href="${def.href(entity)}" data-tip="${kind}:${id}">${icon}${esc(L(entity.name))}</a>`;
  }
  const icon = (src, cls) => (src ? `<img class="${cls || "ico"}" src="${esc(img(src))}" alt="" loading="lazy">` : "");
  const table = (head, rows, opts) => {
    const sortable = opts && opts.sortable;
    const th = head.map((h) => {
      const [label, type] = Array.isArray(h) ? h : [h, null];
      const numeric = type === "num";
      return `<th${numeric ? ' class="num"' : ""}${sortable && type ? ` data-sort="${type}"` : ""}>${label}</th>`;
    }).join("");
    return `<div class="twrap"><table class="wt"${sortable ? " data-sortable" : ""}><thead><tr>${th}</tr></thead><tbody>${rows.join("")}</tbody></table></div>`;
  };
  const td = (html, value, cls) => `<td${cls ? ` class="${cls}"` : ""}${value != null ? ` data-v="${esc(value)}"` : ""}>${html}</td>`;
  const tdn = (value, text) => td(text != null ? text : n(value), value, "num");

  // ---------- item cards (also the hover tooltips) ----------

  function attrLines(attrs, scale) {
    return Object.keys(attrs || {}).map((key) => `<div class="mod">+${n(Math.round(attrs[key] * (scale || 1)))} ${esc(attrName(key))}</div>`).join("");
  }

  function weaponCard(w) {
    const q = qual(w.super ? "super" : "normal");
    return `<div class="icard" style="--qc:#${q.color}">
      <div class="ih"><b>${esc(L(w.name))}</b><small>${esc(w.super ? L(q.label) : T("Arma", "Weapon"))}</small></div>
      <div class="art"><img src="${esc(img(w.super ? w.tiers[3] : w.icon))}" alt=""></div>
      <div class="sec">
        <div class="row"><span>${T("Dano", "Damage")}:</span><b>${n(Math.round(w.damage * q.damage))}</b></div>
        <div class="row"><span>${T("Raio da explosão", "Blast radius")}:</span><b>${n(w.radius)}</b></div>
        <div class="row"><span>${T("Ângulo", "Angle")}:</span><b>${w.angle[0]}°–${w.angle[1]}°</b></div>
      </div>
      <div class="sec">${attrLines(w.attrs, q.attrs)}</div>
      <div class="sec pow"><b>POW · ${esc(L(w.pow.name))}</b><br>${esc(L(w.pow.desc))}</div>
      <div class="sec req">${w.super ? T("Só no baú do chefe", "Boss chest only") : w.premium ? T("Founder Pack · só aparência", "Founder Pack · cosmetic only") : T(`Loja: ${n(w.price)} moedas`, `Shop: ${n(w.price)} gold`)}</div>
    </div>`;
  }

  function enemyCard(e) {
    const rank = rankName(e.rank);
    return `<div class="icard" style="--qc:#${esc(e.color || "ffffff")}">
      <div class="ih"><b>${esc(L(e.name))}</b><small>${esc(rank)}</small></div>
      <div class="art"><img src="${esc(img(e.sprite))}" alt=""></div>
      <div class="sec">
        <div class="row"><span>${T("Vida", "HP")}:</span><b>${n(e.hp)}</b></div>
        ${e.damage ? `<div class="row"><span>${T("Dano", "Damage")}:</span><b>${n(e.damage)}${e.fury_damage ? ` / ${n(e.fury_damage)} ${T("em fúria", "in fury")}` : ""}</b></div>` : ""}
      </div>
      ${e.abilities.length ? `<div class="sec">${e.abilities.map((a) => `<div class="mod">${esc(L(a.name))}</div>`).join("")}</div>` : ""}
      ${(e.mechanics || []).length ? `<div class="sec pow">${e.mechanics.map(mechName).join(" · ")}</div>` : ""}
    </div>`;
  }

  function simpleCard(title, sub, art, lines, color) {
    return `<div class="icard" style="--qc:#${color || "f4ead6"}">
      <div class="ih"><b>${esc(title)}</b><small>${esc(sub)}</small></div>
      ${art ? `<div class="art"><img src="${esc(img(art))}" alt="" style="width:96px;height:96px"></div>` : ""}
      <div class="sec">${lines}</div>
    </div>`;
  }

  const RARITY = { common: ["f4ead6", "Comum", "Common"], rare: ["7ad8ff", "Rara", "Rare"], epic: ["c99bff", "Épica", "Epic"], legendary: ["ffb347", "Lendária", "Legendary"] };
  const rarityName = (r) => T(RARITY[r][1], RARITY[r][2]);

  function tipFor(kind, id) {
    const def = ENT[kind];
    const e = def && byId(def.list(), id);
    if (!e) return "";
    switch (kind) {
      case "weapon": return weaponCard(e);
      case "enemy": return enemyCard(e);
      case "currency": return simpleCard(L(e.name), T("Moeda de criação", "Crafting currency") + " · " + rarityName(e.rarity), e.icon, `<div>${esc(L(e.desc))}</div>`, RARITY[e.rarity][0]);
      case "cosmetic": return simpleCard(L(e.name), L(e.slot_name), e.icon, attrLines(e.attrs) + (e.hp ? `<div class="mod">+${n(e.hp)} ${T("vida", "life")}</div>` : "") + `<div class="req">${e.premium ? T("Loja premium · só aparência", "Premium shop · cosmetic only") : T(`${n(e.price)} moedas`, `${n(e.price)} gold`)}</div>`, e.premium ? "ffb347" : null);
      case "instance": return simpleCard(L(e.name), T("Instância", "Dungeon"), e.map_icon, `<div>${esc(L(e.desc))}</div>`, e.color);
      case "arena": return simpleCard(L(e.name), e.pve_only ? T("Só na Instância", "Dungeon only") : T("Arena", "Arena"), null, `<img src="${esc(img(e.thumb))}" alt="" style="width:100%;image-rendering:pixelated">`);
      case "skill": return simpleCard(L(e.name), T("Habilidade · tecla ", "Skill · key ") + e.key, e.icon, `<div>${esc(L(e.desc))}</div><div class="req">${T("Energia", "Energy")} ${e.energy} · Delay +${e.delay}</div>`);
      case "tool": return simpleCard(L(e.name), T("Ferramenta (Z X C)", "Tool (Z X C)"), e.icon, `<div>${esc(L(e.desc))}</div><div class="req">${n(e.price)} ${T("moedas", "gold")}</div>`);
      case "aux": return simpleCard(L(e.name), T("Item auxiliar (V)", "Support item (V)"), e.icon, `<div>${esc(L(e.desc))}</div>`);
      case "pet": return petCard(e);
      case "status": return simpleCard(L(e.name), T("Efeito de estado", "Status effect"), e.icon, `<div>${esc(L(e.desc))}</div><div class="req">${e.turns === 1 ? T("1 turno", "1 turn") : T(`${e.turns} turnos`, `${e.turns} turns`)}</div>`, e.color);
      default: return "";
    }
  }

  // ---------- vocabulary ----------

  function rankName(rank) {
    return { minion: T("Lacaio", "Minion"), guardian: T("Guardião", "Guardian"), boss: T("Chefe", "Boss"), totem: T("Totem", "Totem") }[rank] || rank;
  }
  function mechName(m) {
    return { fury: T("Fúria", "Fury"), summon: T("Invocação", "Summon"), freeze: T("Congelamento", "Freeze"), teleport: T("Teletransporte", "Teleport") }[m] || m;
  }
  function slotName(slot) {
    return { skin: T("Skins", "Skins"), camisa: T("Camisas", "Shirts"), calca: T("Calças", "Trousers"), chapeu: T("Chapéus", "Hats"), oculos: T("Óculos", "Glasses"), asas: T("Asas", "Wings"), anel: T("Anéis", "Rings"), amuleto: T("Amuletos", "Amulets"), cabelo: T("Cabelos", "Hair") }[slot] || slot;
  }

  function powDetails(p) {
    const list = [`${T("Dano do POW", "POW damage")}: ${mult(p.damage_scale || 1)}`];
    switch (p.kind) {
      case "split": list.push(T(`Solta ${p.fragments} fragmentos com ${pct(p.fragment_scale)} do dano`, `Releases ${p.fragments} fragments with ${pct(p.fragment_scale)} of the damage`)); break;
      case "triple": list.push(T(`${p.balls} projéteis abertos em ${p.spread}°`, `${p.balls} projectiles spread by ${p.spread}°`)); break;
      case "beam": list.push(T(`Raio da explosão ${mult(p.radius_scale)}`, `Blast radius ${mult(p.radius_scale)}`)); break;
      case "giant": list.push(T(`Projétil ${mult(p.size_scale)} maior, explosão ${mult(p.radius_scale)}`, `Projectile ${mult(p.size_scale)} bigger, blast ${mult(p.radius_scale)}`), T("Ignora o vento", "Ignores the wind")); break;
      case "rain": list.push(T(`${p.drops} projéteis caem do céu, ${pct(p.drop_scale)} do dano cada, a ${p.spacing} px um do outro`, `${p.drops} projectiles fall from the sky, ${pct(p.drop_scale)} of the damage each, ${p.spacing} px apart`)); break;
      case "heal": list.push(T(`Cura +${p.heal} nos aliados a até ${p.heal_radius} px e +${p.self_heal} no atirador`, `Heals allies within ${p.heal_radius} px for +${p.heal} and the shooter for +${p.self_heal}`)); break;
      case "drop": list.push(T(`Um segundo impacto cai do céu: dano ${mult(p.drop_damage)}, raio ${mult(p.drop_radius)}`, `A second impact falls from the sky: damage ${mult(p.drop_damage)}, radius ${mult(p.drop_radius)}`)); break;
      case "strike": list.push(T(`${p.bolts} raios com ${pct(p.bolt_scale)} do dano, a ${p.spacing} px um do outro`, `${p.bolts} bolts with ${pct(p.bolt_scale)} of the damage, ${p.spacing} px apart`)); break;
      case "pull": list.push(T(`${p.balls} projéteis que puxam os inimigos até ${p.pull} px para o centro`, `${p.balls} projectiles that pull enemies up to ${p.pull} px toward the centre`)); break;
      case "bull": list.push(T(`Empurra os inimigos ${p.knockback} px; raio ${mult(p.radius_scale)}`, `Knocks enemies back ${p.knockback} px; radius ${mult(p.radius_scale)}`)); break;
      case "boomerang": list.push(T(`Volta acertando de novo com ${pct(p.return_scale)} do dano e cura ${pct(p.lifesteal)} do dano causado`, `Comes back hitting again for ${pct(p.return_scale)} of the damage and heals ${pct(p.lifesteal)} of the damage dealt`)); break;
      default: break;
    }
    return list;
  }

  function abilityText(a, e) {
    const base = e.damage || 0;
    const dmg = a.damage ? ` ${T("Dano", "Damage")}: ${mult(a.damage)} (≈${n(Math.round(base * a.damage * D.pve.ability_damage))}).` : "";
    const parts = {
      leap: T(`Salta até o alvo e golpeia de perto (alcance ${a.reach} px).`, `Leaps onto the target and strikes (reach ${a.reach} px).`),
      dive: T(`Mergulha no alvo e volta à posição (alcance ${a.reach} px).`, `Dives onto the target and flies back (reach ${a.reach} px).`),
      sky: a.count ? T(`${a.count} projéteis caem do céu sobre o alvo.`, `${a.count} projectiles fall from the sky on the target.`) : T("Um projétil cai do céu sobre o alvo.", "A projectile falls from the sky on the target."),
      slam: T(`Onda ao redor do monstro, raio ${a.radius} px.`, `A wave around the monster, ${a.radius} px radius.`),
      breath: T(`Sopro em linha reta: alcance ${a.range} px, largura ${a.width} px.`, `A straight breath: ${a.range} px range, ${a.width} px wide.`),
      guard: T(`Protege os aliados a até ${a.radius} px: o próximo dano que eles recebem cai para ${pct(a.shield)}.`, `Shields allies within ${a.radius} px: the next hit they take drops to ${pct(a.shield)}.`),
      roar: T(`Fortalece os aliados a até ${a.radius} px: +${pct(a.empower - 1)} de dano no próximo ataque.`, `Empowers allies within ${a.radius} px: +${pct(a.empower - 1)} damage on their next attack.`),
      heal: T(`Cura ${pct(a.heal)} da vida dos aliados a até ${a.radius} px.`, `Heals allies within ${a.radius} px for ${pct(a.heal)} of their HP.`),
      hex: T("Maldição: um círculo de runas se fecha no alvo e aplica os efeitos, sem dano.", "Curse: a rune circle closes on the target and applies its effects, without damage."),
    };
    let text = (parts[a.kind] || "") + dmg;
    if (a.knockback) text += T(` Empurra ${a.knockback} px.`, ` Knocks back ${a.knockback} px.`);
    if (a.status && a.status.length) text += " " + T("Efeitos", "Effects") + ": " + a.status.map(statusText).join(", ") + ".";
    if (a.cooldown) text += T(` Recarga: ${a.cooldown} turnos.`, ` Cooldown: ${a.cooldown} turns.`);
    if (a.targets === "all") text += T(" Atinge todos os jogadores.", " Hits every player.");
    if (a.fury) text += T(" Só em fúria.", " Fury only.");
    return text;
  }

  // A status an ability (or an elite) applies: its link, the chance and the turns when they differ.
  function statusText(s) {
    const def = byId(D.statuses, s.id);
    const turns = s.turns || (def && def.turns) || 1;
    const extra = [];
    if (s.chance != null && s.chance < 1) extra.push(pct(s.chance));
    if (s.power) extra.push(T(`${pct(s.power)} do golpe por turno`, `${pct(s.power)} of the hit per turn`));
    extra.push(turns === 1 ? T("1 turno", "1 turn") : T(`${turns} turnos`, `${turns} turns`));
    return `${ref("status", s.id, true)} (${extra.join(", ")})`;
  }

  const KIND_NAMES = { leap: ["Salto", "Leap"], dive: ["Mergulho", "Dive"], sky: ["Do céu", "Skyfall"], slam: ["Onda", "Slam"], breath: ["Sopro", "Breath"], guard: ["Proteção", "Guard"], roar: ["Grito", "Roar"], heal: ["Cura", "Heal"], hex: ["Maldição", "Curse"] };

  // ---------- navigation ----------

  function nav() {
    const w0 = D.weapons[0];
    const icons = D.icons;
    return [
      { title: T("Começando", "Getting started"), items: [
        ["", T("Início da wiki", "Wiki home"), icons.help],
        ["guia/primeiros-passos", T("Primeiros passos", "First steps"), icons.play],
        ["guia/controles", T("Controles", "Controls"), icons.power],
        ["guia/progresso", T("Níveis e patentes", "Levels and ranks"), icons.star],
      ] },
      { title: T("Combate", "Combat"), items: [
        ["guia/combate", T("Turnos, Delay e energia", "Turns, Delay and energy"), icons.team],
        ["guia/mira", T("Mira, força e vento", "Aim, power and wind"), icons.plane],
        ["guia/dano", T("Dano e atributos", "Damage and attributes"), icons.shield],
        ["guia/pow", T("POW", "POW"), icons.pow],
        ["habilidades", T("Habilidades 1–9", "Skills 1–9"), D.skills[0].icon],
        ["ferramentas", T("Ferramentas Z X C", "Tools Z X C"), D.tools[0].icon],
        ["auxiliares", T("Itens auxiliares (V)", "Support items (V)"), D.auxiliary[0].icon],
      ] },
      { title: T("Equipamento", "Gear"), items: [
        ["armas", T("Armas", "Weapons"), w0.icon],
        ["qualidades", T("Qualidades", "Qualities"), byId(D.weapons, "lanca_antiga").tiers[3]],
        ["fortalecimento", T("Fortalecimento", "Strengthening"), D.strengthen.stones[3].icon],
        ["bonus", T("Bônus aleatórios", "Random bonuses"), byId(D.currencies, "estrela").icon],
        ["visual", T("Visual", "Cosmetics"), byId(D.cosmetics, "asas_fenix").icon],
      ] },
      { title: T("Instâncias", "Dungeons"), items: [
        ["instancias", T("Instâncias", "Dungeons"), D.instances[0].map_icon],
        ["monstros", T("Monstros", "Monsters"), byId(D.enemies, "grifo_tempestade").sprite],
        ["efeitos", T("Efeitos e elites", "Effects and elites"), D.statuses[0].icon],
        ["mapas", T("Mapas (itens)", "Maps (items)"), D.instances[2].map_icon],
        ["arenas", T("Arenas", "Arenas"), icons.crown],
      ] },
      { title: T("Mascotes", "Pets"), items: [
        ["mascotes", T("Casa dos Mascotes", "Pet House"), D.pets.species.find((x) => x.rarity === "lendario").art],
        ["cacada", T("Caçada dos Mascotes", "Pet Hunt"), D.pets.species.find((x) => x.rarity === "raro").art],
      ] },
      { title: T("Economia", "Economy"), items: [
        ["moedas", T("Moedas de criação", "Crafting currencies"), byId(D.currencies, "solar").icon],
        ["leilao", T("Leilão e Correio", "Auction and Mail"), icons.mail],
        ["recompensas", T("Recompensas", "Rewards"), icons.coin],
        ["loja", T("Loja", "Shop"), icons.shop],
        ["conquistas", T("Conquistas", "Achievements"), icons.trophy],
      ] },
    ];
  }

  function renderNav(path) {
    const top = path.split("/").slice(0, path.startsWith("guia/") ? 2 : 1).join("/");
    $("side").innerHTML = nav().map((group) => `<h6>${esc(group.title)}</h6>` + group.items.map(([route, label, ico]) =>
      `<a href="#/${route}" class="${route === top ? "on" : ""}">${ico ? `<img src="${esc(img(ico))}" alt="">` : ""}${esc(label)}</a>`).join("")).join("");
  }

  // ---------- pages ----------

  const HOME = { label: () => T("Wiki", "Wiki"), href: "#/" };

  function page(title, crumbs, body, opts) {
    return { title, crumbs: [HOME].concat(crumbs || []), body, ...(opts || {}) };
  }

  function home() {
    const tiles = nav().flatMap((g) => g.items).filter(([route]) => route);
    const counts = {
      armas: D.weapons.length, instancias: D.instances.length, monstros: D.enemies.length, moedas: D.currencies.length,
      visual: D.cosmetics.length, arenas: D.arenas.length, conquistas: D.achievements.length, mascotes: D.pets.species.length, habilidades: D.skills.length, ferramentas: D.tools.length,
    };
    const body = `
      <div class="hero-wiki" style="--hero:url('${esc(img(D.extras.hero.title_bg))}')">
        <h1>${T("Wiki do Gustfire", "Gustfire Wiki")}</h1>
        <p>${T("Como o jogo funciona, com os números de verdade: tudo aqui sai dos mesmos arquivos de balanceamento que o jogo usa. Quando um número muda no jogo, muda aqui também.",
          "How the game works, with the real numbers: everything here comes from the same balance files the game uses. When a number changes in the game, it changes here too.")}</p>
        <a class="btn btn-fire" href="#/guia/primeiros-passos">${T("Comece por aqui", "Start here")}</a>
      </div>
      <div class="tiles">${tiles.map(([route, label, ico]) => `<a class="tile" href="#/${route}"><img src="${esc(img(ico))}" alt=""><div><b>${esc(label)}</b>${counts[route] ? `<span>${counts[route]} ${T("entradas", "entries")}</span>` : ""}</div></a>`).join("")}</div>
      <h2>${T("Em números", "By the numbers")}</h2>
      <div class="kv">
        <div><span>${T("Vida inicial", "Starting HP")}</span><b>${n(D.combat.base_hp)}</b></div>
        <div><span>${T("Energia por turno", "Energy per turn")}</span><b>${n(D.combat.energy)}</b></div>
        <div><span>${T("Turno (PvP)", "Turn (PvP)")}</span><b>${D.combat.turn_seconds} s</b></div>
        <div><span>${T("Vento máximo", "Max wind")}</span><b>±${n(D.combat.wind_max)}</b></div>
        <div><span>${T("Nível máximo", "Max level")}</span><b>${D.max_level}</b></div>
        <div><span>${T("Fortalecimento", "Strengthening")}</span><b>+${D.strengthen.max}</b></div>
        <div><span>${T("Níveis de mapa", "Map levels")}</span><b>1–${D.map_items.max_level}</b></div>
        <div><span>${T("Jogadores por instância", "Players per dungeon")}</span><b>1–4</b></div>
      </div>`;
    return page(T("Wiki", "Wiki"), [], body, { bare: true });
  }

  function guide(slug) {
    const g = GF.GUIDES && GF.GUIDES[slug];
    if (!g) return notFound();
    const body = g.body(D, helpers)[GF.lang] || g.body(D, helpers).pt;
    return page(L(g.title), [{ label: () => T("Guias", "Guides"), href: "#/guia/primeiros-passos" }], `<p class="intro">${L(g.intro)}</p>${body}`, { icon: g.icon && g.icon(D) });
  }

  // --- weapons ---

  function weaponsList(filter) {
    const tabs = [["all", T("Todas", "All")], ["shop", T("Da loja", "Shop")], ["super", T("Super Verdadeiras", "Super True")]];
    const list = D.weapons.filter((w) => filter === "super" ? w.super : filter === "shop" ? !w.super && !w.premium : true);
    const rows = list.map((w) => `<tr id="row-${w.id}">
      ${td(`<span class="name">${icon(w.super ? w.tiers[3] : w.icon)}${ref("weapon", w.id)}</span>`, L(w.name))}
      ${tdn(w.damage)}${tdn(w.radius)}
      ${td(`${w.angle[0]}°–${w.angle[1]}°`, w.angle[0], "num")}
      ${td(`<b>${esc(L(w.pow.name))}</b><br><span class="muted">${esc(L(w.pow.desc))}</span>`, L(w.pow.name))}
      ${td(Object.entries(w.attrs).map(([k, v]) => `${esc(attrName(k).slice(0, 3))} ${v}`).join(" · "), null)}
      ${td(w.super ? `<span class="muted">${T("baú do chefe", "boss chest")}</span>` : w.premium ? `<span class="pill gold">Founder</span>` : n(w.price), w.super || w.premium ? 1e9 : w.price, "num")}
    </tr>`);
    const body = `
      <p class="intro">${T("Cada arma tem ângulo, dano, raio de explosão, atributos e um especial POW próprios. As da loja vêm em Normal e Excelente; a Verdadeira cai nas instâncias e as três Super Verdadeiras só no baú dos chefes.",
        "Each weapon has its own angle, damage, blast radius, attributes and POW special. Shop weapons come in Normal and Excellent; True ones drop in dungeons and the three Super True weapons only in boss chests.")}</p>
      <div class="tabs" data-filter>${tabs.map(([id, label]) => `<button type="button" data-f="${id}" aria-pressed="${(filter || "all") === id}">${esc(label)}</button>`).join("")}</div>
      ${table([[T("Arma", "Weapon"), "text"], [T("Dano", "Damage"), "num"], [T("Raio", "Radius"), "num"], [T("Ângulo", "Angle"), "num"], ["POW", "text"], T("Atributos", "Attributes"), [T("Preço", "Price"), "num"]], rows, { sortable: true })}
      <p class="note">${T(`Os números são da qualidade Normal no +0. Qualidade e fortalecimento multiplicam o dano: veja <a href="#/qualidades">Qualidades</a> e <a href="#/fortalecimento">Fortalecimento</a>.`,
        `Numbers are for Normal quality at +0. Quality and strengthening multiply the damage: see <a href="#/qualidades">Qualities</a> and <a href="#/fortalecimento">Strengthening</a>.`)}</p>`;
    return page(T("Armas", "Weapons"), [], body, {
      icon: D.weapons[0].icon,
      after: () => document.querySelectorAll("[data-filter] button").forEach((b) => b.addEventListener("click", () => render(`armas`, b.dataset.f))),
    });
  }

  function weaponPage(id) {
    const w = byId(D.weapons, id);
    if (!w) return notFound();
    const qs = D.qualities.filter((q) => (w.super ? q.id === "super" : q.id !== "super"));
    const levels = Array.from({ length: D.strengthen.max + 1 }, (_, i) => i);
    const dmgRows = levels.map((lv) => `<tr>${td(`<b>+${lv}</b>`, lv)}${qs.map((q) => tdn(Math.round(w.damage * q.damage * (1 + D.strengthen.damage_bonus[lv])))).join("")}
      ${td(qs.map((q) => Object.entries(w.attrs).map(([k, v]) => Math.round(v * q.attrs * (1 + D.strengthen.attr_per_level * lv))).join("/")).join(" · "), null, "muted")}</tr>`);
    const tierLabels = ["+0–8", "+9", "+10–11", "+12"];
    const drops = w.drops.map((iid) => ref("instance", iid, true)).join(", ");
    // The shop sells Normal and Excellent only; True weapons drop in dungeons.
    const shop = qs.filter((q) => q.id === "normal" || q.id === "excelente").map((q) => `${esc(L(q.label))}: <b>${n(w.price * q.price)}</b>`).join(" · ");
    const body = `
      <div class="entity">
        <div>${weaponCard(w)}</div>
        <div>
          <p class="intro" style="margin-top:0">${esc(L(w.pow.desc))}</p>
          <h2 style="margin-top:0">${T("Especial POW", "POW special")}: ${esc(L(w.pow.name))}</h2>
          <div style="display:flex;gap:20px;align-items:center;flex-wrap:wrap">
            ${w.pow.art ? `<img src="${esc(img(w.pow.art))}" alt="" style="width:128px;height:128px;image-rendering:pixelated">` : ""}
            <ul>${powDetails(w.pow).map((x) => `<li>${esc(x)}</li>`).join("")}</ul>
          </div>
          <h2>${T("Onde conseguir", "Where to get it")}</h2>
          <ul>
            ${w.super ? `<li>${T("Só no baú do chefe destas instâncias", "Only in the boss chest of these dungeons")}: ${drops}. ${T(`Chance de ${pct(D.map_items.loot.super_chance)} + ${pct(D.map_items.loot.super_per_level)} por nível do mapa. Sem garantia: cada chefe é um novo sorteio.`, `${pct(D.map_items.loot.super_chance)} + ${pct(D.map_items.loot.super_per_level)} per map level. No guarantee: every boss is a fresh roll.`)} <a href="#/instancias">${T("Mais sobre o baú", "More about the chest")}</a></li>`
              : `<li>${T("Centro Comercial", "Shopping Center")} (${shop} ${T("moedas", "gold")})</li><li>${T("Verdadeira: baú do chefe de", "True: boss chest of")} ${drops || "—"}</li>`}
          </ul>
          <h2>${T("Evolução da arte", "Art by level")}</h2>
          <div class="pills" style="gap:16px">${w.tiers.map((t, i) => t ? `<span style="text-align:center"><img src="${esc(img(t))}" alt="" style="width:96px;height:96px;image-rendering:pixelated;display:block">${tierLabels[i]}</span>` : "").join("")}</div>
          <h2>${T("Projétil", "Projectile")}</h2>
          <p>${w.projectile.img ? `<img src="${esc(img(w.projectile.img))}" alt="" style="height:40px;image-rendering:pixelated;vertical-align:middle;margin-right:10px">` : ""}
            ${w.projectile.wind_scale < 1 ? T(`Sente só ${pct(w.projectile.wind_scale)} do vento.`, `Only feels ${pct(w.projectile.wind_scale)} of the wind.`) : T("Sente o vento por inteiro.", "Feels the full wind.")}</p>
        </div>
      </div>
      <h2>${T("Dano por qualidade e fortalecimento", "Damage by quality and strengthening")}</h2>
      ${table([T("Nível", "Level")].concat(qs.map((q) => `<span style="color:#${q.color}">${esc(L(q.label))}</span>`)).concat([T("Atributos (" + Object.keys(w.attrs).map((k) => attrName(k).slice(0, 3)).join("/") + ")", "Attributes (" + Object.keys(w.attrs).map((k) => attrName(k).slice(0, 3)).join("/") + ")")]), dmgRows)}
      <h2>${T("Bônus aleatórios possíveis", "Possible random bonuses")}</h2>
      <p>${T(`Excelente: ${D.affixes.counts.excelente.join("–")} bônus · Verdadeira: ${D.affixes.counts.verdadeira.join("–")} · Super: ${D.affixes.counts.super[0]}.`, `Excellent: ${D.affixes.counts.excelente.join("–")} bonuses · True: ${D.affixes.counts.verdadeira.join("–")} · Super: ${D.affixes.counts.super[0]}.`)} ${D.affixes.weapon.map((a) => `<span class="pill">${esc(L(a.text).replace(/%d%%|%d/g, "#").replace("##", "#%"))}</span>`).join(" ")} <a href="#/bonus">${T("Tabela completa", "Full table")}</a></p>`;
    return page(L(w.name), [{ label: () => T("Armas", "Weapons"), href: "#/armas" }], body, { icon: w.super ? w.tiers[3] : w.icon });
  }

  // --- qualities / strengthening / affixes ---

  function qualities() {
    const how = {
      normal: T("Loja, drops comuns", "Shop, common drops"),
      excelente: T("Loja, drops, Brasa (Normal → Excelente)", "Shop, drops, Ember (Normal → Excellent)"),
      verdadeira: T("Baú dos chefes, Coroa (Excelente → Verdadeira)", "Boss chests, Crown (Excellent → True)"),
      super: T("Só no baú dos chefes (três armas)", "Boss chests only (three weapons)"),
    };
    const rows = D.qualities.map((q) => `<tr>
      ${td(`<b style="color:#${q.color}">${esc(L(q.label))}</b>`, null)}
      ${tdn(q.damage, mult(q.damage))}${tdn(q.attrs, mult(q.attrs))}${td(q.price ? mult(q.price) : "—", q.price, "num")}
      ${td((D.affixes.counts[q.id] || [0, 0]).join("–"), null, "num")}${td(esc(how[q.id]), null)}</tr>`);
    const body = `
      <p class="intro">${T("A qualidade multiplica o dano e os atributos das armas e define quantos bônus aleatórios o item pode ter. No jogo ela aparece como um brilho atrás do item, na cor da qualidade.",
        "Quality multiplies a weapon's damage and attributes and sets how many random bonuses an item can have. In game it shows as a glow behind the item, in the quality's colour.")}</p>
      ${table([T("Qualidade", "Quality"), [T("Dano", "Damage"), "num"], [T("Atributos", "Attributes"), "num"], [T("Preço na loja", "Shop price"), "num"], [T("Bônus", "Bonuses"), "num"], T("Como conseguir", "How to get it")], rows)}
      <p class="note">${T("Camisas, calças, chapéus e óculos também têm qualidade (mudada pela Brasa e pela Coroa), mas nelas a qualidade só define o número de bônus: só as armas multiplicam dano e atributos.",
        "Shirts, trousers, hats and glasses have a quality too (changed with Embers and Crowns), but for them it only sets the number of bonuses: only weapons multiply damage and attributes.")}</p>`;
    return page(T("Qualidades", "Qualities"), [], body, { icon: byId(D.weapons, "lanca_antiga").tiers[3] });
  }

  function strengthen() {
    const S = D.strengthen;
    const aura = (lv) => D.auras.find((a) => lv >= a.from && lv <= a.to);
    const rows = Array.from({ length: S.max }, (_, i) => {
      const lv = i + 1;
      const a = aura(lv);
      return `<tr>${td(`<b>+${lv}</b>`, lv)}${tdn(S.success_chance[i], pct(S.success_chance[i]))}${tdn(S.coins[i])}${tdn(S.damage_bonus[lv], "+" + pct(S.damage_bonus[lv]))}
        ${tdn(S.attr_per_level * lv, "+" + pct(S.attr_per_level * lv))}${tdn(S.defense_per_level * lv, "+" + n(S.defense_per_level * lv))}${tdn(S.hp_per_level * lv, "+" + n(S.hp_per_level * lv))}
        ${td(a ? `<span style="color:#${a.color}">■</span> ${esc(L(a.name))}` : "—", null)}</tr>`;
    });
    const stones = S.stones.map((s) => `<tr>${td(`<span class="name">${icon(s.icon, "ico sm")}${esc(L(s.name))}</span>`, null)}${tdn(s.level)}${tdn(s.min_instance_level)}</tr>`);
    const total = S.max;
    const coins = S.coins.reduce((a, b) => a + b, 0);
    const body = `
      <p class="intro">${T(`No Ferreiro, armas, camisas, calças e chapéus sobem até +${S.max}. Cada tentativa usa <b>uma pedra do nível desejado</b> e moedas. Pode falhar: a pedra e as moedas são consumidas, mas o nível do item é preservado.`,
        `At the Blacksmith, weapons, shirts, trousers and hats go up to +${S.max}. Each attempt uses <b>one stone of the target level</b> and gold. Attempts can fail: the stone and gold are consumed, but the item keeps its level.`)}</p>
      ${table([[T("Nível", "Level"), "num"], [T("Chance de sucesso", "Success chance"), "num"], [T("Moedas", "Gold"), "num"], [T("Dano da arma", "Weapon damage"), "num"], [T("Atributos do item", "Item attributes"), "num"], [T("Defesa (roupa/chapéu)", "Defence (outfit/hat)"), "num"], [T("Vida (roupa/chapéu)", "HP (outfit/hat)"), "num"], T("Aura", "Aura")], rows)}
      <p>${T(`Sem falhas: uma pedra de cada nível e <b>${n(coins)}</b> moedas do +0 ao +${S.max}.`, `With no failures: one stone of each level and <b>${n(coins)}</b> gold from +0 to +${S.max}.`)}</p>
      <h2>${T("Pedras de Fortalecimento", "Strengthening Stones")}</h2>
      ${table([T("Pedra", "Stone"), [T("Nível", "Level"), "num"], [T("Nível mínimo do mapa", "Minimum map level"), "num"]], stones)}
      <p>${T("Pedras caem dos monstros das instâncias. Mapas mais difíceis liberam pedras mais raras. Há drops exclusivos do golpe final e drops que cada participante recebe. Chefes garantem uma pedra para cada integrante.", "Stones drop from instance monsters. Harder maps unlock rarer stones. Last-hit loot belongs to the killer; party loot gives every participant a copy. Bosses guarantee a stone for each member.")}</p>
      <h2>${T("Auras", "Auras")}</h2>
      <p>${T("A arma fortalecida ganha uma aura atrás do personagem (fora da batalha: na sala, no salão e na Mochila).", "A strengthened weapon gets an aura behind your character (outside battles: in the room, the hall and the Bag).")}</p>
      <div class="pills">${D.auras.map((a) => `<span class="pill" style="color:#${a.color}">■ ${esc(L(a.name))} · +${a.from}${a.to > a.from ? "–" + a.to : ""}</span>`).join("")}</div>
      <h2>${T("Transferência", "Transfer")}</h2>
      <p>${T(`Troca o nível de fortalecimento entre dois itens do mesmo tipo por ${n(S.transfer_coins)} moedas. Útil para passar o +12 para uma arma melhor.`, `Swaps the strengthening level of two items of the same type for ${n(S.transfer_coins)} gold. Handy to move a +12 onto a better weapon.`)}</p>`;
    return page(T("Fortalecimento", "Strengthening"), [], body, { icon: S.stones[3].icon });
  }

  function affixes() {
    const A = D.affixes;
    const tierHead = A.tiers.map((t) => [`${t.name} <span class="muted">(${T("nível", "level")} ${t.ilvl}+)</span>`, null]);
    const rows = (list) => list.map((a) => `<tr>${td(`<b>${esc(L(a.text).replace(/%d%%/g, "#%").replace(/%d/g, "#"))}</b>`, null)}${a.values.map((v) => td(`${v[0]}–${v[1]}`, v[0], "num")).join("")}</tr>`);
    const body = `
      <p class="intro">${T("Armas, camisas, calças, chapéus e óculos podem ter bônus aleatórios. Cada bônus tem faixas de F1 (a melhor) a F5, e o nível do item (o nível do mapa onde ele caiu) decide quais faixas podem aparecer.",
        "Weapons, shirts, trousers, hats and glasses can roll random bonuses. Each bonus has tiers from F1 (best) to F5, and the item level (the level of the map it dropped on) decides which tiers can appear.")}</p>
      <div class="kv">${Object.entries(A.counts).map(([q, c]) => `<div><span style="color:#${qual(q).color}">${esc(L(qual(q).label))}</span><b>${c[0] === c[1] ? c[0] : c.join("–")} ${T("bônus", "bonuses")}</b></div>`).join("")}</div>
      <h2>${T("Faixas", "Tiers")}</h2>
      ${table([T("Faixa", "Tier"), [T("Nível mínimo do item", "Minimum item level"), "num"], [T("Peso", "Weight"), "num"]], A.tiers.map((t) => `<tr>${td(`<b>${t.name}</b>`)}${tdn(t.ilvl)}${tdn(t.weight)}</tr>`))}
      <p>${T("O peso é a chance relativa de cada faixa entre as liberadas: F5 é a mais comum.", "The weight is each tier's relative chance among the unlocked ones: F5 is the most common.")}</p>
      <h2>${T("Bônus de arma", "Weapon bonuses")}</h2>
      ${table([T("Bônus", "Bonus")].concat(tierHead), rows(A.weapon))}
      <h2>${T("Bônus de camisa, calça, chapéu e óculos", "Shirt, trousers, hat and glasses bonuses")}</h2>
      ${table([T("Bônus", "Bonus")].concat(tierHead), rows(A.armor))}
      <p class="note">${T(`Limites somados: redução de vento até ${A.limits.vento}% e chance de não gastar a habilidade até ${A.limits.poupar}%. Fortalecer multiplica só os atributos base do item: os bônus aleatórios não mudam. Nenhum bônus muda o raio da explosão ou o hitbox.`,
        `Summed caps: wind reduction up to ${A.limits.vento}% and free-skill chance up to ${A.limits.poupar}%. Strengthening only scales the item's base attributes: random bonuses stay the same. No bonus changes the blast radius or the hitbox.`)}</p>
      <p>${T("Para mudar os bônus, use as", "To change bonuses, use the")} <a href="#/moedas">${T("moedas de criação", "crafting currencies")}</a>.</p>`;
    return page(T("Bônus aleatórios", "Random bonuses"), [], body, { icon: byId(D.currencies, "estrela").icon });
  }

  // --- cosmetics / skills / tools / aux ---

  // The chance of each rarity of instance gear on a map of this level (the game's own formula).
  function gearOdds(level) {
    const spans = D.map_items.loot.gear_rarity;
    const weights = D.rarities.map((r) => Math.max(0, spans[r.id][0] + spans[r.id][1] * (level - 1)));
    const total = weights.reduce((a, b) => a + b, 0);
    return weights.map((w) => w / total);
  }

  function rarityPill(id) {
    const r = D.rarities.find((entry) => entry.id === id);
    return r ? `<span class="pill" style="color:#${r.color}">${esc(L(r.label))}</span>` : "";
  }

  function cosmetics(focus) {
    const slots = ["skin", "camisa", "calca", "chapeu", "oculos", "asas", "anel", "amuleto", "cabelo"];
    const gender = (g) => ({ m: T("Masculina", "Male"), f: T("Feminina", "Female"), u: T("Todos", "All") }[g]);
    const levels = [1, 2, 4, 6, 8, 10, 12, 14, 16];
    const oddsTable = table([[T("Nível do mapa", "Map level"), "num"]].concat(D.rarities.map((r) => [L(r.label), "num"])),
      levels.map((lv) => `<tr>${tdn(lv)}${gearOdds(lv).map((p) => td(`${(p * 100).toFixed(p < 0.1 ? 1 : 0)}%`, p, "num")).join("")}</tr>`));
    const body = `
      <p class="intro">${T("As skins, as asas e as tinturas de cabelo são só aparência, e a loja premium vende só aparência (e conveniência). Camisas e calças dão atributos e não aparecem no personagem; chapéus e óculos dão atributos e aparecem sobre a skin. Anéis (dois espaços) e o amuleto (que dá vida) dão atributos e ficam só na ficha.",
        "Skins, wings and hair dyes are appearance only, and the premium shop sells only appearance (and convenience). Shirts and trousers give attributes and do not show on the character; hats and glasses give attributes and show over the skin. Rings (two slots) and the amulet (which gives life) give attributes and show on the sheet only.")}</p>
      <h2>${T("Equipamentos de instância", "Instance gear")}</h2>
      <p>${T("Camisas, calças, chapéus, óculos, anéis e amuletos de quatro raridades (Comum, Raro, Épico e Lendário) só caem nas instâncias, nas cartas do baú e dos monstros, e podem ir ao leilão. Quanto melhor a raridade, mais atributos e mais bonita a arte. Quanto mais alto o nível do mapa, maior a chance das raridades melhores; nada é garantido. Cada peça ainda tem a qualidade (Normal, Excelente, Verdadeira) e os bônus aleatórios.",
        "Shirts, trousers, hats, glasses, rings and amulets in four rarities (Common, Rare, Epic and Legendary) only drop in instances, from chest cards and monsters, and can go to the auction. The better the rarity, the more attributes and the prettier the art. The higher the map level, the likelier the better rarities; nothing is guaranteed. Each piece also has a quality (Normal, Excellent, True) and random bonuses.")}</p>
      ${oddsTable}
      <h2>${T("Asas à venda", "Wings for sale")}</h2>
      <p>${T("As oito asas não caem nas instâncias nem custam moedas: são só aparência (sem atributos nem bônus) e se compram com dinheiro, na aba Asas do Centro Comercial, por R$ 14,90 (Comum), R$ 24,90 (Raro), R$ 39,90 (Épico) ou R$ 59,90 (Lendário). A raridade só muda a cor e o brilho. Chegam vinculadas pelo Correio e não vão ao Leilão; quem já tinha as asas antigas as mantém, sem atributos.",
        "The eight pairs of wings neither drop in instances nor cost coins: they are appearance only (no stats or bonuses) and are bought with real money in the Wings tab of the Shopping Center, for R$ 14.90 (Common), R$ 24.90 (Rare), R$ 39.90 (Epic) or R$ 59.90 (Legendary). The rarity only changes the colour and the glow. They arrive bound by Mail and cannot be auctioned; anyone who already had the old wings keeps them, without stats.")}</p>
      ${slots.map((slot) => `<h2>${esc(slotName(slot))}</h2>` + table(["", [T("Nome", "Name"), "text"], T("Atributos", "Attributes"), [T("Preço", "Price"), "num"], slot === "skin" ? T("Personagem", "Character") : ""],
        D.cosmetics.filter((c) => c.slot === slot).map((c) => `<tr id="row-${c.id}">${td(icon(c.icon))}${td(ref("cosmetic", c.id), L(c.name))}
          ${td(Object.entries(c.attrs).map(([k, v]) => `+${v} ${esc(attrName(k))}`).concat(c.hp ? [`+${c.hp} ${T("vida", "life")}`] : []).join(", ") || `<span class="muted">${T("só aparência", "cosmetic only")}</span>`)}
          ${td(c.premium ? `${c.rarity ? rarityPill(c.rarity) + " " : ""}<span class="pill gold">${T("premium", "premium")}</span>` : c.drop_only ? `${rarityPill(c.rarity)} <span class="muted">${T("instâncias", "instances")}</span>` : n(c.price), c.premium ? 1e9 : c.drop_only ? 1e8 : c.price, "num")}${td(slot === "skin" ? gender(c.gender) : "")}</tr>`), { sortable: true })).join("")}`;
    return page(T("Visual", "Cosmetics"), [], body, { icon: byId(D.cosmetics, "asas_fenix").icon, focus });
  }

  function skills(focus) {
    const rows = D.skills.map((s) => `<tr id="row-${s.id}">${td(`<b style="font:700 20px var(--pixel)">${s.key}</b>`, s.key)}${td(`<span class="name">${icon(s.icon, "ico sm")}${esc(L(s.name))}</span>`)}${td(esc(L(s.desc)))}${tdn(s.energy)}${tdn(s.delay, "+" + s.delay)}</tr>`);
    const body = `
      <p class="intro">${T("Antes de disparar, aperte de 1 a 9 para usar habilidades no tiro do turno. Cada uma gasta energia e aumenta o Delay; dá para combinar várias se a energia deixar.",
        "Before firing, press 1 to 9 to use skills on this turn's shot. Each one costs energy and adds Delay; you can stack several if your energy allows.")}</p>
      ${table([[T("Tecla", "Key"), "num"], T("Habilidade", "Skill"), T("Efeito", "Effect"), [T("Energia", "Energy"), "num"], ["Delay", "num"]], rows, { sortable: true })}
      <p class="note">${T(`Você começa o turno com ${D.combat.energy} de energia (mais a Agilidade/30). Andar também gasta energia. O bônus de arma “chance de não gastar a habilidade” pode deixar uma habilidade de graça.`,
        `You start each turn with ${D.combat.energy} energy (plus Agility/30). Walking spends energy too. The weapon bonus “chance of not spending the skill” can make a skill free.`)}</p>`;
    return page(T("Habilidades 1–9", "Skills 1–9"), [], body, { icon: D.skills[0].icon, focus });
  }

  function tools(focus) {
    const rows = D.tools.map((t) => `<tr id="row-${t.id}">${td(`<span class="name">${icon(t.icon, "ico sm")}${esc(L(t.name))}</span>`, L(t.name))}${td(esc(L(t.desc)))}${tdn(t.price)}</tr>`);
    const body = `
      <p class="intro">${T(`Leve até três ferramentas para a partida (teclas Z, X e C). Cada uma se usa uma vez e soma ${D.combat.delay.tool} de Delay no turno. Escolha na sala, antes de começar.`,
        `Take up to three tools into a match (keys Z, X and C). Each one is used once and adds ${D.combat.delay.tool} Delay that turn. Pick them in the room before starting.`)}</p>
      ${table([[T("Ferramenta", "Tool"), "text"], T("Efeito", "Effect"), [T("Preço", "Price"), "num"]], rows, { sortable: true })}`;
    return page(T("Ferramentas Z X C", "Tools Z X C"), [], body, { icon: D.tools[0].icon, focus });
  }

  function statuses(focus) {
    // Where each effect comes from: the monster abilities that apply it.
    const sources = (id) => D.enemies.flatMap((e) => e.abilities.filter((a) => (a.status || []).some((s) => s.id === id)).map((a) => `${esc(L(a.name))} · ${ref("enemy", e.id)}`));
    const rows = D.statuses.map((s) => `<tr id="row-${s.id}">${td(`<span class="name" style="color:#${esc(s.color)}">${icon(s.icon, "ico sm")}${esc(L(s.name))}</span>`, L(s.name))}${td(esc(L(s.desc)))}${tdn(s.turns)}${td(sources(s.id).join("<br>") || "—")}</tr>`);
    const E = D.elites;
    const affixRows = E.affixes.map((a) => `<tr>${td(`<span class="name" style="color:#${esc(a.color)}">${icon(a.icon, "ico sm")}${esc(L(a.name))}</span>`, L(a.name))}${td(esc(L(a.desc)) + (a.status.length ? "<br>" + a.status.map(statusText).join(", ") : ""))}</tr>`);
    const body = `
      <p class="intro">${T("As habilidades dos monstros deixam efeitos que duram alguns turnos da vítima. O dano por turno (queimação, veneno) bate no começo do turno, e todo efeito conta um turno quando o turno termina. Quem é congelado perde a vez e depois fica 1 turno imune ao gelo. O <b>Elixir Purificador</b> (ferramenta) tira todos.",
        "Monster abilities leave effects that last some of the victim's turns. Damage over time (burning, poison) hits at the start of the turn, and every effect counts one turn when the turn ends. A frozen fighter loses the turn and is then immune to ice for 1 turn. The <b>Purifying Elixir</b> (tool) removes them all.")}</p>
      ${table([[T("Efeito", "Effect"), "text"], T("O que faz", "What it does"), [T("Turnos", "Turns"), "num"], T("Quem aplica", "Applied by")], rows, { sortable: true })}
      <h2>${T("Elites", "Elites")}</h2>
      <p>${T(`Lacaios (e às vezes o guardião) podem vir como elite: ${pct(E.hp - 1)} a mais de vida, ${pct(E.damage - 1)} a mais de dano, maiores e com uma aura na cor do afixo. Chance de ${pct(E.chance)} na entrada livre e +${pct(E.per_level)} por nível de mapa (metade para o guardião, nunca o chefe; até ${E.max_per_wave} por onda). A ameaça de mapa “inimigos de elite” aumenta a chance.`,
        `Minions (and sometimes the guardian) may come as elites: ${pct(E.hp - 1)} more HP, ${pct(E.damage - 1)} more damage, bigger and with an aura in the affix colour. ${pct(E.chance)} chance at the free entry and +${pct(E.per_level)} per map level (half for the guardian, never the boss; up to ${E.max_per_wave} per wave). The “elite enemies” map threat raises the chance.`)}</p>
      ${table([[T("Afixo", "Affix"), "text"], T("O que faz", "What it does")], affixRows, { sortable: true })}`;
    return page(T("Efeitos e elites", "Effects and elites"), [], body, { icon: D.statuses[0].icon, focus });
  }

  function auxiliary(focus) {
    const rows = D.auxiliary.map((a) => `<tr id="row-${a.id}">${td(`<span class="name">${icon(a.icon)}${esc(L(a.name))}</span>`)}${td(esc(L(a.desc)))}${tdn(a.uses)}${tdn(a.price)}</tr>`);
    const body = `
      <p class="intro">${T("O item auxiliar fica equipado na Mochila e se usa com V durante a partida, algumas vezes por batalha.", "The support item is equipped in the Bag and used with V during a match, a few times per battle.")}</p>
      ${table([T("Item", "Item"), T("Efeito", "Effect"), [T("Usos", "Uses"), "num"], [T("Preço", "Price"), "num"]], rows, { sortable: true })}`;
    return page(T("Itens auxiliares", "Support items"), [], body, { icon: D.auxiliary[0].icon, focus });
  }

  // --- dungeons, monsters, maps, arenas ---

  function instancesList() {
    const body = `
      <p class="intro">${T("Instâncias são expedições de 3 fases para até 4 jogadores. Entre com um mapa da Mochila (que define o nível e os modificadores) ou pela entrada livre.",
        "Dungeons are three-phase expeditions for up to 4 players. Enter with a map from your Bag (which sets the level and modifiers) or through the free entrance.")}</p>
      <div class="cards-grid">${D.instances.map((inst) => {
        const boss = byId(D.enemies, inst.boss);
        return `<a class="mcard" href="#/instancias/${inst.id}" data-tip="instance:${inst.id}"><img src="${esc(img(boss.sprite))}" alt=""><b>${esc(L(inst.name))}</b><small>${T("Chefe", "Boss")}: ${esc(L(boss.name))}</small></a>`;
      }).join("")}</div>
      ${lootRules()}`;
    return page(T("Instâncias", "Dungeons"), [], body, { icon: D.instances[0].map_icon });
  }

  function lootRules() {
    const M = D.map_items;
    const lo = M.loot;
    return `
      <h2>${T("Baú do chefe", "Boss chest")}</h2>
      <ul>
        <li>${T(`Você escolhe <b>${lo.boss_picks}</b> de 8 cartas (mais cartas com grupo, com o modificador “+1 carta” e com quantidade de itens).`, `You pick <b>${lo.boss_picks}</b> of 8 cards (more with a party, the “+1 card” modifier and item quantity).`)}</li>
        <li>${T(`Arma Verdadeira: ${pct(lo.true_chance)} + ${pct(lo.true_per_level)} por nível do mapa; Excelente: ${pct(lo.excellent_chance)}.`, `True weapon: ${pct(lo.true_chance)} + ${pct(lo.true_per_level)} per map level; Excellent: ${pct(lo.excellent_chance)}.`)}</li>
        <li>${T(`Super Verdadeira: ${pct(lo.super_chance)} + ${pct(lo.super_per_level)} por nível (${pct(lo.free_super_chance)} na entrada livre). Sem garantia: nenhuma quantidade de chefes derrotados a faz cair. Metade das vezes é a Super da instância; na outra metade, qualquer uma.`,
          `Super True: ${pct(lo.super_chance)} + ${pct(lo.super_per_level)} per level (${pct(lo.free_super_chance)} at the free entrance), no guarantee: no number of boss kills makes it drop. Half the time it is the dungeon's own Super; otherwise any of them.`)}</li>
        <li>${T(`Moedas de criação: ${lo.currency_chance.map((c) => pct(c)).join(" / ")} de chance nas fases 1, 2 e 3 (o chefe sempre dá).`, `Crafting currencies: ${lo.currency_chance.map((c) => pct(c)).join(" / ")} chance in phases 1, 2 and 3 (the boss always gives one).`)}</li>
        <li>${T(`Mapas: ${M.drop_chance.map((c) => pct(c)).join(" / ")} de chance por fase. <a href="#/mapas">Mais sobre mapas</a>.`, `Maps: ${M.drop_chance.map((c) => pct(c)).join(" / ")} chance per phase. <a href="#/mapas">More about maps</a>.`)}</li>
        <li>${T("O loot é pessoal: cada jogador do grupo tem seus drops, seu baú e suas cartas.", "Loot is personal: every player in the party gets their own drops, chest and cards.")}</li>
      </ul>
      <h2>${T("Escala por grupo", "Party scaling")}</h2>
      ${table([T("Jogadores", "Players"), [T("Vida dos inimigos", "Enemy HP"), "num"], [T("Dano", "Damage"), "num"], [T("Lacaios extras", "Extra minions"), "num"], [T("Recompensa", "Rewards"), "num"], [T("Cartas extras", "Extra cards"), "num"], [T("Raridade", "Rarity"), "num"]],
        [0, 1, 2, 3].map((i) => { const P = D.party_scaling; return `<tr>${td(`<b>${i + 1}</b>`)}${tdn(P.hp[i], mult(P.hp[i]))}${tdn(P.damage[i], mult(P.damage[i]))}${tdn(P.extra_minions[i])}${tdn(P.reward[i], mult(P.reward[i]))}${tdn(P.bonus_cards[i])}${tdn(P.rarity[i], "+" + pct(P.rarity[i]))}</tr>`; }))}
      <p>${T(`Com ${D.party_scaling.boss_area_from} ou mais jogadores, o chefe passa a atingir todo mundo a cada rodada.`, `With ${D.party_scaling.boss_area_from} or more players, the boss hits everyone every round.`)}</p>`;
  }

  function instancePage(id) {
    const inst = byId(D.instances, id);
    if (!inst) return notFound();
    const boss = byId(D.enemies, inst.boss);
    const phases = inst.phases.map((ph, i) => {
      const arena = byId(D.arenas, ph.map);
      const objective = ph.objective === "totems" ? T("Objetivo: destruir os cristais que protegem o guardião.", "Objective: destroy the crystals protecting the guardian.")
        : ph.objective === "survive" ? T(`Objetivo: sobreviver ${ph.turns} turnos.`, `Objective: survive ${ph.turns} turns.`) : "";
      return `<div class="phase">
        <img class="map" src="${esc(img(arena.thumb))}" alt="">
        <div><h3>${T("Fase", "Phase")} ${i + 1}: ${esc(L(ph.name))}</h3>
          <p class="muted">${T("Arena", "Arena")}: ${ref("arena", arena.id)}${objective ? " · " + objective : ""}</p>
          ${ph.waves.map((wave, k) => `<div class="wave"><span>${ph.waves.length > 1 ? T("Onda", "Wave") + " " + (k + 1) : T("Inimigos", "Enemies")}</span>${wave.map((eid) => {
            const e = byId(D.enemies, eid);
            return `<a class="foe" href="#/monstros/${eid}" data-tip="enemy:${eid}"><img src="${esc(img(e.sprite))}" alt="">${esc(L(e.name))}</a>`;
          }).join("")}</div>`).join("")}
        </div></div>`;
    }).join("");
    const body = `
      <div class="hero-wiki" style="--hero:url('${esc(img(byId(D.arenas, inst.phases[2].map).bg))}')">
        <h1><img src="${esc(img(inst.map_icon))}" alt="">${esc(L(inst.name))}</h1>
        <p>${esc(L(inst.desc))}</p>
      </div>
      ${phases}
      <h2>${T("Chefe", "Boss")}: ${ref("enemy", boss.id)}</h2>
      <p>${(boss.mechanics || []).map((m) => `<span class="pill gold">${esc(mechName(m))}</span>`).join(" ")} ${bossMechanicsText(boss)}</p>
      <h2>${T("Loot", "Loot")}</h2>
      <p>${T("Armas Verdadeiras", "True weapons")}: ${inst.loot.weapons.map((w) => ref("weapon", w, true)).join(", ")}.<br>
        ${T("Super Verdadeira", "Super True")}: ${ref("weapon", inst.loot.super, true)}.</p>
      ${lootRules()}`;
    return page(L(inst.name), [{ label: () => T("Instâncias", "Dungeons"), href: "#/instancias" }], body, { bare: true });
  }

  function bossMechanicsText(e) {
    const parts = [];
    (e.mechanics || []).forEach((m) => {
      if (m === "fury") parts.push(T(`Abaixo de 50% de vida entra em fúria: ${esc(L(e.fury_name))}, com dano ${n(e.fury_damage)} (em vez de ${n(e.damage)}).`, `Below 50% HP it enters fury: ${esc(L(e.fury_name))}, dealing ${n(e.fury_damage)} (instead of ${n(e.damage)}).`));
      if (m === "summon") parts.push(T(`A cada 3 turnos invoca ${ref("enemy", e.summon)}.`, `Every 3 turns it summons ${ref("enemy", e.summon)}.`));
      if (m === "freeze") parts.push(T("A cada 2 turnos o ataque congela quem acerta: a vítima perde a vez.", "Every other turn its attack freezes whoever it hits: the victim loses a turn."));
      if (m === "teleport") parts.push(T("Depois de cada ataque, voa para outra posição.", "After each attack it flies to another position."));
    });
    return parts.join(" ");
  }

  function monstersList() {
    const ranks = ["boss", "guardian", "minion", "totem"];
    const body = `
      <p class="intro">${T(`Os números são do mapa de nível 1 com um jogador. Cada nível de mapa multiplica a vida por ${mult(D.map_items.hp_per_level)} e o dano por ${mult(D.map_items.damage_per_level)}; o grupo também aumenta (veja <a href="#/instancias">Instâncias</a>).`,
        `Numbers are for a level 1 map with one player. Each map level multiplies HP by ${mult(D.map_items.hp_per_level)} and damage by ${mult(D.map_items.damage_per_level)}; party size adds more (see <a href="#/instancias">Dungeons</a>).`)}</p>
      ${ranks.map((rank) => {
        const list = D.enemies.filter((e) => e.rank === rank);
        if (!list.length) return "";
        return `<h2>${esc(rankName(rank))}${rank === "totem" ? "" : "s"}</h2>` + table(["", [T("Monstro", "Monster"), "text"], [T("Vida", "HP"), "num"], [T("Dano", "Damage"), "num"], T("Habilidades", "Abilities"), T("Aparece em", "Appears in")],
          list.map((e) => `<tr>${td(icon(e.sprite))}${td(ref("enemy", e.id), L(e.name))}${tdn(e.hp)}${tdn(e.damage, e.damage ? n(e.damage) + (e.fury_damage ? ` / ${n(e.fury_damage)}` : "") : "—")}
            ${td(e.abilities.map((a) => esc(L(a.name))).join(", ") || "—")}${td([...new Set(e.appears.map(([iid]) => iid))].map((iid) => ref("instance", iid)).join(", "))}</tr>`), { sortable: true });
      }).join("")}`;
    return page(T("Monstros", "Monsters"), [], body, { icon: byId(D.enemies, "grifo_tempestade").sprite });
  }

  function monsterPage(id) {
    const e = byId(D.enemies, id);
    if (!e) return notFound();
    const levels = [1, 4, 8, 12, 16];
    const scale = (lv, per) => Math.pow(per, lv - 1);
    const body = `
      <div class="entity">
        <div>${enemyCard(e)}</div>
        <div>
          ${(e.mechanics || []).length ? `<h2 style="margin-top:0">${T("Mecânicas", "Mechanics")}</h2><p>${bossMechanicsText(e)}</p>` : ""}
          ${e.rank === "totem" ? `<p class="intro" style="margin-top:0">${T("Não ataca. Enquanto existir, protege o guardião da fase: destrua os cristais primeiro.", "Does not attack. While it stands it protects the phase guardian: destroy the crystals first.")}</p>` : ""}
          <h2 ${(e.mechanics || []).length ? "" : 'style="margin-top:0"'}>${T("Habilidades", "Abilities")}</h2>
          ${e.abilities.length ? e.abilities.map((a) => `<div class="ability" style="--mc:#${esc(e.color || "3aa6ff")}"><b>${esc(L(a.name))}</b><span class="kind">${esc(T(...(KIND_NAMES[a.kind] || [a.kind, a.kind])))}</span><p>${abilityText(a, e)}</p></div>`).join("") : `<p>—</p>`}
          <h2>${T("Onde aparece", "Where it appears")}</h2>
          <ul>${e.appears.map(([iid, p]) => { const inst = byId(D.instances, iid); return `<li>${ref("instance", iid, true)} · ${T("fase", "phase")} ${p + 1}: ${esc(L(inst.phases[p].name))}</li>`; }).join("") || "<li>—</li>"}</ul>
        </div>
      </div>
      ${e.damage || e.hp ? `<h2>${T("Por nível de mapa (1 jogador)", "By map level (1 player)")}</h2>
      ${table([T("Nível", "Level"), [T("Vida", "HP"), "num"], [T("Dano", "Damage"), "num"]], levels.map((lv) => `<tr>${td(`<b>${lv}</b>`)}${tdn(Math.round(e.hp * scale(lv, D.map_items.hp_per_level)))}${tdn(Math.round((e.damage || 0) * scale(lv, D.map_items.damage_per_level)))}</tr>`))}` : ""}`;
    return page(L(e.name), [{ label: () => T("Monstros", "Monsters"), href: "#/monstros" }], body, { icon: e.sprite });
  }

  function mapItems() {
    const M = D.map_items;
    const levels = Array.from({ length: M.max_level }, (_, i) => i + 1);
    const threats = M.mods.filter((m) => m.kind === "threat");
    const rewards = M.mods.filter((m) => m.kind === "reward");
    const modText = (m) => esc(L(m.text).replace(/%d%%/g, m.range ? `${m.range[0]}–${m.range[1]}%` : "#%").replace(/%d/g, m.range ? `${m.range[0]}–${m.range[1]}` : "#"));
    const body = `
      <p class="intro">${T("No lugar de dificuldades fixas, as instâncias usam mapas: itens que caem nas próprias instâncias, com nível de 1 a " + M.max_level + " e modificadores aleatórios de ameaça e de recompensa. O mapa é gasto ao entrar. A entrada livre (sem mapa) continua lá, com recompensa menor.",
        "Instead of fixed difficulties, dungeons use maps: items that drop in the dungeons themselves, with a level from 1 to " + M.max_level + " and random threat and reward modifiers. The map is consumed on entry. The free entrance (no map) is always there, with smaller rewards.")}</p>
      <div style="display:flex;gap:12px;flex-wrap:wrap;margin-bottom:18px">${D.instances.map((i) => `<a class="pill" href="#/instancias/${i.id}"><img src="${esc(img(i.map_icon))}" alt="" style="width:32px;height:32px;image-rendering:pixelated">${esc(L(i.name))}</a>`).join("")}</div>
      <h2>${T("Nível do mapa", "Map level")}</h2>
      ${table([[T("Nível", "Level"), "num"], [T("Vida dos inimigos", "Enemy HP"), "num"], [T("Dano dos inimigos", "Enemy damage"), "num"], [T("Recompensas", "Rewards"), "num"], T("Faixas de bônus liberadas", "Bonus tiers unlocked")],
        levels.map((lv) => `<tr>${td(`<b>${lv}</b>`, lv, "num")}${tdn(Math.pow(M.hp_per_level, lv - 1), mult(Math.pow(M.hp_per_level, lv - 1)))}${tdn(Math.pow(M.damage_per_level, lv - 1), mult(Math.pow(M.damage_per_level, lv - 1)))}
          ${tdn(1 + M.reward_per_level * (lv - 1), mult(1 + M.reward_per_level * (lv - 1)))}${td(D.affixes.tiers.filter((t) => lv >= t.ilvl).map((t) => t.name).reverse().join(" "))}</tr>`))}
      <p>${T(`Entrada livre: nível 1 com ${pct(M.free_reward)} das recompensas.`, `Free entrance: level 1 with ${pct(M.free_reward)} of the rewards.`)}</p>
      <h2>${T("Qualidade do mapa", "Map quality")}</h2>
      ${table([T("Qualidade", "Quality"), [T("Chance", "Chance"), "num"], [T("Modificadores", "Modifiers"), "num"]], M.qualities.map((q) => `<tr>${td(`<b style="color:#${qual(q.id).color}">${esc(L(qual(q.id).label))}</b>`)}${tdn(q.weight, q.weight + "%")}${td(q.mods.join("–"), null, "num")}</tr>`))}
      <h2>${T("Ameaças", "Threats")}</h2>
      <p>${T(`Cada ameaça também dá +${pct(M.threat_quantity)} de quantidade de itens.`, `Each threat also gives +${pct(M.threat_quantity)} item quantity.`)}</p>
      <div class="pills">${threats.map((m) => `<span class="pill threat">${modText(m)}</span>`).join("")}</div>
      <h2>${T("Recompensas", "Rewards")}</h2>
      <div class="pills">${rewards.map((m) => `<span class="pill reward">${modText(m)}</span>`).join("")}</div>
      <h2>${T("Como os mapas caem", "How maps drop")}</h2>
      <ul>
        <li>${T(`Chance por fase vencida: ${M.drop_chance.map((c) => pct(c)).join(", ")} (o chefe é a última).`, `Chance per phase won: ${M.drop_chance.map((c) => pct(c)).join(", ")} (the boss is the last).`)}</li>
        <li>${T(`Nível do mapa que cai: o mesmo (${pct(M.drop_level[0])}), +1 (${pct(M.drop_level[1])}) ou +2 (${pct(M.drop_level[2])}). A entrada livre dá mapas de nível 1.`, `Level of the dropped map: the same (${pct(M.drop_level[0])}), +1 (${pct(M.drop_level[1])}) or +2 (${pct(M.drop_level[2])}). The free entrance drops level 1 maps.`)}</li>
        <li>${T(`${pct(M.other_instance)} das vezes o mapa é de outra instância.`, `${pct(M.other_instance)} of the time the map is for another dungeon.`)}</li>
        <li>${T("Mapas também aceitam moedas de criação no Ferreiro e podem ser vendidos no Leilão.", "Maps also take crafting currencies at the Blacksmith and can be sold at the Auction.")}</li>
      </ul>`;
    return page(T("Mapas", "Maps"), [], body, { icon: D.instances[2].map_icon });
  }

  function arenas(focus) {
    const body = `
      <p class="intro">${T("Onde as batalhas acontecem. O chão é destruído pixel a pixel a cada explosão; algumas arenas só aparecem nas instâncias.", "Where battles happen. The ground is destroyed pixel by pixel with each blast; some arenas only appear in dungeons.")}</p>
      <div class="cards-grid">${D.arenas.map((a) => `<div class="mcard" id="row-${a.id}"><img src="${esc(img(a.thumb))}" alt="" style="height:auto;width:100%"><b>${esc(L(a.name))}</b>
        <small>${a.pve_only ? T("Só na Instância", "Dungeon only") : "PvP · PvE"} · ${a.size[0]}×${a.size[1]}</small>
        ${a.used.length ? `<small>${a.used.map(([iid, p]) => `${ref("instance", iid)} ${T("fase", "phase")} ${p + 1}`).join(" · ")}</small>` : ""}</div>`).join("")}</div>`;
    return page(T("Arenas", "Arenas"), [], body, { icon: D.icons.crown, focus });
  }

  // --- economy ---

  function currencies(focus) {
    const rows = D.currencies.map((c) => `<tr id="row-${c.id}">${td(`<span class="name">${icon(c.icon)}<b style="color:#${RARITY[c.rarity][0]}">${esc(L(c.name))}</b></span>`, L(c.name))}
      ${td(esc(L(c.desc)))}${td(esc(rarityName(c.rarity)))}${tdn(c.min_level, c.min_level ? `${c.min_level}+` : T("qualquer", "any"))}${tdn(c.weight, n(c.weight, 2))}</tr>`);
    const body = `
      <p class="intro">${T("As sete moedas de criação caem nas instâncias (e as duas primeiras, um pouco no PvP) e mudam a qualidade e os bônus de equipamentos e mapas na aba Moedas do Ferreiro. Usar gasta a moeda: é isso que mantém o valor delas no Leilão.",
        "The seven crafting currencies drop in dungeons (the first two also a little in PvP) and change the quality and bonuses of gear and maps in the Blacksmith's Currencies tab. Using one consumes it: that is what keeps their value at the Auction.")}</p>
      ${table([[T("Moeda", "Currency"), "text"], T("Efeito", "Effect"), T("Raridade", "Rarity"), [T("Nível do mapa", "Map level"), "num"], [T("Peso", "Weight"), "num"]], rows, { sortable: true })}
      <p class="note">${T("O peso é a chance relativa entre as moedas liberadas pelo nível do mapa; as raras ficam mais comuns em mapas altos. As moedas de ouro são outra coisa: servem para a loja, o Ferreiro e as taxas.",
        "Weight is the relative chance among the currencies the map level unlocks; the rare ones get more common on high maps. Gold is something else: it pays for the shop, the Blacksmith and fees.")}</p>
      <p>${T("Veja também", "See also")}: <a href="#/bonus">${T("Bônus aleatórios", "Random bonuses")}</a> · <a href="#/leilao">${T("Leilão", "Auction")}</a></p>`;
    return page(T("Moedas de criação", "Crafting currencies"), [], body, { icon: byId(D.currencies, "solar").icon, focus });
  }

  function auction() {
    const A = D.auction;
    const body = `
      <p class="intro">${T("O Leilão da cidade (online) é onde os jogadores vendem uns para os outros os equipamentos que caíram nas instâncias e os mapas.", "The city Auction (online) is where players sell each other the gear that dropped in dungeons and maps.")}</p>
      <div class="kv">
        <div><span>${T("Moedas aceitas", "Accepted currencies")}</span><b>${A.currencies.map((id) => L(byId(D.currencies, id).name)).join(" + ")}</b></div>
        <div><span>${T("Duração", "Duration")}</span><b>${A.hours.join(" / ")} h</b></div>
        <div><span>${T("Taxa para anunciar", "Listing fee")}</span><b>${A.fee_coins.join(" / ")}</b></div>
        <div><span>${T("Comissão", "Commission")}</span><b>${pct(A.commission)}</b></div>
        <div><span>${T("Anúncios ao mesmo tempo", "Listings at once")}</span><b>${A.max_listings}</b></div>
        <div><span>${T("Preço máximo", "Max price")}</span><b>${A.max_price}</b></div>
      </div>
      <h2>${T("Como funciona", "How it works")}</h2>
      <ul>
        <li>${T("<b>Comprar</b>: busca com filtros de tipo, qualidade, nível, fortalecimento, bônus e preço. A compra é imediata e o item vai direto para a Mochila.", "<b>Buy</b>: search by type, quality, level, strengthening, bonus and price. Purchases are instant and the item goes straight to your Bag.")}</li>
        <li>${T("<b>Vender</b>: preço em Solares e/ou Estrelas; anunciar custa uma taxa em moedas de ouro (pela duração) e a venda paga a comissão de cada moeda. O item fica guardado no servidor enquanto está à venda.", "<b>Sell</b>: price in Solars and/or Stars; listing costs a gold fee (by duration) and the sale pays the commission on each currency. The item is held by the server while listed.")}</li>
        <li>${T("<b>Correio</b>: o pagamento das vendas e os itens de anúncios cancelados ou vencidos chegam pelo Correio.", "<b>Mail</b>: sale payments and items from cancelled or expired listings arrive by Mail.")}</li>
        <li>${T("<b>Vinculados</b> não vão ao Leilão: itens da loja, de cupons, cópias do Espelho Celeste, a arma inicial e as Super Verdadeiras depois de equipadas.", "<b>Bound</b> items cannot be listed: shop and coupon items, Sky Mirror copies, the starting weapon and Super True weapons once equipped.")}</li>
      </ul>`;
    return page(T("Leilão e Correio", "Auction and Mail"), [], body, { icon: D.icons.mail });
  }

  function rewards() {
    const R = D.rewards;
    const total = D.reward_cards.filter((c) => !D.currencies.some((x) => x.id === c.id)).reduce((a, c) => a + c.weight, 0);
    const body = `
      <p class="intro">${T("Toda partida dá experiência (EXP), mérito e cartas de recompensa no fim.", "Every match gives experience (EXP), merit and reward cards at the end.")}</p>
      <div class="kv">
        <div><span>${T("EXP na vitória", "EXP on a win")}</span><b>${R.win_exp}</b></div>
        <div><span>${T("EXP na derrota", "EXP on a loss")}</span><b>${R.loss_exp}</b></div>
        <div><span>${T("EXP por dano", "EXP per damage")}</span><b>${n(R.exp_per_damage, 2)}</b></div>
        <div><span>${T("EXP por abate", "EXP per kill")}</span><b>${R.exp_per_kill}</b></div>
        <div><span>${T("Mérito (vitória/derrota)", "Merit (win/loss)")}</span><b>${R.merit_win}/${R.merit_loss}</b></div>
        <div><span>${T("Mérito por abate", "Merit per kill")}</span><b>${R.merit_per_kill}</b></div>
      </div>
      <h2>${T("Cartas de recompensa", "Reward cards")}</h2>
      ${table(["", [T("Carta", "Card"), "text"], T("Raridade", "Rarity"), [T("Chance", "Chance"), "num"]], D.reward_cards.filter((c) => !D.currencies.some((x) => x.id === c.id)).map((c) => `<tr>${td(icon(c.icon, "ico sm"))}${td(esc(L(c.name)), L(c.name))}${td(`<span style="color:#${RARITY[c.rarity][0]}">${esc(rarityName(c.rarity))}</span>`)}${tdn(c.weight / total, pct(c.weight / total, 1))}</tr>`), { sortable: true })}
      <p>${T("No PvP também podem aparecer Brasas e Coroas. Nas instâncias, as recompensas vêm do baú do chefe:", "In PvP, Embers and Crowns can show up too. In dungeons, rewards come from the boss chest:")} <a href="#/instancias">${T("veja o baú", "see the chest")}</a>.</p>`;
    return page(T("Recompensas", "Rewards"), [], body, { icon: D.icons.coin });
  }

  function store() {
    const body = `
      <p class="intro">${T("Gustfire é grátis. A loja com dinheiro de verdade vende só aparência e conveniência (skins, asas, mascotes, abas extras da Mochila e o Passe do Caçador): nada ali tem atributo, tudo chega vinculado pelo Correio e não vai ao Leilão. Não existem caixas de recompensa pagas.",
        "Gustfire is free. The real-money shop only sells looks and convenience (skins, wings, pets, extra Bag tabs and the Hunter Pass): nothing there has stats, everything arrives bound by Mail and cannot be auctioned. There are no paid loot boxes.")}</p>
      ${table([T("Produto", "Product"), T("Inclui", "Includes"), ["BRL", "num"], ["USD", "num"], ["EUR", "num"]], D.store.filter((p) => !/^aba_mochila_[2-9]$/.test(p.sku)).map((p) => p.sku === "aba_mochila_1" ? { ...p, name: { pt: "Abas de Mochila (1 a 6)", en: "Bag tabs (1 to 6)" }, desc: { pt: "Cada aba soma 40 espaços à Mochila; são seis, vendidas uma a uma. Conveniência: não muda atributos.", en: "Each tab adds 40 Bag slots; there are six, sold one by one. Convenience: changes no stats." } } : p).map((p) => `<tr>${td(`<b>${esc(L(p.name))}</b><br><span class="muted">${esc(L(p.desc))}</span>`)}${td((p.items || []).map((i) => ref("cosmetic", i, true)).concat((p.pets || []).map((i) => ref("pet", i, true))).join("<br>"))}
        ${tdn(p.prices.BRL / 100, "R$ " + n(p.prices.BRL / 100, 2))}${tdn(p.prices.USD / 100, "US$ " + n(p.prices.USD / 100, 2))}${tdn(p.prices.EUR / 100, "€ " + n(p.prices.EUR / 100, 2))}</tr>`))}
      <p class="note">${T("Preços de referência; a Steam converte para a moeda da sua carteira. A loja de moedas de ouro do Centro Comercial vende armas Normais e Excelentes, visuais, auxiliares, ferramentas e pedras.",
        "Reference prices; Steam converts them to your wallet currency. The Shopping Center's gold shop sells Normal and Excellent weapons, cosmetics, support items, tools and stones.")}</p>`;
    return page(T("Loja", "Shop"), [], body, { icon: D.icons.shop });
  }

  function achievements() {
    const body = `
      <p class="intro">${T("Conquistas da Steam, liberadas pelo seu perfil online.", "Steam achievements, unlocked by your online profile.")}</p>
      ${table(["", [T("Conquista", "Achievement"), "text"], T("Como liberar", "How to unlock")], D.achievements.map((a) => `<tr>${td(icon(a.icon))}${td(`<b>${esc(L(a.name))}</b>`, L(a.name))}${td(esc(L(a.desc)))}</tr>`), { sortable: true })}`;
    return page(T("Conquistas", "Achievements"), [], body, { icon: D.icons.trophy });
  }

  function notFound() {
    return page(T("Página não encontrada", "Page not found"), [], `<p class="intro">${T("Essa página não existe. Use a busca ou o menu.", "This page does not exist. Use the search or the menu.")}</p>`);
  }

  // ---------- pets (0.19) and the hunt (0.20) ----------

  const petElementById = (id) => byId(D.pets.elements, id);
  const petElement = (sp) => petElementById(sp.element);
  const petRarity = (id) => byId(D.pets.rarities, id);
  const money = (cents, symbol) => { const text = (cents / 100).toFixed(2); return symbol + " " + T(text.replace(".", ","), text); };
  const petPrice = (sp) => sp.price ? money(sp.price.BRL, "R$") : "";
  const rarityTag = (id) => { const r = petRarity(id); return `<span style="color:#${r.color}">${esc(L(r.label))}</span>`; };
  const elementTag = (id) => { const el = petElementById(id); return `<span class="el-tag" style="color:#${el.color}">${icon(el.icon, "inline-ico")}${esc(L(el.name))}</span>`; };

  // Where a pet can come from: the shop always, the boss chest and the Hunt only for Common and Rare.
  const freePet = (sp) => sp.rarity === "comum" || sp.rarity === "raro";

  function petCard(sp) {
    const r = petRarity(sp.rarity);
    return `<div class="icard" style="--qc:#${r.color}">
      <div class="ih"><b>${esc(L(sp.name))}</b><small>${esc(L(r.label))} · ${esc(L(petElement(sp).name))}</small></div>
      <div class="art"><img src="${esc(img(sp.art))}" alt="" style="width:96px;height:96px"></div>
      <div class="sec"><div>${esc(L(sp.desc))}</div></div>
      <div class="sec"><div class="mod">${T("Só aparência: sem atributos e sem poder em batalha.", "Looks only: no attributes and no power in battle.")}</div><div class="mod">${esc(petPrice(sp))}</div></div>
    </div>`;
  }

  function petsHome(filter) {
    const P = D.pets;
    const species = filter && petElementById(filter) ? P.species.filter((sp) => sp.element === filter) : P.species;
    const priceOf = (id) => { const sp = P.species.find((x) => x.rarity === id); return sp && sp.price ? sp.price : null; };
    const body = `
      <p class="intro">${T(`Os mascotes são <b>só aparência</b>: acompanham o seu personagem nas batalhas, mas não dão atributos nem poder e não têm habilidade. Todos estão à venda na aba <b>Mascotes</b> do Centro Comercial, e Comuns e Raros também podem ser achados de graça. Eles sobem de nível na <a href="#/cacada">Caçada</a>, onde lutam sozinhos e rendem moedas e XP. <b>Não existem ovos nem sorteios pagos</b>: você escolhe o mascote que quer.`,
        `Pets are <b>looks only</b>: they follow your character into battle but give no attributes or power and have no skill. All of them are on sale in the <b>Pets</b> tab of the Shopping Center, and Commons and Rares can also be found for free. They level up on the <a href="#/cacada">Hunt</a>, where they fight on their own and earn gold and XP. <b>There are no eggs and no paid draws</b>: you pick the pet you want.`)}</p>
      <div class="kv">
        <div><span>${T("Espécies", "Species")}</span><b>${P.species.length}</b></div>
        <div><span>${T("Elementos", "Elements")}</span><b>${P.elements.length}</b></div>
        <div><span>${T("Nível máximo", "Max level")}</span><b>${P.max_level}</b></div>
        <div><span>${T("Limite da Casa", "House limit")}</span><b>${n(P.max_pets)}</b></div>
      </div>

      <h2>${T("Preços e como conseguir", "Prices and how to get them")}</h2>
      ${table([T("Raridade", "Rarity"), [T("Na loja (BRL)", "In the shop (BRL)"), "num"], [T("Na loja (USD)", "In the shop (USD)"), "num"], T("De graça", "For free"), [T("Ao libertar", "On release"), "num"]],
        P.rarities.map((r) => { const price = priceOf(r.id); return `<tr>${td(rarityTag(r.id))}${tdn(price ? price.BRL : 0, price ? money(price.BRL, "R$") : "—")}${tdn(price ? price.USD : 0, price ? money(price.USD, "US$") : "—")}${td(r.id === "comum" || r.id === "raro" ? T("Baú do chefe e Caçada", "Boss chest and the Hunt") : T("Só na loja", "Shop only"))}${tdn(r.release, n(r.release) + " " + T("moedas", "gold"))}</tr>`; }))}
      <ul>
        <li>${T(`<b>Baú do chefe</b>: ao vencer o chefe de uma instância há ${pct(P.drops.boss_base)} + ${pct(P.drops.boss_per_level)} por nível de mapa (máximo ${pct(P.drops.boss_max)}) de achar o mascote Comum do elemento dela. Sem garantia.`,
          `<b>Boss chest</b>: beating a dungeon boss has ${pct(P.drops.boss_base)} + ${pct(P.drops.boss_per_level)} per map level (max ${pct(P.drops.boss_max)}) to find the Common pet of its element. No guarantee.`)}</li>
        <li>${T(`<b>Caçada</b>: só selvagens Comuns e Raros podem ser capturados, com pouca chance, e só nas primeiras duas horas de cada coleta (o Passe do Caçador não dá mais sorteios).`, `<b>Hunt</b>: only Common and Rare wild pets can be caught, with a low chance, and only in the first two hours of each collection (the Hunter Pass never adds draws).`)}</li>
        <li>${T("A primeira Instância concluída dá um Escaravelho Solar de presente.", "The first dungeon you finish gives a Sun Scarab as a gift.")}</li>
        <li>${T("Quem já tem uma espécie não a compra de novo. Mascotes não vão ao Leilão.", "You cannot buy a species you already own. Pets cannot be auctioned.")}</li>
      </ul>

      <h2>${T("Elementos", "Elements")}</h2>
      ${table(["", [T("Elemento", "Element"), "text"], T("Zona da Caçada", "Hunt zone"), T("Instância (baú do chefe)", "Dungeon (boss chest)")],
        P.elements.map((el) => { const zone = D.pets.hunt.zones.find((z) => z.element === el.id); return `<tr>${td(icon(el.icon))}${td(`<b style="color:#${el.color}">${esc(L(el.name))}</b>`, L(el.name))}${td(esc(L(zone.name)))}${td(ref("instance", el.instance, true))}</tr>`; }))}

      <h2>${T("Níveis", "Levels")}</h2>
      <ul>
        <li>${T(`Nível 1 ao ${P.max_level}; o XP de cada nível é ${P.xp.per_level} × nível. O mascote só ganha XP na Caçada (não há alimentar nem estrelas).`, `Level 1 to ${P.max_level}; each level takes ${P.xp.per_level} × level XP. A pet only earns XP on the Hunt (there is no feeding and no stars).`)}</li>
        <li>${T("O nível só conta na Caçada: em batalha o mascote é só visual.", "Level only matters on the Hunt: in battle the pet is purely cosmetic.")}</li>
      </ul>

      <h2>${T("Espécies", "Species")}</h2>
      <p class="filters">${[["", T("Todas", "All")]].concat(P.elements.map((el) => [el.id, L(el.name)])).map(([id, label]) => `<a class="chip ${(filter || "") === id ? "on" : ""}" href="#/mascotes${id ? "/" + id : ""}">${esc(label)}</a>`).join("")}</p>
      ${table(["", [T("Mascote", "Pet"), "text"], [T("Elemento", "Element"), "text"], [T("Raridade", "Rarity"), "num"], [T("Preço", "Price"), "num"], T("Descrição", "Description")],
        species.map((sp) => `<tr id="row-${sp.id}">${td(icon(sp.art, "ico lg"))}${td(ref("pet", sp.id), L(sp.name))}${td(elementTag(sp.element), L(petElement(sp).name))}${td(rarityTag(sp.rarity), P.rarities.findIndex((r) => r.id === sp.rarity))}${tdn(sp.price ? sp.price.BRL : 0, petPrice(sp))}${td(esc(L(sp.desc)))}</tr>`), { sortable: true })}`;
    return page(T("Casa dos Mascotes", "Pet House"), [], body, { icon: P.species.find((x) => x.rarity === "lendario").art });
  }

  function petPage(id) {
    const P = D.pets;
    const sp = byId(P.species, id);
    const el = petElement(sp);
    const body = `
      <div class="entity">
        <div>${petCard(sp)}</div>
        <div>
          <h2 style="margin-top:0">${T("Elemento", "Element")}</h2>
          <p>${elementTag(sp.element)}</p>
          <h2>${T("Como conseguir", "How to get it")}</h2>
          <ul><li>${T(`<b>Na loja</b>: ${esc(petPrice(sp))} (aba Mascotes do Centro Comercial).`, `<b>In the shop</b>: ${esc(petPrice(sp))} (Pets tab of the Shopping Center).`)}</li>
          ${freePet(sp) && sp.rarity === "comum" ? `<li>${T("Baú do chefe de ", "Boss chest of ")}${ref("instance", el.instance, true)}${T(", sem garantia.", ", no guarantee.")}</li>` : ""}
          ${freePet(sp) ? `<li>${T("Na ", "On the ")}<a href="#/cacada">${T("Caçada", "Hunt")}</a>${T(`: selvagens de ${esc(L(el.name))} podem ser capturados, com pouca chance.`, `: wild ${esc(L(el.name))} pets can be caught, with a low chance.`)}</li>` : `<li>${T("Só se compra: Épicos e Lendários não caem de graça.", "Purchase only: Epics and Legendaries never drop for free.")}</li>`}</ul>
        </div>
      </div>`;
    return page(L(sp.name), [{ label: () => T("Casa dos Mascotes", "Pet House"), href: "#/mascotes" }], body, { icon: sp.art });
  }

  function huntPage() {
    const P = D.pets;
    const H = P.hunt;
    const hours = (sec) => n(sec / 3600) + " h";
    const wheel = H.wheel.map((id) => elementTag(id)).join(" › ") + " › " + elementTag(H.wheel[0]);
    const pass = D.cosmetics.find((c) => c.id === "passe_cacador");
    const R = H.reward;
    const body = `
      <p class="intro">${T("Um modo automático da Casa dos Mascotes: o time luta sozinho, o jogador coleta. A cada encontro o time enfrenta selvagens do elemento da zona, mesmo com o jogo fechado.",
        "An automatic mode of the Pet House: the team fights on its own and you collect. Every encounter the team faces wild pets of the zone's element, even with the game closed.")}</p>
      <div class="kv">
        <div><span>${T("Um encontro a cada", "One encounter every")}</span><b>${H.cycle} s</b></div>
        <div><span>${T("Time", "Team")}</span><b>1–${H.team_max}</b></div>
        <div><span>${T("Níveis de caça", "Hunt levels")}</span><b>${H.tiers}</b></div>
        <div><span>${T("Acumula até", "Stores up to")}</span><b>${hours(H.cap_free)}</b></div>
        <div><span>${T("Com o Passe", "With the Pass")}</span><b>${hours(H.cap_pass)}</b></div>
      </div>
      <h2>${T("Como se joga", "How to play")}</h2>
      <ol>
        <li>${T("Na aba <b>Caçada</b> escolha a <b>zona</b>, o <b>nível de caça</b> e o <b>time</b> (de 1 a " + H.team_max + " mascotes) e toque em <b>INICIAR CAÇADA</b>.", "On the <b>Hunt</b> tab pick the <b>zone</b>, the <b>hunt level</b> and the <b>team</b> (1 to " + H.team_max + " pets) and tap <b>START HUNT</b>.")}</li>
        <li>${T(`O tempo acumula até ${hours(H.cap_free)} (ou ${hours(H.cap_pass)} com o Passe do Caçador). O que passa disso se perde.`, `Time stores up to ${hours(H.cap_free)} (or ${hours(H.cap_pass)} with the Hunter Pass). Anything beyond that is lost.`)}</li>
        <li>${T("<b>COLETAR</b> entrega moedas, XP para cada mascote do time e os mascotes capturados (só Comuns e Raros). A Caçada é o único lugar onde o mascote sobe de nível.", "<b>COLLECT</b> hands over gold, XP for every pet in the team and the captured pets (Commons and Rares only). The Hunt is the only place where a pet levels up.")}</li>
        <li>${T(`Cada nível de caça abre depois de ${H.unlock_wins} vitórias no nível anterior, por zona.`, `Each hunt level unlocks after ${H.unlock_wins} wins on the previous one, per zone.`)}</li>
      </ol>

      <h2>${T("Zonas", "Zones")}</h2>
      <div class="cards-grid">${H.zones.map((z) => `<a class="zone-card" href="#/mascotes/${z.element}" style="--zc:#${petElementById(z.element).color}">
        <img src="${esc(img(z.bg))}" alt="" loading="lazy"><div><b>${esc(L(z.name))}</b><span>${elementTag(z.element)}</span></div></a>`).join("")}</div>

      <h2>${T("Como a luta funciona", "How fights work")}</h2>
      <ul>
        <li>${T("Por turnos e automática: a velocidade define a ordem e cada ação ataca um inimigo vivo sorteado.", "Turn-based and automatic: speed sets the order and each action hits a random living enemy.")}</li>
        <li>${T(`A cada ${H.skill_every}ª ação o mascote usa a habilidade do elemento. Crítico de ${pct(H.crit.base)} (×${GF.num(H.crit.mult, 1)}). No máximo ${H.rounds_max} rodadas: empate conta como derrota. O time se cura entre encontros.`, `Every ${H.skill_every}rd action the pet uses its element's skill. ${pct(H.crit.base)} crit chance (×${GF.num(H.crit.mult, 1)}). At most ${H.rounds_max} rounds: a draw counts as a loss. The team heals between encounters.`)}</li>
        <li>${T(`<b>Roda de elementos</b>: ${wheel}. Vantagem ×${GF.num(H.wheel_bonus, 1)}, desvantagem ×${GF.num(H.wheel_penalty, 1)}.`, `<b>Element wheel</b>: ${wheel}. Advantage ×${GF.num(H.wheel_bonus, 1)}, disadvantage ×${GF.num(H.wheel_penalty, 1)}.`)}</li>
        <li>${T(`Os selvagens ganham +${pct(H.wild_scale)} de vida, ataque e defesa por nível de caça.`, `Wild pets gain +${pct(H.wild_scale)} HP, attack and defense per hunt level.`)}</li>
      </ul>
      ${table(["", [T("Elemento", "Element"), "text"], [T("Habilidade", "Skill"), "text"], T("Efeito", "Effect")],
        P.elements.map((el) => { const sk = H.skills[el.id]; const text = sk.heal ? T(`Cura ${pct(sk.heal)} da vida de todos`, `Heals ${pct(sk.heal)} of everyone's HP`) : sk.buff ? T(`+${pct(sk.buff)} de ataque ao time por ${sk.rounds} rodadas`, `+${pct(sk.buff)} attack to the team for ${sk.rounds} rounds`) : el.id === "mascara" ? T(`Dois golpes de ×${GF.num(sk.mult, 1)}`, `Two hits of ×${GF.num(sk.mult, 1)}`) : el.id === "ceu" ? T(`Todos os inimigos levam ×${GF.num(sk.mult, 1)}`, `Hits every enemy for ×${GF.num(sk.mult, 1)}`) : T(`Golpe de ×${GF.num(sk.mult, 1)}`, `Hit of ×${GF.num(sk.mult, 1)}`); return `<tr>${td(icon(el.icon))}${td(`<b style="color:#${el.color}">${esc(L(el.name))}</b>`)}${td(esc(L(sk.name)))}${td(text)}</tr>`; }))}

      <h2>${T("Selvagens e o Lendário da zona", "Wild pets and the zone's Legendary")}</h2>
      <ul>
        <li>${T(`Cada encontro tem 1, 2 ou 3 selvagens (${H.group_weights.map((v) => v + "%").join(" / ")}). Raridade ${H.wild_rarity.map((v) => v + "%").join(" / ")} (Comum / Raro / Épico); o nível de caça empurra para Raros e Épicos.`, `Each encounter has 1, 2 or 3 wild pets (${H.group_weights.map((v) => v + "%").join(" / ")}). Rarity ${H.wild_rarity.map((v) => v + "%").join(" / ")} (Common / Rare / Epic); a higher hunt level pushes toward Rares and Epics.`)}</li>
        <li>${T(`O <b>Lendário</b> da zona (vida ×${GF.num(H.boss.hp, 0)}, ataque ×${GF.num(H.boss.atk, 2)}) aparece sozinho com ${GF.num(H.boss.chance * 100, 2)}% por encontro, sem garantia. Vencê-lo rende bastante XP e moedas, mas ele <b>não é capturado</b>.`, `The zone's <b>Legendary</b> (HP ×${GF.num(H.boss.hp, 0)}, attack ×${GF.num(H.boss.atk, 2)}) shows up alone with ${GF.num(H.boss.chance * 100, 2)}% per encounter, with no guarantee. Beating it pays a lot of XP and gold, but it <b>cannot be caught</b>.`)}</li>
      </ul>

      <h2>${T("Recompensas", "Rewards")}</h2>
      ${table([T("Selvagem", "Wild pet"), [T("XP (nível 1)", "XP (level 1)"), "num"], [T("Moedas (nível 1)", "Gold (level 1)"), "num"], [T("Captura", "Capture"), "num"]],
        [0, 1, 2, 3].map((i) => { const r = P.rarities[i]; const key = r.id; const cap = H.capture[key] || 0; return `<tr>${td(rarityTag(key))}${tdn(R.xp_base * R.xp_rarity[i], "≈ " + GF.num((R.xp_base + R.xp_per_level) * R.xp_rarity[i], 1))}${tdn(R.coin_per_level * R.coin_rarity[i], "≈ " + GF.num(R.coin_per_level * R.coin_rarity[i], 2))}${tdn(cap, cap > 0 ? GF.num(cap * 100, 2) + "%" : "—")}</tr>`; }))}
      <p>${T(`Só Comuns e Raros são capturados (Épicos, Lendários e o chefe da zona nunca), e a chance sobe ${pct(H.capture.per_tier)} por nível de caça. Só as primeiras 2 horas de cada coleta rolam captura. Capturas entram no nível 1; com a Casa cheia viram moedas. Não há ovos.`, `Only Commons and Rares are caught (never Epics, Legendaries or the zone's boss), and the chance rises ${pct(H.capture.per_tier)} per hunt level. Only the first 2 hours of each collection roll for a catch. Catches arrive at level 1; with a full House they turn into gold. There are no eggs.`)}</p>

      <h2>${T("Passe do Caçador", "Hunter Pass")}</h2>
      <p>${pass ? `${icon(pass.icon, "inline-ico")} ` : ""}${T(`Um item de conveniência da loja: a Caçada passa a acumular até ${hours(H.cap_pass)} parado, em vez de ${hours(H.cap_free)}. <b>Os mascotes não ficam mais fortes por isso</b>: só dá para coletar menos vezes, e as horas extras rendem moedas e XP, nunca mais capturas.`, `A shop convenience item: the Hunt stores up to ${hours(H.cap_pass)} while idle instead of ${hours(H.cap_free)}. <b>Pets do not get stronger because of it</b>: you just collect less often, and the extra hours earn gold and XP, never more catches.`)} <a href="#/loja">${T("Ver na loja", "See in the shop")}</a>.</p>`;
    return page(T("Caçada dos Mascotes", "Pet Hunt"), [], body, { icon: P.species.find((x) => x.rarity === "raro").art });
  }

  // ---------- router ----------

  const ROUTES = {
    "": () => home(),
    guia: (id) => guide(id || "primeiros-passos"),
    armas: (id, filter) => (id && byId(D.weapons, id) ? weaponPage(id) : weaponsList(filter || id)),
    qualidades: () => qualities(),
    fortalecimento: () => strengthen(),
    bonus: () => affixes(),
    visual: (id) => cosmetics(id),
    habilidades: (id) => skills(id),
    ferramentas: (id) => tools(id),
    auxiliares: (id) => auxiliary(id),
    efeitos: (id) => statuses(id),
    instancias: (id) => (id ? instancePage(id) : instancesList()),
    monstros: (id) => (id ? monsterPage(id) : monstersList()),
    mapas: () => mapItems(),
    arenas: (id) => arenas(id),
    moedas: (id) => currencies(id),
    mascotes: (id) => (id && byId(D.pets.species, id) ? petPage(id) : petsHome(id)),
    cacada: () => huntPage(),
    leilao: () => auction(),
    recompensas: () => rewards(),
    loja: () => store(),
    conquistas: () => achievements(),
  };

  function currentPath() {
    return decodeURIComponent(location.hash.replace(/^#\/?/, "")).replace(/\/$/, "");
  }

  function render(path, extra) {
    const keepScroll = extra === "keep-scroll" || (extra != null && extra !== "keep-scroll");
    if (extra === "keep-scroll") extra = undefined;
    path = path == null ? currentPath() : path;
    const [section, id] = path.split("/");
    const route = ROUTES[section] || notFound;
    const result = route(id, extra);
    renderNav(path);
    const crumbs = result.crumbs.map((c, i) => (i === 0 ? `<a href="${c.href}">${esc(c.label())}</a>` : `<span><a href="${c.href}">${esc(c.label())}</a></span>`)).join("")
      + (result.crumbs.length && path ? `<span>${esc(result.title)}</span>` : "");
    const title = result.bare ? "" : `<h1>${result.icon ? `<img src="${esc(img(result.icon))}" alt="">` : ""}${esc(result.title)}</h1>`;
    $("page").innerHTML = `${path ? `<nav class="crumbs">${crumbs}</nav>` : ""}${title}${result.body}
      <p class="updated">${T(`Dados da versão ${esc(D.meta.version)} do jogo, gerados em ${esc(D.meta.built)}.`, `Data from game version ${esc(D.meta.version)}, generated on ${esc(D.meta.built)}.`)}</p>`;
    document.title = `${result.title} · ${T("Wiki do Gustfire", "Gustfire Wiki")}`;
    setupTables();
    if (result.after) result.after();
    if (result.focus) {
      const row = document.getElementById("row-" + result.focus);
      if (row) {
        row.scrollIntoView({ block: "center" });
        row.animate([{ background: "rgba(255,207,74,.35)" }, { background: "transparent" }], { duration: 1800 });
      }
    } else if (!keepScroll) window.scrollTo(0, 0);
    document.body.classList.remove("menu-open");
  }

  // ---------- sortable tables ----------

  function setupTables() {
    document.querySelectorAll("table[data-sortable]").forEach((tableEl) => {
      tableEl.querySelectorAll("th[data-sort]").forEach((th) => {
        th.addEventListener("click", () => {
          const index = [...th.parentNode.children].indexOf(th);
          const dir = th.getAttribute("aria-sort") === "ascending" ? -1 : 1;
          tableEl.querySelectorAll("th").forEach((h) => h.removeAttribute("aria-sort"));
          th.setAttribute("aria-sort", dir === 1 ? "ascending" : "descending");
          const numeric = th.dataset.sort === "num";
          const body = tableEl.tBodies[0];
          const rows = [...body.rows];
          const key = (row) => {
            const cell = row.cells[index];
            const raw = cell.dataset.v != null ? cell.dataset.v : cell.textContent.trim();
            return numeric ? parseFloat(raw) || 0 : raw.toLowerCase();
          };
          rows.sort((a, b) => (key(a) > key(b) ? dir : key(a) < key(b) ? -dir : 0));
          rows.forEach((row) => body.appendChild(row));
        });
      });
    });
  }

  // ---------- search ----------

  const fold = (text) => String(text).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  let index = [];

  function buildIndex() {
    const list = [];
    const add = (label, type, href, iconSrc, extra) => list.push({ label, type, href, icon: iconSrc, key: fold(label + " " + (extra || "")) });
    nav().forEach((g) => g.items.forEach(([route, label, ico]) => route && add(label, T("Página", "Page"), "#/" + route, ico)));
    D.weapons.forEach((w) => {
      add(L(w.name), w.super ? T("Super Verdadeira", "Super True") : T("Arma", "Weapon"), `#/armas/${w.id}`, w.super ? w.tiers[3] : w.icon, w.name.pt + " " + w.name.en);
      add(L(w.pow.name), "POW · " + L(w.name), `#/armas/${w.id}`, w.pow.art || w.icon, w.pow.name.pt + " " + w.pow.name.en);
    });
    D.enemies.forEach((e) => {
      add(L(e.name), rankName(e.rank), `#/monstros/${e.id}`, e.sprite, e.name.pt + " " + e.name.en);
      e.abilities.forEach((a) => add(L(a.name), T("Habilidade de ", "Ability of ") + L(e.name), `#/monstros/${e.id}`, e.sprite, a.name.pt + " " + a.name.en));
    });
    D.instances.forEach((i) => {
      add(L(i.name), T("Instância", "Dungeon"), `#/instancias/${i.id}`, i.map_icon, i.name.pt + " " + i.name.en);
      i.phases.forEach((p) => add(L(p.name), T("Fase de ", "Phase of ") + L(i.name), `#/instancias/${i.id}`, i.map_icon, p.name.pt + " " + p.name.en));
    });
    D.currencies.forEach((c) => add(L(c.name), T("Moeda de criação", "Crafting currency"), `#/moedas/${c.id}`, c.icon, c.name.pt + " " + c.name.en));
    D.pets.species.forEach((sp) => add(L(sp.name), T("Mascote · ", "Pet · ") + L(petElement(sp).name), `#/mascotes/${sp.id}`, sp.art, sp.name.pt + " " + sp.name.en));
    D.pets.elements.forEach((el) => add(L(el.name), T("Elemento dos mascotes", "Pet element"), "#/mascotes", el.icon, el.name.pt + " " + el.name.en));
    D.pets.hunt.zones.forEach((z) => add(L(z.name), T("Zona da Caçada", "Hunt zone"), "#/cacada", petElementById(z.element).icon, z.name.pt + " " + z.name.en));
    D.cosmetics.forEach((c) => add(L(c.name), L(c.slot_name), `#/visual/${c.id}`, c.icon, c.name.pt + " " + c.name.en));
    D.skills.forEach((s) => add(L(s.name), T("Habilidade ", "Skill ") + s.key, `#/habilidades/${s.id}`, s.icon, s.name.pt + " " + s.name.en));
    D.tools.forEach((t) => add(L(t.name), T("Ferramenta", "Tool"), `#/ferramentas/${t.id}`, t.icon, t.name.pt + " " + t.name.en));
    D.auxiliary.forEach((a) => add(L(a.name), T("Item auxiliar", "Support item"), `#/auxiliares/${a.id}`, a.icon, a.name.pt + " " + a.name.en));
    D.statuses.forEach((s) => add(L(s.name), T("Efeito de estado", "Status effect"), `#/efeitos/${s.id}`, s.icon, s.name.pt + " " + s.name.en + " " + s.label.pt + " " + s.label.en));
    D.elites.affixes.forEach((a) => add(L(a.name), T("Elite", "Elite"), "#/efeitos", a.icon, a.name.pt + " " + a.name.en));
    D.arenas.forEach((a) => add(L(a.name), T("Arena", "Arena"), `#/arenas/${a.id}`, a.thumb, a.name.pt + " " + a.name.en));
    D.achievements.forEach((a) => add(L(a.name), T("Conquista", "Achievement"), "#/conquistas", a.icon, a.name.pt + " " + a.name.en));
    D.strengthen.stones.forEach((s) => add(L(s.name), T("Pedra", "Stone"), "#/fortalecimento", s.icon, s.name.pt + " " + s.name.en));
    Object.entries(GF.GUIDES || {}).forEach(([slug, g]) => add(L(g.title), T("Guia", "Guide"), `#/guia/${slug}`, g.icon ? g.icon(D) : D.icons.help, (g.keywords || "")));
    index = list;
  }

  let hits = [];
  let active = 0;

  function search(query) {
    const box = $("results");
    const q = fold(query.trim());
    if (!q) {
      box.hidden = true;
      $("search").setAttribute("aria-expanded", "false");
      return;
    }
    const words = q.split(/\s+/);
    hits = index.map((item) => {
      const label = fold(item.label);
      if (!words.every((w) => item.key.includes(w))) return null;
      const score = (label.startsWith(q) ? 0 : label.includes(q) ? 1 : 2) + item.label.length / 100;
      return { item, score };
    }).filter(Boolean).sort((a, b) => a.score - b.score).slice(0, 14).map((h) => h.item);
    active = 0;
    const mark = (label) => {
      const f = fold(label);
      const at = f.indexOf(words[0]);
      if (at < 0) return esc(label);
      return esc(label.slice(0, at)) + "<mark>" + esc(label.slice(at, at + words[0].length)) + "</mark>" + esc(label.slice(at + words[0].length));
    };
    box.innerHTML = hits.length ? hits.map((h, i) => `<a href="${h.href}" role="option" class="${i === 0 ? "on" : ""}">${h.icon ? `<img src="${esc(img(h.icon))}" alt="">` : "<span></span>"}<span>${mark(h.label)}</span><small>${esc(h.type)}</small></a>`).join("")
      : `<div class="empty">${T("Nada encontrado.", "Nothing found.")}</div>`;
    box.hidden = false;
    $("search").setAttribute("aria-expanded", "true");
  }

  function setupSearch() {
    const input = $("search");
    const box = $("results");
    input.addEventListener("input", () => search(input.value));
    input.addEventListener("focus", () => input.value && search(input.value));
    input.addEventListener("keydown", (e) => {
      const links = [...box.querySelectorAll("a")];
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault();
        if (!links.length) return;
        active = (active + (e.key === "ArrowDown" ? 1 : -1) + links.length) % links.length;
        links.forEach((a, i) => a.classList.toggle("on", i === active));
        links[active].scrollIntoView({ block: "nearest" });
      } else if (e.key === "Enter" && links[active]) {
        location.hash = links[active].getAttribute("href");
        closeSearch();
      } else if (e.key === "Escape") closeSearch();
    });
    box.addEventListener("click", (e) => {
      if (e.target.closest("a")) closeSearch();
    });
    document.addEventListener("click", (e) => {
      if (!e.target.closest(".search")) box.hidden = true;
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "/" && document.activeElement !== input && !/input|textarea/i.test(document.activeElement.tagName)) {
        e.preventDefault();
        input.focus();
        input.select();
      }
    });
    function closeSearch() {
      box.hidden = true;
      input.value = "";
      input.blur();
      $("search").setAttribute("aria-expanded", "false");
    }
  }

  // ---------- hover cards ----------

  function setupTips() {
    if (!window.matchMedia("(hover: hover)").matches) return;
    const tip = $("tip");
    let current = null;
    document.addEventListener("mouseover", (e) => {
      const el = e.target.closest("[data-tip]");
      if (!el || el === current) return;
      current = el;
      const [kind, id] = el.dataset.tip.split(":");
      const html = tipFor(kind, id);
      if (!html) return;
      tip.innerHTML = html;
      tip.hidden = false;
      place(e);
    });
    document.addEventListener("mousemove", (e) => {
      if (!tip.hidden) place(e);
    });
    document.addEventListener("mouseout", (e) => {
      const el = e.target.closest("[data-tip]");
      if (el && !el.contains(e.relatedTarget)) {
        current = null;
        tip.hidden = true;
      }
    });
    window.addEventListener("hashchange", () => {
      current = null;
      tip.hidden = true;
    });
    function place(e) {
      const w = tip.offsetWidth;
      const h = tip.offsetHeight;
      let x = e.clientX + 18;
      let y = e.clientY + 18;
      if (x + w > innerWidth - 8) x = e.clientX - w - 18;
      if (y + h > innerHeight - 8) y = Math.max(8, innerHeight - h - 8);
      tip.style.left = x + "px";
      tip.style.top = y + "px";
    }
  }

  // ---------- helpers for the guides ----------

  const helpers = { ref, icon, table, td, tdn, n, pct, mult, T, esc, img, byId, attrName, L };

  let started = false;

  function start() {
    started = true;
    buildIndex();
    render();
    setupSearch();
    setupTips();
    window.addEventListener("hashchange", () => render());
    $("menu-btn").addEventListener("click", () => document.body.classList.toggle("menu-open"));
  }

  document.addEventListener("gf:lang", () => {
    if (!started) return;
    buildIndex();
    render(null, "keep-scroll");
  });
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
