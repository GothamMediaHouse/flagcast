// Pin sheet on the server: the desk (or a pro's PIN) sets where each pin is, golfers' state has it, junk is cleaned.
// Run against `npx wrangler dev` (local, no GOLF_CREATE_PASS):  node test/pinsheet.test.mjs [http://127.0.0.1:8787]
import assert from 'node:assert/strict';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();

const { id, key } = await post('/golf/api/new', { name: 'Pin sheet test', pass: 'local' });
const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });

await desk('pinsheet', { hole: 18, pin: { d: 'B', s: 'R', on: 26, off: 4 } });
await desk('pinsheet', { hole: 3, pin: { d: 'F', s: 'C', off: 9 } });
let s = await state(id);
assert.deepEqual(s.pinsheet, { 3: { d: 'F', s: 'C' }, 18: { d: 'B', s: 'R', on: 26, off: 4 } });
ok('the desk sets one hole at a time and golfers see it');

await desk('pinsheet', { hole: 3, pin: null });
s = await state(id); assert.deepEqual(Object.keys(s.pinsheet), ['18']); ok('null takes a pin off');

const { status } = await call(`/golf/api/${id}/desk`, { key, op: 'pinsheet', hole: 0, pin: { d: 'F' } });
assert.equal(status, 400); ok('a hole is needed');

await desk('pinsheet', { all: { 1: { d: 'M', s: 'L' }, 2: { d: 'nope' }, 40: { d: 'F' } } });
s = await state(id); assert.deepEqual(s.pinsheet, { 1: { d: 'M', s: 'L' } }); ok('the whole sheet at once, junk dropped');

const cur = await desk('get');
await desk('save', { setup: { ...cur, name: 'Renamed' } });
s = await state(id); assert.deepEqual(s.pinsheet, { 1: { d: 'M', s: 'L' } }); ok('saving the setup keeps the pins');

const bad = await call(`/golf/api/${id}/desk`, { key: 'wrong', op: 'pinsheet', hole: 1, pin: { d: 'F' } });
assert.notEqual(bad.status, 200); ok('a wrong desk key can’t change pins');

const cur2 = await desk('get');
await desk('save', { setup: { ...cur2, pins: [{ name: 'Pro', role: 'pro', pin: '654321' }, { name: 'Marshal', role: 'marshal', pin: '876543' }] } });
await post(`/golf/api/${id}/pro`, { pin: '654321', op: 'pinsheet', hole: 7, spot: { d: 'B', s: 'L', on: 22, off: 5 } });
s = await state(id); assert.deepEqual(s.pinsheet[7], { d: 'B', s: 'L', on: 22, off: 5 }); ok('a golf pro sets a pin with their PIN');
await post(`/golf/api/${id}/pro`, { pin: '654321', op: 'pinsheet', hole: 7, spot: null });
s = await state(id); assert.equal(s.pinsheet[7], undefined); ok('a golf pro takes a pin off');
const m = await call(`/golf/api/${id}/pro`, { pin: '876543', op: 'pinsheet', hole: 7, spot: { d: 'F' } });
assert.equal(m.status, 403); ok('a marshal can’t change pins');
