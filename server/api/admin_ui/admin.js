// Gustfire · Painel da equipe. Sem build e sem bibliotecas: este arquivo é embutido na API.
// Todo texto que vem do servidor entra no DOM por textContent (h() abaixo), nunca por HTML:
// nomes de jogador, mensagens de chat e motivos são dados de terceiros.
'use strict';
(() => {
  const RANK = { viewer: 1, support: 2, admin: 3, owner: 4 };
  const ROLE_NAME = { viewer: 'Visualizador', support: 'Suporte', admin: 'Administrador', owner: 'Dono' };
  const state = { me: null, csrf: '', catalog: null, cleanup: null, overview: null };
  const can = (role) => !!state.me && RANK[state.me.admin.role] >= RANK[role];

  // ---------- DOM ----------

  function append(el, kids) {
    for (const kid of kids.flat(Infinity)) {
      if (kid == null || kid === false) continue;
      el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    }
    return el;
  }

  function h(tag, props, ...kids) {
    const el = document.createElement(tag);
    for (const [key, value] of Object.entries(props || {})) {
      if (value == null || value === false) continue;
      if (key === 'class') el.className = value;
      else if (key.startsWith('on')) el.addEventListener(key.slice(2), value);
      else if (key === 'for') el.setAttribute('for', value);
      else if (key in el && key !== 'list') el[key] = value;
      else el.setAttribute(key, value === true ? '' : value);
    }
    return append(el, kids);
  }

  const SVG = 'http://www.w3.org/2000/svg';
  function svg(tag, props, ...kids) {
    const el = document.createElementNS(SVG, tag);
    for (const [key, value] of Object.entries(props || {})) el.setAttribute(key, value);
    return append(el, kids);
  }

  // ---------- formatting ----------

  const nf = new Intl.NumberFormat('pt-BR');
  const num = (n) => nf.format(Math.round(Number(n) || 0));
  const dateFormat = new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo' });
  const when = (iso) => (iso ? dateFormat.format(new Date(iso)) : '—');
  function ago(iso) {
    if (!iso) return '—';
    const seconds = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
    if (seconds < 90) return 'agora há pouco';
    if (seconds < 5400) return `há ${Math.round(seconds / 60)} min`;
    if (seconds < 129600) return `há ${Math.round(seconds / 3600)} h`;
    return `há ${Math.round(seconds / 86400)} dias`;
  }
  function money(cents, currency) {
    try {
      return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: currency || 'BRL' }).format((cents || 0) / 100);
    } catch (e) {
      return `${((cents || 0) / 100).toFixed(2)} ${currency || ''}`;
    }
  }
  const bytes = (n) => (n > 1048576 ? `${(n / 1048576).toFixed(1)} MB` : `${Math.max(1, Math.round(n / 1024))} KB`);
  const day = (iso) => String(iso).slice(8, 10) + '/' + String(iso).slice(5, 7);
  const short = (text, max) => (text && text.length > max ? text.slice(0, max - 1) + '…' : text || '');
  const qs = (params) => {
    const out = new URLSearchParams();
    for (const [key, value] of Object.entries(params)) if (value !== '' && value != null) out.set(key, value);
    const text = out.toString();
    return text ? '?' + text : '';
  };
  const requestId = () => 'r' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);

  // ---------- API ----------

  async function api(method, path, body) {
    const options = { method, headers: {}, credentials: 'same-origin' };
    if (body !== undefined || method !== 'GET') options.headers['Content-Type'] = 'application/json';
    if (body !== undefined) options.body = JSON.stringify(body);
    if (state.csrf) options.headers['X-CSRF-Token'] = state.csrf;
    const response = await fetch('/admin/api' + path, options);
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch (e) { /* not JSON */ }
    if (!response.ok) {
      const error = new Error((data && data.message) || `Erro ${response.status}`);
      error.status = response.status;
      error.code = data && data.error;
      if (response.status === 401 && path !== '/login' && state.me) {
        state.me = null;
        state.csrf = '';
        route();
      }
      throw error;
    }
    return data;
  }

  // ---------- small components ----------

  function toast(message, kind) {
    const box = document.getElementById('toasts') || document.body.appendChild(h('div', { id: 'toasts', 'aria-live': 'polite' }));
    const item = h('div', { class: 'toast ' + (kind || ''), role: 'status' }, message);
    box.append(item);
    setTimeout(() => item.remove(), kind === 'bad' ? 9000 : 4500);
  }
  const fail = (error) => toast(error.message || 'Algo deu errado.', 'bad');

  // Situations and kinds the API sends as codes.
  const WORDS = { active: 'à venda', sold: 'vendido', cancelled: 'cancelado', expired: 'vencido', open: 'aberta', dismissed: 'descartada', warned: 'avisado', banned: 'banido',
    gift: 'presente', sale: 'venda', purchase: 'compra', returned: 'devolvido', store: 'loja', exchange_fill: 'câmbio', exchange_return: 'câmbio (saldo)' };
  const tr = (code) => WORDS[code] || code;
  const badge = (text, kind) => h('span', { class: 'badge ' + (kind || '') }, text);
  const link = (href, text) => h('a', { href }, text);
  const playerLink = (id, name) => (id ? link('#/players/' + id, name || '#' + id) : h('span', { class: 'muted' }, name || '—'));

  function kpi(label, value, sub, kind, href) {
    const inner = [h('div', { class: 'label' }, label), h('div', { class: 'value' + (String(value).length > 8 ? ' long' : '') }, value), sub ? h('div', { class: 'sub' }, sub) : null];
    return h('div', { class: 'kpi ' + (kind || '') }, href ? h('a', { href }, inner) : inner);
  }

  function dataTable(columns, rows, options) {
    const opts = options || {};
    if (!rows || rows.length === 0) return h('div', { class: 'empty' }, opts.empty || 'Nada por aqui.');
    const head = h('tr', {}, columns.map((c) => h('th', { scope: 'col', class: c.class }, c.title)));
    const body = rows.map((row) => {
      const tr = h('tr', { class: opts.onRow ? 'link' : '' }, columns.map((c) => h('td', { class: c.class }, c.render(row))));
      if (opts.onRow) {
        tr.tabIndex = 0;
        tr.addEventListener('click', (event) => { if (!event.target.closest('a,button,summary,details')) opts.onRow(row); });
        tr.addEventListener('keydown', (event) => { if (event.key === 'Enter') opts.onRow(row); });
      }
      return tr;
    });
    return h('div', { class: 'table-wrap' }, h('table', {}, h('thead', {}, head), h('tbody', {}, body)));
  }

  function pager(page, perPage, total, go) {
    const pages = Math.max(1, Math.ceil(total / perPage));
    return h('div', { class: 'pager' },
      h('span', {}, `${num(total)} resultado(s) · página ${page + 1} de ${pages}`),
      h('button', { class: 'small', disabled: page <= 0, onclick: () => go(page - 1) }, '← Anterior'),
      h('button', { class: 'small', disabled: page + 1 >= pages, onclick: () => go(page + 1) }, 'Próxima →'));
  }

  function pageTitle(title, sub, ...actions) {
    return h('div', { class: 'top' }, h('div', { class: 'grow' }, h('h1', {}, title), sub ? h('div', { class: 'muted small' }, sub) : null), ...actions);
  }

  const jsonBox = (value) => h('pre', { class: 'json mono' }, JSON.stringify(value, null, 2));
  const detailsJson = (value, label) => h('details', {}, h('summary', { class: 'muted small' }, label || 'detalhes'), jsonBox(value));

  function barChart(points, label, cls, format) {
    const W = 420, H = 130, top = 16, bottom = 18;
    const fmt = format || num;
    const max = Math.max(1, ...points.map((p) => p.v));
    const slot = (W - 12) / Math.max(1, points.length);
    const chart = svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'chart', role: 'img', 'aria-label': `${label}: ${points.map((p) => `${p.l} ${fmt(p.v)}`).join(', ')}` });
    points.forEach((p, i) => {
      const height = (H - top - bottom) * (p.v / max);
      chart.append(svg('rect', { class: 'bar ' + (cls || ''), x: 6 + i * slot + 2, y: H - bottom - height, width: Math.max(2, slot - 4), height: p.v > 0 ? Math.max(1, height) : 0 }, svg('title', {}, `${p.l}: ${fmt(p.v)}`)));
      if (i % 2 === points.length % 2) chart.append(svg('text', { x: 6 + i * slot + slot / 2, y: H - 4, 'text-anchor': 'middle' }, p.l));
    });
    chart.append(svg('line', { class: 'axis', x1: 6, x2: W - 6, y1: H - bottom, y2: H - bottom }), svg('text', { x: 6, y: 10 }, `máx. ${fmt(max)}`));
    return chart;
  }

  // ---------- dialogs ----------

  // A form in a <dialog>. `build` returns the fields (nodes); `run(form)` does the work: if it
  // throws, the message stays in the dialog. `after(result)` may return a node shown in place
  // of the form (a temporary password, shown once).
  function dialogForm({ title, intro, fields, submit, danger, run, after }) {
    return new Promise((resolve) => {
      const dialog = h('dialog', { 'aria-labelledby': 'dlg-title' });
      const errorLine = h('p', { class: 'error', role: 'alert', hidden: true });
      const send = h('button', { class: danger ? 'danger' : 'primary', type: 'submit' }, submit || 'Confirmar');
      const cancel = h('button', { type: 'button', class: 'ghost', onclick: () => dialog.close() }, 'Cancelar');
      const form = h('form', { method: 'dialog' }, intro ? h('p', { class: 'muted' }, intro) : null, fields, errorLine, h('div', { class: 'actions' }, cancel, send));
      form.addEventListener('submit', async (event) => {
        event.preventDefault();
        if (!form.reportValidity()) return;
        send.disabled = true;
        errorLine.hidden = true;
        try {
          const result = await run(new FormData(form), form);
          const shown = after ? after(result) : null;
          if (shown) {
            dialog.replaceChildren(h('h2', {}, title), shown, h('div', { class: 'actions' }, h('button', { class: 'primary', onclick: () => dialog.close() }, 'Fechar')));
            resolve(true);
          } else {
            dialog.close();
            resolve(true);
          }
        } catch (error) {
          errorLine.textContent = error.message;
          errorLine.hidden = false;
          send.disabled = false;
        }
      });
      dialog.append(h('h2', { id: 'dlg-title' }, title), form);
      dialog.addEventListener('close', () => { dialog.remove(); resolve(false); });
      document.body.append(dialog);
      dialog.showModal();
      const first = dialog.querySelector('input,textarea,select');
      if (first) first.focus();
    });
  }

  function field(label, input, hint) {
    const id = 'f' + Math.random().toString(36).slice(2, 8);
    input.id = id;
    return h('div', { class: 'field' }, h('label', { for: id }, label), input, hint ? h('div', { class: 'hint' }, hint) : null);
  }
  const reasonField = (label, hint) => field(label || 'Motivo (fica no registro da equipe)', h('textarea', { name: 'reason', required: true, minLength: 3, maxLength: 300 }), hint);

  // The gift: coins plus a few currencies or stones from the catalog.
  function giftEditor(caps) {
    const rows = h('div', { class: 'stack' });
    const coins = h('input', { type: 'number', name: 'coins', min: 0, max: caps.coins, value: 0 });
    const options = (state.catalog ? state.catalog.assets : []).map((a) => h('option', { value: a.id }, `${a.name} (${a.id})`));
    const addRow = () => {
      const row = h('div', { class: 'row' },
        h('select', { 'aria-label': 'Moeda ou pedra', class: 'asset' }, options.map((o) => o.cloneNode(true))),
        h('input', { type: 'number', min: 1, max: caps.asset, value: 1, 'aria-label': 'Quantidade', class: 'amount', style: 'width:110px' }),
        h('button', { type: 'button', class: 'small ghost', onclick: () => row.remove() }, 'Remover'));
      rows.append(row);
    };
    const node = h('div', {}, field('Moedas do jogo', coins, `Até ${num(caps.coins)} por presente.`), h('label', {}, 'Moedas especiais e pedras'), rows,
      h('p', {}, h('button', { type: 'button', class: 'small', onclick: addRow }, '+ Adicionar'), h('span', { class: 'hint muted small' }, `  Até ${num(caps.asset)} de cada.`)));
    return {
      node,
      read() {
        const assets = {};
        rows.querySelectorAll('.row').forEach((row) => {
          const id = row.querySelector('.asset').value;
          assets[id] = (assets[id] || 0) + Number(row.querySelector('.amount').value);
        });
        return { coins: Number(coins.value) || 0, assets };
      },
    };
  }

  const giftSummary = (gift) => [gift.coins > 0 ? `${num(gift.coins)} moedas` : null, ...Object.entries(gift.assets).map(([id, n]) => `${num(n)}× ${assetName(id)}`)].filter(Boolean).join(', ');
  const assetName = (id) => (state.catalog && state.catalog.assets.find((a) => a.id === id) || { name: id }).name;

  async function loadCatalog() {
    if (!state.catalog) state.catalog = await api('GET', '/catalog');
    return state.catalog;
  }

  // ---------- views: sign-in ----------

  const app = document.getElementById('app');

  function loginView() {
    const error = h('p', { class: 'error', role: 'alert', hidden: true });
    const user = h('input', { name: 'username', autocomplete: 'username', required: true, maxLength: 64 });
    const pass = h('input', { name: 'password', type: 'password', autocomplete: 'current-password', required: true });
    const code = h('input', { name: 'code', inputMode: 'numeric', autocomplete: 'one-time-code', maxLength: 8, placeholder: '123456' });
    const codeField = field('Código do autenticador', code, 'Os 6 dígitos do aplicativo.');
    codeField.hidden = true;
    const button = h('button', { class: 'primary', type: 'submit', style: 'width:100%' }, 'Entrar');
    const form = h('form', {
      onsubmit: async (event) => {
        event.preventDefault();
        button.disabled = true;
        error.hidden = true;
        try {
          const me = await api('POST', '/login', { username: user.value.trim(), password: pass.value, code: code.value.trim() });
          state.me = me;
          state.csrf = me.csrf;
          pass.value = '';
          route();
        } catch (e) {
          if (e.code === 'code_required') {
            codeField.hidden = false;
            code.required = true;
            code.focus();
          }
          error.textContent = e.message;
          error.hidden = false;
          button.disabled = false;
        }
      },
    }, field('Usuário', user), field('Senha', pass), codeField, error, button);
    app.replaceChildren(h('main', { class: 'login' }, h('div', { class: 'card' }, h('div', { class: 'brand' }, 'Gustfire'), h('div', { class: 'brand-sub' }, 'Painel da equipe'), form)));
    user.focus();
  }

  // First login: the second factor is enrolled before anything else.
  async function enrollView() {
    const error = h('p', { class: 'error', role: 'alert', hidden: true });
    const code = h('input', { name: 'code', inputMode: 'numeric', autocomplete: 'one-time-code', maxLength: 8, required: true, placeholder: '123456' });
    const secretBox = h('div', { class: 'secret' }, 'Gerando…');
    const uriBox = h('a', { class: 'small', href: '#' }, 'Abrir no aplicativo autenticador');
    const confirm = h('button', { class: 'primary', type: 'submit' }, 'Ativar');
    const form = h('form', {
      onsubmit: async (event) => {
        event.preventDefault();
        confirm.disabled = true;
        error.hidden = true;
        try {
          await api('POST', '/totp/confirm', { code: code.value.trim() });
          state.me = null;
          route();
        } catch (e) {
          error.textContent = e.message;
          error.hidden = false;
          confirm.disabled = false;
        }
      },
    }, h('p', {}, '1. Abra o aplicativo autenticador (Google Authenticator, Authy, 1Password…) e adicione uma conta pela chave abaixo.'), secretBox, h('p', { class: 'small' }, uriBox),
      h('p', { style: 'margin-top:12px' }, '2. Digite o código de 6 dígitos que ele mostrar.'), field('Código', code), error, h('div', { class: 'row' }, confirm, h('button', { type: 'button', class: 'ghost', onclick: logout }, 'Sair')));
    app.replaceChildren(h('main', { class: 'login' }, h('div', { class: 'card' }, h('div', { class: 'brand' }, 'Gustfire'), h('div', { class: 'brand-sub' }, 'Segundo fator obrigatório'), form)));
    try {
      const setup = await api('POST', '/totp/setup', {});
      secretBox.textContent = setup.secret.replace(/(.{4})/g, '$1 ').trim();
      uriBox.href = setup.uri;
    } catch (e) {
      secretBox.textContent = e.message;
    }
    code.focus();
  }

  function forcedPasswordView() {
    const form = passwordForm(async () => { state.me = null; route(); });
    app.replaceChildren(h('main', { class: 'login' }, h('div', { class: 'card' }, h('div', { class: 'brand' }, 'Gustfire'), h('div', { class: 'brand-sub' }, 'Troque a senha temporária'), form,
      h('p', { style: 'margin-top:12px' }, h('button', { class: 'ghost small', onclick: logout }, 'Sair')))));
  }

  function passwordForm(done) {
    const error = h('p', { class: 'error', role: 'alert', hidden: true });
    const current = h('input', { type: 'password', autocomplete: 'current-password', required: true });
    const next = h('input', { type: 'password', autocomplete: 'new-password', required: true, minLength: 12, maxLength: 128 });
    const again = h('input', { type: 'password', autocomplete: 'new-password', required: true });
    const send = h('button', { class: 'primary', type: 'submit' }, 'Trocar a senha');
    return h('form', {
      onsubmit: async (event) => {
        event.preventDefault();
        error.hidden = true;
        if (next.value !== again.value) {
          error.textContent = 'A confirmação é diferente da nova senha.';
          error.hidden = false;
          return;
        }
        send.disabled = true;
        try {
          await api('POST', '/password', { current: current.value, new: next.value });
          toast('Senha trocada.', 'ok');
          await done();
        } catch (e) {
          error.textContent = e.message;
          error.hidden = false;
          send.disabled = false;
        }
      },
    }, field('Senha atual', current), field('Nova senha', next, 'De 12 a 128 caracteres.'), field('Repita a nova senha', again), error, send);
  }

  async function logout() {
    try { await api('POST', '/logout', {}); } catch (e) { /* already out */ }
    state.me = null;
    state.csrf = '';
    state.catalog = null;
    location.hash = '#/';
    route();
  }

  // ---------- shell and routing ----------

  const NAV = [
    { href: '#/', label: 'Visão geral', role: 'viewer' },
    { group: 'Jogadores' },
    { href: '#/players', label: 'Jogadores', role: 'support' },
    { href: '#/reports', label: 'Denúncias', role: 'support', badge: true },
    { group: 'Economia' },
    { href: '#/economy', label: 'Economia', role: 'viewer' },
    { href: '#/orders', label: 'Pagamentos', role: 'support' },
    { href: '#/auction', label: 'Leilão', role: 'support' },
    { href: '#/mail', label: 'Enviar presentes', role: 'admin' },
    { group: 'Operação' },
    { href: '#/audit', label: 'Registro do jogo', role: 'support' },
    { href: '#/servers', label: 'Servidores', role: 'viewer' },
    { group: 'Painel' },
    { href: '#/staff-actions', label: 'Ações da equipe', role: 'admin' },
    { href: '#/staff', label: 'Equipe', role: 'owner' },
    { href: '#/system', label: 'Sistema', role: 'owner' },
    { href: '#/account', label: 'Minha conta', role: 'viewer' },
  ];

  const ROUTES = [
    [/^\/$/, overviewView, 'viewer'],
    [/^\/players$/, playersView, 'support'],
    [/^\/players\/(\d+)$/, playerView, 'support'],
    [/^\/reports$/, reportsView, 'support'],
    [/^\/economy$/, economyView, 'viewer'],
    [/^\/orders$/, ordersView, 'support'],
    [/^\/auction$/, auctionView, 'support'],
    [/^\/mail$/, mailView, 'admin'],
    [/^\/audit$/, auditView, 'support'],
    [/^\/servers$/, serversView, 'viewer'],
    [/^\/staff-actions$/, staffActionsView, 'admin'],
    [/^\/staff$/, staffView, 'owner'],
    [/^\/system$/, systemView, 'owner'],
    [/^\/account$/, accountView, 'viewer'],
  ];

  function shell(path) {
    const reportsBadge = h('span', { class: 'count', hidden: true });
    const nav = h('nav', { class: 'nav', 'aria-label': 'Seções' });
    for (const item of NAV) {
      if (item.group) { nav.append(h('div', { class: 'group' }, item.group)); continue; }
      if (!can(item.role)) continue;
      const active = item.href === '#' + path || (item.href !== '#/' && path.startsWith(item.href.slice(1) + '/'));
      nav.append(h('a', { href: item.href, 'aria-current': active ? 'page' : null }, item.label, item.badge ? reportsBadge : null));
    }
    const side = h('aside', { class: 'side' }, h('div', { class: 'brand' }, 'Gustfire'), h('div', { class: 'brand-sub' }, 'Painel da equipe'),
      h('button', { class: 'menu-toggle small', 'aria-label': 'Menu', onclick: () => side.classList.toggle('open') }, 'Menu'), nav,
      h('div', { class: 'who' }, h('strong', {}, state.me.admin.username), ROLE_NAME[state.me.admin.role], h('div', {}, h('button', { class: 'small ghost', style: 'margin-top:8px', onclick: logout }, 'Sair'))));
    const main = h('main', { class: 'main', id: 'main', tabindex: -1 });
    app.replaceChildren(h('div', { class: 'shell' }, side, main));
    if (can('support')) {
      api('GET', '/overview').then((data) => {
        state.overview = data;
        const open = data.queue.reports_open;
        if (open > 0) { reportsBadge.textContent = open; reportsBadge.hidden = false; }
      }).catch(() => {});
    }
    return main;
  }

  async function route() {
    if (state.cleanup) { state.cleanup(); state.cleanup = null; }
    if (!state.me) {
      try {
        const me = await api('GET', '/me');
        state.me = me;
        state.csrf = me.csrf;
      } catch (e) {
        return loginView();
      }
    }
    if (state.me.stage === 'enroll') return enrollView();
    if (state.me.must_change_password) return forcedPasswordView();
    const path = (location.hash.slice(1) || '/').split('?')[0];
    const found = ROUTES.map(([pattern, view, role]) => ({ match: path.match(pattern), view, role })).find((r) => r.match);
    const main = shell(path);
    if (!found) { main.append(pageTitle('Página não encontrada'), h('p', {}, link('#/', 'Voltar à visão geral'))); return; }
    if (!can(found.role)) { main.append(pageTitle('Sem permissão'), h('p', { class: 'muted' }, `Esta página pede o papel ${ROLE_NAME[found.role]} ou superior.`)); return; }
    main.focus();
    try {
      state.cleanup = (await found.view(main, ...found.match.slice(1))) || null;
    } catch (error) {
      main.append(h('div', { class: 'card' }, h('p', { class: 'error' }, error.message), h('button', { onclick: route }, 'Tentar de novo')));
    }
  }

  // ---------- overview ----------

  async function overviewView(root) {
    const box = h('div', { class: 'stack' });
    root.append(pageTitle('Visão geral', 'Atualiza sozinha a cada 30 segundos. Dias contados no horário de Brasília.'), box);
    async function load() {
      const d = await api('GET', '/overview');
      state.overview = d;
      const live = d.servers.filter((s) => s.age_seconds < 60);
      const online = live.reduce((sum, s) => sum + s.online, 0);
      const a = d.accounts, q = d.queue, al = d.alerts;
      const series = d.series;
      const revenueCurrency = (d.revenue[0] || {}).currency || 'BRL';
      const points = (pick) => series.map((p) => ({ l: day(p.day), v: pick(p) }));
      box.replaceChildren(
        h('div', { class: 'grid kpis' },
          kpi('Online agora', num(online), live.length ? `${live.length} servidor(es)` : 'nenhum servidor respondendo', live.length ? '' : 'bad', '#/servers'),
          kpi('Contas', num(a.total), `${num(a.with_character)} com personagem`),
          kpi('Novas contas', num(a.new_24h), `${num(a.new_7d)} em 7 dias`),
          kpi('Jogaram em 24 h', num(a.active_24h), `${num(a.active_7d)} em 7 dias · ${num(a.active_30d)} em 30`),
          ...d.revenue.map((r) => kpi(`Receita (${r.currency})`, money(r.d1, r.currency), `7 dias ${money(r.d7, r.currency)} · 30 dias ${money(r.d30, r.currency)}`)),
          d.revenue.length ? null : kpi('Receita', '—', 'nenhuma compra paga ainda'),
          kpi('Reembolsos (30 d)', num(d.refunds_30d), '', d.refunds_30d > 0 ? 'warn' : '', '#/orders')),
        h('h2', {}, 'Precisa de atenção'),
        h('div', { class: 'grid kpis' },
          kpi('Denúncias abertas', num(q.reports_open), 'aguardando análise', q.reports_open > 0 ? 'warn' : '', '#/reports'),
          kpi('Pagamentos pendentes', num(q.orders_pending), 'abertos na última hora', '', '#/orders'),
          kpi('Anúncios no leilão', num(q.listings_active), '', '', '#/auction'),
          kpi('Cartas não recebidas', num(q.mail_unclaimed), 'no Correio dos jogadores'),
          kpi('Partidas fora de sincronia', num(al.desync_24h), 'últimas 24 h', al.desync_24h > 0 ? 'warn' : ''),
          kpi('Pagamentos divergentes', num(al.mismatch_30d), 'últimos 30 dias', al.mismatch_30d > 0 ? 'bad' : '', '#/audit'),
          kpi('Silenciados por denúncias', num(al.auto_muted_24h), 'últimas 24 h', al.auto_muted_24h > 0 ? 'warn' : '')),
        h('h2', {}, 'Últimos 14 dias'),
        h('div', { class: 'grid cols-2' },
          h('div', { class: 'card' }, h('h3', {}, 'Novas contas'), barChart(points((p) => p.signups), 'Novas contas por dia')),
          h('div', { class: 'card' }, h('h3', {}, 'Jogadores que entraram'), barChart(points((p) => p.active), 'Jogadores que entraram por dia', 'green')),
          h('div', { class: 'card' }, h('h3', {}, 'Partidas'), barChart(points((p) => p.matches), 'Partidas por dia')),
          h('div', { class: 'card' }, h('h3', {}, `Receita (${revenueCurrency})`), barChart(points((p) => (p.revenue || {})[revenueCurrency] || 0), 'Receita por dia', 'fire', (v) => money(v, revenueCurrency)))),
        h('p', { class: 'muted small' }, `Dados de ${when(d.generated_at)}.`));
    }
    await load();
    const timer = setInterval(() => load().catch(() => {}), 30000);
    return () => clearInterval(timer);
  }

  // ---------- players ----------

  const filters = { players: { q: '', status: '', sort: '', page: 0 }, reports: { status: 'open', page: 0 }, orders: { q: '', status: '', provider: '', page: 0 }, auction: { q: '', status: 'active', page: 0 }, audit: { kind: '', account_id: '', q: '', since: '', until: '' }, actions: { action: '', account_id: '', page: 0 } };

  function playerBadges(p) {
    return [p.banned ? badge('banido', 'bad') : null, p.online_on ? badge('online · ' + p.online_on, 'ok') : null, p.steam ? badge('Steam', 'info') : null, p.character == null ? badge('sem personagem') : null];
  }

  async function playersView(root) {
    const f = filters.players;
    const results = h('div', {});
    const search = h('input', { type: 'search', value: f.q, placeholder: 'Nome, personagem, ID, SteamID ou IP', 'aria-label': 'Buscar jogador', maxLength: 64 });
    const status = h('select', { 'aria-label': 'Situação' }, [['', 'Todos'], ['banned', 'Banidos'], ['online', 'Online agora'], ['no_character', 'Sem personagem']].map(([v, t]) => h('option', { value: v, selected: f.status === v }, t)));
    const sort = h('select', { 'aria-label': 'Ordem' }, [['', 'Mais novos'], ['login', 'Último login']].map(([v, t]) => h('option', { value: v, selected: f.sort === v }, t)));
    const submit = (event) => { event.preventDefault(); f.q = search.value.trim(); f.status = status.value; f.sort = sort.value; f.page = 0; load(); };
    root.append(pageTitle('Jogadores', 'Busque por nome de usuário, personagem, ID, SteamID ou endereço IP.'),
      h('form', { class: 'filters', onsubmit: submit }, h('div', { class: 'field search' }, h('label', {}, 'Busca'), search), h('div', { class: 'field' }, h('label', {}, 'Situação'), status), h('div', { class: 'field' }, h('label', {}, 'Ordem'), sort), h('button', { class: 'primary', type: 'submit' }, 'Buscar')), results);
    async function load() {
      results.replaceChildren(h('p', { class: 'muted' }, 'Buscando…'));
      try {
        const data = await api('GET', '/players' + qs({ q: f.q, status: f.status, sort: f.sort, page: f.page }));
        results.replaceChildren(h('div', { class: 'card' }, dataTable([
          { title: 'ID', class: 'num', render: (p) => p.id },
          { title: 'Usuário', render: (p) => h('strong', {}, p.username) },
          { title: 'Personagem', render: (p) => p.character || '—' },
          { title: 'Partidas', class: 'num', render: (p) => num(p.matches) },
          { title: 'Cadastro', render: (p) => when(p.created_at) },
          { title: 'Último login', render: (p) => ago(p.last_login) },
          { title: 'Situação', render: (p) => h('span', { class: 'row' }, playerBadges(p)) },
        ], data.rows, { onRow: (p) => { location.hash = '#/players/' + p.id; }, empty: 'Nenhum jogador encontrado.' })), pager(f.page, 50, data.total, (page) => { f.page = page; load(); }));
      } catch (e) { results.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    await load();
  }

  function facts(pairs) {
    return h('dl', { class: 'facts' }, pairs.filter(Boolean).map(([k, v]) => [h('dt', {}, k), h('dd', {}, v == null || v === '' ? '—' : v)]));
  }

  async function playerView(root, id) {
    await loadCatalog().catch(() => {});
    const d = await api('GET', '/players/' + id);
    const acc = d.account, prof = d.profile;
    const banned = acc.banned;
    const reload = () => route();
    const act = (label, opts) => h('button', { class: opts.danger ? 'danger' : '', onclick: () => opts.open() }, label);

    const reasonDialog = (title, path, extra) => () => dialogForm({
      title, intro: extra && extra.intro, danger: extra && extra.danger, submit: (extra && extra.submit) || 'Confirmar',
      fields: [extra && extra.fields, reasonField(extra && extra.reasonLabel)],
      run: async (form) => api('POST', `/players/${id}/${path}`, { reason: form.get('reason'), ...(extra && extra.body ? extra.body(form) : {}) }),
      after: extra && extra.after,
    }).then((ok) => { if (ok) { toast('Feito.', 'ok'); reload(); } });

    const actions = [];
    if (can('support')) {
      actions.push(act('Anotar', { open: () => dialogForm({ title: 'Anotação interna', fields: field('Anotação (só a equipe vê)', h('textarea', { name: 'note', required: true, maxLength: 500 })), submit: 'Salvar', run: (form) => api('POST', `/players/${id}/notes`, { note: form.get('note') }) }).then((ok) => ok && reload()) }));
      actions.push(act('Presentear', { open: async () => {
        await loadCatalog();
        const editor = giftEditor(state.catalog.gift_caps);
        const note = h('input', { name: 'note', required: true, minLength: 3, maxLength: 80, placeholder: 'Compensação pela queda de ontem' });
        const rid = requestId();
        dialogForm({
          title: `Presente para ${acc.username}`, intro: 'Vai para o Correio do jogador, que recebe pelo jogo.', submit: 'Enviar',
          fields: [editor.node, field('Mensagem que o jogador vê', note), reasonField('Motivo interno (ticket, contexto)')],
          run: (form) => api('POST', `/players/${id}/gift`, { ...editor.read(), note: form.get('note'), reason: form.get('reason'), request_id: rid }),
        }).then((ok) => { if (ok) { toast('Presente enviado ao Correio.', 'ok'); reload(); } });
      } }));
    }
    if (can('admin')) {
      actions.push(banned
        ? act('Desbanir', { open: reasonDialog('Desbanir ' + acc.username, 'unban', { submit: 'Desbanir', reasonLabel: 'Motivo do desbanimento' }) })
        : act('Banir', { danger: true, open: reasonDialog('Banir ' + acc.username, 'ban', {
          danger: true, submit: 'Banir', intro: 'A conta é desconectada em segundos e não consegue entrar de novo.',
          fields: field('Duração em horas', h('input', { name: 'hours', type: 'number', min: 0, max: 43800, value: 0 }), '0 = sem prazo.'),
          body: (form) => ({ hours: Number(form.get('hours')) || 0 }),
        }) }));
      actions.push(act('Encerrar sessões', { open: reasonDialog('Encerrar as sessões de ' + acc.username, 'sessions/revoke', { intro: 'Os logins guardados deixam de valer. Quem está jogando agora continua até sair.', submit: 'Encerrar' }) }));
      if (!acc.no_password) {
        actions.push(act('Senha temporária', { open: reasonDialog('Senha temporária para ' + acc.username, 'password', {
          submit: 'Gerar senha', reasonLabel: 'Como você confirmou que a pessoa é a dona da conta?',
          intro: 'Gera uma senha, encerra as sessões e mostra a senha uma única vez. A pessoa troca no jogo.',
          after: (r) => h('div', {}, h('p', {}, 'Passe esta senha à pessoa. Ela não aparece de novo:'), h('div', { class: 'secret' }, r.password)),
        }) }));
      }
    }
    if (can('owner')) {
      actions.push(act('Exportar dados', { open: () => dialogForm({ title: 'Exportar os dados de ' + acc.username, intro: 'Baixa a cópia completa (LGPD, direito de acesso). O pedido fica registrado.', submit: 'Baixar', fields: reasonField('Qual foi o pedido da pessoa?'),
        run: async (form) => { window.location.assign(`/admin/api/players/${id}/export?reason=${encodeURIComponent(form.get('reason'))}`); } }) }));
      actions.push(act('Excluir conta', { danger: true, open: () => dialogForm({ title: 'Excluir a conta de ' + acc.username, danger: true, submit: 'Excluir para sempre',
        intro: 'Apaga a conta e o personagem, sem volta. O jogador precisa estar offline.',
        fields: [field(`Digite ${acc.username} para confirmar`, h('input', { name: 'confirm', required: true, autocomplete: 'off' })), reasonField('Qual foi o pedido da pessoa?')],
        run: (form) => api('DELETE', `/players/${id}`, { confirm: form.get('confirm'), reason: form.get('reason') }) }).then((ok) => { if (ok) { toast('Conta excluída.', 'ok'); location.hash = '#/players'; } }) }));
    }

    const data = prof && prof.data ? prof.data : null;
    const label = (key) => SAVE_LABELS[key] || key;
    const scalars = data ? Object.entries(data).filter(([k, v]) => k !== 'name' && ['number', 'string', 'boolean'].includes(typeof v)) : [];
    const counted = data ? Object.entries(data).filter(([k, v]) => k !== 'items' && v && typeof v === 'object').map(([k, v]) => [label(k), Array.isArray(v) ? `${v.length} item(ns)` : `${Object.keys(v).length} campo(s)`]) : [];
    const items = data && data.items && typeof data.items === 'object' ? Object.entries(data.items).sort((x, y) => Number(y[1]) - Number(x[1])) : [];

    const banInfo = banned ? h('div', { class: 'card', style: 'border-color:var(--red)' }, h('h2', {}, 'Conta banida'),
      facts([['Motivo', acc.ban_reason], ['Por', acc.banned_by], ['Quando', when(acc.banned_at)], ['Até', acc.ban_until ? when(acc.ban_until) : 'sem prazo']])) : null;

    root.append(
      pageTitle(acc.username, prof ? `Personagem ${prof.name || '—'} · conta ${acc.id}` : `Conta ${acc.id}, ainda sem personagem`, h('a', { href: '#/players' }, '← Jogadores'), h('span', { class: 'row' }, playerBadges({ banned, online_on: d.presence && d.presence.server_id, steam: !!acc.steam_id, character: prof ? prof.name : null }))),
      h('div', { class: 'row', style: 'margin-bottom:14px' }, actions),
      h('div', { class: 'stack' }, banInfo,
        h('div', { class: 'grid cols-2' },
          h('div', { class: 'card' }, h('h2', {}, 'Conta'), facts([['Cadastro', when(acc.created_at)], ['Último login', `${when(acc.last_login)} (${ago(acc.last_login)})`], ['Termos aceitos', acc.terms_version ? `${acc.terms_version} · ${when(acc.terms_accepted_at)}` : 'não'],
            ['SteamID', acc.steam_id], ['Senha', acc.no_password ? 'não tem (conta Steam)' : 'definida'], ['Sessões abertas', d.sessions.open], ['Online agora', d.presence ? `${d.presence.server_id} (expira ${ago(d.presence.expires_at)})` : 'não'], ['Denúncias feitas', d.reports_made.made]])),
          h('div', { class: 'card' }, h('h2', {}, 'Personagem'), prof ? [facts([['Nome', prof.name], ['Versão do save', prof.version], ['Salvo', `${when(prof.updated_at)} (${ago(prof.updated_at)})`], ...scalars.map(([k, v]) => [label(k), typeof v === 'number' ? num(v) : String(v)]), ...counted]),
            items.length ? [h('h3', { style: 'margin-top:12px' }, 'Moedas e pedras'), facts(items.map(([k, v]) => [assetNameSync(k), num(v)]))] : null,
            h('div', { style: 'margin-top:10px' }, detailsJson(data, 'Ver o save completo (JSON)'))] : h('p', { class: 'muted' }, 'Esta conta ainda não criou personagem.'))),
        h('div', { class: 'grid cols-2' },
          card('Anotações da equipe', dataTable([{ title: 'Quando', render: (n) => when(n.created_at) }, { title: 'Quem', render: (n) => n.admin_name }, { title: 'Nota', render: (n) => n.note }], d.notes, { empty: 'Sem anotações.' })),
          card('Contas que entraram do mesmo IP', dataTable([
            { title: 'Conta', render: (s) => [playerLink(s.id, s.username), s.banned ? ' ' : null, s.banned ? badge('banido', 'bad') : null] }, { title: 'Vezes', class: 'num', render: (s) => s.hits }, { title: 'IPs', render: (s) => h('span', { class: 'mono' }, s.ips.join(', ')) }, { title: 'Visto', render: (s) => ago(s.last_seen) },
          ], d.shared_ips, { empty: 'Nenhuma outra conta usou estes endereços nos últimos 90 dias.' }), 'Pode ser a mesma pessoa, ou uma rede compartilhada (escola, operadora).')),
        card('Denúncias contra este jogador', dataTable([{ title: 'Quando', render: (r) => when(r.created_at) }, { title: 'Quem denunciou', render: (r) => r.reporter_name || '—' }, { title: 'Motivo', render: (r) => badge(r.reason) }, { title: 'Mensagem', render: (r) => short(r.message, 90) }, { title: 'Situação', render: (r) => badge(tr(r.status), r.status === 'open' ? 'warn' : '') }], d.reports_against, { empty: 'Nenhuma.' })),
        h('div', { class: 'grid cols-2' },
          card('Pagamentos', dataTable([{ title: 'Pedido', render: (o) => o.order_id }, { title: 'Produto', render: (o) => o.description || o.sku }, { title: 'Valor', class: 'num', render: (o) => money(o.amount, o.currency) }, { title: 'Situação', render: (o) => orderBadge(o.status) }, { title: 'Quando', render: (o) => when(o.created_at) }], d.orders, { empty: 'Sem pedidos.' })),
          card('Correio', dataTable([{ title: 'Tipo', render: (m) => badge(tr(m.kind)) }, { title: 'Conteúdo', render: (m) => mailText(m) }, { title: 'Enviado', render: (m) => when(m.created_at) }, { title: 'Recebido', render: (m) => (m.claimed_at ? when(m.claimed_at) : badge('na caixa', 'warn')) }], d.mail, { empty: 'Sem cartas.' }))),
        h('div', { class: 'grid cols-2' },
          card('Anúncios no leilão', dataTable([{ title: '#', render: (l) => l.id }, { title: 'Item', render: (l) => `${l.item_id} · ${l.quality}${l.strengthen ? ' +' + l.strengthen : ''}` }, { title: 'Preço', render: (l) => price(l) }, { title: 'Situação', render: (l) => badge(tr(l.status)) }], d.listings, { empty: 'Sem anúncios.' })),
          card('Compras no leilão', dataTable([{ title: '#', render: (l) => l.id }, { title: 'Item', render: (l) => `${l.item_id} · ${l.quality}` }, { title: 'Preço', render: (l) => price(l) }, { title: 'Quando', render: (l) => when(l.closed_at) }], d.purchases, { empty: 'Sem compras.' }))),
        card('Acessos (IP e horário)', dataTable([{ title: 'Quando', render: (a) => when(a.created_at) }, { title: 'Ação', render: (a) => a.action }, { title: 'IP', render: (a) => h('span', { class: 'mono' }, a.ip) }], d.access, { empty: 'Sem registros.' }), 'Guardados por 6 meses (Marco Civil da Internet).'),
        card('Ações da equipe sobre esta conta', dataTable([{ title: 'Quando', render: (a) => when(a.created_at) }, { title: 'Quem', render: (a) => a.admin_name }, { title: 'Ação', render: (a) => actionBadge(a.action) }, { title: 'Motivo', render: (a) => a.reason || '—' }, { title: '', render: (a) => detailsJson(a.detail) }], d.staff_actions, { empty: 'Nenhuma.' })),
        card('Atividade recente no jogo', [dataTable([{ title: 'Quando', render: (a) => when(a.created_at) }, { title: 'Tipo', render: (a) => badge(a.kind) }, { title: 'Detalhe', render: (a) => detailsJson(a.detail, short(JSON.stringify(a.detail), 70)) }], d.activity, { empty: 'Sem atividade registrada.' }), h('p', {}, link('#/audit', 'Abrir o registro completo'))])));
  }

  // Names of the save's fields (PlayerProfile.to_dict); any other key is shown as it is.
  const SAVE_LABELS = { coins: 'Moedas do jogo', merits: 'Méritos', matches: 'Partidas', victories: 'Vitórias', experience: 'Experiência', gender: 'Gênero', tutorial: 'Tutorial', created: 'Personagem criado', inventory: 'Mochila', pets: 'Mascotes', maps: 'Mapas', equipped: 'Equipado', missions: 'Missões', rating: 'Ranqueada', titles: 'Títulos', title: 'Título', hunt: 'Caçada', coupons: 'Cupons usados' };
  const card = (title, body, note) => h('div', { class: 'card' }, h('h2', {}, title), body, note ? h('p', { class: 'muted small', style: 'margin-top:8px' }, note) : null);
  const assetNameSync = (id) => (state.catalog && state.catalog.assets.find((a) => a.id === id)) ? state.catalog.assets.find((a) => a.id === id).name : id;
  const price = (l) => [l.price_solar ? `${num(l.price_solar)} solar` : null, l.price_estrela ? `${num(l.price_estrela)} estrela` : null].filter(Boolean).join(' + ') || '—';
  const mailText = (m) => [m.coins ? `${num(m.coins)} moedas` : null, ...Object.entries(m.currencies || {}).map(([k, v]) => `${num(v)}× ${k}`), m.item_kind ? m.item_kind : null, m.detail && m.detail.note ? `“${m.detail.note}”` : null].filter(Boolean).join(', ') || '—';
  function orderBadge(status) {
    return badge({ paid: 'pago', init: 'aberto', cancelled: 'cancelado', failed: 'falhou', refunded: 'reembolsado' }[status] || status, { paid: 'ok', refunded: 'warn', failed: 'bad' }[status]);
  }

  const ACTIONS = {
    login: 'Entrou no painel', 'player.ban': 'Baniu jogador', 'player.unban': 'Desbaniu jogador', 'player.note': 'Anotou', 'player.gift': 'Presenteou', 'player.revoke_sessions': 'Encerrou sessões', 'player.reset_password': 'Senha temporária',
    'player.export': 'Exportou dados', 'player.delete': 'Excluiu conta', 'report.dismissed': 'Descartou denúncia', 'report.warned': 'Avisou (denúncia)', 'report.banned': 'Baniu (denúncia)', 'auction.cancel': 'Cancelou anúncio', 'broadcast.gift': 'Envio em massa',
    'audit.export': 'Exportou o registro', 'staff.create': 'Criou conta da equipe', 'staff.update': 'Mudou papel/situação', 'staff.reset_2fa': 'Reiniciou o 2FA', 'staff.reset_password': 'Senha temporária (equipe)', 'admin.password': 'Trocou a senha', 'admin.totp': 'Ativou o 2FA',
  };
  const actionBadge = (action) => badge(ACTIONS[action] || action, /ban|delete|reset|revoke/.test(action) ? 'warn' : '');

  // ---------- reports ----------

  async function reportsView(root) {
    const f = filters.reports;
    const results = h('div', { class: 'stack' });
    const tabs = h('div', { class: 'tabs', role: 'group', 'aria-label': 'Situação' });
    root.append(pageTitle('Denúncias do chat', 'As mais antigas primeiro. Banir pede papel de administrador.'), tabs, results);
    async function load() {
      tabs.replaceChildren(...[['open', 'Abertas'], ['dismissed', 'Descartadas'], ['warned', 'Avisados'], ['banned', 'Banidos'], ['all', 'Todas']].map(([v, t]) => h('button', { 'aria-pressed': String(f.status === v), onclick: () => { f.status = v; f.page = 0; load(); } }, t)));
      results.replaceChildren(h('p', { class: 'muted' }, 'Carregando…'));
      try {
        const data = await api('GET', '/reports' + qs({ status: f.status, page: f.page }));
        results.replaceChildren(...(data.rows.length ? data.rows.map(reportCard) : [h('div', { class: 'card empty' }, 'Nenhuma denúncia aqui.')]), pager(f.page, 50, data.total, (page) => { f.page = page; load(); }));
      } catch (e) { results.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    function review(report, status) {
      return dialogForm({
        title: { dismissed: 'Descartar denúncia', warned: 'Avisar o jogador', banned: 'Banir o jogador' }[status] + ` #${report.id}`, danger: status === 'banned', submit: 'Confirmar',
        intro: status === 'banned' ? `${report.reported_name || 'O jogador'} é banido por tempo indeterminado e desconectado em segundos.` : null,
        fields: field('Anotação (opcional)', h('textarea', { name: 'note', maxLength: 500 })),
        run: (form) => api('POST', `/reports/${report.id}/review`, { status, note: form.get('note') }),
      }).then((ok) => { if (ok) { toast('Denúncia analisada.', 'ok'); load(); } });
    }
    function reportCard(r) {
      const lines = (r.context || []).map((line) => h('div', { class: 'chat-line' + (line.text === r.message && line.author === r.reported_name ? ' hit' : '') }, h('b', {}, (line.author || '?') + ': '), line.text));
      return h('div', { class: 'card report ' + r.status },
        h('div', { class: 'card-head' }, h('h2', {}, `#${r.id} · `, playerLink(r.reported_id, r.reported_name), ' ', badge(r.reason, 'warn'), r.auto_muted ? [' ', badge('silenciado automaticamente', 'warn')] : null, r.reported_banned ? [' ', badge('já banido', 'bad')] : null),
          h('span', { class: 'muted small' }, `${when(r.created_at)} · servidor ${r.server_id || '—'}`)),
        facts([['Denunciado por', r.reporter_name || '—'], ['Outras denúncias (30 dias)', r.previous > 0 ? badge(String(r.previous), 'warn') : '0'], r.note ? ['Observação', r.note] : null]),
        h('p', { style: 'margin-top:10px' }, h('b', {}, 'Mensagem: '), h('span', { class: 'chat-line hit' }, r.message)),
        lines.length ? h('details', {}, h('summary', { class: 'muted small' }, `Conversa em volta (${lines.length} linhas)`), h('div', { class: 'stack' }, lines)) : null,
        r.status === 'open'
          ? h('div', { class: 'row', style: 'margin-top:12px' }, h('button', { onclick: () => review(r, 'dismissed') }, 'Descartar'), h('button', { onclick: () => review(r, 'warned') }, 'Avisar'), can('admin') ? h('button', { class: 'danger', onclick: () => review(r, 'banned') }, 'Banir') : null)
          : h('p', { class: 'muted small', style: 'margin-top:10px' }, `${tr(r.status)} por ${r.reviewer || '—'} em ${when(r.reviewed_at)}${r.review_note ? ' · ' + r.review_note : ''}`));
    }
    await load();
  }

  // ---------- economy ----------

  async function economyView(root) {
    const [e] = await Promise.all([api('GET', '/economy'), loadCatalog()]);
    const assets = Object.entries(e.assets).sort((a, b) => b[1] - a[1]);
    const topBox = h('div', {});
    const select = h('select', { 'aria-label': 'Moeda', onchange: () => loadTop() }, h('option', { value: 'coins' }, 'Moedas do jogo'), assets.map(([id]) => h('option', { value: id }, assetNameSync(id))));
    async function loadTop() {
      try {
        const rows = await api('GET', '/economy/top' + qs({ asset: select.value }));
        topBox.replaceChildren(dataTable([{ title: '#', class: 'num', render: (r) => rows.indexOf(r) + 1 }, { title: 'Jogador', render: (r) => [playerLink(r.account_id, r.username), r.banned ? [' ', badge('banido', 'bad')] : null] }, { title: 'Personagem', render: (r) => r.character || '—' }, { title: 'Quantidade', class: 'num', render: (r) => num(r.amount) }], rows, { empty: 'Sem dados.' }));
      } catch (error) { topBox.replaceChildren(h('p', { class: 'error' }, error.message)); }
    }
    const a = e.auction, x = e.exchange;
    const maxAsset = Math.max(1, ...assets.map(([, v]) => v));
    root.append(pageTitle('Economia', `Soma dos saves de ${num(e.players)} personagens. Atualizado ${ago(e.generated_at)}.`),
      h('div', { class: 'stack' },
        h('div', { class: 'grid kpis' }, kpi('Moedas do jogo em circulação', num(e.coins), `${num(e.players ? e.coins / e.players : 0)} por personagem`), kpi('Anúncios ativos', num(a.active), '', '', '#/auction'), kpi('Vendas no leilão (7 d)', num(a.sold_7d), `volume ${num(a.volume_solar_7d)} solar · ${num(a.volume_estrela_7d)} estrela`),
          kpi('Comissões do leilão (7 d)', `${num(a.fees_solar_7d)} solar`, `${num(a.fees_estrela_7d)} estrela`), kpi('Ofertas no Câmbio', num(x.active), `${num(x.fills_7d)} trocas em 7 dias`)),
        h('div', { class: 'grid cols-2' },
          card('Moedas e pedras em circulação', dataTable([{ title: 'Item', render: (r) => assetNameSync(r[0]) }, { title: 'Total', class: 'num', render: (r) => num(r[1]) }, { title: '', render: (r) => h('div', { class: 'meter' }, h('span', { style: `width:${Math.max(2, (r[1] / maxAsset) * 100)}%` })) }], assets, { empty: 'Nenhum item guardado ainda.' }), 'Se uma moeda cresce rápido demais, procure quem a acumula ao lado.'),
          h('div', { class: 'card' }, h('div', { class: 'card-head' }, h('h2', {}, 'Quem mais tem'), select), topBox))));
    await loadTop();
  }

  // ---------- orders ----------

  async function ordersView(root) {
    const f = filters.orders;
    const results = h('div', { class: 'stack' });
    const q = h('input', { type: 'search', value: f.q, placeholder: 'Pedido, conta, usuário, produto ou código Stripe', 'aria-label': 'Buscar' });
    const status = h('select', { 'aria-label': 'Situação' }, [['', 'Todas'], ['paid', 'Pagos'], ['init', 'Abertos'], ['refunded', 'Reembolsados'], ['failed', 'Falharam'], ['cancelled', 'Cancelados']].map(([v, t]) => h('option', { value: v, selected: f.status === v }, t)));
    const provider = h('select', { 'aria-label': 'Origem' }, [['', 'Todas as origens'], ['stripe', 'Stripe (cartão, Pix)'], ['steam', 'Steam']].map(([v, t]) => h('option', { value: v, selected: f.provider === v }, t)));
    root.append(pageTitle('Pagamentos', 'Pedidos da loja (Stripe e Steam). Reembolsos são feitos no painel do Stripe e chegam aqui sozinhos.'),
      h('form', { class: 'filters', onsubmit: (event) => { event.preventDefault(); f.q = q.value.trim(); f.status = status.value; f.provider = provider.value; f.page = 0; load(); } }, h('div', { class: 'field search' }, h('label', {}, 'Busca'), q), h('div', { class: 'field' }, h('label', {}, 'Situação'), status), h('div', { class: 'field' }, h('label', {}, 'Origem'), provider), h('button', { class: 'primary', type: 'submit' }, 'Filtrar')), results);
    async function load() {
      try {
        const data = await api('GET', '/orders' + qs({ q: f.q, status: f.status, provider: f.provider, page: f.page }));
        results.replaceChildren(
          h('div', { class: 'card' }, dataTable([
            { title: 'Pedido', render: (o) => o.order_id }, { title: 'Jogador', render: (o) => playerLink(o.account_id, o.username) }, { title: 'Produto', render: (o) => o.description || o.sku }, { title: 'Valor', class: 'num', render: (o) => money(o.amount, o.currency) },
            { title: 'Situação', render: (o) => orderBadge(o.status) }, { title: 'Origem', render: (o) => o.provider }, { title: 'Quando', render: (o) => when(o.created_at) },
            { title: 'Referência', render: (o) => (o.payment_ref ? h('a', { href: 'https://dashboard.stripe.com/payments/' + encodeURIComponent(o.payment_ref), target: '_blank', rel: 'noopener noreferrer' }, short(o.payment_ref, 18)) : h('span', { class: 'muted' }, o.steam_status || '—')) },
          ], data.rows, { empty: 'Nenhum pedido.' })), pager(f.page, 50, data.total, (page) => { f.page = page; load(); }),
          card('Mais vendidos nos últimos 30 dias', dataTable([{ title: 'Produto', render: (r) => r.sku }, { title: 'Pedidos', class: 'num', render: (r) => num(r.orders) }, { title: 'Receita', class: 'num', render: (r) => money(r.total, r.currency) }], data.by_sku_30d, { empty: 'Sem vendas.' })));
      } catch (e) { results.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    await load();
  }

  // ---------- auction ----------

  async function auctionView(root) {
    const f = filters.auction;
    const results = h('div', { class: 'stack' });
    const q = h('input', { type: 'search', value: f.q, placeholder: 'Item ou vendedor', 'aria-label': 'Buscar' });
    const status = h('select', { 'aria-label': 'Situação' }, [['active', 'À venda'], ['sold', 'Vendidos'], ['cancelled', 'Cancelados'], ['expired', 'Vencidos'], ['all', 'Todos']].map(([v, t]) => h('option', { value: v, selected: f.status === v }, t)));
    root.append(pageTitle('Leilão', 'A coluna "Mercado" é a mediana do preço em solar do mesmo item e qualidade nos últimos 30 dias.'),
      h('form', { class: 'filters', onsubmit: (event) => { event.preventDefault(); f.q = q.value.trim(); f.status = status.value; f.page = 0; load(); } }, h('div', { class: 'field search' }, h('label', {}, 'Busca'), q), h('div', { class: 'field' }, h('label', {}, 'Situação'), status), h('button', { class: 'primary', type: 'submit' }, 'Filtrar')), results);
    function cancel(l) {
      return dialogForm({ title: `Cancelar o anúncio #${l.id}`, danger: true, submit: 'Cancelar anúncio', intro: 'O item volta ao Correio do vendedor. A comissão paga não é devolvida.', fields: reasonField(),
        run: (form) => api('POST', `/auction/${l.id}/cancel`, { reason: form.get('reason') }) }).then((ok) => { if (ok) { toast('Anúncio cancelado.', 'ok'); load(); } });
    }
    function market(l) {
      if (!l.median_solar || !l.price_solar) return h('span', { class: 'muted' }, '—');
      const ratio = l.price_solar / l.median_solar;
      const text = `${ratio.toFixed(2)}× (${num(l.median_solar)})`;
      return ratio < 0.25 || ratio > 4 ? badge(text, 'warn') : h('span', {}, text);
    }
    async function load() {
      try {
        const data = await api('GET', '/auction' + qs({ q: f.q, status: f.status, page: f.page }));
        results.replaceChildren(h('div', { class: 'card' }, dataTable([
          { title: '#', render: (l) => l.id }, { title: 'Item', render: (l) => h('span', {}, h('strong', {}, l.item_id), ` · ${l.quality} · nv ${l.item_level}${l.strengthen ? ' +' + l.strengthen : ''}`) }, { title: 'Vendedor', render: (l) => playerLink(l.seller_id, l.seller_name) },
          { title: 'Preço', render: (l) => price(l) }, { title: 'Mercado', render: market }, { title: 'Situação', render: (l) => [badge(tr(l.status), l.status === 'active' ? 'info' : ''), l.buyer ? ' ' + l.buyer : null] }, { title: 'Criado', render: (l) => when(l.created_at) },
          { title: '', render: (l) => (can('admin') && l.status === 'active' ? h('button', { class: 'small danger', onclick: () => cancel(l) }, 'Cancelar') : null) },
        ], data.rows, { empty: 'Nenhum anúncio.' })), pager(f.page, 50, data.total, (page) => { f.page = page; load(); }));
      } catch (e) { results.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    await load();
  }

  // ---------- gifts ----------

  const SEGMENTS = [['all', 'Todos os jogadores'], ['active_30d', 'Entraram nos últimos 30 dias'], ['active_7d', 'Entraram nos últimos 7 dias'], ['new_7d', 'Contas criadas nos últimos 7 dias']];

  async function mailView(root) {
    await loadCatalog();
    const editor = giftEditor(state.catalog.broadcast_caps);
    const segment = h('select', { name: 'segment', onchange: () => count() }, SEGMENTS.map(([v, t]) => h('option', { value: v }, t)));
    const countText = h('span', { class: 'muted' }, '…');
    const note = h('input', { name: 'note', required: true, minLength: 3, maxLength: 80, placeholder: 'Presente de lançamento' });
    const reason = reasonField('Motivo interno (campanha, ticket)');
    const history = h('div', {});
    let current = 0;
    async function count() {
      try { current = (await api('GET', '/broadcast/count' + qs({ segment: segment.value }))).count; countText.textContent = `${num(current)} jogador(es) vão receber`; } catch (e) { countText.textContent = e.message; }
    }
    const form = h('form', {
      onsubmit: async (event) => {
        event.preventDefault();
        if (!form.reportValidity()) return;
        const gift = editor.read();
        if (gift.coins === 0 && Object.keys(gift.assets).length === 0) return toast('Escolha o que enviar.', 'bad');
        await count();
        const rid = requestId();
        const ok = await dialogForm({ title: 'Confirmar o envio em massa', danger: true, submit: `Enviar para ${num(current)}`,
          intro: `${giftSummary(gift)} para ${num(current)} jogador(es) (${SEGMENTS.find((s) => s[0] === segment.value)[1].toLowerCase()}), com a mensagem “${note.value}”. Não dá para desfazer.`, fields: [],
          run: () => api('POST', '/broadcast', { ...gift, segment: segment.value, expect: current, note: note.value.trim(), reason: reason.querySelector('textarea').value.trim(), request_id: rid }) });
        if (ok) { toast('Presentes enviados ao Correio.', 'ok'); loadHistory(); }
      },
    }, h('div', { class: 'field' }, h('label', {}, 'Quem recebe'), h('div', { class: 'row' }, segment, countText), h('div', { class: 'hint' }, 'Só quem tem personagem e não está banido.')), editor.node, field('Mensagem que o jogador vê no Correio', note), reason, h('button', { class: 'primary', type: 'submit' }, 'Revisar e enviar'));
    async function loadHistory() {
      try {
        const rows = await api('GET', '/staff-actions' + qs({ action: 'broadcast.gift' }));
        history.replaceChildren(dataTable([{ title: 'Quando', render: (a) => when(a.created_at) }, { title: 'Quem', render: (a) => a.admin_name }, { title: 'Grupo', render: (a) => a.target_id }, { title: 'Presente', render: (a) => giftSummary({ coins: a.detail.coins || 0, assets: a.detail.assets || {} }) }, { title: 'Enviados', class: 'num', render: (a) => num(a.detail.sent) }, { title: 'Motivo', render: (a) => a.reason }], rows.rows, { empty: 'Nenhum envio em massa ainda.' }));
      } catch (e) { history.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    root.append(pageTitle('Enviar presentes', 'Moedas e pedras pelo Correio do jogo. Para um jogador só, abra a ficha dele.'), h('div', { class: 'grid cols-2' }, h('div', { class: 'card' }, h('h2', {}, 'Novo envio em massa'), form), card('Envios anteriores', history)));
    await Promise.all([count(), loadHistory()]);
  }

  // ---------- game log ----------

  async function auditView(root) {
    const f = filters.audit;
    const results = h('div', {});
    let rows = [];
    const kind = h('input', { value: f.kind, list: 'kinds', placeholder: 'ex.: match, op.*, auction.*', 'aria-label': 'Tipo' });
    const kinds = h('datalist', { id: 'kinds' });
    const account = h('input', { type: 'number', min: 1, value: f.account_id, placeholder: 'ID da conta', 'aria-label': 'Conta' });
    const text = h('input', { type: 'search', value: f.q, placeholder: 'Texto no detalhe', 'aria-label': 'Texto' });
    const since = h('input', { type: 'date', value: f.since, 'aria-label': 'De' });
    const until = h('input', { type: 'date', value: f.until, 'aria-label': 'Até' });
    const exportLink = h('a', { class: 'btn', href: '#', hidden: !can('admin') }, 'Baixar CSV');
    const params = () => ({ kind: f.kind, account_id: f.account_id, q: f.q, since: f.since, until: f.until });
    root.append(pageTitle('Registro do jogo', 'O que os servidores gravam: partidas, compras, trocas, chat. Sem datas, mostra os últimos 7 dias.'),
      h('form', { class: 'filters', onsubmit: (event) => { event.preventDefault(); Object.assign(f, { kind: kind.value.trim(), account_id: account.value, q: text.value.trim(), since: since.value, until: until.value }); rows = []; load(false); } },
        h('div', { class: 'field' }, h('label', {}, 'Tipo (use * no fim para prefixo)'), kind, kinds), h('div', { class: 'field' }, h('label', {}, 'Conta'), account), h('div', { class: 'field search' }, h('label', {}, 'Texto no detalhe'), text), h('div', { class: 'field' }, h('label', {}, 'De'), since), h('div', { class: 'field' }, h('label', {}, 'Até'), until),
        h('button', { class: 'primary', type: 'submit' }, 'Filtrar'), exportLink), results);
    api('GET', '/audit/kinds').then((list) => kinds.replaceChildren(...list.map((k) => h('option', { value: k.kind }, `${k.kind} (${k.n})`)))).catch(() => {});
    async function load(more) {
      try {
        const page = await api('GET', '/audit' + qs({ ...params(), before: more && rows.length ? rows[rows.length - 1].id : '' }));
        rows = more ? rows.concat(page) : page;
        exportLink.href = '/admin/api/audit.csv' + qs(params());
        results.replaceChildren(h('div', { class: 'card' }, dataTable([
          { title: 'Quando', render: (r) => when(r.created_at) }, { title: 'Tipo', render: (r) => badge(r.kind) }, { title: 'Conta', render: (r) => (r.account_id ? playerLink(r.account_id, r.username) : '—') }, { title: 'Servidor', render: (r) => r.server_id || '—' },
          { title: 'Detalhe', render: (r) => detailsJson(r.detail, short(JSON.stringify(r.detail), 90)) },
        ], rows, { empty: 'Nada no período.' })), page.length >= 100 ? h('p', {}, h('button', { onclick: () => load(true) }, 'Carregar mais')) : null);
      } catch (e) { results.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    await load(false);
  }

  // ---------- staff actions ----------

  async function staffActionsView(root) {
    const f = filters.actions;
    const results = h('div', {});
    const action = h('select', { 'aria-label': 'Ação' }, h('option', { value: '' }, 'Todas as ações'), Object.entries(ACTIONS).map(([v, t]) => h('option', { value: v, selected: f.action === v }, t)));
    const account = h('input', { type: 'number', min: 1, value: f.account_id, placeholder: 'ID da conta', 'aria-label': 'Conta' });
    root.append(pageTitle('Ações da equipe', 'Tudo o que foi feito no painel: quem, o quê, em quem e por quê. Não dá para apagar daqui.'),
      h('form', { class: 'filters', onsubmit: (event) => { event.preventDefault(); f.action = action.value; f.account_id = account.value; f.page = 0; load(); } }, h('div', { class: 'field' }, h('label', {}, 'Ação'), action), h('div', { class: 'field' }, h('label', {}, 'Conta afetada'), account), h('button', { class: 'primary', type: 'submit' }, 'Filtrar')), results);
    async function load() {
      try {
        const data = await api('GET', '/staff-actions' + qs({ action: f.action, account_id: f.account_id, page: f.page }));
        results.replaceChildren(h('div', { class: 'card' }, dataTable([
          { title: 'Quando', render: (a) => when(a.created_at) }, { title: 'Quem', render: (a) => a.admin_name }, { title: 'Ação', render: (a) => actionBadge(a.action) }, { title: 'Alvo', render: (a) => (a.account_id ? playerLink(a.account_id, `conta ${a.account_id}`) : `${a.target_type} ${a.target_id}`) },
          { title: 'Motivo', render: (a) => a.reason || '—' }, { title: 'Detalhe', render: (a) => detailsJson(a.detail) }, { title: 'IP', render: (a) => h('span', { class: 'mono' }, a.ip || '—') },
        ], data.rows, { empty: 'Nenhuma ação.' })), pager(f.page, 50, data.total, (page) => { f.page = page; load(); }));
      } catch (e) { results.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    await load();
  }

  // ---------- servers ----------

  async function serversView(root) {
    const box = h('div', { class: 'stack' });
    root.append(pageTitle('Servidores', 'Cada servidor de jogo avisa a API a cada poucos segundos. Mais de 60 s sem aviso é sinal de problema.'), box);
    async function load() {
      const d = await api('GET', '/servers');
      const db = d.database;
      box.replaceChildren(
        h('div', { class: 'card' }, dataTable([
          { title: 'Servidor', render: (s) => [h('strong', {}, s.name), h('div', { class: 'muted small mono' }, s.id)] }, { title: 'Estado', render: (s) => (s.age_seconds < 60 ? badge('no ar', 'ok') : s.age_seconds < 300 ? badge(`sem aviso há ${s.age_seconds}s`, 'warn') : badge('fora do ar', 'bad')) },
          { title: 'Online', class: 'num', render: (s) => `${num(s.online)} / ${num(s.capacity)}` }, { title: 'Ocupação', render: (s) => h('div', { class: 'meter' + (s.online / Math.max(1, s.capacity) > 0.8 ? ' high' : '') }, h('span', { style: `width:${Math.min(100, (s.online / Math.max(1, s.capacity)) * 100)}%` })) },
          { title: 'Reservas de conta', class: 'num', render: (s) => s.present }, { title: 'Endereço', render: (s) => h('span', { class: 'mono' }, s.url) },
        ], d.servers, { empty: 'Nenhum servidor jamais se anunciou.' })),
        h('div', { class: 'grid cols-2' }, card('API e banco', facts([['API no ar desde', `${when(d.api_started)} (${ago(d.api_started)})`], ['Hora do banco', when(db.now)], ['Tamanho do banco', bytes(db.size_bytes)], ['PostgreSQL', db.version.split(' on ')[0]]]))));
    }
    await load();
    const timer = setInterval(() => load().catch(() => {}), 15000);
    return () => clearInterval(timer);
  }

  // ---------- staff, system, my account ----------

  async function staffView(root) {
    const box = h('div', {});
    root.append(pageTitle('Equipe', 'Quem usa o painel. A conta nova recebe uma senha temporária e cadastra o segundo fator no primeiro acesso.', h('button', { class: 'primary', onclick: create }, 'Nova conta')), h('div', { class: 'card' }, box));
    function create() {
      dialogForm({ title: 'Nova conta da equipe', submit: 'Criar',
        intro: 'Visualizador vê só números. Suporte atende jogadores. Administrador bane e envia presentes grandes. Dono gerencia a equipe.',
        fields: [field('Usuário', h('input', { name: 'username', required: true, pattern: '[A-Za-z0-9_]{3,16}', autocomplete: 'off' }), '3 a 16 letras, números ou _.'),
          field('Papel', h('select', { name: 'role' }, Object.entries(ROLE_NAME).map(([v, t]) => h('option', { value: v }, t))))],
        run: (form) => api('POST', '/staff', { username: form.get('username'), role: form.get('role') }),
        after: (r) => h('div', {}, h('p', {}, `Conta ${r.username} criada. Passe esta senha temporária (aparece só agora):`), h('div', { class: 'secret' }, r.password)),
      }).then(() => load());
    }
    const update = (s, body, text) => api('POST', `/staff/${s.id}/update`, body).then(() => { toast(text, 'ok'); load(); }).catch(fail);
    const secretDialog = (title, path, s, intro) => dialogForm({ title, submit: 'Confirmar', intro, fields: [], run: () => api('POST', `/staff/${s.id}/${path}`, {}), after: (r) => (r && r.password ? h('div', {}, h('p', {}, 'Senha temporária (aparece só agora):'), h('div', { class: 'secret' }, r.password)) : h('p', {}, 'Pronto.')) }).then(() => load());
    async function load() {
      try {
        const list = await api('GET', '/staff');
        box.replaceChildren(dataTable([
          { title: 'Usuário', render: (s) => [h('strong', {}, s.username), s.id === state.me.admin.id ? ' (você)' : ''] },
          { title: 'Papel', render: (s) => (s.id === state.me.admin.id ? ROLE_NAME[s.role] : h('select', { 'aria-label': 'Papel de ' + s.username, onchange: (event) => update(s, { role: event.target.value }, 'Papel alterado.') }, Object.entries(ROLE_NAME).map(([v, t]) => h('option', { value: v, selected: s.role === v }, t)))) },
          { title: 'Situação', render: (s) => [s.active ? badge('ativo', 'ok') : badge('desativado', 'bad'), s.locked ? [' ', badge('bloqueado', 'warn')] : null, s.must_change_password ? [' ', badge('senha temporária', 'warn')] : null] },
          { title: '2FA', render: (s) => (s.totp_enabled ? badge('ativo', 'ok') : badge('pendente', 'warn')) }, { title: 'Último acesso', render: (s) => ago(s.last_login) }, { title: 'Sessões', class: 'num', render: (s) => s.sessions }, { title: 'Criada por', render: (s) => s.created_by || '—' },
          { title: '', render: (s) => (s.id === state.me.admin.id ? null : h('span', { class: 'row' },
            h('button', { class: 'small', onclick: () => update(s, { active: !s.active }, s.active ? 'Conta desativada.' : 'Conta ativada.') }, s.active ? 'Desativar' : 'Ativar'),
            h('button', { class: 'small', onclick: () => secretDialog('Reiniciar o segundo fator de ' + s.username, 'reset-2fa', s, 'A pessoa cadastra um novo aplicativo no próximo acesso.') }, 'Reiniciar 2FA'),
            h('button', { class: 'small', onclick: () => secretDialog('Senha temporária para ' + s.username, 'reset-password', s, 'Encerra as sessões dela e gera uma senha temporária.') }, 'Nova senha'))) },
        ], list));
      } catch (e) { box.replaceChildren(h('p', { class: 'error' }, e.message)); }
    }
    await load();
  }

  async function systemView(root) {
    const d = await api('GET', '/system');
    const s = d.settings;
    const yes = (v) => (v ? badge('sim', 'ok') : badge('não', 'warn'));
    root.append(pageTitle('Sistema', 'Só leitura. Segredos nunca aparecem aqui: o painel mostra apenas se estão configurados.'),
      h('div', { class: 'stack' }, h('div', { class: 'grid cols-2' },
        card('Pagamentos', facts([['Stripe: chave da API', yes(s.stripe_api)], ['Stripe: segredo do webhook', yes(s.stripe_webhook)], ['Steam: loja configurada', yes(s.steam_api)], ['Steam em modo de teste (sandbox)', s.steam_sandbox ? badge('sim', 'warn') : badge('não', 'ok')]])),
        card('Segurança e privacidade', facts([['Versão dos Termos exigida', s.legal_version], ['API atrás de proxy (X-Forwarded-For)', yes(s.trust_proxy)], ['Duração do login de jogador', `${s.session_days} dias`], ['Tentativas de login por minuto (por IP)', s.auth_per_minute],
          ['Painel: segundo fator obrigatório', yes(s.admin.require_2fa)], ['Painel: sessão', `${s.admin.session_hours} h (ociosa: ${s.admin.idle_minutes} min)`], ['Painel: redes liberadas', s.admin.allowed_networks ? String(s.admin.allowed_networks) : 'qualquer endereço'], ['Painel: registro de ações guardado', s.admin.audit_days ? `${s.admin.audit_days} dias` : 'para sempre']])),
        card('Retenção dos registros (dias)', facts(Object.entries(s.retention_days).map(([k, v]) => [{ audit: 'Atividade', chat: 'Chat', access: 'Acessos (Marco Civil)', reports: 'Denúncias analisadas', orders: 'Pedidos', challenge: 'Desafio diário' }[k] || k, v]))),
        card('Migrações aplicadas', dataTable([{ title: 'Arquivo', render: (m) => m.name.replace('migrations/', '') }, { title: 'Quando', render: (m) => when(m.applied_at) }], d.migrations))),
        card('Maiores tabelas', dataTable([{ title: 'Tabela', render: (t) => t.table }, { title: 'Linhas (estimativa)', class: 'num', render: (t) => num(t.rows) }, { title: 'Tamanho', class: 'num', render: (t) => bytes(t.bytes) }], d.tables)),
        h('p', { class: 'muted small' }, `API no ar desde ${when(d.api_started)}.`)));
  }

  async function accountView(root) {
    const me = state.me.admin;
    root.append(pageTitle('Minha conta'), h('div', { class: 'grid cols-2' },
      card('Dados', facts([['Usuário', me.username], ['Papel', ROLE_NAME[me.role]], ['Segundo fator', me.totp_enabled ? badge('ativo', 'ok') : badge('pendente', 'warn')], ['Último acesso', when(me.last_login)]])),
      card('Trocar a senha', passwordForm(async () => { state.me = null; await route(); }), 'Ao trocar, os outros dispositivos saem.')));
  }

  window.addEventListener('hashchange', route);
  route();
})();
