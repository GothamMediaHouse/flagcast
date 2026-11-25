// The lock screen live view: POST …/live registers a phone's Apple push token for its team (only with that team's
// cart code) and answers with the team's card; end: true takes it off.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/live.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const { id, key } = await post('/golf/api/new', { name: 'Live test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
const cur = await desk('get');
const teams = [1, 2].map((i) => ({ id: `team${i}`, name: `Team ${i}`, start: 1, players: [{ id: `p${i}`, name: `Player ${i}`, hcp: 0 }] }));
await desk('save', { setup: { ...cur, teams } });
const got = await desk('get');
const code = (tid) => got.teams.find((t) => t.id === tid).code;
const token = 'ab'.repeat(32);

assert.equal((await call(`/golf/api/${id}/live`, { code: code('team2'), team: 'team1', token })).status, 403); ok('another cart’s code can’t follow a team');
assert.equal((await call(`/golf/api/${id}/live`, { code: code('team1'), team: 'team1', token: 'nope' })).status, 400); ok('a bad token is turned away');

await post(`/golf/api/${id}/score`, { code: code('team1'), team: 'team1', list: [{ p: 'p1', h: 1, v: 3, at: Date.now() }] });
let r = await post(`/golf/api/${id}/live`, { code: code('team1'), team: 'team1', token, env: 'dev' });
assert.equal(r.card.team, 'Team 1'); assert.equal(r.card.thru, '1'); assert.equal(r.card.hole, 2); assert.equal(r.card.of, 2);
ok('a registered phone gets its team’s card back');

await desk('nudge', { team: 'team1', text: 'Keep up the pace' });
r = await post(`/golf/api/${id}/live`, { code: code('team1'), team: 'team1', token, env: 'dev' });
assert.equal(r.card.msg, 'Keep up the pace'); ok('a pro shop message shows on the card');

r = await post(`/golf/api/${id}/live`, { code: code('team1'), team: 'team1', token, end: true });
assert.equal(r.card, null); ok('end takes the phone off');

const st = await (await fetch(`${BASE}/golf/api/${id}/state`)).json();
assert.ok(!JSON.stringify(st).includes(token)); ok('tokens never show in the public state');
console.log(`1..${n}`);
