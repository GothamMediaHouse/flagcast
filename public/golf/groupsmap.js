// "Everyone on the course" on the cart scorecard: a satellite map with where you are (the phone's GPS), your
// group, and every other group sharing its spot (POST …/where → groups). Only while the tournament is on; the
// server leaves out groups that hide and spots older than 15 minutes, and never sends anyone's cart code.
import { post, esc } from '/golf/client.js';
import { TILES, TILE_CREDIT, middle, trackingOn, position, onGps, startGps, gpsWanted } from '/golf/gps.js';

const LEAFLET = 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/';
const HIDE = (code) => `flagcast:hide:${code}`;
export const hidden = (code) => { try { return localStorage.getItem(HIDE(code)) === '1'; } catch { return false; } };
const setHidden = (code, on) => { try { localStorage.setItem(HIDE(code), on ? '1' : '0'); } catch {} };

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

const STYLE = `
.gm { display: grid; gap: 12px; }
.gm .mapbox { position: relative; height: min(62vh, 520px); border-radius: 14px; overflow: hidden; border: 1px solid var(--line); background: #1b2a20; }
.gm .mapbox > div { position: absolute; inset: 0; }
.gm .note { font-size: .86rem; color: var(--muted); }
.gm .row { display: flex; gap: 8px; flex-wrap: wrap; }
.gm .row .btn { flex: 1; }
.gm .tg { display: flex; gap: 10px; align-items: center; font-size: .9rem; }
.gm .list { display: grid; gap: 6px; }
.gm .grp { display: flex; gap: 10px; align-items: center; width: 100%; text-align: left; border: 1px solid var(--line); background: var(--card); color: var(--ink); border-radius: 10px; padding: 9px 10px; font: inherit; }
.gm .grp .n { width: 32px; height: 32px; border-radius: 50%; display: grid; place-items: center; background: #3a8bff; color: #fff; font: 700 .8rem var(--f-mono); flex: none; }
.gm .grp.me .n { background: var(--club, var(--flag)); color: var(--on-flag); }
.gm .grp b { display: block; } .gm .grp small { color: var(--muted); }
.gpin { display: grid; place-items: center; min-width: 26px; height: 26px; padding: 0 6px; border-radius: 13px; background: #3a8bff; color: #fff; border: 2px solid #fff; font: 700 11px var(--f-mono); box-shadow: 0 1px 5px rgba(0,0,0,.6); white-space: nowrap; }
.gpin.me { background: var(--club, #e8c547); color: #1a1a10; }
.gme { width: 16px; height: 16px; border-radius: 50%; background: #2f7bff; border: 3px solid #fff; box-shadow: 0 0 0 8px rgba(58,139,255,.25); }
.ghole { font: 800 11px var(--f-mono); color: #1a1a10; background: rgba(255,255,255,.85); border-radius: 50%; width: 20px; height: 20px; display: grid; place-items: center; }
.leaflet-tooltip.gtip { background: rgba(10,24,16,.85); color: #fff; border: 0; font: 600 11px var(--f-body); padding: 2px 6px; box-shadow: none; }
.leaflet-tooltip.gtip::before { display: none; }`;

const ago = (now, t) => { const m = Math.round((now - t) / 60000); return m < 1 ? 'just now' : `${m} min ago`; };

/** Draws into `el`. opts: { state(), code, team(), hole() }. Returns { destroy() }. */
export function groupsMap(el, opts) {
  if (!document.getElementById('gm-style')) { const st = document.createElement('style'); st.id = 'gm-style'; st.textContent = STYLE; document.head.appendChild(st); }
  const S = opts.state();
  el.innerHTML = `<div class="gm">
    <div class="mapbox"><div id="gmMap"></div></div>
    <div class="note" id="gmNote"></div>
    <div class="row" id="gmActs"></div>
    <label class="tg"><input type="checkbox" id="gmHide"> Hide my group from other golfers</label>
    <div class="list" id="gmList"></div></div>`;
  const $ = (id) => el.querySelector('#' + id);
  $('gmHide').checked = hidden(opts.code);
  let map = null, layer = null, meDot = null, groups = [], off = null, err = '', now = Date.now(), fitted = false, timer = null, stopped = false;

  async function load() {
    const t = opts.team(); if (!t) return;
    try {
      const r = await post('where', { code: opts.code, team: t, hide: hidden(opts.code) });
      groups = r.groups || []; now = r.now || Date.now(); off = null; err = '';
    } catch (e) { groups = []; if (e.status === 409) off = true; else err = e.message; }
    draw();
  }
  function draw() {
    if (stopped) return;
    const s = opts.state(), me = position();
    const on = s && trackingOn(s);
    $('gmNote').innerHTML = !on || off ? (s && s.locked ? 'The results are final, so group spots are off.' : `Groups show here on the day of the tournament${s && s.date ? ` (${esc(s.date)})` : ''}, until the results are final.`)
      : err ? esc(err)
      : `${groups.filter((g) => !g.me).length} other group${groups.filter((g) => !g.me).length === 1 ? '' : 's'} on the map. A group shows up when someone in it has GPS on in Flagcast. Updates every 20 seconds.`;
    $('gmActs').innerHTML = gpsWanted() && me ? `<button class="btn" data-gm="fit">Show everyone</button><button class="btn" data-gm="me">Find me</button>`
      : gpsWanted() ? `<button class="btn" data-gm="fit">Show everyone</button>` : `<button class="btn primary" data-gm="gps">Use my GPS to show where I am</button>`;
    const others = groups.filter((g) => !g.me).sort((a, b) => (a.hole || 99) - (b.hole || 99));
    $('gmList').innerHTML = others.map((g) => `<button class="grp" data-gteam="${esc(g.team)}"><span class="n">${g.hole || '?'}</span><span style="flex:1;min-width:0"><b>${esc(g.name)}</b><small>${g.hole ? `On hole ${g.hole}` : 'On the course'} · ${ago(now, g.t)}</small></span></button>`).join('');
    if (!map) return;
    layer.clearLayers();
    for (const g of groups) {
      if (g.me && me) continue; // your phone's dot is newer than your group's last spot
      L.marker(g.at, { icon: L.divIcon({ className: '', html: `<div class="gpin ${g.me ? 'me' : ''}">${g.hole || '?'}</div>`, iconSize: null, iconAnchor: [13, 13] }) })
        .bindTooltip(g.me ? 'Your group' : esc(String(g.name).split(' / ')[0]), { permanent: true, direction: 'right', offset: [12, 0], className: 'gtip' }).addTo(layer);
    }
    if (me) {
      if (!meDot) meDot = L.marker(me.at, { icon: L.divIcon({ className: '', html: '<div class="gme"></div>', iconSize: [16, 16], iconAnchor: [8, 8] }), zIndexOffset: 1000 }).bindTooltip('You', { direction: 'right', offset: [10, 0], className: 'gtip' }).addTo(map);
      else meDot.setLatLng(me.at);
    }
    if (!fitted && (groups.length || me)) { fitted = true; fit(); }
  }
  function fit() {
    const me = position(), pts = [...groups.map((g) => g.at), ...(me ? [me.at] : [])];
    const s = opts.state(), holes = Object.values((s && s.map && s.map.holes) || {}).flatMap((h) => [h.tee, middle(h)]).filter(Boolean);
    const all = pts.length ? pts : holes;
    if (all.length === 1) map.setView(all[0], 17); else if (all.length) map.fitBounds(all, { padding: [40, 40], maxZoom: 17 });
  }

  loadLeaflet().then((L) => {
    if (stopped) return;
    map = L.map($('gmMap'), { zoomControl: false, attributionControl: true });
    L.tileLayer(TILES, { maxNativeZoom: 19, maxZoom: 20, attribution: TILE_CREDIT }).addTo(map);
    // the hole numbers on their greens, so the map reads like the course
    const s = opts.state();
    for (const [n, h] of Object.entries((s && s.map && s.map.holes) || {})) {
      const g = middle(h); if (!g) continue;
      if (h.tee) L.polyline([h.tee, ...((h.line) || []), g], { color: '#fff', weight: 1.5, opacity: 0.5, dashArray: '4 5', interactive: false }).addTo(map);
      L.marker(g, { icon: L.divIcon({ className: '', html: `<div class="ghole">${esc(n)}</div>`, iconSize: [20, 20], iconAnchor: [10, 10] }), interactive: false }).addTo(map);
    }
    layer = L.layerGroup().addTo(map);
    fitted = false; fit(); draw();
  }).catch((e) => { $('gmMap').parentElement.innerHTML = `<p class="note" style="padding:16px;color:#fff">${esc(e.message)}</p>`; });

  el.addEventListener('click', onClick);
  function onClick(e) {
    const b = e.target.closest('[data-gm],[data-gteam]'); if (!b) return;
    if (b.dataset.gm === 'gps') { startGps(); draw(); }
    else if (b.dataset.gm === 'fit' && map) fit();
    else if (b.dataset.gm === 'me' && map && position()) map.setView(position().at, 18);
    else if (b.dataset.gteam && map) { const g = groups.find((x) => x.team === b.dataset.gteam); if (g) { map.setView(g.at, 18); el.querySelector('.mapbox').scrollIntoView({ behavior: 'smooth', block: 'center' }); } }
  }
  $('gmHide').addEventListener('change', (e) => { setHidden(opts.code, e.target.checked); load(); });
  const unGps = onGps(() => draw());
  load(); timer = setInterval(load, 20000);
  return { refresh: draw, destroy() { stopped = true; clearInterval(timer); unGps(); el.removeEventListener('click', onClick); if (map) map.remove(); } };
}
