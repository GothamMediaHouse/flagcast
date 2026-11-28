// Multi-day tournaments: rounds with dates, each round's scores kept when the next starts, the total leaderboard,
// an older Manager's Save keeping the rounds, going back a round, and the tournament moving on by itself on a round's date.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/multiday.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';
import { board, totalBoard, leaderboard, roundNow, showsTotal, roundName, roundDay, indivBoard } from '../public/golf/core.js';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const post = async (path, body, want = 200) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json(); if (r.status !== want) throw new Error(`${path} ${r.status} ${JSON.stringify(j)}`); return j;
};
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const day = (k) => new Date(Date.now() - 4 * 3600000 + k * 86400000).toISOString().slice(0, 10);

const { id, key } = await post('/golf/api/new', { name: 'Member-Guest', pass: 'local' });
const desk = (op, b = {}, want) => post(`/golf/api/${id}/desk`, { key, op, ...b }, want);
const got = await desk('get');
const teams = [
  { id: 'teama', name: 'Fox / Ramirez', players: [{ id: 'a1', name: 'Matt Fox', hcp: 0 }, { id: 'a2', name: 'Luis Ramirez', hcp: 0 }] },
  { id: 'teamb', name: 'Chen / Walsh', players: [{ id: 'b1', name: 'Amy Chen', hcp: 0 }, { id: 'b2', name: 'Pat Walsh', hcp: 0 }] },
];
await desk('save', { setup: { ...got, date: day(5), teams, format: { type: 'bestball', count: 1, allowance: 100, show: 'net' },
  rounds: [{ date: day(5) }, { date: day(6) }, { date: day(7) }, { date: 'nope' }, { date: day(9) }] } });
let s = await state(id);
assert.deepEqual(s.rounds.map((r) => r.date), [day(5), day(6), day(7), '']); // four at most; a bad date is left blank
assert.equal(s.date, day(5)); assert.equal(s.round, 0); assert.equal(s.boardBy, 'total'); assert.ok(showsTotal(s));
assert.equal(roundName(s), 'Round 1 of 4'); assert.match(roundDay(s, 0), /^(Sun|Mon|Tue|Wed|Thu|Fri|Sat) \d+ [A-Z][a-z]{2}$/);
ok('rounds and their dates saved; round 1’s date is the tournament’s');

await desk('save', { setup: { ...(await desk('get')), rounds: [{ date: day(5) }, { date: day(6) }, { date: day(7) }] } });
const codes = Object.fromEntries((await desk('get')).teams.map((t) => [t.id, t.code]));
const card = (team, p, holes) => post(`/golf/api/${id}/score`, { code: codes[team], team, list: holes.map((v, i) => ({ p, h: i + 1, v, at: Date.now() })) });
// round 1: Fox / Ramirez −2 thru 3 (3,3,3 on 4,5,4), Chen / Walsh E thru 3
await card('teama', 'a1', [3, 4, 4]); await card('teama', 'a2', [5, 5, 5]);
await card('teamb', 'b1', [4, 5, 4]); await card('teamb', 'b2', [5, 6, 5]);
s = await state(id);
assert.deepEqual(board(s, s.scores).map((l) => [l.name, l.score, l.thru]), [['Fox / Ramirez', -2, '3'], ['Chen / Walsh', 0, '3']]);
ok('round 1 scores on the board');

// round 2 starts: round 1 is put away, the cards are empty
await desk('round', { round: 1 });
s = await state(id);
assert.equal(s.round, 1); assert.deepEqual(s.scores, {}); assert.equal(roundNow(s), 1);
assert.deepEqual(s.past['0'].scores.teama.a1.slice(0, 3), [3, 4, 4]); assert.equal(s.past['0'].format.type, 'bestball');
let tb = board(s, s.scores);
assert.deepEqual(tb.map((l) => [l.name, l.score, l.thru, l.pos]), [['Fox / Ramirez', -2, 'R1 F', '1'], ['Chen / Walsh', 0, 'R1 F', '2']]);
ok('round 2 starts empty; the board still shows the round 1 totals');

// round 2: Chen / Walsh −3 thru 2, Fox / Ramirez +1 thru 1 → Chen / Walsh lead −3 to −1
await card('teamb', 'b1', [2, 4]); await card('teamb', 'b2', [5, 5]);
await card('teama', 'a1', [5]); await card('teama', 'a2', [6]);
s = await state(id);
tb = totalBoard(s, s.scores);
assert.deepEqual(tb.map((l) => [l.name, l.score, l.today.score, l.thru, l.pos, l.played]), [['Chen / Walsh', -3, -3, '2', '1', 5], ['Fox / Ramirez', -1, 1, '1', '2', 4]]);
assert.deepEqual(tb[0].rounds.map((r) => r && r.score), [0, -3, null]);
assert.deepEqual(leaderboard(s, s.scores).map((l) => l.score), [-3, 1]); // round 2 alone
ok('the total adds the rounds up, with each round’s score');

// each round on its own
await desk('save', { setup: { ...(await desk('get')), boardBy: 'round' } });
s = await state(id);
assert.equal(showsTotal(s), false); assert.deepEqual(board(s, s.scores).map((l) => l.score), [-3, 1]);
ok('“Each round” shows only the round being played');

// a Manager from before multi-day saves without rounds or boardBy: they stay
const old = await desk('get'); delete old.rounds; delete old.boardBy;
await desk('save', { setup: { ...old, date: day(5) } });
s = await state(id);
assert.deepEqual(s.rounds.map((r) => r.date), [day(5), day(6), day(7)]); assert.equal(s.boardBy, 'round'); assert.equal(s.round, 1);
ok('an older Manager’s Save keeps the rounds');

// can't take rounds off while a later one is being played
const e = await desk('save', { setup: { ...(await desk('get')), rounds: [] } }, 400);
assert.match(e.error, /Round 2 is being played/);
ok('rounds can’t be taken off under the round being played');

// back to round 1 for a fix: its scores come back, round 2's are kept
await desk('round', { round: 0 });
s = await state(id);
assert.equal(s.round, 0); assert.deepEqual(s.scores.teama.a1.slice(0, 3), [3, 4, 4]); assert.deepEqual(s.past['1'].scores.teamb.b1.slice(0, 2), [2, 4]);
await desk('round', { round: 1 });
s = await state(id);
assert.deepEqual(s.scores.teamb.b1.slice(0, 2), [2, 4]);
await desk('round', { round: 7 }, 400);
ok('going back a round and forward again keeps both rounds');

// a lock is the round's own: round 2 locked, round 3 starts open
await desk('lock', { locked: true });
await desk('round', { round: 2 });
s = await state(id);
assert.equal(s.locked, false); assert.equal(s.past['1'].locked, true);
ok('each round has its own lock');

// a tournament whose round 2 is today moves on by itself
const t2 = await post('/golf/api/new', { name: 'Two days', pass: 'local' });
const d2 = (op, b = {}) => post(`/golf/api/${t2.id}/desk`, { key: t2.key, op, ...b });
await d2('save', { setup: { ...(await d2('get')), teams, rounds: [{ date: day(-1) }, { date: day(0) }] } });
s = await state(t2.id);
assert.equal(s.round, 1); ok('on round 2’s date the tournament moves on to it');
await d2('round', { round: 0 });
s = await state(t2.id);
assert.equal(s.round, 0); ok('and the desk can still go back to round 1');

// Individuals add up too (a 36-hole club championship)
const ind = indivBoard({ ...s, format: { ...s.format, indiv: true } }, s.scores);
assert.ok(Array.isArray(ind));
ok('Individuals board works over rounds');
console.log(`1..${n}`);
