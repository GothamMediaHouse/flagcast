// A Save from a desk opened a while ago keeps what happened since: a late group a pro added (and its scores), a player
// a pro moved, and teams with scores when an old app sends no version. A team taken off comes back with Restore.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/stalesave.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const post = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json(); if (!r.ok) throw new Error(`${path} ${r.status} ${JSON.stringify(j)}`); return j;
};
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const { id, key } = await post('/golf/api/new', { name: 'Stale save test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
let cur = await desk('get');
await desk('save', { setup: { ...cur, pins: [{ name: 'Pro', role: 'pro', pin: '482915' }],
  teams: [{ id: 'teama', name: 'A', players: [{ id: 'pa', name: 'Al' }, { id: 'pb', name: 'Bea' }] }, { id: 'teamb', name: 'B', players: [{ id: 'pc', name: 'Cy' }] }] } });
const old = await desk('get'); // a desk opens the setup

// the pro adds a late group, which scores; and moves Bea to team B
const late = await post(`/golf/api/${id}/pro`, { pin: '482915', op: 'team', team: 'new', name: 'Late group', players: [{ name: 'Dee' }] });
const lateP = (await desk('get')).teams.find((t) => t.id === late.team).players[0].id;
await post(`/golf/api/${id}/score`, { code: late.code, team: late.team, list: [{ p: lateP, h: 1, v: 4 }] });
await post(`/golf/api/${id}/pro`, { pin: '482915', op: 'move', player: 'pb', to: 'teamb' });

// the old desk changes the ticker and saves
await desk('save', { setup: { ...old, screens: { ...old.screens, ticker: 'Lunch at 1' } } });
let s = await state(id);
assert.equal(s.screens.ticker, 'Lunch at 1');
assert.deepEqual(s.teams.map((t) => t.name), ['A', 'B', 'Late group']);
assert.equal(s.scores[late.team][lateP][0], 4);
ok('a Save from an older copy keeps the late group and its scores');
assert.deepEqual(s.teams.find((t) => t.id === 'teamb').players.map((p) => p.name), ['Cy', 'Bea']);
assert.deepEqual(s.teams.find((t) => t.id === 'teama').players.map((p) => p.name), ['Al']);
ok('and the pro’s player move');
assert.ok(!s.teams.some((t) => 'sv' in t || 'code' in t) && !('removed' in s));
ok('the public state has no versions, codes or removed teams');

// an up-to-date desk can still take a team off; it's kept for Restore with its scores
cur = await desk('get');
await desk('save', { setup: { ...cur, teams: cur.teams.filter((t) => t.id !== late.team) } });
s = await state(id);
assert.ok(!s.teams.some((t) => t.id === late.team) && !s.scores[late.team]);
assert.equal((await desk('get')).removed.length, 1);
ok('a current desk takes a team off');
await desk('restore', { team: late.team });
s = await state(id);
assert.ok(s.teams.some((t) => t.id === late.team)); assert.equal(s.scores[late.team][lateP][0], 4);
ok('Restore brings it back with its scores');

// an app that sends no version can't drop a team that has scores
cur = await desk('get'); delete cur.v;
await desk('save', { setup: { ...cur, teams: cur.teams.filter((t) => t.id !== late.team && t.id !== 'teama') } });
s = await state(id);
assert.ok(s.teams.some((t) => t.id === late.team)); assert.ok(!s.teams.some((t) => t.id === 'teama'));
ok('with no version, a team with scores stays and one without goes');
console.log(`\n${n} passed`);
