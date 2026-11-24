// Flagcast TV: pair a TV with a code from the Manager, it follows the club's tournament of the day, and removing it unpairs it.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/tv.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status >= 300) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const today = new Date().toISOString().slice(0, 10);

const admin = (op, b = {}) => post('/golf/api/club/admin', { pass: 'local', op, ...b });
const { made: { club } } = await admin('create', { name: `TV test club ${Date.now()}` });
const ev = (await admin('event', { club, name: 'TV Member-Guest' })).made, later = (await admin('event', { club, name: 'Next one' })).made;
const desk = (e, op, b = {}) => post(`/golf/api/${e.id}/desk`, { key: e.key, op, ...b });
const g = await desk(later, 'get'); await desk(later, 'save', { setup: { ...g, date: '2099-01-02' } });

// a new TV
const hi = await post('/golf/api/tv/hello', { kind: 'androidtv' });
assert.match(hi.code, /^[A-HJ-NP-Z2-9]{6}$/); assert.ok(hi.pair.length >= 24);
assert.equal((await post('/golf/api/tv/wait', { code: hi.code, pair: hi.pair })).waiting, true);
assert.equal((await call('/golf/api/tv/wait', { code: hi.code, pair: 'nope' })).status, 410);
ok('a new TV gets a code and waits');

assert.equal((await call('/golf/api/tv/add', { id: ev.id, key: 'wrong', code: hi.code, name: 'Bar' })).status, 403);
assert.equal((await call('/golf/api/tv/add', { id: ev.id, key: ev.key, code: 'ZZZZZZ', name: 'Bar' })).status, 404);
const add = await post('/golf/api/tv/add', { id: ev.id, key: ev.key, code: hi.code.toLowerCase(), name: 'Clubhouse bar', where: 'Over the taps' });
assert.equal(add.tvs.length, 1); assert.equal(add.tv.name, 'Clubhouse bar'); assert.equal(add.tv.kind, 'androidtv');
assert.equal((await call('/golf/api/tv/add', { id: ev.id, key: ev.key, code: hi.code, name: 'Again' })).status, 404);
ok('the Manager connects it with the desk key (a wrong key or code is refused, a code works once)');

const got = await post('/golf/api/tv/wait', { code: hi.code, pair: hi.pair });
assert.equal(got.tv, add.tv.id); assert.ok(got.token.length >= 32);
assert.equal((await call('/golf/api/tv/wait', { code: hi.code, pair: hi.pair })).status, 410);
ok('the TV gets its token once');

let now = await post('/golf/api/tv/now', { token: got.token, today });
assert.equal(now.event, null); assert.equal(now.next.name, 'Next one'); assert.equal(now.tv.name, 'Clubhouse bar');
assert.equal(now.club.flagcast, true); // no club logo yet
ok('no tournament today: the idle screen with the next one');

const g2 = await desk(ev, 'get'); await desk(ev, 'save', { setup: { ...g2, date: today } });
await new Promise((r) => setTimeout(r, 61000)); // the club's tournament list is kept for a minute
now = await post('/golf/api/tv/now', { token: got.token, today, feed: 1 });
assert.equal(now.event.id, ev.id); assert.ok(Array.isArray(now.feed.pages) && now.feed.pages.length);
let s = await (await fetch(`${BASE}/golf/api/${ev.id}/state`)).json();
const d = s.displays.find((x) => x.id === add.tv.id); assert.ok(d && d.tv); assert.equal(d.name, 'Clubhouse bar');
ok('today’s tournament: the TV joins its screens and gets the feed');

// a Manager that loaded the setup before the TV joined saves it: the TV stays
await desk(ev, 'save', { setup: { ...g2, date: today, displays: [] } });
s = await (await fetch(`${BASE}/golf/api/${ev.id}/state`)).json();
assert.ok(s.displays.some((x) => x.id === add.tv.id));
ok('an older setup saved over it keeps the TV');

await post('/golf/api/tv/edit', { id: ev.id, key: ev.key, tv: add.tv.id, name: 'Bar TV' });
s = await (await fetch(`${BASE}/golf/api/${ev.id}/state`)).json();
assert.equal(s.displays.find((x) => x.id === add.tv.id).name, 'Bar TV');
ok('renaming it renames its screen');

const list = await post('/golf/api/tv/list', { id: later.id, key: later.key });
assert.equal(list.tvs[0].on, true);
await post('/golf/api/tv/remove', { id: ev.id, key: ev.key, tv: add.tv.id });
assert.equal((await call('/golf/api/tv/now', { token: got.token, today })).status, 401);
s = await (await fetch(`${BASE}/golf/api/${ev.id}/state`)).json();
assert.ok(!s.displays.some((x) => x.id === add.tv.id));
ok('removing it unpairs the TV and takes it off the tournament');
