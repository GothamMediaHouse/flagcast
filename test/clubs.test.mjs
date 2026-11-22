// Each club sees only its own tournaments; only Flagcast staff see every club's.
//   npx wrangler dev --var GOLF_CREATE_PASS:test-pass --var ADMIN_EMAIL:staff@example.com
//   node test/clubs.test.mjs http://127.0.0.1:8787 test-pass staff@example.com
// (local only: needs no email key, so sign-in codes come back in the answer)
import assert from 'node:assert/strict';

const [BASE, PASS, STAFF] = process.argv.slice(2);
if (!BASE || !PASS || !STAFF) { console.log('usage: node test/clubs.test.mjs <local server> <GOLF_CREATE_PASS> <ADMIN_EMAIL>'); process.exit(1); }
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const post = async (path, body) => { const r = await fetch(`${BASE}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
const club = (op, body) => post(`/golf/api/club/${op}`, body);
const signIn = async (email) => {
  const s = await club('start', { email }); assert.ok(s.j.devCode, 'local dev gives the code back');
  const v = await club('verify', { email, code: s.j.devCode }); assert.ok(v.j.token); return v.j.token;
};

const t = Date.now(), aEmail = `a-${t}@example.com`, bEmail = `b-${t}@example.com`;
// two clubs, made by Flagcast with the passcode
let r = await club('admin', { pass: PASS, op: 'create', name: `Club A ${t}`, email: aEmail, credits: -1 }); assert.equal(r.status, 200); const aId = r.j.made.club;
r = await club('admin', { pass: PASS, op: 'create', name: `Club B ${t}`, email: bEmail, credits: -1 }); assert.equal(r.status, 200); const bId = r.j.made.club;
const a = await signIn(aEmail), b = await signIn(bEmail);
r = await post('/golf/api/new', { token: a, name: `A open ${t}` }); assert.equal(r.status, 200); const aEv = r.j.id;
r = await post('/golf/api/new', { token: b, name: `B open ${t}` }); assert.equal(r.status, 200); const bEv = r.j.id;
ok('two clubs, one tournament each');

r = await club('me', { token: a }); assert.equal(r.j.club.id, aId); assert.deepEqual(r.j.events.map((e) => e.id), [aEv]); assert.equal(r.j.admin, false);
r = await club('me', { token: b }); assert.equal(r.j.club.id, bId); assert.deepEqual(r.j.events.map((e) => e.id), [bEv]);
ok('each club’s list has only its own tournament');

for (const op of [undefined, 'events', 'log', 'day']) {
  r = await club('admin', { token: a, ...(op ? { op } : {}), id: bEv }); assert.equal(r.status, 403, `club token, admin op ${op}`);
}
r = await club('admin', { token: a, pass: 'wrong', op: 'events' }); assert.equal(r.status, 403);
r = await post('/golf/api/new', { token: a, pass: 'wrong', name: 'x', club: bId }); assert.equal(r.status, 403);
ok('a club’s sign-in can’t open Admin (every club’s list, Event day, the log, screens) or make for another club');

r = await club('hide', { token: a, id: bEv }); assert.equal(r.status, 200);
r = await club('me', { token: b }); assert.deepEqual(r.j.events.map((e) => e.id), [bEv]);
r = await post(`/golf/api/${bEv}/desk`, { op: 'get', key: '' }); assert.notEqual(r.status, 200);
ok('a club can’t hide another club’s tournament, and a desk needs its key');

const staff = await signIn(STAFF);
r = await club('me', { token: staff }); assert.equal(r.j.admin, true);
r = await club('admin', { token: staff, op: 'events' }); assert.equal(r.status, 200);
const ids = r.j.events.map((e) => e.id); assert.ok(ids.includes(aEv) && ids.includes(bEv));
r = await club('admin', { pass: PASS, op: 'events' }); assert.equal(r.status, 200); assert.ok(r.j.events.some((e) => e.id === bEv));
ok('Flagcast staff (ADMIN_EMAIL sign-in or the passcode) still see every club’s tournaments');

console.log(`\n${n} passed`);
