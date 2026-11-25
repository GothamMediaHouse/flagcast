// "Try a demo" in the player and TV apps: GET /golf/api/demo gives the newest tournament Admin marked Demo and its
// sample cart, so Apple's reviewers (who have no tournament code) can open it. A 1 on that cart is no hole-in-one.
//   npx wrangler dev --var GOLF_CREATE_PASS:test-pass --var ADMIN_EMAIL:staff@example.com
//   node test/trydemo.test.mjs http://127.0.0.1:8787 test-pass staff@example.com
import assert from 'node:assert/strict';

const [BASE, PASS] = process.argv.slice(2);
if (!BASE || !PASS) { console.log('usage: node test/trydemo.test.mjs <local server> <GOLF_CREATE_PASS>'); process.exit(1); }
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const post = async (path, body) => { const r = await fetch(`${BASE}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
const demo = async () => { const r = await fetch(`${BASE}/golf/api/demo`); return { status: r.status, j: await r.json().catch(() => ({})) }; };
const admin = (b) => post('/golf/api/club/admin', { pass: PASS, ...b });

const t = Date.now(), email = `demo-${t}@example.com`;
let r = await admin({ op: 'create', name: `Demo club ${t}`, email, credits: -1 }); assert.equal(r.status, 200);
const s = await post('/golf/api/club/start', { email }); const v = await post('/golf/api/club/verify', { email, code: s.j.devCode }); const token = v.j.token;
const mk = async (name) => {
  const e = (await post('/golf/api/new', { token, name })).j;
  const cur = (await post(`/golf/api/${e.id}/desk`, { key: e.key, op: 'get' })).j;
  const teams = [1, 2, 3].map((i) => ({ id: `team${i}`, name: `Team ${i}`, start: i, players: [{ id: `p${i}`, name: `Player ${i}`, hcp: 10 }] }));
  assert.equal((await post(`/golf/api/${e.id}/desk`, { key: e.key, op: 'save', setup: { ...cur, teams } })).status, 200);
  return e;
};
const a = await mk(`Demo A ${t}`), b = await mk(`Demo B ${t}`);

r = await demo(); assert.equal(r.status, 404); assert.match(r.j.error, /demo isn’t available/); ok('no Demo tournament: a plain message');

assert.equal((await admin({ op: 'demo', id: a.id, on: true })).status, 200);
r = await demo(); assert.equal(r.status, 200); assert.equal(r.j.id, a.id); assert.equal(r.j.name, `Demo A ${t}`); assert.equal(r.j.team, 'team3');
assert.match(r.j.code, /^[A-HJ-NP-Z2-9]{6}$/); ok('the marked Demo tournament and its last cart');
const code = r.j.code;
r = await post(`/golf/api/${a.id}/cart`, { code }); assert.deepEqual(r.j.teams, ['team3']); ok('the sample cart code opens that cart');

r = await post(`/golf/api/${a.id}/score`, { code, team: 'team3', list: [{ p: 'p3', h: 7, v: 1, at: Date.now() }, { p: 'p3', h: 1, v: 4, at: Date.now() }] });
assert.equal(r.status, 200);
let st = (await (await fetch(`${BASE}/golf/api/${a.id}/state`)).json());
assert.equal(st.scores.team3.p3[0], 4); assert.equal(st.scores.team3.p3[6], 1); assert.equal((st.aces || []).length, 0); ok('demo cart scores, and a 1 there is no hole-in-one take-over');

assert.equal((await admin({ op: 'demo', id: b.id, on: true })).status, 200);
r = await demo(); assert.equal(r.j.id, b.id); ok('the newest Demo tournament wins');
await admin({ op: 'archive', id: b.id, on: true });
r = await demo(); assert.equal(r.j.id, a.id); ok('an archived one is skipped');
await admin({ op: 'demo', id: a.id, on: false });
r = await demo(); assert.equal(r.status, 404); ok('Stop demo takes it off');

r = await post(`/golf/api/${a.id}/try`, {}); assert.notEqual(r.status, 200); assert.equal(r.j.code, undefined); ok('the sample cart lookup is not on the web');
