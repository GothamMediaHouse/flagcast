// Sample groups on Demo tournaments walk the course map, from the clock alone.  node --test test/demogroups.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { demoGroups } from '../demogroups.js';
import { trackingOn } from '../public/golf/gps.js';

const map = JSON.parse(readFileSync(new URL('./fixtures/torrey-south.json', import.meta.url)));
const teams = [1, 2, 3].map((i) => ({ id: `team${i}`, name: `Team ${i}`, start: i, players: [{ id: `p${i}`, name: `Player ${i}` }] }));
const ev = { demo: true, date: '2020-01-01', teams, map };
const near = (a, b) => Math.abs(a[0] - b[0]) < 0.02 && Math.abs(a[1] - b[1]) < 0.02;

test('eight groups spread round the course, using the demo teams first', () => {
  const g = demoGroups(ev, Date.UTC(2026, 10, 25, 15));
  assert.equal(g.length, 8);
  assert.deepEqual(g.slice(0, 3).map((x) => x.name), ['Team 1', 'Team 2', 'Team 3']);
  assert.ok(g.every((x) => x.sample && x.hole >= 1 && x.hole <= 18 && near(x.at, map.holes[1].tee)));
  assert.ok(new Set(g.map((x) => x.hole)).size >= 6, 'on different holes');
});

test('they move, and come back the same for everyone at the same time', () => {
  const t = Date.UTC(2026, 10, 25, 15);
  assert.deepEqual(demoGroups(ev, t), demoGroups(ev, t));
  const a = demoGroups(ev, t), b = demoGroups(ev, t + 3 * 60000);
  assert.ok(a.filter((x, i) => x.at[0] !== b[i].at[0] || x.at[1] !== b[i].at[1]).length >= 4);
  const later = demoGroups(ev, t + 14 * 60000);
  assert.ok(later.every((x, i) => x.hole !== a[i].hole), 'on to the next hole');
});

test('courses with no map get none; teams with a real phone are skipped', () => {
  assert.equal(demoGroups({ ...ev, map: undefined }).length, 0);
  const g = demoGroups(ev, Date.now(), new Set(['team1', 'team2']));
  assert.ok(!g.some((x) => x.team === 'team1' || x.team === 'team2'));
  assert.equal(g[0].team, 'team3'); assert.equal(g.length, 8);
  assert.ok(g.every((x) => !('code' in x)));
});

test('a demo has the map on any day, until the results are final', () => {
  assert.equal(trackingOn({ date: '2020-01-01' }), false);
  assert.equal(trackingOn({ date: '2020-01-01', demo: true }), true);
  assert.equal(trackingOn({ date: '', brand: { marked: true } }), true);
  assert.equal(trackingOn({ date: '', brand: { marked: true }, locked: true }), false);
});
