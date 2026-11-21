// Course maps keep each hole's line (its doglegs) for "Fly the hole".
//   node test/flyover.test.mjs                         the importer, on Torrey Pines South (fixtures/torrey-south.json)
//   node test/flyover.test.mjs http://127.0.0.1:8787   plus: the server keeps the line, and the live state says when carts last scored
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { simplify } from '../public/golf/osm.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const fx = JSON.parse(fs.readFileSync(new URL('./fixtures/torrey-south.json', import.meta.url)));

assert.deepEqual(simplify([[0, 0], [50, 1], [100, 0]], 6), [[0, 0], [100, 0]]);
assert.deepEqual(simplify([[0, 0], [50, 40], [100, 0]], 6), [[0, 0], [50, 40], [100, 0]]);
ok('a nearly straight line loses its points; a bend keeps them');

assert.equal(Object.keys(fx.holes).length, 18);
for (const [h, hole] of Object.entries(fx.holes)) {
  const osm = fx.osmLines[h];
  assert.ok(hole.line.length <= Math.max(0, osm.length - 2), `hole ${h}: no more bends than the OSM line has`);
  for (const p of hole.line) assert.ok(osm.some((q) => Math.abs(q[0] - p[0]) < 1e-5 && Math.abs(q[1] - p[1]) < 1e-5), `hole ${h}: each bend is a point of the hole's own line`);
}
assert.ok(Object.values(fx.holes).filter((x) => x.line.length).length >= 10);
ok('Torrey Pines South: the doglegs come through from OpenStreetMap, in order, only from the hole itself');

const BASE = process.argv[2];
if (BASE) {
  const post = async (path, body) => { const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); const j = await r.json(); if (!r.ok) throw new Error(JSON.stringify(j)); return j; };
  const { id, key } = await post('/golf/api/new', { name: 'Flyover test', pass: 'local' });
  await post(`/golf/api/${id}/desk`, { key, op: 'map', map: { src: 'osm', holes: { 6: fx.holes[6], 3: { ...fx.holes[3], line: [[999, 0], 'x'] } } } });
  const s = await (await fetch(`${BASE}/golf/api/${id}/state`)).json();
  assert.deepEqual(s.map.holes[6].line, fx.holes[6].line.map((p) => p.map((v) => Math.round(v * 1e6) / 1e6)));
  assert.deepEqual(s.map.holes[3].line, []);
  ok('the server keeps a hole’s line (and drops points that aren’t points)');
  const ev = await post(`/golf/api/${id}/desk`, { key, op: 'get' });
  await post(`/golf/api/${id}/desk`, { key, op: 'save', setup: { ...ev, teams: [{ name: 'A', players: [{ name: 'P' }] }] } });
  const t = (await post(`/golf/api/${id}/desk`, { key, op: 'get' })).teams[0];
  const before = Date.now();
  await post(`/golf/api/${id}/score`, { team: t.id, desk: key, list: [{ p: t.players[0].id, h: 1, v: 4 }] });
  const s2 = await (await fetch(`${BASE}/golf/api/${id}/state`)).json();
  assert.ok(s2.lastAt[t.id] >= before - 1000);
  ok('the live state says when each cart last scored (the Day of checks)');
}
console.log(`\n${n} passed`);
