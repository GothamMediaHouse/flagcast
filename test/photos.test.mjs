// Photos a club adds for its golfers (brand.js, golf.js op 'photo'): a cover photo, hole photos and sponsor banners.
//   node test/photos.test.mjs                                   unit tests, no server needed
//   node test/photos.test.mjs http://127.0.0.1:8797 test-pass   plus the API on `npx wrangler dev`
import assert from 'node:assert/strict';
import { cleanPhoto, photoLinks, PHOTO_SLOT, PHOTO_MAX } from '../brand.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/eL9GtQAAAABJRU5ErkJggg==';
const JPG = 'data:image/jpeg;base64,' + Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 16, 74, 70, 73, 70, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0xff, 0xd9]).toString('base64');
const SVG = 'data:image/svg+xml;base64,' + Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>').toString('base64');

assert.equal(cleanPhoto(PNG).type, 'image/png'); assert.equal(cleanPhoto(JPG).type, 'image/jpeg');
assert.notEqual(cleanPhoto(PNG).v, cleanPhoto(JPG).v);
assert.throws(() => cleanPhoto(SVG), /JPEG or PNG/);
assert.throws(() => cleanPhoto('data:image/jpeg;base64,' + Buffer.from('not a jpeg at all').toString('base64')), /isn’t the photo/);
assert.throws(() => cleanPhoto('data:image/jpeg;base64,' + 'A'.repeat(PHOTO_MAX)), /too big/);
ok('photos: JPEG, PNG or WebP only; SVG, fakes and big files are refused');

for (const k of ['cover', 'h1', 'h18', 's-abc12']) assert.ok(PHOTO_SLOT.test(k), k);
for (const k of ['h0', 'h19', 'x', 's-', 'cover2', 'state']) assert.ok(!PHOTO_SLOT.test(k), k);
const links = photoLinks({ id: 'abcd2345', sponsors: [{ id: 'sp1' }], photos: { cover: 'v1', h7: 'v2', 's-sp1': 'v3', 's-gone': 'v4' } });
assert.deepEqual(links, { cover: '/golf/api/abcd2345/photo/cover?v=v1', holes: { 7: '/golf/api/abcd2345/photo/h7?v=v2' }, sponsors: { sp1: '/golf/api/abcd2345/photo/s-sp1?v=v3' } });
assert.deepEqual(photoLinks({ id: 'abcd2345' }), { cover: '', holes: {}, sponsors: {} });
ok('photo spots: cover, holes 1 to 18, sponsors still in the tournament');

const BASE = process.argv[2], PASS = process.argv[3] || 'test-pass';
if (BASE) {
  const post = async (path, body) => { const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
  const made = await post('/golf/api/new', { pass: PASS, name: 'Photo test' });
  assert.equal(made.status, 200, JSON.stringify(made.j)); const { id, key } = made.j;
  const desk = (b) => post(`/golf/api/${id}/desk`, { key, ...b });
  const state = async () => (await fetch(`${BASE}/golf/api/${id}/state`)).json();

  let s = await state(); assert.deepEqual(s.photos, { cover: '', holes: {}, sponsors: {} });
  let r = await desk({ op: 'photo', slot: 'cover', image: JPG }); assert.equal(r.status, 200, JSON.stringify(r.j));
  r = await desk({ op: 'photo', slot: 'h7', image: PNG }); assert.equal(r.status, 200);
  s = await state(); assert.ok(s.photos.cover.startsWith(`/golf/api/${id}/photo/cover?v=`)); assert.ok(s.photos.holes[7]);
  let img = await fetch(BASE + s.photos.cover); assert.equal(img.status, 200); assert.equal(img.headers.get('content-type'), 'image/jpeg');
  assert.equal(Buffer.from(await img.arrayBuffer()).toString('base64'), JPG.split(',')[1]);
  ok('the desk adds a cover and a hole photo; golfers load them by address');

  assert.equal((await post(`/golf/api/${id}/desk`, { key: 'wrong', op: 'photo', slot: 'cover', image: JPG })).status, 403);
  assert.equal((await desk({ op: 'photo', slot: 'h19', image: JPG })).status, 400);
  assert.equal((await desk({ op: 'photo', slot: 'cover', image: SVG })).status, 400);
  assert.equal((await fetch(`${BASE}/golf/api/${id}/photo/h3`)).status, 404);
  assert.equal((await fetch(`${BASE}/golf/api/${id}/photo/cover`, { method: 'POST' })).status, 405);
  ok('a wrong desk key, a wrong spot, an SVG and a missing photo are refused');

  const setup = (await desk({ op: 'get' })).j;
  r = await desk({ op: 'save', setup: { ...setup, sponsors: [{ id: 'sp1', name: 'Bank', spot: 'title' }] } }); assert.equal(r.status, 200);
  r = await desk({ op: 'photo', slot: 's-sp1', image: JPG }); assert.ok(r.j.photos.sponsors.sp1);
  s = await state(); assert.ok(s.photos.sponsors.sp1);
  r = await desk({ op: 'save', setup: { ...setup, sponsors: [] } }); assert.deepEqual(r.j.photos.sponsors, {});
  assert.equal((await desk({ op: 'get' })).j.photos.cover, s.photos.cover); // saving the setup keeps the photos
  ok('a sponsor banner shows while the sponsor is in; removing the sponsor removes it; saving keeps the rest');

  r = await desk({ op: 'photo', slot: 'cover', image: '' }); assert.equal(r.j.photos.cover, '');
  assert.equal((await fetch(BASE + s.photos.cover)).status, 404);
  ok('taking a photo off');
}
console.log(`1..${n}`);
