// Runs the website's scoring math (public/golf/core.js) on sample tournaments and writes what it gets to
// FlagcastTests/core-fixture.json. The app's unit tests run the Swift port on the same input and must match.
//   node apps/flagcast-ios/tools/make-core-fixture.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import * as core from '../../../public/golf/core.js';

const here = dirname(fileURLToPath(import.meta.url));

// a small seeded random, so the fixture is the same every time
let seed = 20261119;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];

const NAMES = ['Sam Ortiz', 'Sam Lee', 'Ana Park', 'Ben Cole', 'Cara Diaz', 'Dev Shah', 'Eli Ford', 'Fay Grant', 'Gus Hale', 'Ivy Moss',
  'Jon Reed', 'Kim Lowe', 'Lou Nash', 'Max Pike', 'Nia Rowe', 'Oli Sims', 'Pat Todd', 'Quin Vale', 'Rae West', 'Ty Young', 'Uma Zane', 'Vic Bay'];
const HCPS = [0, 4, 8, 12.4, 18, 22, 27, 36, -2, -3.5, 15, 9, 30, 1];

function makeEvent(type, opts = {}) {
  const holes = core.defaultHoles();
  const teams = [];
  let ni = 0;
  for (let t = 0; t < (opts.teams || 6); t++) {
    const players = [];
    for (let k = 0; k < (opts.size || 4); k++) players.push({ id: `p${t}${k}`, name: NAMES[ni++ % NAMES.length], hcp: pick(HCPS), guest: false });
    teams.push({ id: `t${t}x`, name: t === 1 ? '' : `Team ${t + 1}`, flight: t % 2 ? 'B' : 'A', start: opts.shotgun ? (t * 3) % 18 + 1 : 1, hcp: pick([0, 6, 9.6, 14, -1]), cart: '', players });
  }
  return {
    id: 'sample01', name: `Sample ${type}`, club: 'Club', date: '', sideGames: true, flights: ['A', 'B'],
    course: { name: 'Course', holes },
    format: { type, count: opts.count || 1, allowance: opts.allowance ?? 100, show: opts.show || 'net', nine: opts.nine || '' },
    teams, screens: { title: '', ticker: '', seconds: 12, skins: true, rows: 10 }, cams: {}, sponsors: [], schedule: [], displays: [],
    fund: { on: false, label: '', goal: 0, raised: 0, give: '' },
    contests: [
      { id: 'c1', kind: 'ctp', hole: 4, label: '', sponsor: '', entries: [{ name: 'Ana Park', dist: 6.5 }, { name: 'Ben Cole', dist: 3.04 }, { name: 'Cara Diaz', dist: 6.5 }, { name: 'Zero', dist: 0 }] },
      { id: 'c2', kind: 'ld', hole: 2, label: 'Long drive', sponsor: 'X', entries: [{ name: 'Dev Shah', dist: 281.5 }, { name: 'Eli Ford', dist: 300.49 }, { name: 'Fay Grant', dist: 281.5 }] },
    ],
    locked: false, aces: [], news: [], nudges: [], live: { force: {}, take: null }, online: {},
  };
}

// scores: some teams finished, some part way, some not started; pickups, aces and ties along the way
function makeScores(ev, opts = {}) {
  const sc = {};
  ev.teams.forEach((t, ti) => {
    // the holes this team plays, in order from its start (a 9-hole round starts outside its 9 at the first hole)
    const ph = core.playHoles(ev), k0 = Math.max(0, ph.indexOf(t.start || 1)), ord = [...ph.slice(k0), ...ph.slice(0, k0)];
    const upto = Math.min(ord.length, opts.allDone ? 18 : [18, 18, 11, 7, 0, 18][ti % 6]);
    if (!upto) return;
    const who = ev.format.type === 'scramble' ? ['T'] : t.players.map((p) => p.id);
    const s = {};
    for (const id of who) {
      const arr = Array(18).fill(null);
      for (let k = 0; k < upto; k++) {
        const i = ord[k] - 1, par = ev.course.holes[i].par;
        const r = rnd();
        arr[i] = r < 0.04 ? 0 : r < 0.08 ? (par === 3 ? 1 : par - 2) : r < 0.3 ? par - 1 : r < 0.6 ? par : r < 0.85 ? par + 1 : par + 2 + Math.floor(rnd() * 2);
      }
      // a hole one player forgot (holes not done for the team)
      if (who.length > 1 && upto > 3 && rnd() < 0.3) arr[ord[2] - 1] = null;
      s[id] = arr;
    }
    sc[t.id] = s;
  });
  // the last team copies the first one's handicaps and scores, to exercise ties and the card-off
  if (opts.twins && sc[ev.teams[0].id]) {
    const a = ev.teams[0], b = ev.teams[ev.teams.length - 1];
    sc[b.id] = Object.fromEntries((ev.format.type === 'scramble' ? ['T'] : b.players.map((p) => p.id)).map((pid, k) => [pid, (sc[a.id][ev.format.type === 'scramble' ? 'T' : a.players[k].id] || []).slice()]));
    b.players = a.players.map((p, k) => ({ ...b.players[k], hcp: p.hcp }));
    b.hcp = a.hcp;
  }
  return sc;
}

const lineOut = (l) => ({ key: l.key, teamId: l.teamId, name: l.name, sub: l.sub, flight: l.flight, start: l.start, played: l.played, total: l.total,
  toPar: l.toPar, nr: l.nr, score: l.score, pos: l.pos, thru: l.thru, card: l.card });

const SIDE_CFGS = [
  { skins: { on: true, amt: 5, net: true, carry: true }, nassau: { on: true, amt: 10, net: true, sides: {} }, birdies: { on: true, amt: 2, net: false } },
  { skins: { on: true, amt: 3, net: false, carry: false }, nassau: { on: true, amt: 7, net: false, sides: {} }, birdies: { on: true, amt: 1.5, net: true } },
  { skins: { on: false, amt: 5, net: true }, nassau: { on: true, amt: 10, net: true, sides: { 't0x:p00': 'B', 't0x:p01': 'B', 't0x:p02': 'A', 't0x:p03': 'A' } }, birdies: { on: false, amt: 2 } },
  // the newer games: Stableford, Vegas, Wolf, closest to the pin and long drive (picks name players that may not be in the cart)
  { skins: { on: true, amt: 1, net: true, carry: true }, stableford: { on: true, net: true }, vegas: { on: true, amt: 1, net: true },
    wolf: { on: true, amt: 2, net: false, picks: { 1: 't0x:p01', 2: 'lone', 3: 't1x:p10', 5: 'lone', 6: 't2x:p21', 10: 't3x:p30', 11: 'lone' } },
    closest: { on: true, amt: 2, picks: { 4: 't0x:p00', 7: 't1x:p11', 11: 't2x:p20', 16: 't3x:p31' } }, longDrive: { on: true, amt: 3, picks: { 2: 't1x:p10', 8: 't0x:p01', 13: 't2x:p21' } } },
  { stableford: { on: true, net: false }, vegas: { on: true, amt: 0.5, net: false, sides: { 't2x:p20': 'B', 't3x:p30': 'A' } },
    wolf: { on: true, amt: 1, net: true, picks: { 1: 'lone', 2: 't0x:p00', 4: 't2x:p20', 9: 'lone', 18: 't3x:p31' } } },
];

const cases = [];
const variants = [
  ['bestball', { count: 2, allowance: 85, shotgun: true, twins: true }],
  ['bestball', { count: 1, allowance: 100, show: 'gross' }],
  ['stroke', { teams: 4, size: 2, allowance: 95, twins: true }],
  ['stableford', { count: 2, allowance: 90, shotgun: true }],
  ['scramble', { allowance: 25, twins: true }],
  ['bestball', { count: 3, allowance: 80, allDone: true, twins: true }],
  ['bestball', { count: 2, allowance: 90, nine: 'back', shotgun: true, twins: true }],
  ['stroke', { teams: 4, size: 2, allowance: 100, nine: 'front', twins: true }],
  ['stableford', { count: 1, allowance: 100, nine: 'back', allDone: true }],
];
for (const [type, opts] of variants) {
  const ev = makeEvent(type, opts);
  const scores = makeScores(ev, opts);
  const out = {
    teamCards: Object.fromEntries(ev.teams.map((t) => [t.id, core.teamCard(ev, t, scores[t.id])])),
    leaderboard: core.leaderboard(ev, scores).map(lineOut),
    leaderboardA: core.leaderboard(ev, scores, { flight: 'A' }).map(lineOut),
    leaderboardGross: core.leaderboard(ev, scores, { mode: 'gross' }).map(lineOut),
    holeStats: ev.course.holes.map((h) => core.holeStats(ev, scores, h.n)),
    skins: core.skins(ev, scores),
    skinsNoCarry: core.skins(ev, scores, false),
    contests: ev.contests.map((c) => ({ leader: core.contestLeader(c), dist: core.contestLeader(c).map((e) => core.fmtDist(c, e.dist)) })),
    sideGames: type === 'scramble' ? [] : [[ev.teams[0].id], [ev.teams[0].id, ev.teams[1].id], [ev.teams[2].id, ev.teams[3].id]].flatMap((ids) =>
      SIDE_CFGS.map((cfg) => ({ teamIds: ids, cfg, out: core.sideGames(ev, scores, ids, cfg) }))),
  };
  cases.push({ event: ev, scores, out });
}

const strokes = [];
for (let h = -6; h <= 40; h++) for (let si = 1; si <= 18; si++) strokes.push([h, si, core.strokesOn(h, si)]);
const playing = [[12.4, 85], [-2.5, 100], [-3.5, 90], [36, 75], [18, 100], [7.5, 100], [0, 50], [-0.5, 100], [10.5, 100]].map(([h, a]) => [h, a, core.playing(h, a)]);
const fmtPar = [-12, -1, 0, 1, 7].flatMap((n) => [[n, false, core.fmtPar(n, false)], [n, true, core.fmtPar(n, true)]]);
const marks = [];
for (let v = 0; v <= 9; v++) for (const par of [3, 4, 5]) marks.push([v, par, core.mark(v, par)]);
const dists = [0, 0.04, 3.04, 6.5, 12.99, 281.5, 300.49].flatMap((d) => [['ctp', d, core.fmtDist({ kind: 'ctp' }, d)], ['ld', d, core.fmtDist({ kind: 'ld' }, d)]]);

writeFileSync(join(here, '../FlagcastTests/core-fixture.json'), JSON.stringify({ cases, strokes, playing, fmtPar, marks, dists }));
console.log(`Wrote ${cases.length} sample tournaments to FlagcastTests/core-fixture.json`);
