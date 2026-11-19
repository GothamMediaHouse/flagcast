// Course maps made automatically from OpenStreetMap. Many courses there have each hole drawn as a line from tee
// to green (golf=hole, ref = hole number), with greens, tees, bunkers and water drawn as shapes. This turns that
// into Flagcast's map: tee, front / middle / back of the green, and hazards with where you reach and carry them.
// Map data © OpenStreetMap contributors (ODbL).
export const OSM_CREDIT = 'Course data © OpenStreetMap contributors';
const OVERPASS = 'https://overpass-api.de/api/interpreter';

// flat x/y in metres around a point (fine at golf-course size)
function frame(o) {
  const kx = 111320 * Math.cos((o[0] * Math.PI) / 180), ky = 110574;
  return { to: (p) => [(p[1] - o[1]) * kx, (p[0] - o[0]) * ky], back: (q) => [o[0] + q[1] / ky, o[1] + q[0] / kx] };
}
const pts = (el) => (el.geometry || []).map((g) => [g.lat, g.lon]);
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const centroid = (xy) => { const n = xy.length - (dist(xy[0], xy[xy.length - 1]) < 0.5 ? 1 : 0); let x = 0, y = 0; for (let i = 0; i < n; i++) { x += xy[i][0]; y += xy[i][1]; } return [x / n, y / n]; };
// distance from point p to the line a→b (and how far along it, 0..1)
function toSeg(p, a, b) {
  const dx = b[0] - a[0], dy = b[1] - a[1], L2 = dx * dx + dy * dy || 1;
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / L2));
  return { d: Math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy), t };
}
function toPath(p, line) { let best = { d: Infinity }; for (let i = 1; i < line.length; i++) { const r = toSeg(p, line[i - 1], line[i]); if (r.d < best.d) best = r; } return best.d; }

// ask OpenStreetMap for the golf shapes in a box [south, west, north, east]
export async function fetchGolf([s, w, n, e]) {
  const bb = `${s},${w},${n},${e}`;
  const q = `[out:json][timeout:25];(way["golf"="hole"](${bb});way["golf"~"^(green|tee|bunker|water_hazard|lateral_water_hazard|fairway)$"](${bb});way["natural"="water"](${bb});way["natural"="sand"](${bb}););out geom;`;
  const r = await fetch(OVERPASS, { method: 'POST', body: 'data=' + encodeURIComponent(q), headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
  if (!r.ok) throw new Error(r.status === 429 || r.status === 504 ? 'The map data service is busy. Try again in a minute.' : 'The map data service didn’t answer. Try again.');
  return (await r.json()).elements || [];
}

// → { holes: { n: { tee, f, m, b, hz } }, found: [n…], unnumbered }
export function buildMap(elements, near) {
  const holesEl = elements.filter((x) => x.tags && x.tags.golf === 'hole' && x.geometry && x.geometry.length >= 2);
  const o = near || pts(holesEl[0] || elements[0] || { geometry: [{ lat: 0, lon: 0 }] })[0];
  const F = frame(o), XY = (el) => pts(el).map(F.to);
  const greens = elements.filter((x) => x.tags?.golf === 'green').map((x) => ({ xy: XY(x) })).map((g) => ({ ...g, c: centroid(g.xy) }));
  const hazards = elements.filter((x) => x.tags && x.geometry && (x.tags.golf === 'bunker' || x.tags.natural === 'sand' || x.tags.golf === 'water_hazard' || x.tags.golf === 'lateral_water_hazard' || x.tags.natural === 'water'))
    .map((x) => ({ k: x.tags.golf === 'bunker' || x.tags.natural === 'sand' ? 'bunker' : 'water', name: x.tags.name || '', xy: XY(x) }));
  // a hole number used twice (27 holes, or two courses): keep the one nearest where you're looking
  const byRef = new Map(); let unnumbered = 0;
  for (const h of holesEl) {
    const n = parseInt(h.tags.ref, 10);
    if (!(n >= 1 && n <= 18)) { unnumbered++; continue; }
    const line = XY(h), d = Math.hypot(...line[0]);
    if (!byRef.has(n) || d < byRef.get(n).d) byRef.set(n, { line, d });
  }
  const out = {};
  for (const [n, { line }] of byRef) {
    const tee = line[0], end = line[line.length - 1], prev = line[line.length - 2];
    let dir = [end[0] - prev[0], end[1] - prev[1]]; const dl = Math.hypot(...dir) || 1; dir = [dir[0] / dl, dir[1] / dl];
    // the green this hole ends on: the green shape at (or nearest) the end of the line
    const g = greens.map((x) => ({ ...x, d: dist(x.c, end) })).sort((a, b) => a.d - b.d)[0];
    let f, m, b;
    if (g && g.d < 45) {
      m = g.c;
      const proj = g.xy.map((p) => (p[0] - m[0]) * dir[0] + (p[1] - m[1]) * dir[1]);
      const lo = Math.min(...proj), hi = Math.max(...proj);
      f = [m[0] + dir[0] * lo, m[1] + dir[1] * lo]; b = [m[0] + dir[0] * hi, m[1] + dir[1] * hi];
    } else { m = end; f = [end[0] - dir[0] * 12, end[1] - dir[1] * 12]; b = [end[0] + dir[0] * 12, end[1] + dir[1] * 12]; }
    const path = [...line.slice(0, -1), m];
    // hazards in play: shapes within 35 m of the line from tee to green, not behind the tee or past the green
    const hz = [];
    for (const z of hazards) {
      if (toPath(centroid(z.xy), path) > 35 && Math.min(...z.xy.map((p) => toPath(p, path))) > 12) continue;
      // along the hole: how far from the tee each edge is (straight-line from the tee, like the yardages)
      const along = z.xy.map((p) => ({ p, a: dist(p, tee) }));
      const near = along.reduce((x, y) => (y.a < x.a ? y : x)), far = along.reduce((x, y) => (y.a > x.a ? y : x));
      if (near.a < 30 || near.a > dist(tee, b) + 15) continue;
      const c = centroid(z.xy), side = (c[0] - tee[0]) * (m[1] - tee[1]) - (c[1] - tee[1]) * (m[0] - tee[0]);
      const greenside = dist(c, m) < 45;
      const label = z.name || `${greenside ? 'Greenside' : side > 0 ? 'Right' : 'Left'} ${z.k === 'bunker' ? 'bunker' : 'water'}`;
      hz.push({ k: z.k, n: label.slice(0, 40), p: F.back(near.p), c: greenside && z.k === 'bunker' ? null : F.back(far.p), a: near.a });
    }
    hz.sort((x, y) => x.a - y.a);
    out[n] = { tee: F.back(tee), f: F.back(f), m: F.back(m), b: F.back(b), hz: hz.slice(0, 10).map(({ a, ...z }) => ({ id: Math.random().toString(36).slice(2, 7), ...z })) };
  }
  return { holes: out, found: [...byRef.keys()].sort((a, b) => a - b), unnumbered };
}
