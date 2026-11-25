// Shamble, match play (singles, four-ball, scramble), the team cup and the Individuals leaderboard (public/golf/core.js).
// Same hand-worked answers as CoreTests.testMatchPlay in the players' app.   node test/matchplay.test.mjs
import assert from 'node:assert/strict';
import { defaultHoles, matchPlay, matches, matchFor, cup, fmtPts, individuals, leaderboard, teamBall, formatName, hasIndividuals, teamCard } from '../public/golf/core.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const holes = defaultHoles(); // stroke index 1 is hole 5, 2 is hole 12
const fill = (arr) => [...arr, ...Array(18 - arr.length).fill(null)];

// singles: Ann (0) v Cy (2): Cy gets a stroke on holes 5 and 12
const ev = {
  format: { type: 'match', match: 'singles', allowance: 100 }, course: { holes },
  teams: [{ id: 'ta', name: 'Ann', start: 1, side: 'A', players: [{ id: 'p1', name: 'Ann Fox', hcp: 0 }] },
          { id: 'tb', name: 'Cy', start: 1, side: 'B', players: [{ id: 'p3', name: 'Cy Park', hcp: 2 }] }],
  matches: [{ id: 'm1', a: 'ta', b: 'tb' }],
};
let sc = { ta: { p1: fill([4, 5, 4, 3, 4]) }, tb: { p3: fill([5, 4, 4, 2, 5]) } };
let r = matchPlay(ev, sc, ev.matches[0]);
assert.deepEqual(r.holes.slice(0, 6).map((h) => h.r), ['A', 'B', 'H', 'B', 'H', null]);
assert.equal(r.text, '1 UP'); assert.equal(r.thru, '5'); assert.equal(r.leader, 'B'); assert.equal(r.done, false);
assert.equal(r.holes[4].sb.p3, 1); assert.equal(r.holes[4].sa.p1, 0); assert.equal(r.strokes['tb:p3'], 2);
assert.deepEqual(matchFor(r, 'ta'), { text: '1 DOWN', state: 'down' });
assert.deepEqual(matchFor(r, 'tb'), { text: '1 UP', state: 'up' }); ok('singles: holes won with strokes off the low player');

// Ann wins 1–5 and halves the rest: 5 up with 4 to play after 14 closes it out 5&4; hole 15 doesn't count
sc = { ta: { p1: fill(Array(15).fill(4)) }, tb: { p3: fill([...Array(5).fill(6), ...Array(10).fill(4)]) } };
sc.tb.p3[11] = 5; // net 4 on hole 12 with Cy's stroke: still halved
sc.tb.p3[14] = 3; // after the match is over
r = matchPlay(ev, sc, ev.matches[0]);
assert.equal(r.done, true); assert.equal(r.text, '5&4'); assert.equal(r.winner, 'A'); assert.equal(r.thru, 'F');
assert.equal(r.holes[14].after, true); assert.equal(r.holes[14].r, null); assert.equal(r.played, 14);
assert.deepEqual(matchFor(r, 'ta'), { text: 'WON 5&4', state: 'won' });
assert.deepEqual(matchFor(r, 'tb'), { text: 'LOST 5&4', state: 'lost' }); ok('closed out 5&4, later holes ignored');

// dormie, then 1 UP after 18; and a picked-up ball (0) loses the hole
sc = { ta: { p1: Array(18).fill(4) }, tb: { p3: Array(18).fill(4) } };
sc.tb.p3[11] = 4; // Cy nets 3 on 12: Cy wins 12
sc.ta.p1[0] = 0; // Ann picks up on 1: Cy wins 1
sc.ta.p1[4] = 3; // Ann's 3 halves hole 5 with Cy's net 3
sc.tb.p3[17] = 6; sc.ta.p1[16] = 3; sc.ta.p1[15] = 2; // Ann wins 16, 17, 18
r = matchPlay(ev, sc, ev.matches[0]);
assert.equal(r.holes[0].r, 'B'); assert.equal(r.holes[11].r, 'B');
assert.equal(r.done, true); assert.equal(r.text, '1 UP'); assert.equal(r.winner, 'A');
const r17 = matchPlay(ev, { ta: { p1: sc.ta.p1.slice(0, 17) }, tb: { p3: sc.tb.p3.slice(0, 17) } }, ev.matches[0]);
assert.equal(r17.text, 'AS'); assert.equal(r17.dormie, false);
const r16 = matchPlay(ev, { ta: { p1: [...sc.ta.p1.slice(0, 15), 4] }, tb: { p3: sc.tb.p3.slice(0, 16) } }, ev.matches[0]);
assert.equal(r16.text, '2 UP'); assert.equal(r16.leader, 'B'); assert.equal(r16.dormie, true); ok('dormie, 1 UP at the last, pick-ups lose the hole');

// all square after 18: halved
const cy = Array(18).fill(4); cy[4] = 5; cy[11] = 5; // net 4s with Cy's strokes
r = matchPlay(ev, { ta: { p1: Array(18).fill(4) }, tb: { p3: cy } }, ev.matches[0]);
assert.equal(r.halved, true); assert.equal(r.text, 'Halved'); assert.deepEqual(matchFor(r, 'tb'), { text: 'HALVED', state: 'halved' }); ok('halved');

// four-ball at 90%: best ball a side. Handicaps 10/4 v 6/8 → playing 9/4 v 5/7 → strokes off 4: 5, 0 v 1, 3
const fb = {
  format: { type: 'match', match: 'fourball', allowance: 90, cup: { on: true, a: 'Reds', b: 'Blues' } }, course: { holes },
  teams: [{ id: 'ta', name: 'Fox / Lee', start: 1, side: 'A', players: [{ id: 'a1', hcp: 10 }, { id: 'a2', hcp: 4 }] },
          { id: 'tb', name: 'Park / Ortiz', start: 1, side: 'B', players: [{ id: 'b1', hcp: 6 }, { id: 'b2', hcp: 8 }] },
          { id: 'tc', name: 'Byrne / Shah', start: 10, side: 'A', players: [{ id: 'c1', hcp: 0 }, { id: 'c2', hcp: 0 }] },
          { id: 'td', name: 'Kowal / Diaz', start: 10, side: 'B', players: [{ id: 'd1', hcp: 0 }, { id: 'd2', hcp: 0 }] },
          { id: 'te', name: 'Quinn / Ford', start: 1, side: 'B', players: [{ id: 'e1', hcp: 0 }] },
          { id: 'tf', name: 'Reyes / Hall', start: 1, side: 'A', players: [{ id: 'f1', hcp: 0 }] }],
  matches: [{ id: 'm1', a: 'ta', b: 'tb' }, { id: 'm2', a: 'tc', b: 'td' }, { id: 'm3', a: 'te', b: 'tf' }],
};
// hole 1 (SI 7): a1 gets 1 (5→4), a2 4; b1 0 → 4, b2 1 (5→4): halved. hole 2 (SI 3): a1 6-1=5, a2 5; b1 5, b2 5-1=4 → B
const fsc = { ta: { a1: fill([5, 6]), a2: fill([4, 5]) }, tb: { b1: fill([4, 5]), b2: fill([5, 5]) },
  tc: { c1: fill([]), c2: fill([]) }, td: { d1: fill([]), d2: fill([]) } };
fsc.tc.c1[9] = 3; fsc.tc.c2[9] = 4; fsc.td.d1[9] = 4; fsc.td.d2[9] = 4; // match 2 starts on 10: Byrne / Shah win it
fsc.te = { e1: Array(18).fill(4) }; fsc.tf = { f1: Array(18).fill(4) }; fsc.te.e1[0] = 3; // match 3: Quinn wins 1 UP
r = matchPlay(fb, fsc, fb.matches[0]);
assert.deepEqual(r.strokes, { 'ta:a1': 5, 'ta:a2': 0, 'tb:b1': 1, 'tb:b2': 3 });
assert.deepEqual(r.holes.slice(0, 2).map((h) => h.r), ['H', 'B']); assert.equal(r.text, '1 UP'); assert.equal(r.leader, 'B');
const m2 = matchPlay(fb, fsc, fb.matches[1]);
assert.equal(m2.holes[0].hole, 10); assert.equal(m2.text, '1 UP'); assert.equal(m2.thru, '1'); ok('four-ball best ball at 90%, starting on 10');

// the cup: match 3 is done (Quinn, a Blue, won it as side a). Now: match 1 Blue leads, match 2 Red leads
const all = matches(fb, fsc), c = cup(fb, fsc, all);
assert.equal(all[2].winner, 'A');
assert.deepEqual([c.A, c.B, c.nowA, c.nowB, c.left, c.total, c.toWin], [0, 1, 1, 2, 2, 3, 2]);
assert.equal(fmtPts(6.5), '6½'); assert.equal(fmtPts(0.5), '½'); assert.equal(fmtPts(0), '0'); assert.equal(fmtPts(12), '12'); ok('team cup points, now and final');

// scramble match: one team ball 'T' with the team handicap
const scr = { format: { type: 'match', match: 'scramble', allowance: 100 }, course: { holes },
  teams: [{ id: 'ta', hcp: 3, start: 1, players: [{ id: 'x' }, { id: 'y' }] }, { id: 'tb', hcp: 0, start: 1, players: [{ id: 'z' }] }],
  matches: [{ id: 'm', a: 'ta', b: 'tb' }] };
assert.equal(teamBall(scr), true); assert.equal(hasIndividuals(scr), false); assert.deepEqual(individuals(scr, {}), []);
r = matchPlay(scr, { ta: { T: fill([4, 5]) }, tb: { T: fill([4, 4]) } }, scr.matches[0]);
assert.deepEqual(r.holes.slice(0, 2).map((h) => h.r), ['H', 'H']); // ta gets a stroke on hole 2 (SI 3)
assert.equal(r.text, 'AS'); assert.equal(formatName(scr), 'Scramble match play'); assert.equal(formatName(fb), 'Four-ball match play'); ok('scramble match');

// shamble: scored like best ball (best 2 of each player's own ball)
const sh = { format: { type: 'shamble', count: 2, allowance: 100, show: 'net' }, course: { holes },
  teams: [{ id: 'ta', name: 'A', flight: 'A', start: 1, players: [{ id: 'p1', name: 'Ann Fox', hcp: 0 }, { id: 'p2', name: 'Bob Lee', hcp: 18 }, { id: 'p3', name: 'Cal Ng', hcp: 0 }] },
          { id: 'tb', name: 'B', flight: 'B', start: 1, players: [{ id: 'p4', name: 'Dee Roe', hcp: 9 }] }] };
const ssc = { ta: { p1: fill([4]), p2: fill([5]), p3: fill([6]) }, tb: { p4: fill([3]) } };
const card = teamCard(sh, sh.teams[0], ssc.ta);
assert.equal(card[0].gross, 9); assert.equal(card[0].net, 8); assert.equal(card[0].par, 8); assert.equal(formatName(sh), 'Shamble'); ok('shamble counts like best ball');

// Individuals: every player on a line, net or gross, by flight
const ind = individuals(sh, ssc);
assert.deepEqual(ind.map((l) => [l.name, l.score]), [['Dee Roe', -2], ['Ann Fox', 0], ['Bob Lee', 0], ['Cal Ng', 2]]);
assert.deepEqual(ind.map((l) => l.pos), ['1', 'T2', 'T2', '4']);
assert.deepEqual(individuals(sh, ssc, { mode: 'gross' }).map((l) => [l.name, l.score]), [['Dee Roe', -1], ['Ann Fox', 0], ['Bob Lee', 1], ['Cal Ng', 2]]);
assert.deepEqual(individuals(sh, ssc, { flight: 'A', mode: 'gross' }).map((l) => l.name), ['Ann Fox', 'Bob Lee', 'Cal Ng']);
assert.equal(leaderboard(sh, ssc).length, 2); // the team board is unchanged
const stab = individuals({ ...sh, format: { type: 'stableford', count: 2 } }, ssc);
assert.deepEqual(stab.map((l) => [l.name, l.score]), [['Dee Roe', 4], ['Ann Fox', 2], ['Bob Lee', 2], ['Cal Ng', 0]]);
assert.equal(hasIndividuals({ format: { type: 'stroke' } }), false); ok('Individuals leaderboard: net, gross, flights, Stableford');

// a Save from a Manager made before match play keeps the pairings, match settings and cup sides
const { keepMatch } = await import('../setup.js');
const evm = { format: { type: 'match', match: 'singles', cup: { on: true, a: 'Reds', b: 'Blues' } }, matches: [{ id: 'm1', a: 'ta', b: 'tb' }],
  teams: [{ id: 'ta', side: 'A' }, { id: 'tb', side: 'B' }] };
const kept = keepMatch({ format: { type: 'match', allowance: 90 }, teams: [{ id: 'ta', name: 'x' }, { id: 'tb', side: '' }] }, evm);
assert.deepEqual(kept.matches, evm.matches); assert.equal(kept.format.match, 'singles'); assert.equal(kept.format.cup.on, true); assert.equal(kept.format.allowance, 90);
assert.equal(kept.teams[0].side, 'A'); assert.equal(kept.teams[1].side, '');
assert.deepEqual(keepMatch({ matches: [], format: { match: 'fourball' } }, evm).matches, []); ok('an older Manager\'s Save keeps match play settings');

// the TV apps get matches and Individuals as leaderboard pages
const { tvFeed } = await import('../tvfeed.js');
const feed = tvFeed({ ...fb, id: 'abcdefgh', name: 'Cup', scores: fsc, flights: [], sponsors: [], screens: { rows: 10 }, displays: [] }, '');
const mp = feed.pages.find((x) => x.title === 'Matches');
assert.ok(mp); assert.equal(mp.rows.length, 3); assert.equal(mp.rows[0].name, 'Fox / Lee v Park / Ortiz'); assert.equal(mp.rows[0].score, '1 UP');
assert.equal(mp.rows[2].score, '1 UP'); assert.equal(mp.rows[2].thru, 'F'); assert.match(mp.sub, /Reds 0, Blues 1/);
const f2 = tvFeed({ ...sh, format: { ...sh.format, indiv: true }, id: 'abcdefgh', name: 'Champ', scores: ssc, flights: [], sponsors: [], screens: { rows: 10 }, displays: [] }, '');
const ip = f2.pages.find((x) => x.title === 'Individuals');
assert.ok(ip); assert.deepEqual(ip.rows.map((r) => r.name), ['Dee Roe', 'Ann Fox', 'Bob Lee', 'Cal Ng']); ok('TV apps: matches and Individuals pages');
