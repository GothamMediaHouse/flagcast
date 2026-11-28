// Can go live (Admin → Staff): a club's pro or a volunteer, signed in with their email, may go live on a hole of the
// tournaments Flagcast picked for them (any, one club's, or one), and nothing else. Admin can take it off at once.
// Run against the same server as golive.test (Cloudflare Stream stand-in on 8793, no Admin passcode on this computer):
//   node test/golivestaff.test.mjs [http://127.0.0.1:8787] [8793]   (npm test does all of that)
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const MOCK_PORT = Number(process.argv[3] || 8793);
const inputs = {}; let made = 0;
const mock = createServer((req, res) => {
  let body = ''; req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const send = (o, status = 200) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    const m = req.url.match(/^\/accounts\/acc\/stream\/live_inputs(?:\/([0-9a-f]{32}))?$/);
    if (!m || req.headers.authorization !== 'Bearer tok') return send({ success: false, errors: [{ message: 'no' }] }, 404);
    if (req.method === 'POST' && !m[1]) {
      const uid = String(++made).padStart(32, 'a');
      inputs[uid] = { uid, meta: JSON.parse(body).meta, rtmps: { url: 'rtmps://live.cloudflare.com:443/live/', streamKey: `k${uid}` }, srt: { url: 'srt://live.cloudflare.com:778', streamId: `s${uid}`, passphrase: `p${uid}` } };
      return send({ success: true, result: inputs[uid] });
    }
    if (req.method === 'GET' && inputs[m[1]]) return send({ success: true, result: { ...inputs[m[1]], status: { current: { state: 'disconnected' } } } });
    send({ success: false, errors: [{ message: 'no' }] }, 404);
  });
});
await new Promise((r) => mock.listen(MOCK_PORT, '127.0.0.1', r));

const post = async (path, body) => { const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
const club = (op, b) => post(`/golf/api/club/${op}`, b);
const admin = async (op, b = {}) => { const r = await club('admin', { pass: 'local', op, ...b }); assert.equal(r.status, 200, JSON.stringify(r.j)); return r.j; };
const signIn = async (email) => { const s = await club('start', { email }); const v = await club('verify', { email, code: s.j.devCode }); assert.ok(v.j.token, JSON.stringify(v.j)); return v.j.token; };
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

try {
  const t = Date.now(), cam = `jamie-${t}@example.com`;
  // two clubs, a tournament each (and an old one at club A that's over)
  const A = (await admin('create', { name: `Iron Horse ${t}`, email: `a-${t}@example.com`, credits: -1 })).made.club;
  const B = (await admin('create', { name: `Other ${t}`, email: `b-${t}@example.com`, credits: -1 })).made.club;
  const aEv = (await admin('event', { club: A, name: 'Member-Guest' })).made, bEv = (await admin('event', { club: B, name: 'Club Champs' })).made;
  const old = (await admin('event', { club: A, name: 'Last spring' })).made;
  const oldSetup = (await post(`/golf/api/${old.id}/desk`, { key: old.key, op: 'get' })).j;
  assert.equal((await post(`/golf/api/${old.id}/desk`, { key: old.key, op: 'save', setup: { ...oldSetup, date: '2025-04-12', rounds: [{ date: '2025-04-12' }] } })).status, 200);
  const tok = await signIn(cam);

  // before Flagcast switches it on: nothing, and not Admin
  let r = await club('me', { token: tok }); assert.equal(r.j.camera, false); assert.equal(r.j.admin, false);
  assert.equal((await club('cameras', { token: tok })).status, 403);
  assert.equal((await club('camera', { token: tok, id: aEv.id, hole: 7 })).status, 403);
  assert.equal((await club('cameras', {})).status, 401, 'signed in only');
  ok('someone signed in without Can go live can’t list or go live');

  // one tournament
  let j = await admin('golive-set', { email: cam, where: 'event', event: aEv.id, name: 'Jamie' });
  const row = j.golive.find((x) => x.email === cam);
  assert.equal(row.where, 'event'); assert.equal(row.event, aEv.id); assert.equal(row.eventName, 'Member-Guest'); assert.match(row.clubName, /^Iron Horse/); assert.equal(row.name, 'Jamie');
  assert.ok(!j.staff.some((x) => x.email === cam), 'not on the Admin list');
  r = await club('me', { token: tok }); assert.equal(r.j.camera, true); assert.equal(r.j.admin, false);
  r = await club('cameras', { token: tok }); assert.equal(r.status, 200);
  assert.deepEqual(r.j.events.map((e) => e.id), [aEv.id]); assert.equal(r.j.events[0].key, undefined, 'no desk key');
  assert.equal(r.j.events[0].holes.length, 18); assert.equal(r.j.events[0].name, 'Member-Guest');
  ok('Admin gives one tournament: it is the only one listed, without its desk key, and they still aren’t Admin');

  r = await club('camera', { token: tok, id: aEv.id, hole: 7 }); assert.equal(r.status, 200, JSON.stringify(r.j));
  assert.ok(r.j.srt && r.j.rtmps && r.j.playback);
  let s = await state(aEv.id); assert.equal(s.golive[7].by, 'Jamie'); assert.equal(s.cams[7], r.j.playback);
  r = await club('cameras', { token: tok }); assert.deepEqual(r.j.events[0].golive, { 7: 'Jamie' });
  assert.equal((await club('camera', { token: tok, id: bEv.id, hole: 7 })).status, 403, 'not the other club’s');
  assert.equal((await club('camera', { token: tok, id: aEv.id, hole: 40 })).status, 400);
  r = await club('camera', { token: tok, id: aEv.id, hole: 7, stop: true }); assert.equal(r.status, 200);
  s = await state(aEv.id); assert.equal(s.golive[7], undefined); assert.equal(s.cams[7], undefined);
  ok('they go live on hole 7 under their name, and stop; another club’s tournament is refused');

  // one club: its tournaments, but not the one that's over
  await admin('golive-set', { email: cam, where: 'club', club: A });
  r = await club('cameras', { token: tok }); assert.deepEqual(r.j.events.map((e) => e.id).sort(), [aEv.id].sort(), 'the old one is over');
  assert.equal((await club('camera', { token: tok, id: old.id, hole: 3 })).status, 403);
  assert.equal((await club('camera', { token: tok, id: bEv.id, hole: 3 })).status, 403);
  ok('one club: that club’s tournaments that aren’t over');

  // any tournament; then taken off: refused at once
  await admin('golive-set', { email: cam, where: 'any' });
  r = await club('cameras', { token: tok }); assert.ok(r.j.events.some((e) => e.id === bEv.id) && r.j.events.some((e) => e.id === aEv.id));
  assert.equal((await club('camera', { token: tok, id: bEv.id, hole: 0 })).status, 200);
  j = await admin('golive-remove', { email: cam }); assert.ok(!j.golive.some((x) => x.email === cam));
  assert.equal((await club('camera', { token: tok, id: bEv.id, hole: 0, stop: true })).status, 403, 'off means off, even to stop (the desk stops it)');
  r = await club('me', { token: tok }); assert.equal(r.j.camera, false);
  ok('any tournament works, and taking Can go live off refuses the next try');

  // bad input
  assert.equal((await club('admin', { pass: 'local', op: 'golive-set', email: 'nope', where: 'any' })).status, 400);
  assert.equal((await club('admin', { pass: 'local', op: 'golive-set', email: cam, where: 'event', event: 'zzzzzzzz' })).status, 400);
  assert.equal((await club('admin', { pass: 'local', op: 'golive-set', email: cam, where: 'moon' })).status, 400);
  ok('a bad email, a missing tournament or no “where” is refused');
} finally { mock.close(); }
