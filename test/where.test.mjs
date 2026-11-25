// Golfers' course map: POST …/where sends a group's spot and returns where the other groups are (no codes), only
// on the tournament day, without hidden groups, and with your own group marked me.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/where.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const { id, key } = await post('/golf/api/new', { name: 'Where test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
const today = new Date(Date.now() - 6 * 3600000).toISOString().slice(0, 10); // inside the 04:00–11:00 UTC (+1 day) window
const cur = await desk('get');
const teams = [1, 2, 3].map((i) => ({ id: `team${i}`, name: `Team ${i}`, start: i, players: [{ id: `p${i}`, name: `Player ${i}`, hcp: 10 }] }));
await desk('save', { setup: { ...cur, date: today, teams } });
const got = await desk('get');
const code = (tid) => got.teams.find((t) => t.id === tid).code;
const where = (tid, b = {}) => call(`/golf/api/${id}/where`, { code: code(tid), team: tid, ...b });

{
  const { status } = await call(`/golf/api/${id}/where`, { code: 'ZZZZZZ', team: 'team1' });
  assert.equal(status, 403); ok('a wrong cart code sees nothing');
}
let r = await where('team1', { at: [33.0, -117.0], acc: 5, hole: 3 });
assert.equal(r.status, 200); assert.equal(r.j.groups.length, 1); assert.equal(r.j.groups[0].me, true);
ok('your own group comes back marked me');

await where('team2', { at: [33.001, -117.001], acc: 4, hole: 5 });
r = await where('team3'); // just looking, no spot of its own
assert.equal(r.status, 200);
assert.deepEqual(r.j.groups.map((g) => g.team).sort(), ['team1', 'team2']);
assert.ok(r.j.groups.every((g) => !g.code && !('code' in g)));
assert.equal(r.j.groups.find((g) => g.team === 'team2').hole, 5);
ok('a group sees the others, with holes and no codes, without sending a spot');

await where('team2', { hide: true });
r = await where('team3');
assert.deepEqual(r.j.groups.map((g) => g.team), ['team1']);
r = await where('team2');
assert.equal(r.j.hide, true); assert.equal(r.j.groups.find((g) => g.team === 'team2').me, true);
const dg = await desk('groups');
assert.ok(dg.groups.some((g) => g.team === 'team2'));
ok('a hidden group is left out for golfers, still sees itself, and the desk still sees it');

await where('team2', { at: [33.002, -117.002], hole: 6 }); // hide is kept on new spots
r = await where('team1'); assert.ok(!r.j.groups.some((g) => g.team === 'team2'));
await where('team2', { hide: false });
r = await where('team1'); assert.ok(r.j.groups.some((g) => g.team === 'team2' && g.hole === 6));
ok('hiding sticks until the group shows itself again');

{
  const { status } = await where('team1', { at: [999, 0] });
  assert.equal(status, 400); ok('a bad spot is refused');
}
await desk('lock', { locked: true });
r = await where('team1');
assert.equal(r.status, 409); assert.deepEqual(r.j.groups, []);
ok('results final: nobody sees any group');
