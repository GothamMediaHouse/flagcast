// "Fly the hole" on the web: the same flight as the players' app and the Mac Manager (a straight port of
// apps/flagcast-ios/Flagcast/Model/FlyPath.swift, so all three fly the same line). Points are [lat, lng].
// The camera glides on one continuous path: on the tee box nearly level with the golfer, an even push down the middle
// of the hole, round its doglegs (the course map's line), easing to a stop short of the green, looking at it.

export const C = {
  startPitch: 73, startLook: 85, cruisePitch: 72, cruiseLook: 150, endPitch: 68, endLook: 90,
  nearest: 88, behindTee: 10, speed: 24, holdSecs: 1, arriveSecs: 1.6,
};
const YD = 1.0936133, R = 6371008.8, T = Math.PI / 180;

export function yds(a, b) {
  if (!a || !b) return null;
  const dla = (b[0] - a[0]) * T, dlo = (b[1] - a[1]) * T;
  const h = Math.sin(dla / 2) ** 2 + Math.cos(a[0] * T) * Math.cos(b[0] * T) * Math.sin(dlo / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(h))) * YD;
}
export function bearing(a, b) {
  const la1 = a[0] * T, la2 = b[0] * T, dlo = (b[1] - a[1]) * T;
  return ((Math.atan2(Math.sin(dlo) * Math.cos(la2), Math.cos(la1) * Math.sin(la2) - Math.sin(la1) * Math.cos(la2) * Math.cos(dlo)) / T) + 360) % 360;
}
export function offset(a, yards, deg) {
  const d = yards / YD / R, br = deg * T, la1 = a[0] * T, lo1 = a[1] * T;
  const la2 = Math.asin(Math.sin(la1) * Math.cos(d) + Math.cos(la1) * Math.sin(d) * Math.cos(br));
  const lo2 = lo1 + Math.atan2(Math.sin(br) * Math.sin(d) * Math.cos(la1), Math.cos(d) - Math.sin(la1) * Math.sin(la2));
  return [la2 / T, lo2 / T];
}
export const green = (h) => h && (h.m || h.f || null);

/** tee → the bends (in order down the hole, only ones between the tee and the green) → green */
export function holePath(h, tee, g) {
  let bends = (h.line || []).slice();
  if (!bends.length) bends = (h.hz || []).filter((z) => z.k === 'layup').map((z) => z.p);
  const total = yds(tee, g) || 0;
  bends = bends.filter((b) => { const a = yds(tee, b) || 0, c = yds(b, g) || 0; return a > 25 && c > 25 && a < total + 60; })
    .sort((x, y) => (yds(tee, x) || 0) - (yds(tee, y) || 0));
  return [tee, ...bends, g];
}
export const length = (pts) => pts.slice(1).reduce((s, b, i) => s + (yds(pts[i], b) || 0), 0);
/** the point s yards along a path from its start (the end if past it) */
export function point(pts, s) {
  let left = Math.max(0, s);
  for (let i = 1; i < pts.length; i++) {
    const a = pts[i - 1], b = pts[i], len = yds(a, b) || 0;
    if (left <= len && len > 0) return offset(a, left, bearing(a, b));
    left -= len;
  }
  return pts[pts.length - 1];
}
/** the point s yards along a path, carried on past either end in a straight line */
function along(pts, s, total) {
  if (s < 0 && pts.length > 1) return offset(pts[0], -s, bearing(pts[1], pts[0]));
  if (s > total && pts.length > 1) return offset(pts[pts.length - 1], s - total, bearing(pts[pts.length - 2], pts[pts.length - 1]));
  return point(pts, s);
}
/** corners rounded off (Chaikin, three passes), ends kept */
export function rounded(pts) {
  let p = pts;
  for (let k = 0; k < 3 && p.length > 2; k++) {
    const q = [p[0]];
    for (let i = 1; i < p.length; i++) {
      const a = p[i - 1], b = p[i];
      q.push([a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25], [a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75]);
    }
    q.push(p[p.length - 1]); p = q;
  }
  return p;
}
const smooth = (u) => { const t = Math.max(0, Math.min(1, u)); return t * t * (3 - 2 * t); };
const lerp = (a, b, t) => a + (b - a) * t;
/** 0…1 along the run, u of the way through the glide: eases in over 18%, even, eases out over the last 30% */
export function progress(u) {
  const A = 0.18, D = 0.30, v = 1 / (1 - (A + D) / 2), t = Math.max(0, Math.min(1, u));
  if (t < A) return v * (t / 2 - A / (2 * Math.PI) * Math.sin(Math.PI * t / A));
  if (t > 1 - D) { const r = 1 - t; return 1 - v * (r / 2 - D / (2 * Math.PI) * Math.sin(Math.PI * r / D)); }
  return v * (A / 2 + (t - A));
}

/** The flight for one hole (h from the course map), or null when it has no tee or green. */
export function makePath(h) {
  const tee = h?.tee, g = green(h);
  if (!tee || !g) return null;
  const points = holePath(h, tee, g), path = rounded(points);
  const totalYds = Math.max(40, length(path));
  const cruiseLook = Math.max(C.endLook, Math.min(C.cruiseLook, totalYds * 0.5)), endLook = Math.min(C.endLook, totalYds * 0.45);
  const travelYds = Math.max(20, totalYds - endLook + C.behindTee);
  const travelSecs = Math.min(22, Math.max(7, travelYds / C.speed + 2.4));
  const fp = { points, path, totalYds, cruiseLook, endLook, travelYds, travelSecs, totalSecs: C.holdSecs + travelSecs + C.arriveSecs };
  /** the camera s yards along its run: its eye on the ground, what it looks at, its tilt */
  fp.shot = (s) => {
    const se = s - C.behindTee;
    const climb = smooth(s / Math.min(140, Math.max(40, travelYds * 0.35)));
    const ahead = lerp(C.startLook + C.behindTee, cruiseLook, climb);
    const sl = Math.min(totalYds, se + ahead);
    const left = totalYds - se, near = smooth(1 - (left - endLook) / Math.max(40, cruiseLook - endLook));
    let pitch = lerp(C.startPitch, C.cruisePitch, climb); pitch = lerp(pitch, C.endPitch, near);
    return { eye: along(path, se, totalYds), look: point(path, sl), pitch };
  };
  /** t seconds in: the point it looks at, which way it faces, its distance (m, along the line of sight), its tilt */
  fp.camera = (t) => {
    const u = (t - C.holdSecs) / travelSecs, c = fp.shot(progress(u) * travelYds);
    const ground = Math.max(20, yds(c.eye, c.look) || 20) / YD;
    return { at: c.look, heading: bearing(c.eye, c.look), metres: Math.max(C.nearest, ground / Math.sin(c.pitch * T)), pitch: c.pitch };
  };
  fp.height = (t) => { const c = fp.camera(t); return c.metres * Math.cos(c.pitch * T); };
  return fp;
}
