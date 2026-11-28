// The sample tournaments for demos, in the "Flagcast Demo" club:
//  · "Sample Member-Guest", marked Demo (Flagcast's logo; "Try a demo" opens it; sample groups walk the course map).
//    40 made-up teams of a member and a guest on three sets of tees (Handicap Index → course handicap per tee), best
//    ball with an Individuals board, scores part way through the round, placeholder sponsors, skins, a TV.
//    Closest to the pin and long drive with golfer entries (one waiting for the pro's check). Cameras on Apple's
//    public HLS test pattern: the par 3s, the long drive hole, the clubhouse, the 18th green and one "Live from the
//    pro" feed, with two saved replays. Its "Try a demo" cart is a foursome that starts with Skins and Wolf on.
//  · "Sample Club Cup": four-ball match play, Reds against Blues for the cup, 8 matches part way round.
//
//   node tools/demo-seed.mjs                      make them, or reset them to a fresh mid-round state (run again any time)
//   node tools/demo-seed.mjs http://127.0.0.1:8787   the same on a local copy of the site
//   --logo <file.png>   give the demo club this logo (white on see-through looks best). The Member-Guest stays marked
//                       Demo ("Try a demo" needs that), so the club's logo shows on the Club Cup and its other tournaments
//
// Needs Flagcast Admin: it uses the sign-in saved by Flagcast Manager on this Mac (never printed or stored here).
// Locally (wrangler dev with no passcode set) no sign-in is needed.
import fs from 'node:fs';
import os from 'node:os';

const args = process.argv.slice(2), li = args.indexOf('--logo'), LOGO = li >= 0 ? args.splice(li, 2)[1] : '';
const BASE = (args[0] || 'https://flagcast.app').replace(/\/$/, '');
const CLUB = 'Flagcast Demo', NAME = 'Sample Member-Guest', CUP = 'Sample Club Cup', COURSE_Q = 'torrey pines', PRO = 'Chris Doyle';
const CAM = 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8';
const local = /127\.0\.0\.1|localhost/.test(BASE);
let token = '';
if (!local) {
  try { token = JSON.parse(fs.readFileSync(`${os.homedir()}/Library/Application Support/Flagcast Manager/manager.json`, 'utf8')).token || ''; } catch {}
  if (!token) { console.error('Sign in to Flagcast Manager on this Mac with a Flagcast Admin account first.'); process.exit(1); }
}
const post = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json', 'user-agent': 'FlagcastDemoSeed/1.0' }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({})); if (!r.ok) throw new Error(`${path}: ${j.error || r.status}`); return j;
};
const admin = (b) => post('/golf/api/club/admin', { token, ...b });

// 1) the demo club and its sample tournament (found again on later runs)
let { clubs } = await admin({});
let club = clubs.find((c) => c.name === CLUB);
if (!club) { await admin({ op: 'create', name: CLUB, credits: 0 }); ({ clubs } = await admin({})); club = clubs.find((c) => c.name === CLUB); }
if (club.status !== 'active') await admin({ op: 'on', club: club.id });
const findOrMake = async (name) => {
  const e = club.events.find((x) => x.name === name && !x.archived);
  if (e) return e;
  const j = await admin({ op: 'event', club: club.id, name }); return { id: j.made.id, key: j.made.key };
};
const ev = await findOrMake(NAME);
const { id, key } = ev;
const deskOf = (eid, ekey) => (op, b = {}) => post(`/golf/api/${eid}/desk`, { key: ekey, op, ...b });
const desk = deskOf(id, key);

// 2) the course: the first library match, a middle tee
const hit = (await (await fetch(`${BASE}/golf/api/courses?q=${encodeURIComponent(COURSE_Q)}`)).json()).courses?.[0];
let holes = Array.from({ length: 18 }, (_, i) => ({ n: i + 1, par: [4, 4, 3, 4, 4, 5, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5][i], yds: 380, hcp: i + 1 })), courseName = 'Sample Course', at = null, tees = [];
if (hit) {
  const card = await (await fetch(`${BASE}/golf/api/courses/${hit.id}`)).json();
  const men = (card.tees || []).filter((t) => !t.women && t.holes?.length === 18);
  const tee = [...men].sort((a, b) => Math.abs(a.yards - 6700) - Math.abs(b.yards - 6700))[0];
  if (tee) {
    holes = tee.holes.map((h, i) => ({ n: i + 1, par: h.par, yds: h.yds, hcp: h.hcp || i + 1 }));
    // three sets of tees (back, the middle one the card shows, forward), so players can play from different tees
    const byLen = [...men].sort((a, b) => b.yards - a.yards), back = byLen[0], fwd = byLen[byLen.length - 1];
    tees = [tee, back, fwd].filter((t, i, a) => t && a.indexOf(t) === i).map((t) => ({ name: t.name, slope: t.slope, rating: t.rating }));
  }
  courseName = card.name || hit.name; at = card.at || hit.at || null;
}
const par3 = holes.filter((h) => h.par === 3).map((h) => h.n), par5 = holes.filter((h) => h.par === 5).map((h) => h.n);
if (!tees.length) tees = [{ name: 'Blue', slope: 128, rating: 71.4 }, { name: 'Black', slope: 136, rating: 73.6 }, { name: 'White', slope: 121, rating: 69.2 }];
tees = tees.map((t, i) => ({ id: ['mid', 'back', 'fwd'][i], ...t }));

// 3) the setup: made-up teams, placeholder sponsors, contests, a TV
// 40 made-up teams of two (no real people): a shotgun start, two or three teams on every hole, four flights
const FIRST = ['Sam', 'Dana', 'Lee', 'Chris', 'Pat', 'Jordan', 'Alex', 'Robin', 'Taylor', 'Morgan', 'Casey', 'Jamie', 'Drew', 'Riley', 'Avery', 'Quinn', 'Jesse', 'Reese', 'Cameron', 'Skyler',
  'Parker', 'Rowan', 'Emerson', 'Hayden', 'Kendall', 'Logan', 'Peyton', 'Sage', 'Blake', 'Shawn'];
const LAST = ['Ortiz', 'Price', 'Novak', 'Hale', 'Moreno', 'Blake', 'Kim', 'Shaw', 'Reed', 'Ash', 'Lin', 'Cole', 'Park', 'Stone', 'Hunt', 'Diaz', 'Webb', 'Fischer', 'Lowe', 'Barrett',
  'Quill', 'Marsh', 'Doyle', 'Keane', 'Vance', 'Holt', 'Pryor', 'Wilde', 'Sutton', 'Grove', 'Tate', 'Rowe', 'Nash', 'Ellis', 'Frost', 'Lyle', 'Marsden', 'Oakes', 'Penn', 'Rudd'];
const TEAMS = ['The Birdie Hunters', 'Fairway Kings', 'Grip It & Sip It', 'Sand Savers', 'Back Nine Bandits', 'Eagle Eyes', 'The Shankopotamus', 'Pin Seekers',
  'Tee Time Titans', 'The Mulligans', 'Divot Diggers', 'Bogey Brothers', 'Short Game Sharks', 'The Wedge Issue', 'Putt Pirates', 'Fore Play',
  'The Dogleggers', 'Chip Shots', 'Hole Lotta Fun', 'The Sandbaggers', 'Green Machine', 'Slice Squad', 'Par-Tee Animals', 'The Hookers & Slicers',
  'Ace Ventura', 'Course Correction', 'Club Sandwich', 'The Fringe', 'Golden Tees', 'Water Hazards', 'Stick Figures', 'The Albatross',
  'Lip Outs', 'Range Rovers', 'Bunker Busters', 'The Flagsticks', 'Rough Riders', 'Up & Downers', 'Grass Kickers', 'Two Putt Wonders'];
// the last team is the "Try a demo" cart: a foursome, so Wolf and the other side games have players for them
const teamsIn = TEAMS.map((n, i) => [n, (i === TEAMS.length - 1 ? [0, 1, 2, 3] : [0, 1]).map((j) => `${FIRST[(i * 2 + j) % FIRST.length]} ${LAST[(i * 7 + j * 3) % LAST.length]}`)]);
// each player: a Handicap Index and their tees (low indexes on the back tees, high ones forward, most in the middle);
// the server works out the course handicap from the tees' slope and rating. The second of each pair is the guest.
const teeFor = (x) => (x < 6 && tees[1] ? tees[1].id : x > 16 && tees[2] ? tees[2].id : tees[0].id);
const playerOf = (old) => (p, i, j) => { const x = ((i * 3 + j * 5) % 22) + ((i + j) % 10) / 10; return { id: old.get(p), name: p, index: x, tee: teeFor(x), guest: j % 2 === 1 }; };
const idsOf = (got) => [new Map((got.teams || []).map((t) => [t.name, t.id])), new Map((got.teams || []).flatMap((t) => (t.players || []).map((p) => [p.name, p.id])))];
const got = await desk('get'); delete got.stats;
const [keepIds, keepPlayers] = idsOf(got);
const teams = teamsIn.map(([n, ps], i) => ({ id: keepIds.get(n), name: n, flight: 'ABCD'[Math.floor(i / 10)], start: (i % 18) + 1, cart: String(i + 1),
  players: ps.map((p, j) => playerOf(keepPlayers)(p, i, j)) }));
const sponsors = [
  { name: 'Your Title Sponsor', line: 'Title sponsor placeholder', spot: 'title' },
  { name: 'Leaderboard Sponsor', line: 'Your logo on every leaderboard', spot: 'leaderboard' },
  { name: 'Par 3 Camera Sponsor', line: 'Cameras brought to you by…', spot: 'cam', holes: par3 },
  { name: 'Hole Sponsor', line: 'Hole sponsor placeholder', spot: 'hole', holes: [1, 10] },
];
const names = teamsIn.flatMap(([, ps]) => ps);
// closest to the pin on two par 3s and long drive on a par 5: golfers enter their own (the pro checks the top 3),
// for points. The results go in after the Save (a Save never changes contest results).
const sameContest = (c) => (got.contests || []).find((x) => x.kind === c.kind && x.hole === c.hole);
const contests = [
  ...par3.slice(0, 2).map((h, i) => ({ kind: 'ctp', hole: h, label: `Closest to the pin · hole ${h}`, sponsor: 'Par 3 Camera Sponsor', self: true, check: 'top', prize: 25,
    results: [{ name: names[i * 3], dist: 5.5 + i * 3.25 }, { name: names[i * 3 + 5], dist: 11 + i * 2.5 }, { name: names[i * 3 + 20], dist: 18.75 }] })),
  ...par5.slice(0, 1).map((h) => ({ kind: 'ld', hole: h, label: `Longest drive · hole ${h}`, sponsor: '', self: true, check: 'top', prize: 25,
    results: [{ name: names[9], dist: 287 }, { name: names[2], dist: 271 }, { name: names[30], dist: 264 }] })),
].map(({ results, ...c }) => ({ ...c, id: sameContest(c)?.id, results }));
const BAR = [{ k: 'lb', secs: 14 }, { k: 'indiv', secs: 12 }, { k: 'skins', secs: 10 }, { k: 'contests', secs: 10 }, { k: 'p3', secs: 12 }, { k: 'sponsors', secs: 8 }];
const d0 = new Date(), today = `${d0.getFullYear()}-${String(d0.getMonth() + 1).padStart(2, '0')}-${String(d0.getDate()).padStart(2, '0')}`; // the local day, not London's
await desk('save', { setup: { ...got, name: NAME, club: CLUB, date: today, course: { name: courseName, holes, tees, at },
  format: { type: 'bestball', count: 1, allowance: 85, show: 'net', indiv: true }, sideGames: true, flights: ['A', 'B', 'C', 'D'], teams, sponsors,
  contests: contests.map(({ results, ...c }) => c),
  screens: { ...(got.screens || {}), title: NAME, ticker: 'Welcome to the Sample Member-Guest · a Flagcast demo tournament', seconds: 12, rows: 10, skins: true },
  displays: (got.displays?.length ? got.displays : [{ name: 'Clubhouse bar', where: 'Over the bar', group: 'Clubhouse' }])
    .map((d) => (d.name === 'Clubhouse bar' ? { ...d, playlist: BAR } : d)) } });

// 4) fresh scores: each team part way round (9 to 14 holes from its starting hole), the same every run
const now = Date.now();
async function scoreAll(eid, ekey, d, seed, played = (i) => 9 + ((i * 5) % 6)) {
  const e = await d('get');
  for (const t of e.teams) await d('clear', { team: t.id });
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  for (const [i, t] of e.teams.entries()) {
    const n = played(i, t), list = [];
    for (let k = 0; k < n; k++) {
      const h = ((t.start - 1 + k) % 18) + 1, par = holes[h - 1].par;
      for (const p of t.players) { const r = rnd(); list.push({ p: p.id, h, v: par + (r < 0.16 ? -1 : r < 0.62 ? 0 : r < 0.9 ? 1 : 2), at: now - (n - k) * 11 * 60000 }); }
    }
    if (list.length) await post(`/golf/api/${eid}/score`, { team: t.id, desk: ekey, list });
  }
  return e;
}
// the "Try a demo" cart starts on its first hole with nothing in (it clears itself 3 hours after its last score anyway)
const ev2 = await scoreAll(id, key, desk, 11, (i, t) => (i === TEAMS.length - 1 ? 0 : 9 + ((i * 5) % 6)));

// contest results: the checked ones (as a marshal would enter them), then one golfer's long drive from the scorecard
// that beats them all, so it waits in the pro's "To check" list
for (const c of ev2.contests || []) {
  const want = contests.find((x) => x.kind === c.kind && x.hole === c.hole); if (!want) continue;
  await desk('contest', { id: c.id, entries: want.results });
  if (c.kind === 'ld') {
    const t = ev2.teams[11], p = t?.players?.[0];
    if (t?.code && p) await post(`/golf/api/${id}/enter`, { code: t.code, team: t.id, contest: c.id, player: p.id, dist: 296 });
  }
}

// 5) Demo on (Flagcast's logo, "Try a demo", sample groups on the map), then the cameras on Apple's test pattern:
// the par 3s, the long drive hole, the clubhouse (0), the 18th green, and one hole shown as the pro's Go live feed.
// Two saved replays.
if (LOGO) await admin({ op: 'brand', club: club.id, logo: 'data:image/png;base64,' + fs.readFileSync(LOGO).toString('base64') });
await admin({ op: 'demo', id, on: true });
const proHole = holes.find((h) => h.n >= 10 && h.par === 4 && !par5.slice(0, 1).includes(h.n))?.n || 10;
const camHoles = [...new Set([...par3, ...par5.slice(0, 1), 0, 18, proHole])];
await admin({ op: 'cams', id, cams: Object.fromEntries(camHoles.map((h) => [h, CAM])), live: { [proHole]: PRO } });
await desk('camshow', { off: [], clips: true });
for (const r of ev2.replays || []) await desk('replay', { remove: r.id });
await desk('replay', { hole: par3[0], label: `${names[0]} to 4 feet`, url: CAM });
await desk('replay', { hole: par3[1] || par3[0], label: `${names[13]} hits the pin`, url: CAM });

console.log(`${NAME} (${id.toUpperCase()}) in ${CLUB} · ${courseName} · ${ev2.teams.length} teams · par 3s ${par3.join(', ')} · pro live on ${proHole}`);
console.log(`Live leaderboard: ${BASE}/g/${id}`);
console.log(`TV board:         ${BASE}/g/${id}/board`);

// 6) "Sample Club Cup": four-ball match play, Reds against Blues. 16 teams, paired off on the same starting hole.
const cupEv = await findOrMake(CUP), cupDesk = deskOf(cupEv.id, cupEv.key);
const cupGot = await cupDesk('get'); delete cupGot.stats;
const [cupIds, cupPlayers] = idsOf(cupGot);
const cupTeams = teamsIn.slice(0, 16).map(([n, ps], i) => ({ id: cupIds.get(n), name: n, side: i < 8 ? 'A' : 'B', start: ((i % 8) * 2) + 1, cart: String(i + 1),
  players: ps.map((p, j) => playerOf(cupPlayers)(p, i, j)) }));
await cupDesk('save', { setup: { ...cupGot, name: CUP, club: CLUB, date: today, course: { name: courseName, holes, tees, at },
  format: { type: 'match', match: 'fourball', allowance: 90, show: 'net', cup: { on: true, a: 'Reds', b: 'Blues' } }, flights: [], teams: cupTeams,
  matches: [], sponsors: sponsors.slice(0, 2), contests: [],
  screens: { ...(cupGot.screens || {}), title: CUP, ticker: 'The Sample Club Cup · Reds v Blues · a Flagcast demo', seconds: 12, rows: 10, skins: false } } });
const cupNow = await cupDesk('get'); delete cupNow.stats;
const byName = new Map(cupNow.teams.map((t) => [t.name, t.id]));
const matches = cupTeams.slice(0, 8).map((t, i) => ({ a: byName.get(t.name), b: byName.get(cupTeams[i + 8].name) }));
await cupDesk('save', { setup: { ...cupNow, matches } });
// matches part way round: some finished, most 8 to 14 holes in (both teams of a match the same)
await scoreAll(cupEv.id, cupEv.key, cupDesk, 29, (i) => [18, 16, 14, 12, 11, 10, 9, 8][i % 8]);
console.log(`${CUP} (${cupEv.id.toUpperCase()}) · 8 four-ball matches · ${BASE}/g/${cupEv.id}`);
console.log('Desk links: in Flagcast Manager → Admin → Tournaments (they’re private: not printed here)');
