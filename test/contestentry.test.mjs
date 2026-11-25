// Golfers enter their own long drive / closest to the pin; pros check them. Run against `npx wrangler dev`:
//   node test/contestentry.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();

const { id, key } = await post('/golf/api/new', { name: 'Contest entry test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
const cur = await desk('get');
await desk('save', { setup: { ...cur, pins: [{ name: 'Pro', role: 'pro', pin: '654321' }, { name: 'Marshal', role: 'marshal', pin: '876543' }],
  teams: [{ name: 'Smith', players: [{ name: 'Al Smith', hcp: 10 }, { name: 'Bo Smith', hcp: 12 }] }, { name: 'Jones', players: [{ name: 'Cy Jones', hcp: 5 }, { name: 'Di Jones' }, { name: 'Ed Jones' }, { name: 'Fi Jones' }] }],
  contests: [{ id: 'ld7', kind: 'ld', hole: 7, sponsor: 'Harbor Bank' }, { id: 'ctp12', kind: 'ctp', hole: 12, check: 'none' }, { id: 'staff3', kind: 'ctp', hole: 3, self: false }] } });
const full = await desk('get');
const [A, B] = full.teams;
const enter = (t, b) => call(`/golf/api/${id}/enter`, { code: t.code, team: t.id, ...b });

let s = await state(id);
assert.deepEqual(s.contests.map((c) => [c.id, c.self, c.check, c.prize]), [['ld7', true, 'top', 0], ['ctp12', true, 'none', 0], ['staff3', false, 'top', 0]]);
ok('contests: golfers enter their own by default, top 3 checked, no prize');

assert.equal((await enter(A, { contest: 'ld7', player: A.players[0].id, dist: 280, code: 'WRONG1' })).status, 403);
assert.equal((await enter(A, { contest: 'ld7', player: B.players[0].id, dist: 280 })).status, 400);
assert.equal((await enter(A, { contest: 'staff3', player: A.players[0].id, dist: 4 })).status, 403);
assert.equal((await enter(A, { contest: 'ld7', player: A.players[0].id, dist: 600 })).status, 400);
assert.equal((await enter(A, { contest: 'ctp12', player: A.players[0].id, dist: 250 })).status, 400);
ok('refused: wrong code, a player from another cart, a staff-only contest, silly distances');

let r = await enter(A, { contest: 'ld7', player: A.players[0].id, dist: 280 });
assert.equal(r.status, 200); assert.equal(r.j.entry.ok, false); assert.equal(r.j.entry.by, 'golfer');
r = await enter(A, { contest: 'ld7', player: A.players[0].id, dist: 285 });
s = await state(id);
assert.deepEqual(s.contests[0].entries.map((e) => [e.name, e.dist, e.ok]), [['Al Smith', 285, false]]);
ok('a golfer’s drive waits for a check (top 3), and sending again replaces it');

for (const [i, d] of [[0, 300], [1, 295], [2, 290]]) await enter(B, { contest: 'ld7', player: B.players[i].id, dist: d });
r = await enter(B, { contest: 'ld7', player: B.players[3].id, dist: 200 });
assert.equal(r.j.entry.ok, true); ok('a drive outside the top 3 goes straight up');

r = await enter(A, { contest: 'ctp12', player: A.players[1].id, dist: 4.25 });
assert.equal(r.j.entry.ok, true); ok('trust golfers: no check');

await post(`/golf/api/${id}/pro`, { pin: '876543', op: 'check', id: 'ld7', name: 'Al Smith', do: 'ok' });
await post(`/golf/api/${id}/pro`, { pin: '654321', op: 'check', id: 'ld7', name: 'Cy Jones', do: 'change', dist: 260 });
await post(`/golf/api/${id}/pro`, { pin: '654321', op: 'check', id: 'ld7', name: 'Di Jones', do: 'remove' });
s = await state(id);
const ld = s.contests[0];
assert.deepEqual(ld.entries.map((e) => [e.name, e.dist, e.ok, e.okBy || '']), [['Al Smith', 285, true, 'Marshal'], ['Cy Jones', 260, true, 'Pro'], ['Ed Jones', 290, false, ''], ['Fi Jones', 200, true, '']]);
ok('a marshal OKs, the pro changes one and takes one off');

assert.equal((await enter(A, { contest: 'ld7', player: A.players[0].id, dist: 320 })).status, 409); ok('a checked entry is locked for the golfer');

// a Save made from an older copy (no entries, no settings) keeps the results and the settings
await desk('save', { setup: { ...full, contests: [{ id: 'ld7', kind: 'ld', hole: 7, label: 'Big drive' }, { id: 'ctp12', kind: 'ctp', hole: 12 }, { id: 'new1', kind: 'ld', hole: 1, entries: [{ name: 'X', dist: 1 }] }] } });
s = await state(id);
assert.equal(s.contests[0].label, 'Big drive'); assert.equal(s.contests[0].entries.length, 4); assert.equal(s.contests[1].check, 'none');
assert.deepEqual(s.contests[2].entries, []); ok('a Save keeps results and settings it didn’t send; a new contest starts empty');

// the desk's results list (older Managers): unchanged entries keep their check, a new one counts at once
await desk('contest', { id: 'ld7', entries: s.contests[0].entries.filter((e) => e.name !== 'Fi Jones').map(({ name, dist }) => ({ name, dist })).concat([{ name: 'Gus', dist: 240 }]) });
s = await state(id);
assert.deepEqual(s.contests[0].entries.map((e) => [e.name, e.ok]), [['Al Smith', true], ['Cy Jones', true], ['Ed Jones', false], ['Gus', true]]);
ok('the desk’s results list keeps checks');

// GPS drive: yards from the hole's tee on the course map
await desk('map', { map: { holes: { 1: { tee: [40.0, -74.0], m: [40.004, -74.0] } } } });
r = await enter(A, { contest: 'new1', player: A.players[1].id, at: [40.0024, -74.0] });
assert.equal(r.status, 200); assert.ok(Math.abs(r.j.entry.dist - 292) <= 2, r.j.entry.dist); assert.equal(r.j.entry.gps, r.j.entry.dist);
r = await enter(A, { contest: 'new1', player: A.players[1].id, dist: 330, at: [40.0024, -74.0] });
assert.equal(r.j.entry.dist, 330); assert.ok(r.j.entry.gps > 280 && r.j.entry.gps < 300);
const st = await desk('stats');
assert.ok(st.clog.some((x) => x.did === 'golfer' && x.gps)); assert.ok(st.clog.some((x) => x.did === 'remove' && x.by === 'Pro'));
assert.equal((await state(id)).clog, undefined);
ok('a GPS drive is measured from the tee; typed ones keep the GPS number beside them; the desk sees the log, golfers don’t');

await desk('lock', { locked: true });
assert.equal((await enter(A, { contest: 'ctp12', player: A.players[0].id, dist: 3 })).status, 423); ok('no entries once the results are final');
