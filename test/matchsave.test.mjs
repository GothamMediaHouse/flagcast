// Match play on the server: the desk saves pairings, match type, cup sides and the Individuals switch; scores for a
// scramble match go in as one team ball; a Save from a Manager made before match play keeps it all; the report lists matches.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/matchsave.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';
import { matches, cup } from '../public/golf/core.js';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const post = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json(); if (!r.ok) throw new Error(`${path} ${r.status} ${JSON.stringify(j)}`); return j;
};
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const { id, key } = await post('/golf/api/new', { name: 'Match play test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
const got = await desk('get');
const teams = [
  { id: 'tmaa', name: 'Fox / Lee', start: 1, side: 'A', hcp: 4, players: [{ id: 'a1', name: 'Matt Fox', hcp: 4 }, { id: 'a2', name: 'Sam Lee', hcp: 10 }] },
  { id: 'tmbb', name: 'Park / Ortiz', start: 1, side: 'B', hcp: 2, players: [{ id: 'b1', name: 'Jin Park', hcp: 6 }, { id: 'b2', name: 'Ana Ortiz', hcp: 8 }] },
  { id: 'tmcc', name: 'Byrne / Shah', start: 10, side: 'Z', players: [{ id: 'c1', name: 'Pat Byrne', hcp: 0 }] },
];
await desk('save', { setup: { ...got, teams, format: { type: 'match', match: 'fourball', allowance: 90, cup: { on: true, a: 'Reds', b: 'Blues' }, indiv: true },
  matches: [{ id: 'mt1', a: 'tmaa', b: 'tmbb' }, { id: 'mt2', a: 'tmcc', b: 'tmcc' }, { id: 'mt3', a: 'tmaa', b: 'tmcc' }, { id: 'mt4', a: 'nope', b: 'tmbb' }] } });
let s = await state(id);
assert.equal(s.format.type, 'match'); assert.equal(s.format.match, 'fourball'); assert.deepEqual(s.format.cup, { on: true, a: 'Reds', b: 'Blues' }); assert.equal(s.format.indiv, true);
assert.deepEqual(s.matches, [{ id: 'mt1', a: 'tmaa', b: 'tmbb' }]); // a team against itself, a team twice, an unknown team: dropped
assert.deepEqual(s.teams.map((t) => t.side), ['A', 'B', '']); ok('pairings, match type, cup and sides saved and cleaned');

// a Manager from before match play saves without matches, match settings or sides: they stay
const old = await desk('get');
const strip = { ...old, format: { type: 'match', count: 1, allowance: 90, show: 'net', nine: '' }, teams: old.teams.map(({ side, ...t }) => t) };
delete strip.matches;
await desk('save', { setup: strip });
s = await state(id);
assert.deepEqual(s.matches, [{ id: 'mt1', a: 'tmaa', b: 'tmbb' }]); assert.equal(s.format.match, 'fourball'); assert.equal(s.format.cup.on, true);
assert.deepEqual(s.teams.map((t) => t.side), ['A', 'B', '']); ok('an older Manager’s Save keeps match play');

// scores: Park wins hole 1 (Lee's stroke isn't enough), so Park / Ortiz are 1 UP
const codes = Object.fromEntries((await desk('get')).teams.map((t) => [t.id, t.code]));
await post(`/golf/api/${id}/score`, { code: codes.tmaa, team: 'tmaa', list: [{ p: 'a1', h: 1, v: 5, at: Date.now() }, { p: 'a2', h: 1, v: 6, at: Date.now() }] });
await post(`/golf/api/${id}/score`, { code: codes.tmbb, team: 'tmbb', list: [{ p: 'b1', h: 1, v: 3, at: Date.now() }, { p: 'b2', h: 1, v: 5, at: Date.now() }] });
s = await state(id);
const r = matches(s, s.scores)[0];
assert.equal(r.text, '1 UP'); assert.equal(r.leader, 'B'); assert.deepEqual([cup(s, s.scores).nowA, cup(s, s.scores).nowB], [0, 1]); ok('scores make the match');

const rep = await desk('report');
assert.deepEqual(rep.results[0], ['Match', 'Side A', 'Side B', 'Result', 'Winner', 'Holes played']);
assert.deepEqual(rep.results[1], [1, 'Fox / Lee', 'Park / Ortiz', '1 UP thru 1', '', 1]);
assert.deepEqual(rep.results.at(-1), ['Points', '0', '0']); ok('report lists the matches and the cup');

// a scramble match: one ball a team, entered as T (a player's score is ignored)
await desk('save', { setup: { ...(await desk('get')), format: { type: 'match', match: 'scramble', allowance: 100 } } });
await post(`/golf/api/${id}/score`, { code: codes.tmcc, team: 'tmcc', list: [{ p: 'T', h: 10, v: 4, at: Date.now() }, { p: 'c1', h: 11, v: 4, at: Date.now() }] });
s = await state(id);
assert.equal(s.scores.tmcc.T[9], 4); assert.equal(s.scores.tmcc.c1?.[10] ?? null, null); ok('scramble match scores one team ball');

// shamble saves as its own format
await desk('save', { setup: { ...(await desk('get')), format: { type: 'shamble', count: 2, allowance: 80 } } });
s = await state(id);
assert.equal(s.format.type, 'shamble'); assert.equal(s.format.count, 2); ok('shamble saves');
