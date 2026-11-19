// Hole GPS: yardages from the phone's location and a course view of each hole (satellite picture turned so the
// tee is at the bottom and the green at the top, like golf GPS apps). The course map comes from S.map
// (made on /g/<id>/map): per hole tee, f/m/b (front, middle, back of the green) and hz (hazards: p reach, c carry).

// satellite pictures. Esri World Imagery: free to try; for paid use sign up for ArcGIS Location Platform and
// add the key here (…/tile/{z}/{y}/{x}?token=KEY), or swap in another provider with the same tile layout.
export const TILES = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
export const TILE_CREDIT = 'Imagery © Esri, Maxar, Earthstar Geographics';
const MAXZ = 19;

const R = 6371008.8, YD = 1.0936133;
// yards between two [lat, lng] points
export function yds(a, b) {
  if (!a || !b) return null;
  const t = Math.PI / 180, dla = (b[0] - a[0]) * t, dlo = (b[1] - a[1]) * t;
  const h = Math.sin(dla / 2) ** 2 + Math.cos(a[0] * t) * Math.cos(b[0] * t) * Math.sin(dlo / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h))) * YD;
}
export const middle = (h) => h && (h.m || (h.f && h.b ? [(h.f[0] + h.b[0]) / 2, (h.f[1] + h.b[1]) / 2] : h.f || h.b)) || null;
export const holeMap = (S, n) => (S && S.map && S.map.holes && (S.map.holes[n] || S.map.holes[String(n)])) || null;
export const mapped = (S) => !!(S && S.map && S.map.holes && Object.values(S.map.holes).some((h) => middle(h)));
export const HZ_LABEL = { bunker: 'Bunker', water: 'Water', trees: 'Trees', layup: 'Layup', other: 'Hazard' };
const HZ_COLOR = { bunker: '#f2e2b0', water: '#5fb4ff', trees: '#7fd18b', layup: '#ffffff', other: '#ffb36b' };

// group tracking runs only while the tournament is on: on its date (US time zones: 04:00 UTC that day to
// 11:00 UTC the next) and until the results are made final. The server checks the same thing.
export function trackingOn(S, now = Date.now()) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec((S && S.date) || ''); if (!m || S.locked) return false;
  const d = Date.UTC(+m[1], +m[2] - 1, +m[3]);
  return now >= d + 4 * 3600000 && now <= d + 35 * 3600000;
}

// ---- where the phone is ----
let watch = null, fix = null; const subs = new Set();
const KEY = 'flagcast:gps';
export const gpsWanted = () => { try { return localStorage.getItem(KEY) === '1'; } catch { return false; } };
export const position = () => fix;
// start following the phone. fn({ at: [lat, lng], acc (yards), t } | { error })
export function startGps(fn) {
  if (fn) subs.add(fn);
  try { localStorage.setItem(KEY, '1'); } catch {}
  if (watch != null || !navigator.geolocation) { if (!navigator.geolocation) fn && fn({ error: 'This phone can’t share its location.' }); else if (fix && fn) fn(fix); return; }
  watch = navigator.geolocation.watchPosition((p) => {
    fix = { at: [p.coords.latitude, p.coords.longitude], acc: Math.round(p.coords.accuracy * YD), t: Date.now() };
    subs.forEach((f) => f(fix));
  }, (e) => {
    const error = e.code === 1 ? 'Location is off for Flagcast. Turn it on in your phone’s settings to see yardages.' : 'Can’t find your spot yet. Yardages show once the phone has GPS.';
    if (e.code === 1) { stopGps(); }
    subs.forEach((f) => f({ error }));
  }, { enableHighAccuracy: true, maximumAge: 3000, timeout: 20000 });
}
export function stopGps() {
  if (watch != null) navigator.geolocation.clearWatch(watch);
  watch = null; fix = null;
  try { localStorage.setItem(KEY, '0'); } catch {}
}
export const onGps = (fn) => { subs.add(fn); return () => subs.delete(fn); };

// from where: the phone when it's on this hole, otherwise the tee
export function origin(h, me) {
  const g = middle(h);
  if (me && g) {
    const toG = yds(me, g), len = h.tee ? yds(h.tee, g) : 600;
    if (toG <= len + 40 && toG < 700) return { at: me, me: true };
  }
  return h && h.tee ? { at: h.tee, me: false } : null;
}

// the yardages for one hole from a point: { f, m, b, hz: [{ name, k, reach, carry }] }, hazards behind you left out
export function yardages(h, from) {
  if (!h || !from) return null;
  const g = middle(h), toG = yds(from, g);
  const r = (p) => (p ? Math.round(yds(from, p)) : null);
  const hz = (h.hz || []).map((z) => ({ src: z, name: z.n || HZ_LABEL[z.k] || 'Hazard', k: z.k, reach: r(z.p), carry: r(z.c) }))
    .filter((z) => toG == null || yds(z.src.c || z.src.p, g) <= toG + 5).sort((a, b) => a.reach - b.reach);
  return { f: r(h.f), m: r(g), b: r(h.b), hz };
}

// ---- web mercator ----
const W = (z) => 256 * 2 ** z;
const toPx = ([lat, lng], z) => {
  const s = Math.sin((Math.max(-85, Math.min(85, lat)) * Math.PI) / 180);
  return { x: ((lng + 180) / 360) * W(z), y: (0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI)) * W(z) };
};
const fromPx = ({ x, y }, z) => {
  const n = Math.PI - (2 * Math.PI * y) / W(z);
  return [(180 / Math.PI) * Math.atan(0.5 * (Math.exp(n) - Math.exp(-n))), (x / W(z)) * 360 - 180];
};

// ---- the course view ----
// holeView(canvas) → { draw(h, me), destroy() }. Tap the picture to measure: you → there → the green.
const tiles = new Map();
function tile(z, x, y, redraw) {
  const k = `${z}/${x}/${y}`; let t = tiles.get(k);
  if (!t) {
    t = new Image(); t.decoding = 'async'; t.onload = redraw; t.onerror = () => { t.bad = true; };
    t.src = TILES.replace('{z}', z).replace('{x}', x).replace('{y}', y);
    tiles.set(k, t); if (tiles.size > 400) tiles.delete(tiles.keys().next().value);
  } else if (!t.complete) t.addEventListener('load', redraw, { once: true });
  return t;
}

export function holeView(canvas) {
  const ctx = canvas.getContext('2d');
  let H = null, ME = null, tap = null, view = null, raf = 0;
  const redraw = () => { if (!raf) raf = requestAnimationFrame(() => { raf = 0; paint(); }); };

  function layout() {
    const dpr = Math.min(3, window.devicePixelRatio || 1);
    const w = canvas.clientWidth || 360, hgt = canvas.clientHeight || 480;
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(hgt * dpr)) { canvas.width = Math.round(w * dpr); canvas.height = Math.round(hgt * dpr); }
    const g = middle(H); if (!g) return null;
    const o = origin(H, ME), a = o ? o.at : null;
    // bottom = where you hit from, top = the green; fit them in 80% of the height
    const z0 = 0, pa = a ? toPx(a, z0) : null, pg = toPx(g, z0);
    let ang = 0, len = 0;
    if (pa) { const dx = pg.x - pa.x, dy = pg.y - pa.y; ang = Math.atan2(dx, -dy); len = Math.hypot(dx, dy); }
    const span = hgt * (pa ? 0.74 : 0.5);
    // zoom: the hole fits, but never closer in than about 70 yards top to bottom
    const px70 = 70 / YD / (156543.03 * Math.cos((g[0] * Math.PI) / 180)); // 70 yards in zoom-0 pixels
    const z = Math.min(MAXZ + 1.5, Math.log2(span / Math.max(len, px70)));
    const zi = Math.max(1, Math.min(MAXZ, Math.ceil(z))), sc = 2 ** (z - zi);
    const mid = pa ? { x: (pa.x + pg.x) / 2, y: (pa.y + pg.y) / 2 } : pg;
    const c = { x: w / 2, y: hgt * (pa ? 0.5 : 0.45) };
    const m = { x: mid.x * 2 ** zi, y: mid.y * 2 ** zi };
    const cos = Math.cos(-ang), sin = Math.sin(-ang);
    const fwd = (p) => { const q = toPx(p, zi), dx = (q.x - m.x) * sc, dy = (q.y - m.y) * sc; return { x: c.x + dx * cos - dy * sin, y: c.y + dx * sin + dy * cos }; };
    const back = (s) => { const dx = s.x - c.x, dy = s.y - c.y; return fromPx({ x: m.x + (dx * cos + dy * sin) / sc, y: m.y + (-dx * sin + dy * cos) / sc }, zi); };
    return { w, hgt, dpr, zi, sc, ang, m, c, fwd, back, from: o };
  }

  function paint() {
    view = layout(); const v = view;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.fillStyle = '#16301f'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    if (!v) return;
    ctx.setTransform(v.dpr, 0, 0, v.dpr, 0, 0);
    // satellite tiles, turned
    ctx.save(); ctx.translate(v.c.x, v.c.y); ctx.rotate(-v.ang); ctx.scale(v.sc, v.sc); ctx.translate(-v.m.x, -v.m.y);
    const r = Math.hypot(v.w, v.hgt) / v.sc / 2 + 256, n = 2 ** v.zi, seam = 1.5 / v.sc; // overlap so no lines show between tiles
    for (let ty = Math.floor((v.m.y - r) / 256); ty <= Math.floor((v.m.y + r) / 256); ty++) {
      if (ty < 0 || ty >= n) continue;
      for (let tx = Math.floor((v.m.x - r) / 256); tx <= Math.floor((v.m.x + r) / 256); tx++) {
        const wx = ((tx % n) + n) % n, t = tile(v.zi, wx, ty, redraw);
        if (t.complete && !t.bad && t.naturalWidth) { ctx.drawImage(t, tx * 256, ty * 256, 256 + seam, 256 + seam); continue; }
        // still loading: show the zoomed-out picture under it meanwhile
        const up = tile(v.zi - 1, wx >> 1, ty >> 1, redraw);
        if (up.complete && !up.bad && up.naturalWidth) ctx.drawImage(up, (wx & 1) * 128, (ty & 1) * 128, 128, 128, tx * 256, ty * 256, 256 + seam, 256 + seam);
      }
    }
    ctx.restore();
    const h = H, g = middle(h), P = (p) => v.fwd(p);
    // line from where you are (or the tee) to the green
    const from = v.from && v.from.at;
    const label = (x, y, text, bg = 'rgba(10,24,16,.82)', fg = '#fff') => {
      ctx.font = '700 13px system-ui, -apple-system, sans-serif';
      const w = ctx.measureText(text).width + 12;
      ctx.fillStyle = bg; roundRect(ctx, x - w / 2, y - 11, w, 22, 11); ctx.fill();
      ctx.fillStyle = fg; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(text, x, y + 0.5);
    };
    const dot = (p, rad, fill, stroke = '#fff') => { const s = P(p); ctx.beginPath(); ctx.arc(s.x, s.y, rad, 0, 7); ctx.fillStyle = fill; ctx.fill(); ctx.lineWidth = 2; ctx.strokeStyle = stroke; ctx.stroke(); return s; };
    ctx.lineCap = 'round';
    if (tap && from) {
      const a = P(from), t = P(tap), gg = P(g);
      ctx.setLineDash([]); ctx.strokeStyle = '#e8c547'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(t.x, t.y); ctx.lineTo(gg.x, gg.y); ctx.stroke();
      dot(tap, 7, '#e8c547', '#1a1a10');
      label((a.x + t.x) / 2, (a.y + t.y) / 2, `${Math.round(yds(from, tap))}`, '#e8c547', '#1a1a10');
      label((t.x + gg.x) / 2, (t.y + gg.y) / 2, `${Math.round(yds(tap, g))}`, '#e8c547', '#1a1a10');
    } else if (from) {
      const a = P(from), gg = P(g);
      ctx.setLineDash([6, 7]); ctx.strokeStyle = 'rgba(255,255,255,.85)'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(gg.x, gg.y); ctx.stroke(); ctx.setLineDash([]);
    }
    // hazards
    for (const z of h.hz || []) {
      const s = dot(z.p, 5, HZ_COLOR[z.k] || '#ffb36b', 'rgba(0,0,0,.6)');
      if (z.c) { const e = P(z.c); ctx.strokeStyle = HZ_COLOR[z.k] || '#ffb36b'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(s.x, s.y); ctx.lineTo(e.x, e.y); ctx.stroke(); }
      if (from) label(s.x + (s.x > v.w / 2 ? -34 : 34), s.y, `${Math.round(yds(from, z.p))}${z.c ? `–${Math.round(yds(from, z.c))}` : ''}`);
    }
    // the green: front, middle, back
    for (const k of ['f', 'b']) if (h[k]) dot(h[k], 3.5, '#fff', 'rgba(0,0,0,.5)');
    const gs = P(g);
    ctx.beginPath(); ctx.moveTo(gs.x, gs.y); ctx.lineTo(gs.x, gs.y - 24); ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.stroke();
    ctx.beginPath(); ctx.moveTo(gs.x, gs.y - 24); ctx.lineTo(gs.x + 13, gs.y - 19); ctx.lineTo(gs.x, gs.y - 14); ctx.closePath(); ctx.fillStyle = '#c8312b'; ctx.fill();
    if (h.tee && !(v.from && v.from.me)) dot(h.tee, 5, '#e8c547', '#1a1a10');
    if (ME) {
      const s = P(ME);
      if (s.x > -20 && s.y > -20 && s.x < v.w + 20 && s.y < v.hgt + 20) {
        ctx.beginPath(); ctx.arc(s.x, s.y, 12, 0, 7); ctx.fillStyle = 'rgba(70,150,255,.25)'; ctx.fill();
        dot(ME, 7, '#3a8bff');
      }
    }
    ctx.font = '10px system-ui, sans-serif'; ctx.textAlign = 'right'; ctx.textBaseline = 'bottom'; ctx.fillStyle = 'rgba(255,255,255,.7)';
    ctx.fillText(TILE_CREDIT, v.w - 6, v.hgt - 4);
  }

  const onTap = (e) => {
    if (!view) return;
    const b = canvas.getBoundingClientRect(), s = { x: e.clientX - b.left, y: e.clientY - b.top };
    const was = tap; tap = view.back(s);
    // tap the same spot again to clear it
    if (was) { const p = view.fwd(was); if (Math.hypot(p.x - s.x, p.y - s.y) < 26) tap = null; }
    paint(); canvas.dispatchEvent(new CustomEvent('measure', { detail: tap && view.from ? { to: Math.round(yds(view.from.at, tap)), left: Math.round(yds(tap, middle(H))) } : null }));
  };
  canvas.addEventListener('click', onTap);
  const ro = typeof ResizeObserver === 'function' ? new ResizeObserver(redraw) : null; ro && ro.observe(canvas);
  return {
    draw(h, me) { if (h !== H) tap = null; H = h; ME = me || null; paint(); },
    clearTap() { tap = null; paint(); },
    destroy() { canvas.removeEventListener('click', onTap); ro && ro.disconnect(); cancelAnimationFrame(raf); },
  };
}

function roundRect(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }
