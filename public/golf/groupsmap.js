// "On the course" from the cart scorecard: a full-screen satellite map with where you are (the phone's GPS), your
// group, and every other group sharing its spot (POST …/where → groups). A sheet at the bottom has the course strip
// (which hole each group is on), the groups just ahead of and behind you, and every group with how far away it is.
// Only while the tournament is on: the server leaves out groups that hide and spots older than 15 minutes, and
// never sends anyone's cart code.
import { post, esc } from '/golf/client.js';
import { TILES, TILE_CREDIT, middle, yds, holeMap, trackingOn, position, onGps, startGps, gpsWanted } from '/golf/gps.js';

const LEAFLET = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/';
const HIDE = (code) => `flagcast:hide:${code}`;
export const hidden = (code) => { try { return localStorage.getItem(HIDE(code)) === '1'; } catch { return false; } };
const setHidden = (code, on) => { try { localStorage.setItem(HIDE(code), on ? '1' : '0'); } catch {} };
const STALE = 6 * 60000; // faded after 6 minutes without a new spot

let leaflet = null;
function loadLeaflet() {
  if (window.L) return Promise.resolve(window.L);
  if (leaflet) return leaflet;
  const css = document.createElement('link'); css.rel = 'stylesheet'; css.href = LEAFLET + 'leaflet.min.css'; document.head.appendChild(css);
  leaflet = new Promise((ok, no) => {
    const s = document.createElement('script'); s.src = LEAFLET + 'leaflet.min.js';
    s.onload = () => ok(window.L); s.onerror = () => { leaflet = null; no(new Error('The map didn’t load. Check your signal and try again.')); };
    document.head.appendChild(s);
  });
  return leaflet;
}

const ICON = {
  back: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"/></svg>',
  me: '<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><path d="M21 3L3 10.5l7.2 2.3L12.5 20z"/></svg>',
  all: '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>',
};

const STYLE = `
.oc { position: fixed; inset: 0; z-index: 50; background: #0b1a12; color: var(--ink); overflow: hidden; }
.oc .ocmap { position: absolute; inset: 0; }
.oc .leaflet-container { background: #0b1a12; font-family: var(--f-body); }
.oc .leaflet-control-attribution { background: rgba(0,0,0,.45); color: rgba(255,255,255,.7); font-size: 9px; }
.oc .leaflet-control-attribution a { color: rgba(255,255,255,.8); }
.oc-top { position: absolute; left: 0; right: 0; top: 0; z-index: 500; display: flex; align-items: center; gap: 10px;
  padding: calc(10px + env(safe-area-inset-top, 0px)) 12px 18px; background: linear-gradient(rgba(6,16,11,.92), rgba(6,16,11,.55) 70%, transparent); color: #fff; pointer-events: none; }
.oc-top > * { pointer-events: auto; }
.oc-ib { width: 44px; height: 44px; border-radius: 50%; border: 0; display: grid; place-items: center; background: rgba(255,255,255,.14); color: #fff; backdrop-filter: blur(8px); -webkit-backdrop-filter: blur(8px); cursor: pointer; flex: none; }
.oc-ttl { flex: 1; min-width: 0; }
.oc-ttl h2 { font: 800 1.45rem/1 var(--f-display); letter-spacing: .02em; text-transform: uppercase; margin: 0; color: #fff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.oc-live { display: inline-flex; align-items: center; gap: 6px; margin-top: 4px; font: 600 .72rem var(--f-mono); letter-spacing: .08em; text-transform: uppercase; color: rgba(255,255,255,.75); }
.oc-live i { width: 7px; height: 7px; border-radius: 50%; background: #48d17c; box-shadow: 0 0 0 0 rgba(72,209,124,.6); animation: ocpulse 2s infinite; }
.oc-live.off i { background: #8a948d; animation: none; }
@keyframes ocpulse { 0% { box-shadow: 0 0 0 0 rgba(72,209,124,.55); } 70% { box-shadow: 0 0 0 8px rgba(72,209,124,0); } 100% { box-shadow: 0 0 0 0 rgba(72,209,124,0); } }
.oc-fabs { position: absolute; right: 12px; z-index: 500; display: grid; gap: 10px; transition: bottom .25s ease; }
.oc-fab { width: 48px; height: 48px; border-radius: 50%; border: 0; display: grid; place-items: center; background: #fff; color: #123628; box-shadow: 0 4px 14px rgba(0,0,0,.35); cursor: pointer; }
.oc-fab.on { background: #2f7bff; color: #fff; }
.oc-fab:disabled { opacity: .45; }
.oc-sheet { position: absolute; left: 0; right: 0; bottom: 0; z-index: 600; background: var(--card); border-radius: 22px 22px 0 0; box-shadow: 0 -8px 30px rgba(0,0,0,.35);
  max-height: 72vh; display: flex; flex-direction: column; transition: max-height .25s ease; padding-bottom: env(safe-area-inset-bottom, 0px); }
.oc-sheet.min { max-height: 228px; }
.oc-grab { border: 0; background: none; padding: 9px 0 4px; display: grid; place-items: center; cursor: pointer; flex: none; }
.oc-grab i { width: 40px; height: 5px; border-radius: 3px; background: var(--line); }
.oc-body { overflow-y: auto; padding: 0 16px 16px; overscroll-behavior: contain; }
.oc-note { font-size: .88rem; color: var(--muted); margin: 4px 0 10px; }
.oc-strip { display: grid; grid-template-columns: repeat(var(--n, 18), 1fr); gap: 3px; margin: 2px 0 12px; }
.oc-h { border: 0; padding: 5px 0 4px; border-radius: 7px; background: var(--paper-2); color: var(--muted); font: 600 .68rem var(--f-mono); display: grid; justify-items: center; gap: 3px; min-width: 0; cursor: pointer; }
.oc-h b { display: flex; gap: 2px; height: 6px; }
.oc-h b s { width: 6px; height: 6px; border-radius: 50%; background: #3a8bff; text-decoration: none; }
.oc-h b s.me { background: var(--club, var(--flag)); box-shadow: 0 0 0 1px #1a1a10 inset; }
.oc-h.has { background: #dfe9fb; color: #1c3f86; }
.oc-h.mine { background: var(--green); color: var(--on-green); }
.oc-near { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; margin-bottom: 12px; }
.oc-nb { border: 1px solid var(--line); border-radius: 12px; padding: 10px 12px; background: var(--paper); text-align: left; font: inherit; color: var(--ink); cursor: pointer; min-width: 0; }
.oc-nb small { display: block; font: 600 .66rem var(--f-mono); letter-spacing: .08em; text-transform: uppercase; color: var(--muted); }
.oc-nb b { display: block; margin-top: 3px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.oc-nb span { font-size: .8rem; color: var(--muted); }
.oc-nb.empty { cursor: default; }
.oc-sec { display: flex; justify-content: space-between; align-items: baseline; margin: 6px 0 6px; }
.oc-sec h3 { font: 700 .72rem var(--f-mono); letter-spacing: .1em; text-transform: uppercase; color: var(--muted); margin: 0; }
.oc-list { display: grid; }
.oc-g { display: flex; gap: 12px; align-items: center; width: 100%; text-align: left; border: 0; border-bottom: 1px solid var(--line); background: none; color: var(--ink); padding: 10px 2px; font: inherit; cursor: pointer; }
.oc-g:last-child { border-bottom: 0; }
.oc-g .n { width: 38px; height: 38px; border-radius: 12px; display: grid; place-items: center; background: #3a8bff; color: #fff; font: 700 .95rem var(--f-mono); flex: none; }
.oc-g.old .n { background: #8a948d; }
.oc-g .who { flex: 1; min-width: 0; }
.oc-g .who b { display: block; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.oc-g .who small { color: var(--muted); }
.oc-g .d { font: 700 .95rem var(--f-mono); text-align: right; white-space: nowrap; }
.oc-g .d small { display: block; font: 500 .66rem var(--f-mono); color: var(--muted); letter-spacing: .06em; text-transform: uppercase; }
.oc-cta { width: 100%; padding: 14px; font-size: 1rem; margin: 2px 0 12px; }
.oc-priv { display: flex; align-items: center; gap: 12px; margin-top: 12px; padding: 12px; border-radius: 12px; background: var(--paper); }
.oc-priv div { flex: 1; font-size: .88rem; } .oc-priv div small { display: block; color: var(--muted); font-size: .78rem; margin-top: 2px; }
.oc-sw { position: relative; width: 50px; height: 30px; flex: none; }
.oc-sw input { position: absolute; inset: 0; opacity: 0; margin: 0; cursor: pointer; z-index: 1; }
.oc-sw span { position: absolute; inset: 0; border-radius: 15px; background: #c3cbc4; transition: background .2s; }
.oc-sw span::after { content: ""; position: absolute; top: 3px; left: 3px; width: 24px; height: 24px; border-radius: 50%; background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.3); transition: transform .2s; }
.oc-sw input:checked + span { background: var(--ok); }
.oc-sw input:checked + span::after { transform: translateX(20px); }
.oc-sw input:focus-visible + span { outline: 2px solid var(--flag); outline-offset: 2px; }
/* pins */
.ocp { display: inline-flex; align-items: center; gap: 0; transform: translate(-15px, -15px); filter: drop-shadow(0 2px 4px rgba(0,0,0,.55)); white-space: nowrap; }
.ocp .h { width: 30px; height: 30px; border-radius: 50%; display: grid; place-items: center; background: #3a8bff; color: #fff; border: 2.5px solid #fff; font: 700 12px var(--f-mono); position: relative; z-index: 1; }
.ocp .t { margin-left: -8px; padding: 3px 8px 3px 12px; border-radius: 0 10px 10px 0; background: rgba(8,20,14,.88); color: #fff; font: 600 11.5px var(--f-body); }
.ocp.me .h { background: var(--club, #e8c547); color: #1a1a10; }
.ocp.me .t { background: var(--club, #e8c547); color: #1a1a10; font-weight: 700; }
.ocp.old { opacity: .6; } .ocp.old .h { background: #8a948d; }
.ocp.pick .h { box-shadow: 0 0 0 4px rgba(255,255,255,.5); }
.ocme { width: 18px; height: 18px; border-radius: 50%; background: #2f7bff; border: 3px solid #fff; transform: translate(-9px, -9px); box-shadow: 0 0 0 10px rgba(47,123,255,.22), 0 1px 4px rgba(0,0,0,.5); }
.ochole { width: 19px; height: 19px; border-radius: 50%; display: grid; place-items: center; transform: translate(-9.5px, -9.5px); background: rgba(255,255,255,.8); color: #1a1a10; font: 800 9.5px var(--f-mono); }
.ocflag { color: #e0362c; transform: translate(-3px, -24px); filter: drop-shadow(0 1px 2px rgba(0,0,0,.6)); }`;

const shortName = (n) => String(n || '').split(' / ')[0];
const ago = (now, t) => { const m = Math.round((now - t) / 60000); return m < 1 ? 'Just now' : `${m} min ago`; };
const fmtYds = (y) => (y == null ? '' : y >= 1000 ? `${(y / 1760).toFixed(1)} mi` : `${Math.round(y / 5) * 5} yds`);

/** Opens full screen over the scorecard. opts: { state(), code, team(), hole(), onClose() }. Returns { refresh(), destroy() }. */
export function groupsMap(opts) {
  if (!document.getElementById('oc-style')) { const st = document.createElement('style'); st.id = 'oc-style'; st.textContent = STYLE; document.head.appendChild(st); }
  const root = document.createElement('section');
  root.className = 'oc'; root.setAttribute('aria-label', 'Where everyone is');
  root.innerHTML = `<div class="ocmap"></div>
    <div class="oc-top"><button class="oc-ib" data-oc="close" aria-label="Back to the scorecard">${ICON.back}</button>
      <div class="oc-ttl"><h2>On the course</h2><div class="oc-live" id="ocLive"><i></i><span>Live</span></div></div></div>
    <div class="oc-fabs" id="ocFabs"><button class="oc-fab" data-oc="all" aria-label="Show everyone">${ICON.all}</button><button class="oc-fab" data-oc="me" aria-label="Find me">${ICON.me}</button></div>
    <div class="oc-sheet min" id="ocSheet"><button class="oc-grab" data-oc="sheet" aria-label="Show more"><i></i></button><div class="oc-body" id="ocBody"></div></div>`;
  document.body.appendChild(root);
  document.documentElement.style.overflow = 'hidden';
  const $ = (id) => root.querySelector('#' + id);
  let map = null, L = null, layer = null, meDot = null, groups = [], off = false, err = '', now = Date.now(), fitted = false, timer = null, stopped = false, pick = null, follow = false, lastBody = '';

  const total = () => (opts.state()?.course?.holes || []).length || 18;
  const mine = () => groups.find((g) => g.me);
  const myHole = () => mine()?.hole || opts.hole() || 0;
  const from = () => position()?.at || mine()?.at || null;
  const others = () => groups.filter((g) => !g.me);
  // holes from me, the way the round goes: 1 = the hole ahead, total-1 = the hole behind
  const gap = (g) => { const h = myHole(); return h && g.hole ? (g.hole - h + total()) % total() : null; };

  async function load() {
    const t = opts.team(); if (!t) return;
    try {
      const r = await post('where', { code: opts.code, team: t, hide: hidden(opts.code) });
      groups = r.groups || []; now = r.now || Date.now(); off = false; err = '';
    } catch (e) { if (e.status === 409) { off = true; groups = []; } else err = e.message; }
    draw();
  }

  function sheet() {
    const s = opts.state(), on = s && trackingOn(s) && !off, me = position(), here = from();
    const live = $('ocLive');
    live.classList.toggle('off', !on || !!err);
    live.querySelector('span').textContent = !on ? 'Off today' : err ? 'No signal' : `Live · ${others().length} group${others().length === 1 ? '' : 's'}`;
    let h = '';
    if (!on) {
      h += `<p class="oc-note" style="margin-top:8px">${s && s.locked ? 'The results are final, so the map of groups is off.' : `Groups show here on the day of the tournament${s && s.date ? ` (${esc(s.date)})` : ''}, until the results are final.`}</p>`;
    } else {
      if (!gpsWanted()) h += `<button class="btn primary oc-cta" data-oc="gps">Show where I am</button>`;
      // the course strip: a cell per hole, a dot per group on it
      const n = total(), by = {};
      for (const g of groups) if (g.hole) (by[g.hole] = by[g.hole] || []).push(g);
      h += `<div class="oc-strip" style="--n:${n}">${Array.from({ length: n }, (_, i) => i + 1).map((k) => {
        const gs = by[k] || [], isMine = k === myHole();
        return `<button class="oc-h ${gs.length ? 'has' : ''} ${isMine ? 'mine' : ''}" data-hole="${k}" aria-label="Hole ${k}: ${gs.length} group${gs.length === 1 ? '' : 's'}">${k}<b>${gs.slice(0, 2).map((g) => `<s class="${g.me ? 'me' : ''}"></s>`).join('')}</b></button>`;
      }).join('')}</div>`;
      // the groups just ahead and behind
      const withGap = others().filter((g) => gap(g) != null);
      const ahead = withGap.filter((g) => gap(g) > 0 && gap(g) <= n / 2).sort((a, b) => gap(a) - gap(b) || (here ? yds(here, b.at) - yds(here, a.at) : 0))[0]
        || withGap.filter((g) => gap(g) === 0).sort((a, b) => (here ? yds(here, a.at) - yds(here, b.at) : 0))[0];
      const behind = withGap.filter((g) => g !== ahead && (gap(g) > n / 2 || gap(g) === 0)).sort((a, b) => ((gap(b) || n) - (gap(a) || n)))[0];
      const nb = (label, g) => g ? `<button class="oc-nb" data-team="${esc(g.team)}"><small>${label}</small><b>${esc(shortName(g.name))}</b><span>Hole ${g.hole}${here ? ` · ${fmtYds(yds(here, g.at))}` : ''}</span></button>`
        : `<div class="oc-nb empty"><small>${label}</small><b>—</b><span>Nobody yet</span></div>`;
      if (myHole() && others().length) h += `<div class="oc-near">${nb('Group ahead', ahead)}${nb('Group behind', behind)}</div>`;
      // everyone, nearest first when we know where you are, otherwise by hole
      const list = others().map((g) => ({ g, d: here ? yds(here, g.at) : null }))
        .sort((a, b) => (a.d != null && b.d != null ? a.d - b.d : (a.g.hole || 99) - (b.g.hole || 99)));
      h += `<div class="oc-sec"><h3>${list.length ? `Every group (${list.length})` : 'Every group'}</h3><h3>${here ? 'Away' : ''}</h3></div>`;
      h += list.length ? `<div class="oc-list">${list.map(({ g, d }) => `<button class="oc-g ${now - g.t > STALE ? 'old' : ''}" data-team="${esc(g.team)}">
          <span class="n">${g.hole || '?'}</span><span class="who"><b>${esc(g.name)}</b><small>${g.hole ? `Hole ${g.hole}` : 'On the course'} · ${ago(now, g.t)}</small></span>
          ${d != null ? `<span class="d">${fmtYds(d)}</span>` : ''}</button>`).join('')}</div>`
        : `<p class="oc-note">No other groups on the map yet. A group shows up when someone in it turns on GPS in Flagcast.</p>`;
      h += `<label class="oc-priv"><div>Show my group to other golfers<small>${hidden(opts.code) ? 'Hidden. Only the tournament desk sees where you are.' : 'They see your group’s name and hole. Never your scores or codes.'}</small></div>
        <span class="oc-sw"><input type="checkbox" id="ocShow" ${hidden(opts.code) ? '' : 'checked'} aria-label="Show my group to other golfers"><span></span></span></label>`;
      if (err) h += `<p class="oc-note">${esc(err)}</p>`;
    }
    if (h !== lastBody) { lastBody = h; const sc = $('ocBody').scrollTop; $('ocBody').innerHTML = h; $('ocBody').scrollTop = sc; }
    $('ocFabs').querySelector('[data-oc="me"]').disabled = !me;
    $('ocFabs').querySelector('[data-oc="me"]').classList.toggle('on', follow);
    placeFabs();
  }
  function placeFabs() { $('ocFabs').style.bottom = `${$('ocSheet').offsetHeight + 14}px`; }

  function draw() {
    if (stopped) return;
    sheet();
    if (!map) return;
    const me = position();
    layer.clearLayers();
    for (const g of groups) {
      if (g.me && me) continue; // your phone's own dot is newer than your group's last spot
      const cls = `ocp ${g.me ? 'me' : ''} ${!g.me && now - g.t > STALE ? 'old' : ''} ${pick === g.team ? 'pick' : ''}`;
      L.marker(g.at, { icon: L.divIcon({ className: '', html: `<div class="${cls}"><span class="h">${g.hole || '?'}</span><span class="t">${g.me ? 'Your group' : esc(shortName(g.name))}</span></div>`, iconSize: [0, 0] }), zIndexOffset: g.me ? 500 : 0 })
        .on('click', () => focus(g)).addTo(layer);
    }
    if (me) {
      if (!meDot) meDot = L.marker(me.at, { icon: L.divIcon({ className: '', html: '<div class="ocme"></div>', iconSize: [0, 0] }), zIndexOffset: 1000, interactive: false }).addTo(map);
      else meDot.setLatLng(me.at);
      if (follow) map.panTo(me.at);
    }
    if (!fitted && (groups.length || me)) { fitted = true; fit(); }
  }
  const pad = () => ({ paddingTopLeft: [40, 90], paddingBottomRight: [40, $('ocSheet').offsetHeight + 30] });
  function fit() {
    if (!map) return;
    const me = position(), pts = [...groups.map((g) => g.at), ...(me ? [me.at] : [])];
    const s = opts.state(), holes = Object.values((s && s.map && s.map.holes) || {}).flatMap((h) => [h.tee, middle(h)]).filter(Boolean);
    const all = pts.length > 1 ? pts : pts.length ? [...pts, ...holes] : holes;
    if (all.length === 1) map.setView(all[0], 17); else if (all.length) map.fitBounds(all, { ...pad(), maxZoom: 18 });
  }
  function focus(g) {
    pick = g.team; follow = false;
    $('ocSheet').classList.add('min'); placeFabs();
    map && map.setView(g.at, 18, { animate: true });
    draw();
  }
  function showHole(n) {
    const gs = groups.filter((g) => g.hole === n), h = holeMap(opts.state(), n);
    const pts = [...gs.map((g) => g.at), ...(h ? [h.tee, middle(h)].filter(Boolean) : [])];
    pick = null; follow = false; $('ocSheet').classList.add('min'); placeFabs();
    if (!map || !pts.length) return;
    if (pts.length === 1) map.setView(pts[0], 18); else map.fitBounds(pts, { ...pad(), maxZoom: 18 });
    draw();
  }

  loadLeaflet().then((Lf) => {
    if (stopped) return;
    L = Lf;
    map = L.map(root.querySelector('.ocmap'), { zoomControl: false, attributionControl: true });
    map.attributionControl.setPrefix(false);
    L.tileLayer(TILES, { maxNativeZoom: 19, maxZoom: 20, attribution: TILE_CREDIT }).addTo(map);
    // the holes: tee to green round the doglegs, the flag, and the hole number by the green
    const s = opts.state();
    for (const [n, h] of Object.entries((s && s.map && s.map.holes) || {})) {
      const g = middle(h); if (!g) continue;
      if (h.tee) L.polyline([h.tee, ...(h.line || []), g], { color: '#fff', weight: 2, opacity: 0.55, dashArray: '2 6', lineCap: 'round', interactive: false }).addTo(map);
      L.marker(g, { icon: L.divIcon({ className: '', html: `<div class="ochole">${esc(n)}</div>`, iconSize: [0, 0] }), interactive: false, zIndexOffset: -1000 }).addTo(map);
    }
    layer = L.layerGroup().addTo(map);
    map.on('dragstart', () => { follow = false; sheet(); });
    fitted = false; fit(); draw();
  }).catch((e) => { root.querySelector('.ocmap').innerHTML = `<p style="padding:120px 20px;color:#fff;text-align:center">${esc(e.message)}</p>`; });

  root.addEventListener('click', onClick);
  function onClick(e) {
    const b = e.target.closest('[data-oc],[data-team],[data-hole]'); if (!b) return;
    e.stopPropagation();
    const a = b.dataset.oc;
    if (a === 'close') return opts.onClose();
    if (a === 'sheet') { $('ocSheet').classList.toggle('min'); setTimeout(placeFabs, 260); placeFabs(); return; }
    if (a === 'gps') { startGps(); follow = true; return draw(); }
    if (a === 'all') { pick = null; follow = false; fit(); return draw(); }
    if (a === 'me') { const p = position(); if (p && map) { follow = true; pick = null; map.setView(p.at, 18); } return draw(); }
    if (b.dataset.hole) return showHole(Number(b.dataset.hole));
    if (b.dataset.team) { const g = groups.find((x) => x.team === b.dataset.team); if (g) focus(g); }
  }
  root.addEventListener('change', (e) => { if (e.target.id === 'ocShow') { setHidden(opts.code, !e.target.checked); lastBody = ''; load(); } });
  const unGps = onGps(() => draw());
  addEventListener('resize', placeFabs);
  load(); timer = setInterval(load, 20000);
  return {
    refresh: draw,
    destroy() {
      stopped = true; clearInterval(timer); unGps(); removeEventListener('resize', placeFabs);
      if (map) map.remove();
      root.remove(); document.documentElement.style.overflow = '';
    },
  };
}
