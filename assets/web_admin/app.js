/* Tiffin desktop admin — a dependency-free SPA over the host's /api (PRD
   §13.4). Scanning is intentionally absent (native app only). Served by the
   embedded shelf server from the same origin, so fetch('/api/...') needs no
   CORS handling. Hash routing means the server only ever serves index.html. */

'use strict';

// --- tiny DOM helper --------------------------------------------------------
function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  if (props) {
    for (const [k, v] of Object.entries(props)) {
      if (k === 'class') el.className = v;
      else if (k === 'html') el.innerHTML = v;
      else if (k === 'text') el.textContent = v;
      else if (k.startsWith('on') && typeof v === 'function') el.addEventListener(k.slice(2), v);
      else if (v === true) el.setAttribute(k, '');
      else if (v !== false && v != null) el.setAttribute(k, v);
    }
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  }
  return el;
}
const $ = (sel, root = document) => root.querySelector(sel);

// --- api client -----------------------------------------------------------
const api = {
  get token() { return localStorage.getItem('tiffin_token'); },
  set token(v) { v ? localStorage.setItem('tiffin_token', v) : localStorage.removeItem('tiffin_token'); },

  async req(method, path, body) {
    let res;
    try {
      res = await fetch('/api' + path, {
        method,
        headers: {
          'content-type': 'application/json',
          ...(this.token ? { authorization: 'Bearer ' + this.token } : {}),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (e) {
      throw { code: 'network', message: 'Could not reach the host. Is the server running?' };
    }
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) {
      if (res.status === 401) { api.token = null; location.hash = '#/login'; }
      throw { code: (data && data.error) || 'error', message: (data && data.message) || `Request failed (${res.status}).` };
    }
    return data;
  },
  get(p) { return this.req('GET', p); },
  post(p, b) { return this.req('POST', p, b === undefined ? null : b); },
  patch(p, b) { return this.req('PATCH', p, b); },
  del(p) { return this.req('DELETE', p); },
};

// --- feedback -----------------------------------------------------------
let toastTimer;
function toast(msg, ok = true, ms) {
  const t = $('#toast');
  t.textContent = msg;
  t.className = 'toast' + (ok ? '' : ' bad');
  t.hidden = false;
  clearTimeout(toastTimer);
  if (ms !== 0) toastTimer = setTimeout(() => (t.hidden = true), ms || (ok ? 3000 : 6000));
}

// Runs fn with visible feedback the whole way: an immediate "Working…" line,
// then a success line, or on failure the error's message + code — never a
// silent no-op.
async function guard(fn, okMsg) {
  toast('Working…', true, 0);
  try {
    const r = await fn();
    toast(okMsg || 'Done.');
    return r ?? true;
  } catch (e) {
    const msg = e && e.message ? e.message : String(e);
    const code = e && e.code ? `  [${e.code}]` : '';
    toast(msg + code, false);
    return false;
  }
}

// Empty-state block — a line of personality instead of a blank table.
const QUIPS = {
  members: ['Not a soul on the list yet. Add your first hungry human.', 'Zero members. Big "new school" energy.'],
  topups: ['No top-ups yet. The ledger is squeaky clean.'],
  scans: ['No scans yet. The scanner is well-rested.'],
  menu: ['Nothing planned this month. Chef’s surprise, then?'],
  categories: ['No categories. "Jain", "Normal", "Staff" — your call.'],
  ingredients: ['Pantry’s empty on paper. Add what you actually buy.'],
  recipes: ['No recipes. The dishes are keeping their secrets.'],
  purchase: ['Shopping list is empty. Either you’re stocked, or menus need planning.'],
  expenses: ['No expenses logged. Profit looks amazing from here.'],
  refunds: ['No refunds. Everyone’s eating what they paid for.'],
  users: ['Just you so far. Add a counter or scanner account when you need one.'],
};
function emptyState(key, title, actionLabel, onAction) {
  const quips = QUIPS[key] || ['Nothing here yet.'];
  return h('div', { class: 'card', style: 'text-align:center;padding:40px' },
    h('div', { style: 'font-size:32px' }, '―'),
    h('h2', {}, title),
    h('div', { class: 'muted' }, quips[Math.floor(Math.random() * quips.length)]),
    (actionLabel && onAction)
      ? h('div', { style: 'margin-top:16px' }, h('button', { class: 'primary', onclick: onAction }, actionLabel))
      : null);
}

function modal(title, bodyNode, { okLabel = 'Save', onOk } = {}) {
  return new Promise((resolve) => {
    const close = (val) => { back.remove(); resolve(val); };
    const okBtn = h('button', { class: 'primary', onclick: async () => {
      if (onOk) { const r = await onOk(); if (r === false) return; }
      close(true);
    } }, okLabel);
    const back = h('div', { class: 'modal-back', onclick: (e) => { if (e.target === back) close(false); } },
      h('div', { class: 'modal' },
        h('h2', { text: title }),
        bodyNode,
        h('div', { class: 'actions' },
          h('button', { class: 'ghost', onclick: () => close(false) }, 'Cancel'),
          okBtn)));
    document.body.append(back);
  });
}

// --- small shared state (prices, category/ingredient lists) ---------------
const store = {
  settings: null, categories: null, ingredients: null,
  async ensureSettings() { return this.settings ??= await api.get('/settings'); },
  async ensureCategories() { return this.categories ??= await api.get('/menu-categories'); },
  async ensureIngredients() { return this.ingredients ??= await api.get('/ingredients'); },
  bust() { this.settings = this.categories = this.ingredients = null; },
};

// Local calendar date (not UTC) — `toISOString` would roll the day over for
// users east/west of UTC. Menu entry dates from the API are already local
// `yyyy-mm-dd`, so the grid must compare against a local "today" too.
const ymd = (d) => {
  const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
  return local.toISOString().slice(0, 10);
};
const fmtDate = (s) => new Date(s).toLocaleString();
const fmtDay = (s) => new Date(s).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });

// --- views --------------------------------------------------------------
const views = {};

views.login = async () => {
  const branding = await api.get('/settings/branding').catch(() => ({ appName: 'Tiffin' }));
  const u = h('input', { autofocus: true });
  const p = h('input', { type: 'password' });
  const err = h('div', { class: 'muted', style: 'color:var(--reject)' });
  const btn = h('button', { class: 'primary', onclick: () => submit() }, 'Sign in');
  let busy = false;
  const submit = async () => {
    if (busy) return;
    err.textContent = '';
    busy = true;
    btn.disabled = true;
    btn.textContent = 'Signing in…';
    try {
      const s = await api.post('/auth/login', { username: u.value.trim(), password: p.value });
      if (s.role !== 'admin' && s.role !== 'counter') {
        err.textContent = 'This surface is for admin/counter accounts.';
        return;
      }
      api.token = s.token;
      localStorage.setItem('tiffin_role', s.role);
      localStorage.setItem('tiffin_user', s.username);
      location.hash = '#/members';
    } catch (e) {
      err.textContent = e.message;
    } finally {
      busy = false;
      btn.disabled = false;
      btn.textContent = 'Sign in';
    }
  };
  for (const el of [u, p]) {
    el.addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
  }
  return h('div', { class: 'login-wrap' },
    h('div', { class: 'card login-card' },
      h('h1', { text: branding.appName }),
      h('div', { class: 'muted' }, 'Desktop admin'),
      h('label', {}, 'Username'), u,
      h('label', {}, 'Password'), p,
      err,
      h('div', { style: 'margin-top:16px' }, btn)));
};

// generic resource table with add/edit/delete via a field spec
function crudView({ title, path, columns, fields, toBody, canDelete = true, extra, emptyKey }) {
  return async () => {
    const rows = await api.get(path);
    const openForm = (row) => {
      const inputs = {};
      const body = h('div', {});
      for (const f of fields) {
        let input;
        if (f.type === 'select') {
          input = h('select', {}, ...f.options.map((o) =>
            h('option', { value: o.value, ...(String(row?.[f.key] ?? f.default) === String(o.value) ? { selected: true } : {}) }, o.label)));
        } else if (f.type === 'textarea') {
          input = h('textarea', { rows: 3 }); input.value = row?.[f.key] ?? '';
        } else {
          input = h('input', { type: f.type || 'text' });
          input.value = row?.[f.key] ?? (f.default ?? '');
        }
        inputs[f.key] = input;
        body.append(h('label', {}, f.label), input);
      }
      modal(row ? `Edit ${title}` : `New ${title}`, body, {
        onOk: async () => {
          const payload = toBody(inputs, row);
          const ok = await guard(
            () => row ? api.patch(`${path}/${row.id}`, payload) : api.post(path, payload),
            'Saved.');
          if (ok) render();
          return ok;
        },
      });
    };
    return h('div', {},
      h('div', { class: 'row between' }, h('h1', { text: title }),
        h('button', { class: 'primary', onclick: () => openForm(null) }, '+ New')),
      extra ? extra(render) : null,
      rows.length === 0
        ? emptyState(emptyKey || 'members', `No ${title.toLowerCase()} yet`, `+ New ${title}`, () => openForm(null))
        : h('table', {},
        h('thead', {}, h('tr', {}, ...columns.map((c) => h('th', { text: c.label })), h('th', { text: '' }))),
        h('tbody', {}, ...rows.map((r) => h('tr', {},
          ...columns.map((c) => h('td', {}, c.render ? c.render(r) : String(r[c.key] ?? ''))),
          h('td', {},
            h('button', { class: 'ghost', onclick: () => openForm(r) }, 'Edit'),
            canDelete ? h('button', { class: 'ghost danger', onclick: async () => {
              if (await guard(() => api.del(`${path}/${r.id}`), 'Deleted.')) render();
            } }, 'Del') : null))))));
  };
}

// members ------------------------------------------------------------------
views.members = async () => {
  const [members, settings] = await Promise.all([
    api.get('/members'), store.ensureSettings(),
  ]);

  const openForm = (m) => {
    const type = h('select', {}, h('option', { value: 'student' }, 'Student'), h('option', { value: 'staff' }, 'Staff'));
    if (m) { type.value = m.type; type.disabled = true; }
    const name = h('input', {}); name.value = m?.name ?? '';
    const className = h('input', {}); className.value = m?.className ?? '';
    const roll = h('input', {}); roll.value = m?.rollNumber ?? '';
    const staffId = h('input', {}); staffId.value = m?.staffId ?? '';
    const grace = h('input', { type: 'number' }); grace.value = m?.graceAllowanceOverride ?? '';
    const status = h('select', {}, h('option', { value: 'active' }, 'Active'), h('option', { value: 'inactive' }, 'Inactive'));
    if (m) status.value = m.status;
    const studentFields = h('div', {}, h('label', {}, 'Class'), className, h('label', {}, 'Roll number'), roll);
    const staffFields = h('div', {}, h('label', {}, 'Staff ID'), staffId);
    const sync = () => { const s = type.value === 'student'; studentFields.hidden = !s; staffFields.hidden = s; };
    type.addEventListener('change', sync);
    const body = h('div', {}, h('label', {}, 'Type'), type, h('label', {}, 'Name'), name,
      studentFields, staffFields,
      h('label', {}, 'Grace override (blank = global)'), grace,
      ...(m ? [h('label', {}, 'Status'), status] : []));
    sync();
    modal(m ? 'Edit member' : 'New member', body, {
      onOk: async () => {
        const isStudent = type.value === 'student';
        const payload = {
          name: name.value.trim(),
          className: isStudent ? (className.value.trim() || null) : null,
          rollNumber: isStudent ? (roll.value.trim() || null) : null,
          staffId: !isStudent ? (staffId.value.trim() || null) : null,
          graceAllowanceOverride: grace.value === '' ? null : Number(grace.value),
        };
        let ok;
        if (m) ok = await guard(() => api.patch(`/members/${m.id}`, { ...payload, status: status.value }), 'Member updated.');
        else ok = await guard(() => api.post('/members', { type: type.value, ...payload }), 'Member created.');
        if (ok) render();
        return ok;
      },
    });
  };

  const credit = (m) => {
    const l = h('input', { type: 'number', value: '0' });
    const b = h('input', { type: 'number', value: '0' });
    const br = h('input', { type: 'number', value: '0' });
    modal(`Credit ${m.name}`, h('div', {}, h('label', {}, 'Lunch'), l, h('label', {}, 'Breakfast'), b, h('label', {}, 'Brunch'), br), {
      okLabel: 'Add units',
      onOk: async () => {
        const ok = await guard(() => api.post(`/members/${m.id}/credit`, {
          lunch: Number(l.value) || 0, breakfast: Number(b.value) || 0, brunch: Number(br.value) || 0,
        }), 'Units added.');
        if (ok) render();
        return ok;
      },
    });
  };

  const showQr = async (m) => {
    const res = await fetch(`/api/members/${m.id}/qr`, { headers: { authorization: 'Bearer ' + api.token } });
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    modal(m.name, h('div', { style: 'text-align:center' },
      h('img', { src: url, style: 'width:280px;height:280px;image-rendering:pixelated' }),
      h('div', { class: 'muted' }, m.qrCodeId)), { okLabel: 'Close', onOk: () => { URL.revokeObjectURL(url); } });
  };

  const header = h('div', { class: 'row between' },
    h('h1', {}, members.length ? `Members (${members.length})` : 'Members'),
    h('button', { class: 'primary', onclick: () => openForm(null) }, '+ New member'));

  if (!members.length) {
    return h('div', {}, header,
      emptyState('members', 'No members yet', '+ New member', () => openForm(null)));
  }

  return h('div', {}, header,
    h('table', {},
      h('thead', {}, h('tr', {}, ...['Name', 'Type', 'Detail', 'Lunch', 'Bfast', 'Brunch', 'Status', ''].map((t) => h('th', { text: t })))),
      h('tbody', {}, ...members.map((m) => h('tr', {},
        h('td', { text: m.name }),
        h('td', { text: m.type }),
        h('td', { text: m.type === 'student' ? `${m.className || '—'} / ${m.rollNumber || '—'}` : (m.staffId || '—') }),
        h('td', { text: m.balances.lunch }),
        h('td', { text: m.balances.breakfast }),
        h('td', { text: m.balances.brunch }),
        h('td', {}, m.status === 'active' ? h('span', { class: 'pill ok' }, 'active') : h('span', { class: 'pill' }, 'inactive')),
        h('td', {},
          h('button', { class: 'ghost', onclick: () => openForm(m) }, 'Edit'),
          h('button', { class: 'ghost', onclick: () => credit(m) }, 'Credit'),
          h('button', { class: 'ghost', onclick: () => showQr(m) }, 'QR')))))),
    h('div', { class: 'muted', style: 'margin-top:8px' }, `Unit prices: lunch ${settings.unitPrices.lunch} · breakfast ${settings.unitPrices.breakfast} · brunch ${settings.unitPrices.brunch}`));
};

// top-ups ----------------------------------------------------------------
views.topups = async () => {
  const [members, settings, topups] = await Promise.all([
    api.get('/members?status=active'), store.ensureSettings(), api.get('/topups'),
  ]);
  const memberById = Object.fromEntries(members.map((m) => [m.id, m]));
  if (!members.length) return h('div', {}, h('h1', {}, 'Top-ups & billing'),
    emptyState('members', 'No members to top up', '', null));


  const open = () => {
    const sel = h('select', {}, ...members.map((m) => h('option', { value: m.id }, `${m.name} (${m.type})`)));
    const l = h('input', { type: 'number', value: '0' });
    const b = h('input', { type: 'number', value: '0' });
    const br = h('input', { type: 'number', value: '0' });
    const method = h('select', {}, h('option', { value: 'cash' }, 'Cash'), h('option', { value: 'upi' }, 'UPI'));
    const total = h('b', { text: 'Rs. 0.00' });
    const recalc = () => {
      const p = settings.unitPrices;
      const amt = (Number(l.value) || 0) * p.lunch + (Number(b.value) || 0) * p.breakfast + (Number(br.value) || 0) * p.brunch;
      total.textContent = 'Rs. ' + amt.toFixed(2);
    };
    [l, b, br].forEach((i) => i.addEventListener('input', recalc));
    const body = h('div', {}, h('label', {}, 'Member'), sel,
      h('label', {}, 'Lunch units'), l, h('label', {}, 'Breakfast units'), b, h('label', {}, 'Brunch units'), br,
      h('label', {}, 'Payment'), method,
      h('div', { class: 'card', style: 'margin-top:12px' }, h('div', { class: 'row between' }, h('span', {}, 'TOTAL'), total)));
    modal('Top-up & bill', body, {
      okLabel: 'Charge',
      onOk: async () => {
        if ((Number(l.value) || 0) + (Number(b.value) || 0) + (Number(br.value) || 0) === 0) {
          toast('Add at least one unit.', false); return false;
        }
        const created = await guard(() => api.post('/topups', {
          memberId: Number(sel.value), lunchUnits: Number(l.value) || 0,
          breakfastUnits: Number(b.value) || 0, brunchUnits: Number(br.value) || 0,
          paymentMethod: method.value,
        }), 'Balances credited.');
        if (created) { render(); showBill(created); }
        return !!created;
      },
    });
  };

  const showBill = async (t) => {
    const kids = [h('div', {}, `Amount: Rs. ${t.amount.toFixed(2)} (${t.paymentMethod.toUpperCase()})`),
      h('div', {}, `Status: ${t.paymentStatus}`)];
    if (t.paymentMethod === 'upi' && t.hasUpiQr) {
      const res = await fetch(`/api/topups/${t.id}/upi-qr`, { headers: { authorization: 'Bearer ' + api.token } });
      const url = URL.createObjectURL(await res.blob());
      kids.push(h('div', { class: 'muted', style: 'margin-top:12px' }, 'Ask the payer to scan:'),
        h('img', { src: url, style: 'width:220px;height:220px' }));
    }
    if (t.hasBill) kids.push(h('div', { style: 'margin-top:12px' },
      h('a', { href: `/api/topups/${t.id}/bill?token=${api.token}`, target: '_blank' }, 'Open bill PDF')));
    modal(`Bill #${t.id}`, h('div', {}, ...kids), { okLabel: 'Done', onOk: () => {} });
  };

  return h('div', {},
    h('div', { class: 'row between' }, h('h1', {}, 'Top-ups & billing'),
      h('button', { class: 'primary', onclick: open }, '+ New top-up')),
    h('table', {},
      h('thead', {}, h('tr', {}, ...['#', 'Member', 'L/B/Br', 'Amount', 'Method', 'Status', 'When', ''].map((t) => h('th', { text: t })))),
      h('tbody', {}, ...topups.map((t) => h('tr', {},
        h('td', { text: t.id }),
        h('td', { text: memberById[t.memberId]?.name ?? t.memberId }),
        h('td', { text: `${t.lunchUnits}/${t.breakfastUnits}/${t.brunchUnits}` }),
        h('td', { text: 'Rs. ' + t.amount.toFixed(2) }),
        h('td', { text: t.paymentMethod }),
        h('td', {}, t.paymentStatus === 'confirmed' ? h('span', { class: 'pill ok' }, 'confirmed') : h('span', { class: 'pill warn' }, 'pending')),
        h('td', { text: fmtDate(t.createdAt) }),
        h('td', {},
          t.paymentStatus === 'pending' ? h('button', { class: 'ghost', onclick: async () => {
            if (await guard(() => api.post(`/topups/${t.id}/confirm-payment`), 'Confirmed.')) render();
          } }, 'Mark received') : null,
          t.hasBill ? h('a', { href: `/api/topups/${t.id}/bill?token=${api.token}`, target: '_blank' }, h('button', { class: 'ghost' }, 'Bill')) : null))))));
};

// scan log -------------------------------------------------------------
views.scans = async () => {
  const scans = await api.get('/scans?limit=300');
  if (!scans.length) return h('div', {},
    h('h1', {}, 'Scan log'),
    emptyState('scans', 'No scan log yet', null, null));

  return h('div', {},
    h('h1', {}, 'Scan log'),
    h('table', {},
      h('thead', {}, h('tr', {}, ...['Member', 'Meal', 'When', 'Flags', ''].map((t) => h('th', { text: t })))),
      h('tbody', {}, ...scans.map((s) => h('tr', {},
        h('td', { text: s.memberName }),
        h('td', { text: s.mealType }),
        h('td', { text: fmtDate(s.scannedAt) }),
        h('td', {}, s.reversed ? h('span', { class: 'pill bad' }, 'reversed') : (s.viaGrace ? h('span', { class: 'pill warn' }, 'grace') : '')),
        h('td', {}, (s.result === 'accepted' && !s.reversed) ? h('button', { class: 'ghost', onclick: async () => {
          const r = await guard(() => api.post('/scan/reverse', { scanId: s.id }));
          if (r && r.success) { toast(r.message); render(); }
          else if (r) toast(r.message, false);
        } }, 'Reverse') : ''))))));
};

// menu calendar ------------------------------------------------------
// Month grid + day panel, matching the mobile app (lib/ui/admin/menu_screen.dart).
// Selected month/day survive a re-render (they live outside the view fn).
const MEAL_COLOR = { breakfast: 'var(--warn)', lunch: 'var(--accent)', brunch: 'var(--accept)' };
const menuState = {
  month: new Date(new Date().getFullYear(), new Date().getMonth(), 1),
  day: ymd(new Date()),
};

views.menu = async () => {
  const m = menuState.month;
  const monthStart = new Date(m.getFullYear(), m.getMonth(), 1);
  const monthEnd = new Date(m.getFullYear(), m.getMonth() + 1, 0);
  const [entries, cats] = await Promise.all([
    api.get(`/menu?start=${ymd(monthStart)}&end=${ymd(monthEnd)}`), store.ensureCategories(),
  ]);
  const byDay = {};
  for (const e of entries) (byDay[e.date] ??= []).push(e);

  const addEntry = (dateStr) => {
    const date = h('input', { type: 'date', value: dateStr });
    const meal = h('select', {}, ...['breakfast', 'lunch', 'brunch'].map((x) => h('option', { value: x }, x)));
    const catBox = h('div', { class: 'row' }, ...cats.map((c) => {
      const cb = h('input', { type: 'checkbox', value: c.name, style: 'width:auto' });
      return h('label', { style: 'display:flex;gap:4px;align-items:center;text-transform:none' }, cb, c.name);
    }));
    const items = h('input', { placeholder: 'dal, rice, sabzi' });
    modal('Add menu entry', h('div', {}, h('label', {}, 'Date'), date, h('label', {}, 'Meal'), meal,
      h('label', {}, 'Categories'), catBox, h('label', {}, 'Items (comma-separated)'), items), {
      okLabel: 'Add',
      onOk: async () => {
        const chosen = [...catBox.querySelectorAll('input:checked')].map((i) => i.value);
        const ok = await guard(() => api.post('/menu', {
          date: date.value, mealType: meal.value, categories: chosen,
          items: items.value.split(',').map((s) => s.trim()).filter(Boolean),
        }), 'Entry added.');
        if (ok) { menuState.day = date.value; render(); }
        return ok;
      },
    });
  };
  const stepMonth = (delta) => {
    menuState.month = new Date(m.getFullYear(), m.getMonth() + delta, 1);
    render();
  };

  // grid: Monday-first, leading blanks for the first row
  const leadingBlanks = (monthStart.getDay() + 6) % 7;
  const todayStr = ymd(new Date());
  const cells = [];
  for (let i = 0; i < leadingBlanks; i++) cells.push(h('div', { class: 'cal-cell blank' }));
  for (let d = 1; d <= monthEnd.getDate(); d++) {
    const dateStr = ymd(new Date(m.getFullYear(), m.getMonth(), d));
    const dayEntries = byDay[dateStr] || [];
    const meals = [...new Set(dayEntries.map((e) => e.mealType))];
    const cls = 'cal-cell'
      + (dateStr === menuState.day ? ' selected' : '')
      + (dateStr === todayStr ? ' today' : '');
    cells.push(h('div', { class: cls, onclick: () => { menuState.day = dateStr; render(); } },
      h('div', { class: 'cal-num' }, String(d)),
      h('div', { class: 'cal-dots' }, ...meals.map((mt) =>
        h('span', { class: 'cal-dot', style: `background:${MEAL_COLOR[mt] || 'var(--ink)'}` }))),
      dayEntries.length ? h('div', { class: 'cal-count' }, String(dayEntries.length)) : null));
  }

  const selEntries = (byDay[menuState.day] || []).slice()
    .sort((a, b) => a.mealType.localeCompare(b.mealType));
  const panel = h('div', { class: 'card' },
    h('div', { class: 'row between' },
      h('h3', { style: 'margin:0', text: fmtDay(menuState.day) }),
      h('button', { class: 'primary', onclick: () => addEntry(menuState.day) }, '+ Add')),
    selEntries.length
      ? h('div', {}, ...selEntries.map((e) => h('div', { class: 'row between', style: 'padding:6px 0;border-top:2px solid var(--surface-muted)' },
          h('div', {},
            h('span', { class: 'cal-dot', style: `background:${MEAL_COLOR[e.mealType] || 'var(--ink)'};margin-right:6px` }),
            h('b', {}, e.mealType + ' '),
            h('span', { class: 'muted' }, e.categories.join(', ')),
            h('div', {}, e.items.join(', '))),
          h('button', { class: 'ghost danger', onclick: async () => {
            if (await guard(() => api.del(`/menu/${e.id}`), 'Removed.')) render();
          } }, 'Del'))))
      : h('div', { class: 'muted', style: 'margin-top:8px' }, 'Nothing planned for this day.'));

  return h('div', {},
    h('div', { class: 'row between' },
      h('div', { class: 'row' },
        h('button', { class: 'ghost', onclick: () => stepMonth(-1) }, '‹'),
        h('h1', { style: 'margin:0', text: m.toLocaleDateString(undefined, { month: 'long', year: 'numeric' }) }),
        h('button', { class: 'ghost', onclick: () => stepMonth(1) }, '›')),
      h('button', { class: 'primary', onclick: () => addEntry(menuState.day) }, '+ Add entry')),
    h('div', { class: 'cal-head' }, ...['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((w) => h('div', {}, w))),
    h('div', { class: 'cal-grid' }, ...cells),
    panel);
};

views.categories = crudView({
  title: 'Menu category', path: '/menu-categories', emptyKey: 'categories',
  columns: [{ label: 'Name', key: 'name' }, { label: 'Description', key: 'description' }],
  fields: [{ key: 'name', label: 'Name' }, { key: 'description', label: 'Description' }],
  toBody: (i) => ({ name: i.name.value.trim(), description: i.description.value.trim() || null }),
});

views.ingredients = crudView({
  title: 'Ingredient', path: '/ingredients', emptyKey: 'ingredients',
  columns: [{ label: 'Name', key: 'name' }, { label: 'Unit', key: 'unit' }],
  fields: [{ key: 'name', label: 'Name' }, { key: 'unit', label: 'Unit (kg, litre, pcs…)' }],
  toBody: (i) => ({ name: i.name.value.trim(), unit: i.unit.value.trim() }),
});

// recipes -----------------------------------------------------------
views.recipes = async () => {
  const [recipes, ingredients] = await Promise.all([api.get('/recipes'), store.ensureIngredients()]);
  const nameById = Object.fromEntries(ingredients.map((i) => [i.id, i.name]));

  const open = (r) => {
    const dish = h('input', {}); dish.value = r?.dishName ?? '';
    const lines = h('div', {});
    const addLine = (ri) => {
      const sel = h('select', { style: 'width:50%' }, ...ingredients.map((i) => h('option', { value: i.id }, i.name)));
      if (ri) sel.value = ri.ingredientId;
      const note = h('input', { style: 'width:45%', placeholder: '2kg / 50 servings' }); note.value = ri?.quantityNote ?? '';
      lines.append(h('div', { class: 'row', style: 'margin-bottom:4px' }, sel, note));
    };
    (r?.ingredients ?? [null]).forEach(addLine);
    modal(r ? 'Edit recipe' : 'New recipe', h('div', {}, h('label', {}, 'Dish name'), dish,
      h('label', {}, 'Ingredients'), lines,
      h('button', { class: 'ghost', onclick: () => addLine(null) }, '+ ingredient')), {
      onOk: async () => {
        const rows = [...lines.querySelectorAll('.row')].map((row) => {
          const [sel, note] = row.querySelectorAll('select,input');
          return { ingredientId: Number(sel.value), quantityNote: note.value.trim() };
        }).filter((x) => x.quantityNote);
        const payload = { dishName: dish.value.trim(), ingredients: rows };
        const ok = await guard(() => r ? api.patch(`/recipes/${r.id}`, payload) : api.post('/recipes', payload), 'Saved.');
        if (ok) render();
        return ok;
      },
    });
  };
  const header = h('div', { class: 'row between' }, h('h1', {}, 'Recipes'),
    h('button', { class: 'primary', onclick: () => open(null) }, '+ New'));
  if (!recipes.length) {
    return h('div', {}, header,
      emptyState('recipes', 'No recipes yet', '+ New recipe', () => open(null)));
  }
  return h('div', {}, header,
    h('table', {}, h('thead', {}, h('tr', {}, h('th', {}, 'Dish'), h('th', {}, 'Ingredients'), h('th', {}, ''))),
      h('tbody', {}, ...recipes.map((r) => h('tr', {},
        h('td', { text: r.dishName }),
        h('td', { text: r.ingredients.map((x) => nameById[x.ingredientId] || x.ingredientId).join(', ') }),
        h('td', {}, h('button', { class: 'ghost', onclick: () => open(r) }, 'Edit'),
          h('button', { class: 'ghost danger', onclick: async () => { if (await guard(() => api.del(`/recipes/${r.id}`), 'Deleted.')) render(); } }, 'Del')))))));
};

// purchase schedule ------------------------------------------------
views.purchase = async () => {
  const [items, ingredients] = await Promise.all([api.get('/purchase-schedule'), store.ensureIngredients()]);
  const generate = () => {
    const s = h('input', { type: 'date', value: ymd(new Date()) });
    const e = h('input', { type: 'date', value: ymd(new Date(Date.now() + 7 * 864e5)) });
    modal('Generate from menu', h('div', {}, h('label', {}, 'From'), s, h('label', {}, 'To'), e), {
      okLabel: 'Generate',
      onOk: async () => {
        const r = await guard(() => api.post(`/purchase-schedule/generate?start=${s.value}&end=${e.value}`));
        if (r) { toast(`Added ${r.created} new item(s).`); render(); }
        return !!r;
      },
    });
  };
  const addManual = () => {
    const sel = h('select', {}, ...ingredients.map((i) => h('option', { value: i.id }, i.name)));
    const date = h('input', { type: 'date', value: ymd(new Date()) });
    const note = h('input', { placeholder: '5kg' });
    modal('Add purchase item', h('div', {}, h('label', {}, 'Ingredient'), sel, h('label', {}, 'Date'), date, h('label', {}, 'Quantity note'), note), {
      okLabel: 'Add',
      onOk: async () => {
        const ok = await guard(() => api.post('/purchase-schedule', {
          date: date.value, ingredientId: Number(sel.value), quantityNote: note.value.trim(),
        }), 'Item added.');
        if (ok) render();
        return ok;
      },
    });
  };
  const byDay = {};
  for (const it of items) (byDay[it.date] ??= []).push(it);
  if (!items.length) return h('div', {}, h('h1', {}, 'Purchase schedule'),
    emptyState('purchase', 'Nothing to buy', 'Generate from menu', generate));
  return h('div', {},
    h('div', { class: 'row between' }, h('h1', {}, 'Purchase schedule'),
      h('div', { class: 'row' }, h('button', { onclick: generate }, 'Generate'), h('button', { class: 'primary', onclick: addManual }, '+ Item'))),
    ...Object.keys(byDay).sort().map((d) => h('div', { class: 'card' },
      h('h3', { text: fmtDay(d) }),
      ...byDay[d].map((it) => {
        const cb = h('input', { type: 'checkbox', style: 'width:auto', ...(it.purchased ? { checked: true } : {}) });
        cb.addEventListener('change', async () => {
          await guard(() => api.patch(`/purchase-schedule/${it.id}`, { purchased: cb.checked }));
          render();
        });
        return h('div', { class: 'row between' },
          h('label', { style: 'display:flex;gap:8px;align-items:center;text-transform:none' }, cb,
            h('span', {}, `${it.ingredientName} — ${it.quantityNote} (${it.ingredientUnit})`),
            h('span', { class: 'muted' }, it.source === 'manual' ? ' manual' : ' from menu')),
          h('button', { class: 'ghost danger', onclick: async () => { if (await guard(() => api.del(`/purchase-schedule/${it.id}`), 'Removed.')) render(); } }, 'Del'));
      }))),
    items.length ? null : h('div', { class: 'muted' }, 'Nothing scheduled.'));
};

// expenses --------------------------------------------------------
views.expenses = async () => {
  const [list, summary] = await Promise.all([api.get('/expenses'), api.get('/expenses/summary')]);
  const open = () => {
    const cat = h('input', {}); const desc = h('input', {});
    const amt = h('input', { type: 'number' }); const date = h('input', { type: 'date', value: ymd(new Date()) });
    modal('Log expense', h('div', {}, h('label', {}, 'Category'), cat, h('label', {}, 'Description'), desc,
      h('label', {}, 'Amount (Rs.)'), amt, h('label', {}, 'Date'), date), {
      onOk: async () => {
        const ok = await guard(() => api.post('/expenses', {
          category: cat.value.trim(), description: desc.value.trim(), amount: Number(amt.value) || 0, date: date.value,
        }), 'Logged.');
        if (ok) render();
        return ok;
      },
    });
  };
  return h('div', {},
    h('div', { class: 'row between' }, h('h1', {}, 'Expenses & revenue'), h('button', { class: 'primary', onclick: open }, '+ Log expense')),
    h('div', { class: 'summary' },
      h('div', { class: 'stat' }, h('b', { text: 'Rs. ' + summary.revenue.toFixed(0) }), 'Revenue'),
      h('div', { class: 'stat' }, h('b', { text: 'Rs. ' + summary.expenses.toFixed(0) }), 'Expenses'),
      h('div', { class: 'stat' }, h('b', { text: 'Rs. ' + summary.profit.toFixed(0) }), 'Profit')),
    list.length === 0 ? emptyState('expenses', 'No expenses logged', '+ Log expense', open) :
    h('table', { style: 'margin-top:16px' }, h('thead', {}, h('tr', {}, ...['Date', 'Category', 'Description', 'Amount'].map((t) => h('th', { text: t })))),
      h('tbody', {}, ...list.map((e) => h('tr', {},
        h('td', { text: new Date(e.date).toLocaleDateString() }),
        h('td', { text: e.category }), h('td', { text: e.description }),
        h('td', { text: 'Rs. ' + e.amount.toFixed(2) }))))));
};

// refunds -------------------------------------------------------
views.refunds = async () => {
  const [list, members] = await Promise.all([api.get('/refunds'), api.get('/members')]);
  const nameById = Object.fromEntries(members.map((m) => [m.id, m.name]));
  const open = () => {
    const sel = h('select', {}, ...members.map((m) => h('option', { value: m.id }, m.name)));
    const l = h('input', { type: 'number' }); const b = h('input', { type: 'number' }); const br = h('input', { type: 'number' });
    const reason = h('input', {});
    const prefill = () => { const m = members.find((x) => x.id === Number(sel.value)); l.value = m.balances.lunch; b.value = m.balances.breakfast; br.value = m.balances.brunch; };
    sel.addEventListener('change', prefill); prefill();
    modal('New refund', h('div', {}, h('label', {}, 'Member'), sel, h('label', {}, 'Lunch'), l, h('label', {}, 'Breakfast'), b,
      h('label', {}, 'Brunch'), br, h('label', {}, 'Reason (optional)'), reason), {
      okLabel: 'Process',
      onOk: async () => {
        const ok = await guard(() => api.post('/refunds', {
          memberId: Number(sel.value), lunchUnits: Number(l.value) || 0, breakfastUnits: Number(b.value) || 0,
          brunchUnits: Number(br.value) || 0, reason: reason.value.trim() || null,
        }), 'Refund recorded.');
        if (ok) render();
        return ok;
      },
    });
  };
  return h('div', {},
    h('div', { class: 'row between' }, h('h1', {}, 'Refunds'), h('button', { class: 'primary', onclick: open }, '+ New refund')),
    list.length === 0 ? emptyState('refunds', 'No refunds yet', '+ New refund', open) :
    h('table', {}, h('thead', {}, h('tr', {}, ...['Member', 'L/B/Br', 'Amount', 'By', 'Reason', 'When'].map((t) => h('th', { text: t })))),
      h('tbody', {}, ...list.map((r) => h('tr', {},
        h('td', { text: nameById[r.memberId] ?? r.memberId }),
        h('td', { text: `${r.lunchUnits}/${r.breakfastUnits}/${r.brunchUnits}` }),
        h('td', { text: 'Rs. ' + r.refundAmount.toFixed(2) }),
        h('td', { text: r.processedBy }), h('td', { text: r.reason || '' }),
        h('td', { text: fmtDate(r.createdAt) }))))));
};

// users -------------------------------------------------------
views.users = async () => {
  const users = await api.get('/users');

  const open = (u) => {
    const name = h('input', {}); name.value = u?.username ?? '';
    const pw = h('input', { type: 'password', placeholder: u ? 'blank = keep' : '' });
    const role = h('select', {}, ...['admin', 'counter', 'scanner'].map((r) => h('option', { value: r }, r)));
    if (u) role.value = u.role;
    const status = h('select', {}, h('option', { value: 'active' }, 'active'), h('option', { value: 'inactive' }, 'inactive'));
    if (u) status.value = u.status;
    modal(u ? u.username : 'New user', h('div', {}, h('label', {}, 'Username'), name, h('label', {}, 'Password'), pw,
      h('label', {}, 'Role'), role, ...(u ? [h('label', {}, 'Status'), status] : [])), {
      onOk: async () => {
        let ok;
        if (u) ok = await guard(() => api.patch(`/users/${u.id}`, { username: name.value.trim() === u.username ? undefined : name.value.trim(), password: pw.value || undefined, role: role.value, status: status.value }), 'Saved.');
        else ok = await guard(() => api.post('/users', { username: name.value.trim(), password: pw.value, role: role.value }), 'User created.');
        if (ok) render();
        return ok;
      },
    });
  };
  const header = h('div', { class: 'row between' }, h('h1', {}, 'Users'),
    h('button', { class: 'primary', onclick: () => open(null) }, '+ New user'));
  if (!users.length) {
    return h('div', {}, header,
      emptyState('users', 'No users yet', '+ New user', () => open(null)));
  }
  return h('div', {}, header,
    h('table', {}, h('thead', {}, h('tr', {}, ...['Username', 'Role', 'Status', ''].map((t) => h('th', { text: t })))),
      h('tbody', {}, ...users.map((u) => h('tr', {},
        h('td', { text: u.username }), h('td', { text: u.role }), h('td', { text: u.status }),
        h('td', {}, h('button', { class: 'ghost', onclick: () => open(u) }, 'Edit'),
          h('button', { class: 'ghost danger', onclick: async () => { if (await guard(() => api.del(`/users/${u.id}`), 'Deleted.')) render(); } }, 'Del')))))));
};

// settings ---------------------------------------------------
views.settings = async () => {
  const [s, zones] = await Promise.all([api.get('/settings'), api.get('/settings/timezones')]);
  const f = {};
  const field = (key, label, val, type = 'text') => { const i = h('input', { type }); i.value = val; f[key] = i; return h('div', {}, h('label', {}, label), i); };
  const win = {};
  const winRow = (m) => {
    const st = h('input', { value: s.mealWindows[m].start, style: 'width:45%' });
    const en = h('input', { value: s.mealWindows[m].end, style: 'width:45%' });
    win[m] = { st, en };
    return h('div', {}, h('label', {}, m), h('div', { class: 'row' }, st, en));
  };
  // Type-to-filter combobox rather than a 600-option <select>: the browser
  // filters a <datalist> natively. A typo is caught server-side by the tz
  // validator, so a bad value fails loudly instead of being silently kept.
  const tzList = h('datalist', { id: 'tz-options' }, ...zones.map((z) => h('option', { value: z })));
  const tz = h('input', { list: 'tz-options', placeholder: 'Search zones, e.g. Asia/Kolkata' });
  tz.value = s.localTimezone;
  const graceOn = h('input', { type: 'checkbox', style: 'width:auto', ...(s.graceAllowanceEnabled ? { checked: true } : {}) });

  const save = async () => {
    const ok = await guard(() => api.patch('/settings', {
      appName: f.appName.value.trim(),
      unitPrices: { lunch: Number(f.lunch.value), breakfast: Number(f.breakfast.value), brunch: Number(f.brunch.value) },
      mealWindows: Object.fromEntries(['breakfast', 'lunch', 'brunch'].map((m) => [m, { start: win[m].st.value.trim(), end: win[m].en.value.trim() }])),
      localTimezone: tz.value,
      graceAllowanceEnabled: graceOn.checked,
      graceAllowanceUnits: Number(f.graceUnits.value),
      reversalWindowMinutes: Number(f.reversal.value),
      prepLeadMinutes: Number(f.prepLead.value),
      purchaseLeadDays: Number(f.purchaseLead.value),
      upiId: f.upiId.value.trim(),
      upiPayeeName: f.upiPayee.value.trim(),
    }), 'Settings saved.');
    if (ok) { store.bust(); render(); }
  };

  return h('div', {},
    h('h1', {}, 'Settings'),
    h('div', { class: 'card' }, h('h3', {}, 'Branding'), field('appName', 'App name', s.appName)),
    h('div', { class: 'card' }, h('h3', {}, 'Unit prices (Rs.)'), h('div', { class: 'grid2' },
      field('lunch', 'Lunch', s.unitPrices.lunch, 'number'),
      field('breakfast', 'Breakfast', s.unitPrices.breakfast, 'number'),
      field('brunch', 'Brunch', s.unitPrices.brunch, 'number'))),
    h('div', { class: 'card' }, h('h3', {}, 'Meal windows (HH:MM)'), winRow('breakfast'), winRow('lunch'), winRow('brunch')),
    h('div', { class: 'card' }, h('h3', {}, 'Timezone'), tz, tzList),
    h('div', { class: 'card' }, h('h3', {}, 'Grace allowance'),
      h('label', { style: 'display:flex;gap:8px;text-transform:none' }, graceOn, 'Enabled'),
      field('graceUnits', 'Default grace units', s.graceAllowanceUnits, 'number')),
    h('div', { class: 'card' }, h('h3', {}, 'Windows & reminders'), h('div', { class: 'grid2' },
      field('reversal', 'Reversal window (min)', s.reversalWindowMinutes, 'number'),
      field('prepLead', 'Prep reminder lead (min)', s.prepLeadMinutes, 'number'),
      field('purchaseLead', 'Purchase reminder lead (days)', s.purchaseLeadDays, 'number'))),
    h('div', { class: 'card' }, h('h3', {}, 'UPI'),
      field('upiId', 'UPI ID (blank = cash only)', s.upiId), field('upiPayee', 'Payee name', s.upiPayeeName)),
    h('button', { class: 'primary', onclick: save }, 'Save settings'));
};

// --- shell + router -----------------------------------------------------
const NAV = [
  ['members', 'Members'], ['topups', 'Top-ups'], ['scans', 'Scan log'],
  ['menu', 'Menu calendar'], ['categories', 'Categories'], ['ingredients', 'Ingredients'],
  ['recipes', 'Recipes'], ['purchase', 'Purchase schedule'], ['expenses', 'Expenses'],
  ['refunds', 'Refunds'], ['settings', 'Settings'], ['users', 'Users'],
];

const spinner = () => h('div', { class: 'spinner' });

let _shellRoute = null;
let _mainEl = null;

async function render() {
  const app = $('#app');
  const route = (location.hash.replace('#/', '') || 'members');

  if (!api.token || route === 'login') {
    _shellRoute = null;
    app.replaceChildren(await views.login());
    return;
  }
  const role = localStorage.getItem('tiffin_role');
  const allowed = role === 'admin' ? NAV : NAV.filter(([k]) => ['topups', 'purchase'].includes(k));
  const view = views[route] || views.members;

  // Rebuild the shell only on a route *change*; a same-route re-render (after a
  // create/edit/delete) just swaps the main pane, so the nav never flashes and
  // the old content stays visible (dimmed) until the new data lands.
  if (_shellRoute !== route || !_mainEl || !document.body.contains(_mainEl)) {
    const side = h('nav', { class: 'side' },
      h('div', { class: 'brand' }, 'TIFFIN · ADMIN'),
      ...allowed.map(([k, label]) => h('a', { href: '#/' + k, class: route === k ? 'active' : '' }, label)),
      h('div', { class: 'spacer' }),
      h('div', { class: 'muted' }, localStorage.getItem('tiffin_user') + ' · ' + role),
      h('button', { class: 'ghost', onclick: () => { api.token = null; location.hash = '#/login'; } }, 'Sign out'));
    _mainEl = h('main', {}, spinner());
    app.replaceChildren(h('div', { class: 'shell' }, side, _mainEl));
    _shellRoute = route;
  }
  _mainEl.classList.add('loading');
  try {
    const node = await view();
    _mainEl.classList.remove('loading');
    _mainEl.replaceChildren(node);
  } catch (e) {
    _mainEl.classList.remove('loading');
    _mainEl.replaceChildren(h('div', { class: 'card', style: 'border-color:var(--reject)' },
      h('h2', {}, 'Could not load'), h('div', {}, e.message || String(e)),
      h('button', { onclick: render, style: 'margin-top:12px' }, 'Retry')));
  }
}

window.addEventListener('hashchange', render);
render();
