// Flagcast Manager on the web: the green sidebar (the club's tournaments, each opening into its sections), the course
// photos (satellite tiles of the tournament's own course) and the small helpers Home and the desk share.
// Matches the Mac Manager (apps/flagcast-mac: ManagerSidebar, PhotoPage, HomeDashboard). A club's sign-in lists only
// its own tournaments; Flagcast staff (ADMIN_EMAIL) also get every club's. Desk links opened in this browser belong to
// the account signed in when they were opened, so one club never sees another's on a shared computer.
import { api as clubApi, token, esc, creditsText } from '/golf/club.js';
import { TILES } from '/golf/gps.js';

// ---- icons (simple line drawings, 24 × 24) ----
const P = {
  overview: '<rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/>',
  setup: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  teams: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8"/>',
  scores: '<path d="M10 6h11M10 12h11M10 18h11M4 6h1v4M4 10h2M6 18H4c0-1 2-2 2-3s-1-1.5-2-1"/>',
  contests: '<path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6M18 9h1.5a2.5 2.5 0 0 0 0-5H18M4 22h16M10 14.7V17c0 .6-.5 1-1 1.2C7.9 18.8 7 20.2 7 22M14 14.7V17c0 .6.5 1 1 1.2 1.1.6 2 2 2 3.8M18 2H6v7a6 6 0 0 0 12 0V2z"/>',
  screens: '<rect x="2" y="7" width="20" height="13" rx="2"/><path d="m17 2-5 5-5-5"/>',
  staff: '<circle cx="12" cy="12" r="10"/><circle cx="12" cy="10" r="3"/><path d="M7 20.7v-1.7a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v1.7"/>',
  links: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
  report: '<path d="M3 3v18h18"/><path d="M18 17V9M13 17V5M8 17v-3"/>',
  map: '<path d="M14.1 4.6 9.9 2.4a2 2 0 0 0-1.8 0L3.6 4.7A1 1 0 0 0 3 5.6v14.8a1 1 0 0 0 1.4.9l3.7-1.9a2 2 0 0 1 1.8 0l4.2 2.2a2 2 0 0 0 1.8 0l4.5-2.3a1 1 0 0 0 .6-.9V3.6a1 1 0 0 0-1.4-.9l-3.7 1.9a2 2 0 0 1-1.8 0zM9 2.2v15M15 6.8v15"/>',
  groups: '<path d="M20 10c0 6-8 12-8 12s-8-6-8-12a8 8 0 0 1 16 0z"/><circle cx="12" cy="10" r="3"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  tv: '<rect x="2" y="7" width="20" height="13" rx="2"/><path d="m17 2-5 5-5-5"/>',
  video: '<path d="m22 8-6 4 6 4V8z"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
  phone: '<rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/>',
  menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
  link2: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M12 1v3M12 20v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M1 12h3M20 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
};
export const icon = (k, size = 15) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[k] || ''}</svg>`;

// the sections of a tournament, in the sidebar (the Mac's order)
export const SECTIONS = [['overview', 'Overview'], ['setup', 'Setup'], ['teams', 'Teams'], ['scores', 'Scores'], ['contests', 'Contests'],
  ['screens', 'Screens & sponsors'], ['staff', 'Staff'], ['links', 'Links & cart cards'], ['report', 'Report'], ['map', 'Course map'], ['groups', 'Where the groups are']];
export const sectionTitle = (s) => (SECTIONS.find((x) => x[0] === s) || [s, s])[1];
export const deskURL = (id, key, s = 'overview') => `/g/${id}/desk#${key}&${s}`;

// ---- dates ----
export const today = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`; };
const asDate = (s) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s || ''); return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null; };
/** "SAT NOV 21" */
export const dayLine = (s) => { const d = asDate(s); return d ? d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).replace(/,/g, '').toUpperCase() : ''; };
export const shortDate = (s) => { const d = asDate(s); return d ? d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' }) : ''; };
export const monthDay = (s) => { const d = asDate(s); return d ? [d.toLocaleDateString('en-US', { month: 'short' }).toUpperCase(), String(d.getDate())] : ['', '–']; };

/** Which tournament Home leads with: today's, else the next one, else the latest made. */
export function featured(list) {
  const t = today();
  return list.find((e) => e.date === t) || list.filter((e) => (e.date || '') > t).sort((a, b) => a.date.localeCompare(b.date))[0]
    || [...list].sort((a, b) => (b.created || 0) - (a.created || 0))[0] || null;
}
/** What's left before a tournament is ready. */
export function stepsLeft(S) {
  const out = [];
  if (!S.date) out.push('Set the date');
  if (!S.course?.name) out.push('Pick the course');
  if (!(S.teams || []).length) out.push('Add teams');
  if (!(S.displays || []).length) out.push('Add a TV');
  return out;
}
/** The tournament's day, or scores in the last three hours (the Mac's DayOfChecks.isEventDay). */
export const isEventDay = (S) => S.date === today() || Math.max(0, ...Object.values(S.lastAt || {})) > Date.now() - 3 * 3600000;
/** Carts that have gone quiet: no score for 20 minutes, once the round has been going 20 minutes. */
export function slowCarts(S, now = Date.now()) {
  const last = S.lastAt || {}, quiet = 20 * 60000, first = Math.min(...Object.values(last));
  if (!Object.keys(last).length || now - first <= quiet) return [];
  return (S.teams || []).filter((t) => !last[t.id] || now - last[t.id] > quiet);
}
export const teamName = (t) => t.name || (t.players || []).map((p) => p.name.split(' ').pop()).join(' / ') || 'Team';

// ---- course photos: satellite tiles of the tournament's own course ----
const pts = (S) => Object.values(S?.map?.holes || {}).flatMap((h) => [h.tee, h.m || h.f || h.b]).filter((p) => Array.isArray(p) && p.length === 2);
/** The whole course: from the course map (every hole), else the course's spot from Find the course. */
export function courseView(S) {
  const p = pts(S);
  if (p.length >= 2) {
    const la = p.map((x) => x[0]), lo = p.map((x) => x[1]), c = [(Math.min(...la) + Math.max(...la)) / 2, (Math.min(...lo) + Math.max(...lo)) / 2];
    const span = Math.max(700, Math.max((Math.max(...la) - Math.min(...la)) * 111000, (Math.max(...lo) - Math.min(...lo)) * 111000 * Math.cos(c[0] * Math.PI / 180)) * 1.15);
    return { center: c, span };
  }
  const a = S?.course?.at; if (a && Number.isFinite(a.lat)) return { center: [a.lat, a.lng], span: 1400 };
  return null;
}
const mid = (h) => h && (h.m || (h.f && h.b ? [(h.f[0] + h.b[0]) / 2, (h.f[1] + h.b[1]) / 2] : h.f || h.b));
/** One hole from tee to green, turned so the green is at the top. */
export function holeView(S, n) {
  const h = S?.map?.holes?.[n] || S?.map?.holes?.[String(n)], g = mid(h);
  if (!h?.tee || !g) return null;
  const t = Math.PI / 180, dy = (g[0] - h.tee[0]) * 111000, dx = (g[1] - h.tee[1]) * 111000 * Math.cos(h.tee[0] * t);
  return { center: [(h.tee[0] + g[0]) / 2, (h.tee[1] + g[1]) / 2], span: Math.max(180, Math.hypot(dx, dy) * 1.25), bearing: Math.atan2(dx, dy) / t, tall: true };
}
/** Fill box (position: relative or absolute) with the satellite picture: view = { center, span, bearing }. */
export function paintPhoto(box, view) {
  if (!box) return;
  const draw = () => {
    box.querySelector('.tiles')?.remove();
    if (!view) return;
    const W = box.clientWidth || 800, H = box.clientHeight || 300; if (!W || !H) return;
    const rot = view.bearing || 0, diag = rot ? Math.ceil(Math.hypot(W, H)) : 0, w = diag || W, h = diag || H;
    // the span fits the box's long side (the height when the hole stands upright)
    const fit = view.tall ? H : W, lat = view.center[0], cos = Math.cos(lat * Math.PI / 180);
    let z = Math.floor(Math.log2(156543.03 * cos * fit / view.span)); z = Math.max(12, Math.min(19, z));
    const dpr = Math.min(2, window.devicePixelRatio || 1), zz = Math.min(19, z + (dpr > 1.2 ? 1 : 0)), sc = 2 ** (zz - z), ts = 256 / sc;
    const n = 2 ** zz, x = (view.center[1] + 180) / 360 * n * 256, s = Math.sin(lat * Math.PI / 180), y = (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * n * 256;
    const x0 = x - (w / 2) * sc, y0 = y - (h / 2) * sc;
    const el = document.createElement('div'); el.className = 'tiles';
    el.style.cssText = `width:${w}px;height:${h}px;margin:${-h / 2}px 0 0 ${-w / 2}px;${rot ? `transform:rotate(${-rot}deg)` : ''}`;
    let left = 0;
    for (let tx = Math.floor(x0 / 256); tx <= Math.floor((x0 + w * sc) / 256); tx++) for (let ty = Math.floor(y0 / 256); ty <= Math.floor((y0 + h * sc) / 256); ty++) {
      if (ty < 0 || ty >= n) continue;
      const i = new Image(); i.alt = ''; i.decoding = 'async'; i.loading = 'eager'; left++;
      i.onload = i.onerror = () => { if (--left <= 0) el.classList.add('ready'); };
      i.style.cssText = `left:${(tx * 256 - x0) / sc}px;top:${(ty * 256 - y0) / sc}px;width:${ts}px;height:${ts}px`;
      i.src = TILES.replace('{z}', zz).replace('{y}', ty).replace('{x}', ((tx % n) + n) % n);
      el.appendChild(i);
    }
    setTimeout(() => el.classList.add('ready'), 2500);
    box.appendChild(el);
  };
  draw();
  if (box._ro) box._ro.disconnect();
  let last = box.clientWidth;
  box._ro = new ResizeObserver(() => { if (Math.abs(box.clientWidth - last) > 40) { last = box.clientWidth; draw(); } });
  box._ro.observe(box);
}

// ---- the tournaments this sign-in can open ----
const LINKS = 'flagcast:desk-links', META = 'flagcast:ev-meta';
const read = (k, store = localStorage) => { try { return JSON.parse(store.getItem(k)) || null; } catch { return null; } };
const write = (k, v, store = localStorage) => { try { store.setItem(k, JSON.stringify(v)); } catch {} };
/** a tournament opened by its desk link: remembered for the account signed in now ('' when signed out) */
export function rememberLink(e, email) {
  const all = (read(LINKS) || []).filter((x) => !(x.id === e.id && (x.owner || '') === (email || '')));
  all.unshift({ id: e.id, key: e.key, name: e.name || 'Tournament', owner: email || '', at: Date.now() });
  write(LINKS, all.slice(0, 40));
}
export function forgetLink(id, email) { write(LINKS, (read(LINKS) || []).filter((x) => !(x.id === id && (x.owner || '') === (email || '')))); }
let ME;
/** the signed-in account ({ email, club, events, admin… }), or null */
export function getMe() {
  if (!ME) ME = token.get() ? clubApi('me').catch(() => null) : Promise.resolve(null);
  return ME;
}
/** Every tournament for the sidebar: the club's, then (for staff) every club's, then desk links opened as this account. */
export async function myEvents(me) {
  const out = [], seen = new Set(), add = (e) => { if (!e || !e.id || !e.key || seen.has(e.id)) return; seen.add(e.id); out.push(e); };
  for (const e of me?.events || []) add({ ...e, club: me.club?.name || '', fromClub: true });
  if (me?.admin) {
    try { const j = await clubApi('admin', {}); for (const c of j.clubs || []) for (const e of c.events || []) if (!e.hidden && !e.archived) add({ ...e, club: c.name, staff: true }); } catch {}
  }
  const email = me?.email || '';
  for (const e of read(LINKS) || []) if ((e.owner || '') === email) add({ ...e, created: e.at, fromLink: true });
  // tournaments made in this browser before club accounts (only while signed out)
  if (!email) for (const m of read('golf:mine') || []) add({ id: m.id, key: m.key, name: m.name, created: m.at, fromLink: true });
  return out;
}
/** name, date and locked for each tournament, from its public state (kept for this visit) */
export async function withMeta(list, need = 40) {
  const cache = read(META, sessionStorage) || {};
  const todo = list.slice(0, need).filter((e) => !cache[e.id] || Date.now() - cache[e.id].t > 5 * 60000);
  let i = 0;
  await Promise.all(Array.from({ length: Math.min(6, todo.length) }, async () => {
    while (i < todo.length) {
      const e = todo[i++];
      try { const r = await fetch(`/golf/api/${e.id}/state`, { cache: 'no-store' }); if (r.ok) { const s = await r.json(); cache[e.id] = { name: s.name, date: s.date || '', locked: !!s.locked, t: Date.now() }; } } catch {}
    }
  }));
  write(META, cache, sessionStorage);
  return list.map((e) => (cache[e.id] ? { ...e, name: cache[e.id].name || e.name, date: cache[e.id].date, locked: cache[e.id].locked } : e));
}
export function setMeta(id, m) { const c = read(META, sessionStorage) || {}; c[id] = { ...(c[id] || {}), ...m, t: Date.now() }; write(META, c, sessionStorage); }

// ---- the sidebar ----
/**
 * mountSidebar(el, { current: { id, key, name }, section, onSection, onNew })
 * current: the tournament open on this page (always listed, even when signed out). onSection(s): a section of the open
 * tournament was picked (no page load). Returns { setSection, setCurrent, refresh, me }.
 */
export async function mountSidebar(el, opts = {}) {
  let me = await getMe(), list = [], q = '', section = opts.section || 'overview', cur = opts.current || null;
  const isLive = (e) => e.date === today() && !e.locked;
  const initials = (s) => String(s || '?').split(/[\s@.]+/).filter(Boolean).slice(0, 2).map((w) => w[0]).join('').toUpperCase();
  const canMake = !!(me?.club && me.club.status === 'active' && me.club.credits !== 0);
  const clubLine = () => !me ? 'to see your club’s tournaments' : !me.club ? (me.admin ? 'Flagcast staff' : 'Club not set up yet') : me.club.status === 'pending' ? 'Waiting for Flagcast' : me.club.status === 'off' ? 'Switched off' : creditsText(me.club.credits).replace(' to make', '');
  function draw() {
    const shown = list.filter((e) => !q || `${e.name} ${e.club || ''}`.toLowerCase().includes(q));
    el.innerHTML = `
      ${me?.admin ? `<div class="mode"><a href="/golf/" aria-current="page">Manager</a><a href="/golf/admin/">Admin</a></div>` : ''}
      <a class="brand" href="/golf/"><img src="/golf/brand/mark.svg" alt=""><div><b>FLAGCAST</b><small>MANAGER</small></div></a>
      <label class="find">${icon('search', 13)}<input id="sideFind" placeholder="Find a tournament" value="${esc(q)}" aria-label="Find a tournament"></label>
      <nav class="list" aria-label="Tournaments">
        <div class="head">TOURNAMENTS</div>
        ${list.length ? '' : `<div class="empty">${me ? (canMake ? 'No tournaments yet. Make one below.' : 'No tournaments yet.') : 'Sign in to see your club’s tournaments.'}</div>`}
        ${shown.map((e) => {
          const open = cur && cur.id === e.id;
          return `<a class="ev ${open ? 'open' : ''}" href="${open ? '/golf/' : deskURL(e.id, e.key)}" ${open ? 'data-close="1"' : ''} title="${esc(e.name)}${e.club && e.staff ? ` · ${esc(e.club)}` : ''}">
            <span class="chev">${open ? '▼' : '▶'}</span><span class="nm">${esc(e.name)}${e.staff && e.club ? `<span class="cl">${esc(e.club)}</span>` : ''}</span>
            ${isLive(e) ? '<span class="live">LIVE</span>' : e.date ? `<span class="dt">${shortDate(e.date)}</span>` : ''}</a>
            ${open ? SECTIONS.map(([k, t]) => `<a class="sec" href="${deskURL(e.id, e.key, k)}" data-sec="${k}" aria-current="${section === k ? 'page' : 'false'}">${icon(k)}<span>${t}</span></a>`).join('') : ''}`;
        }).join('')}
      </nav>
      <a class="new" href="/golf/#new" aria-disabled="${canMake ? 'false' : 'true'}" data-new="1">${icon('plus', 13)} New tournament</a>
      <hr>
      <a class="me" href="/golf/">${me?.club?.logo ? `<span class="av"><img src="${esc(me.club.logo)}" alt=""></span>` : `<span class="av">${esc(initials(me?.club?.name || me?.email))}</span>`}
        <div><b>${esc(me?.club?.name || me?.email || 'Sign in')}</b><small>${esc(clubLine())}</small></div></a>`;
  }
  el.addEventListener('input', (e) => { if (e.target.id !== 'sideFind') return; q = e.target.value.trim().toLowerCase(); const pos = e.target.selectionStart; draw(); const f = el.querySelector('#sideFind'); f.focus(); f.setSelectionRange(pos, pos); });
  el.addEventListener('click', (e) => {
    const a = e.target.closest('a'); if (!a) return;
    if (a.dataset.sec && opts.onSection) { e.preventDefault(); section = a.dataset.sec; draw(); opts.onSection(section); document.body.classList.remove('side-open'); return; }
    if (a.dataset.new && opts.onNew) { e.preventDefault(); opts.onNew(); document.body.classList.remove('side-open'); }
  });
  async function refresh() {
    list = await myEvents(me);
    if (cur && !list.some((e) => e.id === cur.id)) list.unshift({ ...cur, fromLink: true });
    draw();
    list = await withMeta(list);
    draw();
  }
  // phones: the menu button and the dark scrim
  if (!document.querySelector('.scrimbg')) { const s = document.createElement('div'); s.className = 'scrimbg'; s.onclick = () => document.body.classList.remove('side-open'); document.body.appendChild(s); }
  await refresh();
  return {
    me,
    refresh,
    setSection(s) { section = s; draw(); },
    setCurrent(c) { cur = { ...cur, ...c }; list = list.map((e) => (e.id === cur.id ? { ...e, ...c } : e)); if (cur.id) setMeta(cur.id, { name: c.name, date: c.date, locked: c.locked }); draw(); },
  };
}
export const menuButton = () => `<button class="gbtn menu-btn" type="button" onclick="document.body.classList.toggle('side-open')" aria-label="Tournaments">${icon('menu', 15)}</button>`;
