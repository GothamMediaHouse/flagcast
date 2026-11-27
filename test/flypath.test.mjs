// "Fly the hole" on the web (public/golf/flypath.js) flies like the players' app (FlyPath.swift, FlyTests.swift):
// on Torrey Pines South it opens low behind each tee box, stays over the hole round its doglegs, never looks past the
// green, and turns smoothly.   node test/flypath.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { makePath, yds, offset, bearing, progress } from '../public/golf/flypath.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const fx = JSON.parse(fs.readFileSync(new URL('./fixtures/torrey-south.json', import.meta.url)));
// metres from p to a polyline
const off = (p, line) => { let best = Infinity; for (let i = 1; i < line.length; i++) for (let k = 0; k <= 40; k++) { const a = line[i - 1], b = line[i]; best = Math.min(best, yds(p, [a[0] + (b[0] - a[0]) * k / 40, a[1] + (b[1] - a[1]) * k / 40])); } return best; };
const eye = (c) => offset(c.at, c.metres * Math.sin(c.pitch * Math.PI / 180) * 1.0936133, (c.heading + 180) % 360);

for (let h = 1; h <= 18; h++) {
  const hole = fx.holes[h], osm = fx.osmLines[h], tee = hole.tee, g = hole.m || hole.f;
  const p = makePath(hole);
  assert.equal(p.points.length, hole.line.filter((b) => yds(tee, b) > 25 && yds(b, g) > 25).length + 2, `hole ${h}: tee, bends, green`);
  // it opens behind the tee box, low, with the tee box in the bottom of the frame (MapLibre's 36.87° view)
  const c0 = p.camera(0), behind = yds(eye(c0), tee), toTee = Math.atan2(behind / 1.0936133, p.height(0)) * 180 / Math.PI;
  assert.ok(behind > 50 && behind < 70, `hole ${h}: opens behind the tee box (${behind.toFixed(0)} yds)`);
  assert.ok(toTee > c0.pitch - 18.4 + 3 && toTee < c0.pitch, `hole ${h}: the tee box is in the bottom of the opening shot`);
  assert.ok(p.height(0) < 30, `hole ${h}: opens low`);
  const back = [offset(tee, 80, bearing(p.path[1], tee)), tee];   // the line of the hole carried on back behind the tee
  let last = null, hs = [];
  for (let t = 0; t <= p.totalSecs; t += 0.25) {
    const c = p.camera(t), e = eye(c);
    assert.ok(off(c.at, osm) < 30, `hole ${h} at ${t}s: looks along the hole`);
    assert.ok(yds(tee, c.at) <= yds(tee, g) + 40, `hole ${h}: never looks past the green`);
    assert.ok(Math.min(off(e, osm), off(e, back)) < 35, `hole ${h} at ${t}s: the camera is over the hole`);
    if (last) { let d = Math.abs(c.heading - last.heading) % 360; if (d > 180) d = 360 - d; assert.ok(d < 12, `hole ${h} at ${t}s: turns smoothly (${d.toFixed(1)}°)`); }
    last = c; hs.push(p.height(t));
  }
  assert.ok(Math.max(...hs) < 50, `hole ${h}: stays low`);
  assert.ok(hs.at(-1) > 12 && hs.at(-1) < 40, `hole ${h}: ends low over the green`);
}
ok('every hole at Torrey Pines South flies like the app: from behind the tee box, over the hole, round the doglegs, short of the green');

let prev = -1; for (let u = 0; u <= 1.0001; u += 0.01) { const v = progress(u); assert.ok(v >= prev - 1e-12); prev = v; }
assert.ok(Math.abs(progress(0)) < 1e-9 && Math.abs(progress(1) - 1) < 1e-9);
ok('the glide only moves forward, from the tee (0) to the end of the run (1)');

const t0 = [32.9, -117.25], bend = offset(t0, 250, 10), gr = offset(bend, 150, 330);
const p = makePath({ tee: t0, m: gr, line: [bend] });
assert.ok(p.points.length === 3 && Math.abs(bearing(p.camera(p.totalSecs).at, gr)) >= 0);
assert.ok(off(p.camera(p.totalSecs * 0.6).at, [t0, bend, gr]) < 30);
ok('a made-up dogleg: the flight turns at the bend instead of cutting the corner');
