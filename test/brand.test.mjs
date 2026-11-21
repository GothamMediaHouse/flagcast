// Club branding (brand.js, clubs.js, golf.js): club logos instead of the Flagcast logo.
//   node test/brand.test.mjs                         unit tests, no server needed
//   node test/brand.test.mjs http://127.0.0.1:8787   plus the API on `npx wrangler dev` (local, no email key)
import assert from 'node:assert/strict';
import { cleanLogo, cleanAccent, brandFor, logoOf, logoVersion, decodeLogo, LOGO_MAX } from '../brand.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
// made-up logos: a 1×1 PNG, a plain SVG, and an SVG with a script in it
const PNG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/eL9GtQAAAABJRU5ErkJggg==';
const svg = (body) => `data:image/svg+xml;base64,${Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">${body}</svg>`).toString('base64')}`;
const SVG = svg('<circle cx="5" cy="5" r="4" fill="#1a6b3c"/>');

assert.equal(cleanLogo(PNG), PNG); assert.equal(cleanLogo(SVG), SVG); assert.equal(cleanLogo(''), ''); assert.equal(cleanLogo(null), '');
assert.throws(() => cleanLogo(svg('<script>alert(1)</script>')), /scripts or links/);
assert.throws(() => cleanLogo(svg('<rect onload="x()" width="1" height="1"/>')), /scripts or links/);
assert.throws(() => cleanLogo(svg('<image href="https://evil.example/x.png"/>')), /scripts or links/);
assert.throws(() => cleanLogo('data:image/png;base64,' + Buffer.from('GIF89a not a png').toString('base64')), /isn’t the image/);
assert.throws(() => cleanLogo('data:text/html;base64,PGgxPmhpPC9oMT4='), /PNG, JPEG, WebP or SVG/);
assert.throws(() => cleanLogo('https://example.com/logo.png'), /PNG, JPEG, WebP or SVG/);
assert.throws(() => cleanLogo('data:image/png;base64,' + 'A'.repeat(LOGO_MAX)), /too big/);
ok('logos: PNG/JPEG/WebP and plain SVG only; scripts, links, fakes and big files are refused');

assert.equal(cleanAccent('#1A6B3C'), '#1a6b3c'); assert.equal(cleanAccent('red'), ''); assert.equal(cleanAccent('#12345'), '');
assert.notEqual(logoVersion(PNG), logoVersion(SVG)); assert.equal(logoVersion(PNG), logoVersion(PNG));
ok('accent colours are #rrggbb; a new logo gets a new address');

const ev = { id: 'abcd2345', club: 'Demo Golf Club' };
assert.deepEqual(brandFor(ev), { logo: '', accent: '', demo: true, marked: false, powered: false, club: 'Demo Golf Club' });
assert.equal(logoOf(ev), null);
ok('no logo anywhere: the Flagcast logo (demo)');
const clubbed = { ...ev, clubBrand: { logo: PNG, accent: '#1a6b3c', powered: true } };
let b = brandFor(clubbed);
assert.equal(b.logo, `/golf/api/abcd2345/logo?v=${logoVersion(PNG)}`); assert.equal(b.demo, false); assert.equal(b.accent, '#1a6b3c'); assert.equal(b.powered, true);
assert.equal(logoOf(clubbed).type, 'image/png');
b = brandFor({ ...clubbed, logo: SVG }); assert.equal(b.logo, `/golf/api/abcd2345/logo?v=${logoVersion(SVG)}`); assert.equal(logoOf({ ...clubbed, logo: SVG }).type, 'image/svg+xml');
ok('the club’s logo, or the tournament’s own instead');
b = brandFor({ ...clubbed, demo: true });
assert.equal(b.logo, ''); assert.equal(b.demo, true); assert.equal(b.marked, true); assert.equal(b.powered, false); assert.equal(logoOf({ ...clubbed, demo: true }), null);
ok('a tournament Admin marks Demo shows the Flagcast logo whatever the club has');

const BASE = process.argv[2];
if (BASE) {
  const call = async (op, body) => { const r = await fetch(`${BASE}/golf/api/club/${op}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json().catch(() => ({})) }; };
  const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();
  // a made-up club with an owner, signed in with a code (local dev hands it back)
  const email = `brand-${Date.now()}@example.com`;
  let r = await call('admin', { op: 'create', name: 'Brand Test Club', email, credits: 5 }); assert.equal(r.status, 200);
  const club = r.j.made.club;
  r = await call('start', { email }); r = await call('verify', { email, code: r.j.devCode }); const token = r.j.token; assert.ok(token);
  const make = async (name) => (await fetch(`${BASE}/golf/api/new`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token, name }) })).json();
  r = { j: await make('Brand test') }; const { id, key } = r.j; assert.ok(id, JSON.stringify(r.j));
  let s = await state(id);
  assert.equal(s.brand.demo, true); assert.equal(s.brand.logo, ''); assert.equal((await fetch(`${BASE}/golf/api/${id}/logo`)).status, 404);
  ok('a club with no logo: its tournament shows Flagcast’s, and has no logo to serve');

  r = await call('brand', { logo: PNG }); assert.equal(r.status, 401);
  r = await call('brand', { token: 'not-a-session', logo: PNG }); assert.equal(r.status, 401);
  r = await call('brand', { token, logo: svg('<script>x</script>') }); assert.equal(r.status, 400);
  s = await state(id); assert.equal(s.brand.demo, true);
  ok('setting the logo needs the club’s own sign-in; a bad logo is refused and changes nothing');

  r = await call('brand', { token, logo: PNG, accent: '#1A6B3C' }); assert.equal(r.status, 200);
  assert.match(r.j.club.logo, new RegExp(`^/golf/api/club/logo/${club}\\?v=`)); assert.equal(r.j.club.accent, '#1a6b3c');
  s = await state(id); assert.equal(s.brand.demo, false); assert.equal(s.brand.accent, '#1a6b3c');
  assert.ok(!JSON.stringify(s).includes(PNG.slice(30, 80)), 'the logo itself is not in the live state');
  let img = await fetch(BASE + s.brand.logo); assert.equal(img.status, 200); assert.equal(img.headers.get('content-type'), 'image/png');
  assert.match(img.headers.get('content-security-policy'), /default-src 'none'/);
  assert.deepEqual(new Uint8Array(await img.arrayBuffer()), decodeLogo(PNG).bytes);
  img = await fetch(BASE + r.j.club.logo); assert.equal(img.status, 200);
  ok('the club sets its logo and colour: its tournaments show it at once, served as an image');

  const s2 = await make('Second');
  assert.equal((await state(s2.id)).brand.demo, false);
  ok('a new tournament starts with the club’s logo');

  r = await fetch(`${BASE}/golf/api/${id}/desk`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key, op: 'get' }) }).then((x) => x.json());
  delete r.stats;
  let d = await fetch(`${BASE}/golf/api/${id}/desk`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key, op: 'save', setup: { ...r, logo: SVG } }) });
  assert.equal(d.status, 200); s = await state(id); assert.equal(s.brand.logo, `/golf/api/${id}/logo?v=${logoVersion(SVG)}`);
  d = await fetch(`${BASE}/golf/api/${id}/desk`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key, op: 'save', setup: { name: 'Brand test' } }) });
  s = await state(id); assert.equal(s.brand.logo, `/golf/api/${id}/logo?v=${logoVersion(SVG)}`, 'a save without logo keeps it');
  d = await fetch(`${BASE}/golf/api/${id}/desk`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ key, op: 'save', setup: { name: 'Brand test', logo: '' } }) });
  s = await state(id); assert.equal(s.brand.logo, `/golf/api/${id}/logo?v=${logoVersion(PNG)}`, 'back to the club’s');
  ok('a tournament can use its own logo, and go back to the club’s');

  r = await call('admin', { op: 'demo', id, on: true }); assert.equal(r.status, 200);
  s = await state(id); assert.equal(s.brand.demo, true); assert.equal(s.brand.marked, true); assert.equal((await fetch(`${BASE}/golf/api/${id}/logo`)).status, 404);
  r = await call('admin', { op: 'events' }); assert.equal(r.j.events.find((e) => e.id === id).demo, true);
  r = await call('admin', { op: 'demo', id, on: false }); s = await state(id); assert.equal(s.brand.demo, false);
  ok('Admin’s Demo switch shows the Flagcast logo, and Admin’s list says so');

  r = await call('admin', { op: 'brand', club, powered: true }); s = await state(id); assert.equal(s.brand.powered, true);
  r = await call('admin', { op: 'brand', club, logo: '' }); s = await state(id); assert.equal(s.brand.demo, true); assert.equal(s.brand.powered, false);
  r = await call('admin', {}); const c = r.j.clubs.find((x) => x.id === club); assert.equal(c.logo, ''); assert.equal(c.powered, true); assert.ok(!('logo' in c && c.logo.startsWith('data:')));
  ok('Admin sets “Powered by Flagcast” and can take the logo off (back to Flagcast’s)');
  await call('admin', { op: 'delete', club }).catch(() => {});
}
console.log(`\n${n} passed`);
