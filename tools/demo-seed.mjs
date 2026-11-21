// The sample tournament for demos: "Sample Member-Guest" in the "Flagcast Demo" club, marked Demo (so it shows the
// Flagcast logo). 40 made-up teams, sponsors as placeholders, scores part way through the round, contests, skins, a TV,
// and par 3 cameras on Apple's public HLS test pattern with two saved replays.
//
//   node tools/demo-seed.mjs                      make it, or reset it to a fresh mid-round state (run again any time)
//   node tools/demo-seed.mjs http://127.0.0.1:8787   the same on a local copy of the site
//   --logo <file.png>   give the demo club this logo (white on see-through looks best): then the tournament isn't
//                       marked Demo, so it shows the club's logo the way a real club's would
//
// Needs Flagcast Admin: it uses the sign-in saved by Flagcast Manager on this Mac (never printed or stored here).
// Locally (wrangler dev with no passcode set) no sign-in is needed.
import fs from 'node:fs';
import os from 'node:os';

const args = process.argv.slice(2), li = args.indexOf('--logo'), LOGO = li >= 0 ? args.splice(li, 2)[1] : '';
const BASE = (args[0] || 'https://flagcast.app').replace(/\/$/, '');
const CLUB = 'Flagcast Demo', NAME = 'Sample Member-Guest', COURSE_Q = 'torrey pines';
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
let ev = club.events.find((e) => e.name === NAME && !e.archived);
if (!ev) { const j = await admin({ op: 'event', club: club.id, name: NAME }); ev = { id: j.made.id, key: j.made.key }; }
const { id, key } = ev;
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });

// 2) the course: the first library match, a middle tee
const hit = (await (await fetch(`${BASE}/golf/api/courses?q=${encodeURIComponent(COURSE_Q)}`)).json()).courses?.[0];
let holes = Array.from({ length: 18 }, (_, i) => ({ n: i + 1, par: [4, 4, 3, 4, 4, 5, 4, 3, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5][i], yds: 380, hcp: i + 1 })), courseName = 'Sample Course', at = null, tees = [];
if (hit) {
  const card = await (await fetch(`${BASE}/golf/api/courses/${hit.id}`)).json();
  const men = (card.tees || []).filter((t) => !t.women && t.holes?.length === 18);
  const tee = men.sort((a, b) => Math.abs(a.yards - 6700) - Math.abs(b.yards - 6700))[0];
  if (tee) {
    holes = tee.holes.map((h, i) => ({ n: i + 1, par: h.par, yds: h.yds, hcp: h.hcp || i + 1 }));
    tees = [{ name: tee.name, slope: tee.slope, rating: tee.rating }];
  }
  courseName = card.name || hit.name; at = card.at || hit.at || null;
}
const par3 = holes.filter((h) => h.par === 3).map((h) => h.n), par5 = holes.filter((h) => h.par === 5).map((h) => h.n);

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
const teamsIn = TEAMS.map((n, i) => [n, [0, 1].map((j) => `${FIRST[(i * 2 + j) % FIRST.length]} ${LAST[(i * 7 + j * 3) % LAST.length]}`)]);
const got = await desk('get'); delete got.stats;
const keepIds = new Map((got.teams || []).map((t) => [t.name, t.id]));
const teams = teamsIn.map(([n, ps], i) => ({ id: keepIds.get(n), name: n, flight: 'ABCD'[Math.floor(i / 10)], start: (i % 18) + 1, cart: String(i + 1),
  players: ps.map((p, j) => ({ name: p, hcp: (i * 3 + j * 5) % 18 })) }));
const sponsors = [
  { name: 'Your Title Sponsor', line: 'Title sponsor placeholder', spot: 'title' },
  { name: 'Leaderboard Sponsor', line: 'Your logo on every leaderboard', spot: 'leaderboard' },
  { name: 'Par 3 Camera Sponsor', line: 'Cameras brought to you by…', spot: 'cam', holes: par3 },
  { name: 'Hole Sponsor', line: 'Hole sponsor placeholder', spot: 'hole', holes: [1, 10] },
];
const names = teamsIn.flatMap(([, ps]) => ps);
const contests = [
  ...par3.slice(0, 2).map((h, i) => ({ kind: 'ctp', hole: h, label: `Closest to the pin · hole ${h}`, sponsor: 'Par 3 Camera Sponsor', entries: [{ name: names[i * 3], dist: 54 + i * 31 }, { name: names[i * 3 + 5], dist: 97 + i * 12 }] })),
  ...par5.slice(0, 1).map((h) => ({ kind: 'ld', hole: h, label: `Longest drive · hole ${h}`, sponsor: '', entries: [{ name: names[9], dist: 287 }, { name: names[2], dist: 271 }] })),
];
const d0 = new Date(), today = `${d0.getFullYear()}-${String(d0.getMonth() + 1).padStart(2, '0')}-${String(d0.getDate()).padStart(2, '0')}`; // the local day, not London's
await desk('save', { setup: { ...got, name: NAME, club: CLUB, date: today, course: { name: courseName, holes, tees, at },
  format: { type: 'bestball', count: 1, allowance: 85, show: 'net' }, flights: ['A', 'B', 'C', 'D'], teams, sponsors, contests,
  screens: { ...(got.screens || {}), title: NAME, ticker: 'Welcome to the Sample Member-Guest · a Flagcast demo tournament', seconds: 12, rows: 10, skins: true },
  displays: got.displays?.length ? got.displays : [{ name: 'Clubhouse bar', where: 'Over the bar', group: 'Clubhouse', playlist: [{ k: 'lb', secs: 14 }, { k: 'skins', secs: 10 }, { k: 'contests', secs: 10 }, { k: 'sponsors', secs: 8 }] }] } });

// 4) fresh scores: each team part way round (9 to 14 holes from its starting hole), the same every run
const ev2 = await desk('get');
for (const t of ev2.teams) await desk('clear', { team: t.id });
let seed = 11; const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
const now = Date.now();
for (const [i, t] of ev2.teams.entries()) {
  const played = 9 + ((i * 5) % 6), list = [];
  for (let k = 0; k < played; k++) {
    const h = ((t.start - 1 + k) % 18) + 1, par = holes[h - 1].par;
    for (const p of t.players) { const r = rnd(); list.push({ p: p.id, h, v: par + (r < 0.16 ? -1 : r < 0.62 ? 0 : r < 0.9 ? 1 : 2), at: now - (played - k) * 11 * 60000 }); }
  }
  await post(`/golf/api/${id}/score`, { team: t.id, desk: key, list });
}

// 5) par 3 cameras (Apple's test pattern) and two replays; Demo on, so it shows the Flagcast logo
await admin({ op: 'cams', id, cams: Object.fromEntries(par3.map((h) => [h, CAM])) });
for (const r of ev2.replays || []) await desk('replay', { remove: r.id });
await desk('replay', { hole: par3[0], label: `${names[0]} to 4 feet`, url: CAM });
await desk('replay', { hole: par3[1] || par3[0], label: `${names[13]} hits the pin`, url: CAM });
if (LOGO) await admin({ op: 'brand', club: club.id, logo: 'data:image/png;base64,' + fs.readFileSync(LOGO).toString('base64') });
await admin({ op: 'demo', id, on: !LOGO && !club.logo });

console.log(`${NAME} (${id.toUpperCase()}) in ${CLUB} · ${courseName} · ${ev2.teams.length} teams · par 3s ${par3.join(', ')}`);
console.log(`Live leaderboard: ${BASE}/g/${id}`);
console.log(`TV board:         ${BASE}/g/${id}/board`);
console.log('Desk link: in Flagcast Manager → Admin → Tournaments (it’s private: not printed here)');
