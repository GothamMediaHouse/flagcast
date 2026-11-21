// Screens: where/group per screen, Send now (one, a group's list, every screen), timed sends that end on their own, scenes.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/screens.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const post = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json(); if (!r.ok) throw new Error(`${path} ${r.status} ${JSON.stringify(j)}`); return j;
};
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);

const ev = await post('/golf/api/new', { name: 'Screens test', pass: 'local' });
const { id, key } = ev; assert.ok(id && key);
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });

const got = await desk('get');
const displays = [
  { id: 'bar01', name: 'Bar', where: 'Clubhouse bar, over the taps', group: 'Clubhouse', playlist: [{ k: 'lb', secs: 10 }, { k: 'sponsors', secs: 8 }] },
  { id: 'pro01', name: 'Pro shop', where: 'Pro shop door', group: 'Clubhouse', playlist: [{ k: 'lb', secs: 10 }] },
  { id: 'tee01', name: '10th tee', where: 'x'.repeat(60), group: 'Course and a long group name here', playlist: [] },
];
await desk('save', { setup: { ...got, displays } });
let s = await state(id);
assert.equal(s.displays[0].where, 'Clubhouse bar, over the taps'); assert.equal(s.displays[0].group, 'Clubhouse');
assert.equal(s.displays[2].where.length, 40); assert.equal(s.displays[2].group.length, 24);
ok('where and group are kept and clipped (40 / 24)');

await desk('screen', { display: 'bar01', page: { k: 'skins' } });
s = await state(id);
assert.equal(s.live.force.bar01.k, 'skins'); assert.equal(s.live.force.bar01.until, undefined);
ok('Send now until I change it: no until');

await desk('screen', { display: ['bar01', 'pro01'], page: { k: 'lb', fl: 'A' }, mins: 15 });
s = await state(id);
for (const d of ['bar01', 'pro01']) { const f = s.live.force[d]; assert.equal(f.k, 'lb'); assert.equal(f.fl, 'A'); assert.ok(Math.abs(f.until - f.at - 15 * 60000) < 5); }
assert.equal(s.live.force.tee01, undefined);
ok('Send now to a group (a list of screens) for 15 minutes sets until');

await desk('screen', { display: '*', page: { k: 'fund' }, mins: 9999 });
s = await state(id);
assert.equal(Object.keys(s.live.force).length, 3); assert.ok(s.live.force.tee01.until - s.live.force.tee01.at <= 600 * 60000);
ok('every screen; minutes are capped at 600');

await desk('scene', { save: 'Lunch' });
await desk('screen', { display: 'bar01', page: { k: 'contests' }, mins: 0.05 });  // 3 seconds
s = await state(id); assert.equal(s.live.force.bar01.k, 'contests'); assert.ok(s.live.force.bar01.until);
await sleep(3500);
await desk('flash', { text: '' }); // any later change drops the expired send
s = await state(id);
assert.equal(s.live.force.bar01, undefined); assert.equal(s.live.force.pro01.k, 'fund');
ok('a timed send is dropped on the next change once it is over; the others stay');

await desk('scene', { apply: (await desk('get')).scenes.find((x) => x.name === 'Lunch').id });
s = await state(id);
assert.equal(s.live.force.bar01.k, 'fund'); assert.equal(s.live.force.bar01.until, undefined);
ok('scenes save the page, not the timer');

await desk('screen', { display: 'pro01', page: null });
s = await state(id); assert.equal(s.live.force.pro01, undefined);
ok('back to its playlist');

// ---- par 3 camera links: Flagcast staff only ----
{
  const cur = await desk('get');
  const p3 = cur.course.holes.find((h) => h.par === 3)?.n || 3;
  await desk('save', { setup: { ...cur, cams: { [p3]: 'https://evil.example/club.m3u8' } } });
  let st = await state(id);
  assert.equal(st.cams[p3], undefined);
  ok('a club desk save can’t set camera links');
  // the admin op (local dev: no GOLF_CREATE_PASS, so the local passcode check lets it in)
  const r = await post('/golf/api/club/admin', { pass: 'local', op: 'cams', id, cams: { [p3]: 'https://cams.example/hole.m3u8', 99: 'https://x', 0: 'https://y', [p3 === 1 ? 2 : 1]: 'http://not-https' } });
  st = await state(id);
  assert.equal(st.cams[p3], 'https://cams.example/hole.m3u8', JSON.stringify({ p3, r, cams: st.cams })); assert.equal(Object.keys(st.cams).length, 1);
  ok('Admin sets camera links (https only, real holes)');
  await desk('save', { setup: { ...(await desk('get')), cams: {} } });
  st = await state(id); assert.equal(st.cams[p3], 'https://cams.example/hole.m3u8');
  ok('a later club save keeps Flagcast’s camera links');
}

console.log(`\n${n} passed`);
