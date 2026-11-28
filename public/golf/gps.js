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
// the hole from `from` to the green round its doglegs: you, the bends still ahead (h.line), the green
export function ahead(h, from, g) {
  const left = yds(from, g) || 0;
  const bends = ((h && h.line) || []).filter((b) => yds(b, g) < left - 20 && yds(from, b) > 20).sort((x, y) => yds(y, g) - yds(x, g));
  return [from, ...bends, g];
}
// where that line is `d` yards from `from` as the crow flies (where a carry arc crosses the fairway)
export function cross(pts, from, d) {
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1], b = pts[i], n = Math.max(1, Math.ceil((yds(a, b) || 0) / 2));
    for (let k = 0; k <= n; k++) { const p = [a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n]; if (yds(from, p) >= d) return p; }
  }
  return null;
}
export const middle = (h) => h && (h.m || (h.f && h.b ? [(h.f[0] + h.b[0]) / 2, (h.f[1] + h.b[1]) / 2] : h.f || h.b)) || null;
export const holeMap = (S, n) => (S && S.map && S.map.holes && (S.map.holes[n] || S.map.holes[String(n)])) || null;
export const mapped = (S) => !!(S && S.map && S.map.holes && Object.values(S.map.holes).some((h) => middle(h)));
export const HZ_LABEL = { bunker: 'Bunker', water: 'Water', trees: 'Trees', layup: 'Layup', other: 'Hazard' };
const HZ_COLOR = { bunker: '#f2e2b0', water: '#5fb4ff', trees: '#7fd18b', layup: '#ffffff', other: '#ffb36b' };

// group tracking runs only while the tournament is on: on its date (US time zones: 04:00 UTC that day to
// 11:00 UTC the next), or any of its rounds' dates, and until the results are made final. The server checks the same thing.
export function trackingOn(S, now = Date.now()) {
  if (S && !S.locked && (S.demo || S.brand?.marked)) return true; // a Demo tournament (Admin's switch): any day, sample groups walk it
  if (!S || S.locked) return false;
  const dates = [S.date, ...(S.rounds || []).map((r) => r && r.date)];
  return dates.some((x) => {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(x || ''); if (!m) return false;
    const d = Date.UTC(+m[1], +m[2] - 1, +m[3]);
    return now >= d + 4 * 3600000 && now <= d + 35 * 3600000;
  });
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
  let H = null, ME = null, tap = null, view = null, raf = 0, credit = false; const flatCanvas = document.createElement('canvas');
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
    const span = hgt * (pa ? 0.62 : 0.5);
    // zoom: the hole fits, but never closer in than about 70 yards top to bottom
    const px70 = 70 / YD / (156543.03 * Math.cos((g[0] * Math.PI) / 180)); // 70 yards in zoom-0 pixels
    const z = Math.min(MAXZ + 1.5, Math.log2(span / Math.max(len, px70)));
    const zi = Math.max(1, Math.min(MAXZ, Math.ceil(z))), sc = 2 ** (z - zi);
    const mid = pa ? { x: (pa.x + pg.x) / 2, y: (pa.y + pg.y) / 2 } : pg;
    const c = { x: w / 2, y: hgt * (pa ? 0.56 : 0.5) }; // the green sits below the yardage box
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
    // satellite tiles: laid out flat on one picture first, then turned in one go (no lines between tiles)
    const r = Math.hypot(v.w, v.hgt) / v.sc / 2 + 64, n = 2 ** v.zi;
    const tx0 = Math.floor((v.m.x - r) / 256), tx1 = Math.floor((v.m.x + r) / 256), ty0 = Math.floor((v.m.y - r) / 256), ty1 = Math.floor((v.m.y + r) / 256);
    const flat = flatCanvas;
    flat.width = (tx1 - tx0 + 1) * 256; flat.height = (ty1 - ty0 + 1) * 256;
    const fc = flat.getContext('2d'); fc.fillStyle = '#2c4a2a'; fc.fillRect(0, 0, flat.width, flat.height);
    for (let ty = ty0; ty <= ty1; ty++) {
      if (ty < 0 || ty >= n) continue;
      for (let tx = tx0; tx <= tx1; tx++) {
        const wx = ((tx % n) + n) % n, t = tile(v.zi, wx, ty, redraw), x = (tx - tx0) * 256, y = (ty - ty0) * 256;
        if (t.complete && !t.bad && t.naturalWidth) { fc.drawImage(t, x, y); continue; }
        // still loading: show the zoomed-out picture under it meanwhile
        const up = tile(v.zi - 1, wx >> 1, ty >> 1, redraw);
        if (up.complete && !up.bad && up.naturalWidth) fc.drawImage(up, (wx & 1) * 128, (ty & 1) * 128, 128, 128, x, y, 256, 256);
      }
    }
    ctx.save(); ctx.translate(v.c.x, v.c.y); ctx.rotate(-v.ang); ctx.scale(v.sc, v.sc); ctx.translate(-v.m.x, -v.m.y);
    ctx.imageSmoothingQuality = 'high'; ctx.drawImage(flat, tx0 * 256, ty0 * 256);
    ctx.restore();
    const h = H, g = middle(h), P = (p) => v.fwd(p);
    const from = v.from && v.from.at;
    // soft shade at the top and bottom so the labels read on any picture
    let gr = ctx.createLinearGradient(0, 0, 0, 120); gr.addColorStop(0, 'rgba(0,0,0,.35)'); gr.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = gr; ctx.fillRect(0, 0, v.w, 120);
    gr = ctx.createLinearGradient(0, v.hgt - 90, 0, v.hgt); gr.addColorStop(0, 'rgba(0,0,0,0)'); gr.addColorStop(1, 'rgba(0,0,0,.3)');
    ctx.fillStyle = gr; ctx.fillRect(0, v.hgt - 90, v.w, 90);
    const FONT = '-apple-system, system-ui, "Segoe UI", sans-serif';
    const shadow = (on) => { ctx.shadowColor = on ? 'rgba(0,0,0,.45)' : 'transparent'; ctx.shadowBlur = on ? 6 : 0; ctx.shadowOffsetY = on ? 1 : 0; };
    // a pill with the number; dot = the hazard's colour
    const label = (x, y, text, { bg = 'rgba(12,22,16,.88)', fg = '#fff', dot: dc = null, size = 13 } = {}) => {
      ctx.font = `700 ${size}px ${FONT}`;
      const tw = ctx.measureText(text).width, w = tw + (dc ? 26 : 16), hh = size + 10;
      x = Math.max(w / 2 + 4, Math.min(v.w - w / 2 - 4, x));
      shadow(true); ctx.fillStyle = bg; roundRect(ctx, x - w / 2, y - hh / 2, w, hh, hh / 2); ctx.fill(); shadow(false);
      if (dc) { ctx.beginPath(); ctx.arc(x - w / 2 + 11, y, 4, 0, 7); ctx.fillStyle = dc; ctx.fill(); }
      ctx.fillStyle = fg; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(text, x + (dc ? 5 : 0), y + 0.5);
    };
    const ring = (p, rad, fill, stroke = '#fff', lw = 2) => { const s = P(p); shadow(true); ctx.beginPath(); ctx.arc(s.x, s.y, rad, 0, 7); ctx.fillStyle = fill; ctx.fill(); shadow(false); ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.stroke(); return s; };
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const line = (pts, color, width, dash = []) => {
      ctx.setLineDash(dash); shadow(true); ctx.strokeStyle = color; ctx.lineWidth = width; ctx.beginPath();
      pts.forEach((q, i) => (i ? ctx.lineTo(q.x, q.y) : ctx.moveTo(q.x, q.y))); ctx.stroke(); shadow(false); ctx.setLineDash([]);
    };
    if (from) {
      const a = P(from), gg = P(g), toG = yds(from, g);
      // carry arcs every 50 yards from where you are (like the rings in golf GPS apps)
      // the hole from here to the green round its doglegs; each arc is centred where it crosses that line
      const way = ahead(h, from, g), wayPx = way.map(P);
      const pxPerYd = Math.hypot(gg.x - a.x, gg.y - a.y) / toG;
      for (let d = 50; d < toG - 25; d += 50) {
        if (d < 100 && toG > 250) continue;
        const r = d * pxPerYd; if (r < 40) continue;
        const c = cross(way, from, d), cp = c ? P(c) : gg, up = Math.atan2(cp.y - a.y, cp.x - a.x);
        const span = Math.min(0.5, 70 / r);
        ctx.strokeStyle = 'rgba(255,255,255,.55)'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(a.x, a.y, r, up - span, up + span); ctx.stroke();
        const ex = a.x + r * Math.cos(up + span), ey = a.y + r * Math.sin(up + span);
        ctx.font = `700 11px ${FONT}`; ctx.fillStyle = 'rgba(255,255,255,.9)'; ctx.textAlign = 'left'; ctx.textBaseline = 'middle';
        shadow(true); ctx.fillText(String(d), ex + 4, ey); shadow(false);
      }
      if (tap) {
        const t = P(tap);
        line([a, t, gg], '#f2d04f', 3);
        ring(tap, 8, '#f2d04f', '#1a1a10');
        label((a.x + t.x) / 2 + 26, (a.y + t.y) / 2, `${Math.round(yds(from, tap))}`, { bg: '#f2d04f', fg: '#1a1a10', size: 15 });
        label((t.x + gg.x) / 2 + 26, (t.y + gg.y) / 2, `${Math.round(yds(tap, g))}`, { bg: '#f2d04f', fg: '#1a1a10', size: 15 });
      } else line(wayPx, 'rgba(255,255,255,.95)', 2.5);
    }
    // hazards: a small ring where you reach it, a line to where it's carried, and the numbers
    for (const z of h.hz || []) {
      const c = HZ_COLOR[z.k] || '#ffb36b';
      if (z.c) line([P(z.p), P(z.c)], c, 2.5);
      const s = ring(z.p, 4.5, c, 'rgba(0,0,0,.55)', 1.5);
      if (z.c) ring(z.c, 3.5, c, 'rgba(0,0,0,.55)', 1.5);
      if (from) label(s.x + (s.x > v.w / 2 ? -44 : 44), s.y, `${Math.round(yds(from, z.p))}${z.c ? ` · ${Math.round(yds(from, z.c))}` : ''}`, { dot: c });
    }
    // the green: front and back marks, and the flag in the middle
    for (const k of ['f', 'b']) if (h[k]) ring(h[k], 3, 'rgba(255,255,255,.9)', 'rgba(0,0,0,.4)', 1);
    const gs = P(g);
    shadow(true);
    ctx.beginPath(); ctx.ellipse(gs.x, gs.y, 4, 2, 0, 0, 7); ctx.fillStyle = 'rgba(0,0,0,.5)'; ctx.fill();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(gs.x, gs.y); ctx.lineTo(gs.x, gs.y - 34); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(gs.x + 1, gs.y - 34); ctx.quadraticCurveTo(gs.x + 10, gs.y - 32, gs.x + 18, gs.y - 28); ctx.quadraticCurveTo(gs.x + 10, gs.y - 25, gs.x + 1, gs.y - 22); ctx.closePath();
    ctx.fillStyle = '#e0362c'; ctx.fill(); shadow(false);
    if (h.tee && !(v.from && v.from.me)) {
      const s = ring(h.tee, 9, '#f2d04f', '#1a1a10', 1.5);
      ctx.font = `800 10px ${FONT}`; ctx.fillStyle = '#1a1a10'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText('T', s.x, s.y + 0.5);
    }
    if (ME) {
      const s = P(ME);
      if (s.x > -20 && s.y > -20 && s.x < v.w + 20 && s.y < v.hgt + 20) {
        ctx.beginPath(); ctx.arc(s.x, s.y, 16, 0, 7); ctx.fillStyle = 'rgba(58,139,255,.22)'; ctx.fill();
        ring(ME, 7.5, '#2f7bff', '#fff', 3);
      }
    }
    ctx.font = '10px system-ui, sans-serif'; ctx.textAlign = 'right'; ctx.textBaseline = 'bottom'; ctx.fillStyle = 'rgba(255,255,255,.7)';
    ctx.fillText(credit ? `${TILE_CREDIT} · Course data © OpenStreetMap` : TILE_CREDIT, v.w - 6, v.hgt - 4);
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
    draw(h, me, osm) { if (h !== H) tap = null; H = h; ME = me || null; credit = !!osm; paint(); },
    clearTap() { tap = null; paint(); },
    destroy() { canvas.removeEventListener('click', onTap); ro && ro.disconnect(); cancelAnimationFrame(raf); },
  };
}

function roundRect(c, x, y, w, h, r) { c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r); c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath(); }

// ---- the pin sheet: where the hole is cut on each green (Manager → Pin sheet) ----
// S.pinsheet = { '<hole>': { d: 'F'|'M'|'B' (front, middle, back), s: 'L'|'C'|'R' (left, center, right),
//   on: paces from the front edge (optional), off: paces in from the left or right edge (optional) } }
// The course map has only the front, middle and back of each green, so the pin's yards come from those:
// front + paces on when the paces are known (a pace is about a yard), else halfway to the middle for a front or back pin.
export const PIN_DEPTH = { F: 'Front', M: 'Middle', B: 'Back' }, PIN_SIDE = { L: 'left', C: '', R: 'right' };
export function cleanPin(p) {
  if (!p || typeof p !== 'object' || !PIN_DEPTH[p.d]) return null;
  const s = PIN_SIDE[p.s] !== undefined ? p.s : 'C';
  const n = (v, hi) => { const x = Math.round(Number(v)); return Number.isFinite(x) ? Math.min(hi, Math.max(0, x)) : 0; };
  const on = n(p.on, 60), off = s === 'C' ? 0 : n(p.off, 30);
  return { d: p.d, s, ...(on ? { on } : {}), ...(off ? { off } : {}) };
}
export const pinOf = (S, n) => (S && S.pinsheet && (S.pinsheet[n] || S.pinsheet[String(n)])) || null;
/** "Back right", "Middle", "Front left" */
export function pinLabel(p) {
  if (!p || !PIN_DEPTH[p.d]) return '';
  const side = PIN_SIDE[p.s] || '';
  return side ? `${PIN_DEPTH[p.d]} ${side}` : PIN_DEPTH[p.d];
}
/** "26 on · 4 R" (what's on a printed pin sheet), '' when no paces */
export function pinPaces(p) {
  if (!p) return '';
  return [p.on ? `${p.on} on` : '', p.off && p.s !== 'C' ? `${p.off} ${p.s}` : ''].filter(Boolean).join(' · ');
}
/** yards to the pin, from the yards to the front, middle and back of the green ({ f, m, b }) */
export function pinYards(y, p) {
  if (!p || !y) return null;
  const { f, m, b } = y, r = (v) => (v == null ? null : Math.round(v));
  if (p.on > 0 && f != null) return r(f + p.on);
  if (p.d === 'F') return r(f != null && m != null ? (f + m) / 2 : f ?? m);
  if (p.d === 'B') return r(b != null && m != null ? (m + b) / 2 : b ?? m);
  return r(m ?? f ?? b);
}
// the drawn green the Manager and golfers' screens share (viewBox 0 0 150 140: back at the top, front at the bottom)
export const GREEN_PATH = 'M40 20 C58 6 92 4 114 14 C136 24 146 46 140 70 C134 92 118 100 104 104 C92 108 86 118 74 128 C58 140 30 136 18 118 C6 100 10 82 20 70 C28 60 24 40 40 20 Z';
/** where a pin sits on GREEN_PATH: [x, y] */
export const pinSpot = (p) => [{ L: 44, C: 80, R: 116 }[p && p.s] ?? 80, { B: 30, M: 68, F: 104 }[p && p.d] ?? 68];
