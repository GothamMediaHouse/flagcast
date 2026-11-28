// Privacy on a real local server: a junior event and a group that stays off camera, the daily tidy (spots wiped after
// the day, emails gone after 90 days, deleted tournaments wiped after 30), and deleting one person's details.
//   npx wrangler dev --var GOLF_CREATE_PASS:test-pass --var ADMIN_EMAIL:staff@example.com
//   node test/privacyserver.test.mjs http://127.0.0.1:8787 test-pass
import assert from 'node:assert/strict';

const [BASE, PASS] = process.argv.slice(2);
if (!BASE || !PASS) { console.log('usage: node test/privacyserver.test.mjs <local server> <GOLF_CREATE_PASS>'); process.exit(1); }
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const post = async (path, body) => { const r = await fetch(`${BASE}${path}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
const admin = (b) => post('/golf/api/club/admin', { pass: PASS, ...b });
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
const DAY = 86400000;

const t = Date.now(), email = `privacy-${t}@example.com`;
assert.equal((await admin({ op: 'create', name: `Privacy club ${t}`, email, credits: -1 })).status, 200);
const s = await post('/golf/api/club/start', { email }); const token = (await post('/golf/api/club/verify', { email, code: s.j.devCode })).j.token;
const today = new Date(Date.now() - 6 * 3600000).toISOString().slice(0, 10);
const mk = async (name) => {
  const e = (await post('/golf/api/new', { token, name })).j;
  const desk = async (op, b = {}) => (await post(`/golf/api/${e.id}/desk`, { key: e.key, op, ...b }));
  const cur = (await desk('get')).j;
  const teams = [1, 2].map((i) => ({ id: `team${i}`, name: `Team ${i}`, start: i, players: [{ id: `p${i}`, name: `Player ${i}${t}`, hcp: 10, email: `p${i}-${t}@example.com`, ghin: '1234567' }] }));
  assert.equal((await desk('save', { setup: { ...cur, date: today, teams } })).status, 200);
  const got = (await desk('get')).j;
  const code = (tid) => got.teams.find((x) => x.id === tid).code;
  return { ...e, desk, code };
};

// ---- a junior event
const a = await mk(`Junior ${t}`);
assert.equal((await a.desk('privacy', { junior: true })).status, 200);
let st = await state(a.id);
assert.equal(st.junior, true); assert.equal(st.clipsOff, true); assert.equal(st.notesOff, true); assert.equal(st.everyoneOff, true);
await post(`/golf/api/${a.id}/where`, { code: a.code('team2'), team: 'team2', at: [33, -117], acc: 5, hole: 2 });
let r = await post(`/golf/api/${a.id}/where`, { code: a.code('team1'), team: 'team1', at: [33.001, -117], acc: 5, hole: 1 });
assert.equal(r.status, 200); assert.deepEqual(r.j.groups.map((g) => g.team), ['team1']); assert.equal(r.j.everyoneOff, true); assert.deepEqual(r.j.notes, []);
r = await a.desk('groups'); assert.equal(r.j.groups.length, 2); // the desk still sees both, for pace of play
r = await a.desk('invite', { send: 'new' }); assert.equal(r.status, 403); assert.match(r.j.error, /junior/);
ok('a junior event: golfers see only their own group, no notes, no saved shots, no invite emails; the desk sees everyone');
assert.equal((await a.desk('privacy', { junior: false })).status, 200);
st = await state(a.id); assert.ok(!st.junior); assert.ok(!st.clipsOff);
ok('turning junior off puts it all back');

// ---- a group that asked to stay off camera
assert.equal((await a.desk('privacy', { team: 'team1', nocam: true })).status, 200);
st = await state(a.id); assert.deepEqual(st.nocam, ['team1']);
assert.equal((await a.desk('privacy', { team: 'nope', nocam: true })).status, 404);
assert.equal((await a.desk('privacy', { team: 'team1', nocam: false })).status, 200);
st = await state(a.id); assert.equal(st.nocam, undefined);
ok('the desk can keep a group off camera, and take that off again');

// ---- the daily tidy
r = await admin({ op: 'tidy' }); assert.equal(r.status, 200); assert.ok(r.j.tournaments >= 1);
r = await a.desk('groups'); assert.equal(r.j.groups.length, 2); // still today: spots stay
r = await admin({ op: 'tidy', now: Date.now() + 2 * DAY }); assert.equal(r.status, 200);
r = await a.desk('groups'); assert.equal(r.j.on, true); assert.equal(r.j.groups.length, 0);
ok('the tidy leaves today’s group spots, and wipes them once the day is over');

r = await a.desk('get'); assert.equal(r.j.teams[0].players[0].email, `p1-${t}@example.com`);
r = await admin({ op: 'tidy', now: Date.now() + 95 * DAY }); assert.ok(r.j.personal >= 1);
r = await a.desk('get'); assert.equal(r.j.teams[0].players[0].email, ''); assert.equal(r.j.teams[0].players[0].ghin, ''); assert.equal(r.j.teams[0].players[0].name, `Player 1${t}`);
ok('90 days after the tournament its emails and GHIN numbers are gone, names stay');

// ---- a club deletes a tournament: gone for good 30 days later, unless it's shown again
const b = await mk(`Deleted ${t}`), c = await mk(`Undone ${t}`);
assert.equal((await post('/golf/api/club/hide', { token, id: b.id })).status, 200);
assert.equal((await post('/golf/api/club/hide', { token, id: c.id })).status, 200);
assert.equal((await admin({ op: 'unhide', id: c.id })).status, 200);
r = await admin({ op: 'tidy', now: Date.now() + 10 * DAY }); assert.equal((await post(`/golf/api/${b.id}/desk`, { key: b.key, op: 'get' })).status, 200);
r = await admin({ op: 'tidy', now: Date.now() + 31 * DAY }); assert.ok(r.j.erased >= 1);
assert.equal((await post(`/golf/api/${b.id}/desk`, { key: b.key, op: 'get' })).status, 404);
assert.equal((await post(`/golf/api/${c.id}/desk`, { key: c.key, op: 'get' })).status, 200);
ok('a deleted tournament is wiped for good 30 days later; one shown again stays');

// ---- delete one person's details
r = await admin({ op: 'forget', q: `Player 2${t}` });
assert.equal(r.status, 200); assert.equal(r.j.applied, false);
assert.deepEqual(r.j.tournaments.map((x) => x.id).sort(), [a.id, c.id].sort());
r = await admin({ op: 'forget', q: `p2-${t}@example.com`, apply: true }); // c still has the email (a's went after 90 days)
assert.deepEqual(r.j.tournaments.map((x) => x.id), [c.id]);
r = await c.desk('get'); assert.equal(r.j.teams[1].players[0].name, 'Removed player'); assert.equal(r.j.teams[1].players[0].email, '');
r = await admin({ op: 'forget', q: 'ab' }); assert.equal(r.status, 400);
ok('Admin finds a person by full name or email in every tournament, and removes their details');

console.log(`\n${n} passed`);
