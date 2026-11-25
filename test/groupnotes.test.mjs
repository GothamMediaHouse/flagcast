// Tapping a group on the course map: golfers send ready-made notes to another group (one a minute, the desk can
// turn them off), and each group's spot says since when it's been on its hole.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/groupnotes.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const { id, key } = await post('/golf/api/new', { name: 'Notes test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
const today = new Date(Date.now() - 6 * 3600000).toISOString().slice(0, 10);
const cur = await desk('get');
const teams = [1, 2].map((i) => ({ id: `team${i}`, name: `Team ${i}`, start: i, players: [{ id: `p${i}`, name: `Player ${i}`, hcp: 10 }] }));
await desk('save', { setup: { ...cur, date: today, teams } });
const got = await desk('get');
const code = (tid) => got.teams.find((t) => t.id === tid).code;
const where = (tid, b = {}) => call(`/golf/api/${id}/where`, { code: code(tid), team: tid, ...b });
const state = async () => (await fetch(`${BASE}/golf/api/${id}/state`)).json();

let r = await where('team1', { at: [33, -117], hole: 3 });
assert.ok(r.j.notes.length >= 3); ok('the ready-made notes come with the groups');
const since = r.j.groups[0].since;
r = await where('team1', { at: [33.0005, -117], hole: 3 });
assert.equal(r.j.groups[0].since, since); ok('since stays while the group is on the same hole');
r = await where('team1', { at: [33.001, -117], hole: 4 });
assert.ok(r.j.groups[0].since >= since); ok('since starts again on a new hole');

r = await where('team1', { note: 1, to: 'team2' });
assert.equal(r.status, 200); assert.equal(r.j.sent, true);
let s = await state(); const nd = s.nudges.at(-1);
assert.equal(nd.team, 'team2'); assert.equal(nd.from, 'Team 1'); assert.equal(nd.text, r.j.notes[1]);
ok('a note lands as a nudge to that group, with who sent it');
r = await where('team1', { note: 0, to: 'team2' }); assert.equal(r.status, 429); ok('one note a minute');
r = await where('team2', { note: 99, to: 'team1' }); assert.equal(r.status, 400); ok('only the ready-made notes');
r = await where('team2', { note: 0, to: 'team2' }); assert.equal(r.status, 400); ok('not to your own group');
r = await where('team2', { note: 0, to: 'nobody' }); assert.equal(r.status, 404); ok('no such group');

await desk('notes', { off: true });
s = await state(); assert.equal(s.notesOff, true);
r = await where('team2', { note: 0, to: 'team1' }); assert.equal(r.status, 403);
r = await where('team2'); assert.deepEqual(r.j.notes, []);
ok('the desk turns golfer notes off');
await desk('notes', { off: false });
r = await where('team2', { note: 0, to: 'team1' }); assert.equal(r.status, 200); ok('and back on');

const g = await desk('groups'); assert.ok(g.groups.find((x) => x.team === 'team1').since); ok('the desk sees since');
