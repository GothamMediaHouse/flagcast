// Sample groups for Demo tournaments (Admin's Demo switch, ev.demo): nobody is really playing a demo, so the
// golfers' Everyone map, the desk's "Where the groups are" and the Managers would show an empty course. These groups
// walk the club's course map instead: tee, drive, approach, green, putt out, next tee. Where they are comes from the
// clock alone (no storage, nothing to clean up), so every phone and the desk see the same groups in the same spots.
// Never used for a real tournament: the caller only asks when ev.demo is on.

const HOLE_MINS = 13; // about a 4 hour round
// minutes on each part of a hole: [from, to, minutes], from/to as fractions of the way from the tee to the green
const LEGS = [[0, 0, 2.5], [0, 0.55, 2], [0.55, 0.55, 1.5], [0.55, 0.92, 1.5], [0.92, 0.92, 1], [0.92, 1, 1], [1, 1, 3.5]];
const SAMPLE = ['Miller / Shaw', 'Okafor / Lind', 'Reyes / Bauer', 'Chen / Walsh', 'Novak / Price', 'Duarte / Kim',
  'Hughes / Patel', 'Sato / Brennan', 'Moreau / Ellis', 'Grant / Iyer'];

const mPer = (lat) => [111320, 111320 * Math.cos(lat * Math.PI / 180)];
const dist = (a, b) => { const [y, x] = mPer(a[0]); return Math.hypot((b[0] - a[0]) * y, (b[1] - a[1]) * x); };
// a spot `f` of the way along the path (tee, dogleg points, middle of the green), nudged sideways `side` metres
function along(path, f, side) {
  const lens = path.slice(1).map((p, i) => dist(path[i], p)), total = lens.reduce((a, b) => a + b, 0) || 1;
  let d = Math.max(0, Math.min(1, f)) * total, i = 0;
  while (i < lens.length - 1 && d > lens[i]) d -= lens[i++];
  const a = path[i], b = path[i + 1], k = lens[i] ? d / lens[i] : 0;
  const at = [a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k];
  const [y, x] = mPer(at[0]), dy = (b[0] - a[0]) * y, dx = (b[1] - a[1]) * x, n = Math.hypot(dx, dy) || 1;
  return [at[0] + (dx / n) * side / y, at[1] - (dy / n) * side / x]; // left/right of the line, not along it
}
const round6 = (v) => Math.round(v * 1e6) / 1e6;

// the holes a group can walk: a tee and a middle of the green on the course map, in order
function mapped(ev) {
  const out = [];
  for (let n = 1; n <= 18; n++) {
    const h = ev.map?.holes?.[n]; if (!h || !h.tee || !(h.m || h.f || h.b)) continue;
    out.push({ n, path: [h.tee, ...(h.line || []), h.m || h.f || h.b] });
  }
  return out;
}

// [{ team, name, start, hole, at, acc, t, sample: true }]. Uses the demo's own teams (so the names match the
// leaderboard), skipping `skip` (teams with a real phone on the map), and fills up to 8 groups with sample names.
export function demoGroups(ev, now = Date.now(), skip = new Set()) {
  const holes = mapped(ev); if (holes.length < 2) return [];
  const name = (t) => t.name || t.players.map((p) => String(p.name || '').split(' ').slice(-1)[0]).join(' / ');
  const own = (ev.teams || []).filter((t) => !skip.has(t.id)).map((t) => ({ team: t.id, name: name(t), start: t.start || 0 }));
  const count = Math.min(holes.length, Math.max(own.length, 8), 18);
  const list = own.slice(0, count);
  for (let i = 0; list.length < count; i++) list.push({ team: `sample${i + 1}`, name: SAMPLE[i % SAMPLE.length], start: 0 });
  const legMins = LEGS.reduce((a, l) => a + l[2], 0), clock = now / 60000;
  return list.map((g, i) => {
    // groups spread round the course, a little off the hour so they don't all tee off together
    const pos = clock / HOLE_MINS + (i * holes.length) / count + i * 0.13;
    const k = ((Math.floor(pos) % holes.length) + holes.length) % holes.length, h = holes[k];
    let m = (pos - Math.floor(pos)) * legMins, f = 1;
    for (const [a, b, mins] of LEGS) { if (m <= mins) { f = a + (b - a) * (m / mins); break; } m -= mins; }
    const side = f > 0 && f < 0.92 ? ((i * 7) % 5 - 2) * 6 : ((i * 3) % 3 - 1) * 3; // fairway spread; close on the green
    const at = along(h.path, f, side);
    return { ...g, hole: h.n, at: [round6(at[0]), round6(at[1])], acc: 5, t: now - ((i * 17) % 40) * 1000, sample: true };
  });
}
