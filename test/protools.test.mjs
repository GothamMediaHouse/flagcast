// Golf pro tools on the day: message everyone or one golfer, fix a team, add a late group, move a player, results files.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/protools.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();

const { id, key } = await post('/golf/api/new', { name: 'Pro tools test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
const cur = await desk('get');
await desk('save', { setup: { ...cur, format: { type: 'stroke' }, pins: [{ name: 'Pro', role: 'pro', pin: '654321' }, { name: 'Marshal', role: 'marshal', pin: '876543' }],
  teams: [{ name: 'Smith', players: [{ name: 'Al Smith', hcp: 10, ghin: '1234567' }, { name: 'Bo Smith', hcp: 12 }] }, { name: 'Jones', players: [{ name: 'Cy Jones', hcp: 5 }] }] } });
const pro = (op, b = {}) => post(`/golf/api/${id}/pro`, { pin: '654321', op, ...b });
let s = await state(id);
const [A, B] = s.teams;

await pro('nudge', { team: '*', text: 'Lunch is ready' });
await pro('nudge', { team: A.id, player: A.players[1].id, text: 'Bo, your car lights are on' });
s = await state(id);
assert.deepEqual(s.nudges.map(({ at, ...x }) => x), [{ team: '*', text: 'Lunch is ready' }, { team: A.id, player: A.players[1].id, text: 'Bo, your car lights are on' }]);
ok('a pro messages everyone, and one golfer');
assert.equal((await call(`/golf/api/${id}/pro`, { pin: '654321', op: 'nudge', team: A.id, player: 'nope', text: 'x' })).status, 404); ok('an unknown golfer is refused');

await call(`/golf/api/${id}/score`, { team: A.id, code: (await desk('get')).teams[0].code, list: [{ p: A.players[1].id, h: 1, v: 5 }] });
await pro('team', { team: A.id, name: 'Smith & Co', players: [{ id: A.players[0].id, name: 'Al Smith', hcp: 10 }, { id: A.players[1].id, name: 'Bob Smith', hcp: 12 }, { name: 'Di Late', hcp: 20 }] });
s = await state(id);
const a2 = s.teams.find((t) => t.id === A.id);
assert.equal(a2.name, 'Smith & Co'); assert.deepEqual(a2.players.map((p) => p.name), ['Al Smith', 'Bob Smith', 'Di Late']);
assert.equal(a2.players[1].id, A.players[1].id); assert.equal(s.scores[A.id][A.players[1].id][0], 5);
const full = await desk('get');
assert.equal(full.teams[0].players[0].ghin, '1234567'); assert.equal(full.teams[0].code, (await desk('get')).teams[0].code);
ok('a pro fixes a team: rename, swap a name, add a player; ids, scores, GHIN and cart code kept');

const late = await pro('team', { team: 'new', name: 'Late group', start: 10, players: [{ name: 'Ed Late', hcp: 8 }] });
assert.match(late.code, /^[A-Z0-9]{4,}$/); s = await state(id);
assert.ok(s.teams.find((t) => t.id === late.team && t.start === 10)); assert.equal(s.teams.find((t) => t.id === late.team).code, undefined);
ok('a pro adds a late group and gets its cart code (golfers never see codes)');

await pro('move', { player: A.players[1].id, to: B.id });
s = await state(id);
assert.ok(s.teams.find((t) => t.id === B.id).players.some((p) => p.id === A.players[1].id));
assert.ok(!s.teams.find((t) => t.id === A.id).players.some((p) => p.id === A.players[1].id));
assert.equal(s.scores[B.id][A.players[1].id][0], 5);
ok('a pro moves a player to another cart, scores and all');

const r = await pro('report');
assert.equal(r.results[0][0], 'Flight'); assert.ok(r.results.length > 1);
assert.equal(r.ghin[0][1], 'GHIN number'); assert.ok(r.ghin.some((row) => row[0] === 'Bob Smith'));
ok('a pro gets the results and GHIN files');

assert.equal((await call(`/golf/api/${id}/pro`, { pin: '876543', op: 'team', team: A.id, players: [{ name: 'X' }] })).status, 403);
assert.equal((await call(`/golf/api/${id}/pro`, { pin: '876543', op: 'nudge', team: '*', text: 'x' })).status, 403);
ok('marshals can’t fix teams or message golfers');
