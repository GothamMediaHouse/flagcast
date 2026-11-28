// The Managers' TV page saves each TV at once (desk op tvset, no Save): add a link TV, change what it shows, take it off;
// a club TV keeps the name and place the club gave it, and can't be taken off here.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/tvset.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status >= 300) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const admin = (op, b = {}) => post('/golf/api/club/admin', { pass: 'local', op, ...b });
const { made: { club } } = await admin('create', { name: `TV page test club ${Date.now()}` });
const ev = (await admin('event', { club, name: 'TV page test' })).made;
const desk = (op, b = {}) => post(`/golf/api/${ev.id}/desk`, { key: ev.key, op, ...b });
const deskCall = (op, b = {}) => call(`/golf/api/${ev.id}/desk`, { key: ev.key, op, ...b });

const v0 = (await desk('get')).v || 0;
await desk('tvset', { display: { id: 'pro01', name: 'Pro shop', where: 'Pro shop', group: 'Pro shop', playlist: [{ k: 'lb', secs: 20 }, { k: 'nope' }] } });
let s = await state(ev.id);
assert.equal(s.displays.length, 1); assert.equal(s.displays[0].name, 'Pro shop'); assert.deepEqual(s.displays[0].playlist.map((p) => p.k), ['lb']);
assert.ok(((await desk('get')).v || 0) > v0, 'the version goes up, so an older copy saved later doesn’t look current');
ok('a new link TV is added at once (pages tidied)');

await desk('tvset', { display: { id: 'pro01', name: 'Pro shop TV', where: 'Pro shop', playlist: [{ k: 'p3', secs: 30 }], tv: true } });
s = await state(ev.id);
assert.equal(s.displays[0].name, 'Pro shop TV'); assert.equal(s.displays[0].playlist[0].k, 'p3'); assert.equal(s.displays[0].tv, undefined);
ok('changing it saves at once, and the desk can’t make it a club TV');

assert.equal((await deskCall('tvset', { display: { id: 'BAD ID', name: 'x' } })).status, 400);
assert.equal((await deskCall('tvset', {})).status, 400);
ok('a bad TV is refused');

// a club TV (paired with a code): its name and place come from the club
const hi = await post('/golf/api/tv/hello', { kind: 'appletv' });
const add = await post('/golf/api/tv/add', { id: ev.id, key: ev.key, code: hi.code, name: 'Bar', where: 'Clubhouse' });
const tv = add.tv.id;
await desk('tvset', { display: { id: tv, name: 'Renamed here', where: 'Somewhere', group: 'Clubhouse', playlist: [{ k: 'sponsors', secs: 10 }] } });
s = await state(ev.id);
const d = s.displays.find((x) => x.id === tv);
assert.equal(d.name, 'Bar'); assert.equal(d.where, 'Clubhouse'); assert.equal(d.tv, true); assert.equal(d.playlist[0].k, 'sponsors'); assert.equal(d.group, 'Clubhouse');
ok('a club TV’s pages change here; its name and place stay the club’s');

assert.equal((await deskCall('tvset', { remove: tv })).status, 409);
ok('a club TV can’t be taken off from one tournament');

await desk('screen', { display: 'pro01', page: { k: 'skins' } });
await desk('tvset', { remove: 'pro01' });
s = await state(ev.id);
assert.equal(s.displays.some((x) => x.id === 'pro01'), false); assert.equal(s.live.force.pro01, undefined);
await desk('tvset', { remove: 'pro01' }); // again: nothing to do
ok('a link TV is taken off, with what it was switched to');

// a Save from a copy loaded before keeps the club TV
const g = await desk('get');
await desk('save', { setup: { ...g, displays: [] } });
s = await state(ev.id);
assert.ok(s.displays.some((x) => x.id === tv));
ok('a Save without the club TV keeps it');

console.log(`\n${n} passed`);
