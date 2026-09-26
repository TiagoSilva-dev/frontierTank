/* Shared by the landing page and the wiki: language, navigation, play links, helpers. */
(function () {
  "use strict";
  const GF = (window.GF = window.GF || {});
  const STORE_KEY = "gf-lang";
  const originals = new Map();
  const attrOriginals = new Map();

  GF.config = Object.assign({ playUrl: "/jogar/", steamUrl: "" }, window.GF_CONFIG || {});
  GF.data = window.GF_DATA || {};
  GF.root = document.documentElement.dataset.root || "";

  function detectLang() {
    const query = new URLSearchParams(location.search).get("lang");
    if (query === "pt" || query === "en") return query;
    try {
      const saved = localStorage.getItem(STORE_KEY);
      if (saved === "pt" || saved === "en") return saved;
    } catch (error) { /* storage blocked: follow the browser */ }
    return (navigator.language || "pt").toLowerCase().startsWith("pt") ? "pt" : "en";
  }
  GF.lang = detectLang();

  /** A {pt, en} text from the game data (or a plain string) in the current language. */
  GF.L = function (text) {
    if (text == null) return "";
    if (typeof text === "string") return text;
    return text[GF.lang] != null ? text[GF.lang] : text.pt;
  };
  /** A site string by key; Portuguese strings of static pages come from the page itself. */
  GF.t = function (key, vars) {
    const table = (GF.I18N && GF.I18N[GF.lang]) || {};
    let text = table[key];
    if (text == null) text = ((GF.I18N && GF.I18N.pt) || {})[key];
    if (text == null) text = key;
    if (vars) text = text.replace(/\{(\w+)\}/g, (m, name) => (vars[name] != null ? vars[name] : m));
    return text;
  };
  GF.num = function (value, digits) {
    const locale = GF.lang === "pt" ? "pt-BR" : "en-US";
    return Number(value).toLocaleString(locale, { maximumFractionDigits: digits == null ? 2 : digits });
  };
  GF.img = function (path) {
    return path ? GF.root + path : "";
  };
  GF.esc = function (text) {
    return String(text == null ? "" : text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  };

  function translateStatic() {
    const en = (GF.I18N && GF.I18N.en) || {};
    const pt = (GF.I18N && GF.I18N.pt) || {};
    document.querySelectorAll("[data-i18n], [data-i18n-html]").forEach((el) => {
      const html = el.hasAttribute("data-i18n-html");
      const key = el.getAttribute(html ? "data-i18n-html" : "data-i18n");
      if (!originals.has(el)) originals.set(el, html ? el.innerHTML : el.textContent);
      let value = GF.lang === "en" ? en[key] : pt[key];
      if (value == null) value = GF.lang === "pt" ? originals.get(el) : value;
      if (value == null) return;
      if (html) el.innerHTML = value;
      else el.textContent = value;
    });
    document.querySelectorAll("[data-i18n-attr]").forEach((el) => {
      el.getAttribute("data-i18n-attr").split(";").forEach((pair) => {
        const [attr, key] = pair.split(":");
        if (!attrOriginals.has(el)) attrOriginals.set(el, {});
        const saved = attrOriginals.get(el);
        if (!(attr in saved)) saved[attr] = el.getAttribute(attr) || "";
        const value = GF.lang === "en" ? en[key] : pt[key] || saved[attr];
        if (value != null) el.setAttribute(attr, value);
      });
    });
  }

  function updatePlayLinks() {
    document.querySelectorAll("[data-play]").forEach((link) => {
      const url = GF.config.playUrl || "#";
      link.href = url + (url.includes("?") ? "&" : "?") + "lang=" + GF.lang;
    });
  }

  GF.setLang = function (lang, persist) {
    if (lang !== "pt" && lang !== "en") return;
    GF.lang = lang;
    if (persist) {
      try { localStorage.setItem(STORE_KEY, lang); } catch (error) { /* private mode */ }
    }
    document.documentElement.lang = lang === "pt" ? "pt-BR" : "en";
    document.querySelectorAll("[data-lang]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.lang === lang)));
    translateStatic();
    updatePlayLinks();
    document.dispatchEvent(new CustomEvent("gf:lang", { detail: lang }));
  };

  function setupNav() {
    const nav = document.getElementById("nav");
    if (!nav) return;
    const onScroll = () => nav.classList.toggle("solid", window.scrollY > 40);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    const toggle = nav.querySelector(".nav-toggle");
    if (toggle) {
      toggle.addEventListener("click", () => {
        const open = !nav.classList.contains("open");
        nav.classList.toggle("open", open);
        toggle.setAttribute("aria-expanded", String(open));
      });
      nav.querySelectorAll(".nav-links a").forEach((link) => link.addEventListener("click", () => {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      }));
    }
    document.querySelectorAll("[data-lang]").forEach((button) => button.addEventListener("click", () => GF.setLang(button.dataset.lang, true)));
  }

  GF.reveal = function (root) {
    const items = (root || document).querySelectorAll(".reveal:not(.in)");
    if (!("IntersectionObserver" in window)) {
      items.forEach((el) => el.classList.add("in"));
      return;
    }
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: "0px 0px -8% 0px" });
    items.forEach((el) => observer.observe(el));
  };

  GF.start = function () {
    setupNav();
    GF.setLang(GF.lang, false);
    GF.reveal();
    const year = document.getElementById("year");
    if (year) year.textContent = String(new Date().getFullYear());
    const version = document.getElementById("version");
    if (version && GF.data.meta) version.textContent = GF.t("footer.version", { v: GF.data.meta.version });
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", GF.start);
  else setTimeout(GF.start, 0);
})();
