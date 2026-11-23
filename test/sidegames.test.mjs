// Side games on the web scorecard (public/golf/core.js) score exactly like the players' app (Core.swift):
// the same cart and the same hand-worked answers as CoreTests.testStablefordVegasWolfAndPicks.   node test/sidegames.test.mjs
import assert from 'node:assert/strict';
import { sideGames, defaultHoles } from '../public/golf/core.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const ev = {
  format: {}, course: { holes: defaultHoles() },
  teams: [{ id: 'ta', start: 1, players: [{ id: 'p1', name: 'Ann', hcp: 0 }, { id: 'p2', name: 'Bob', hcp: 0 }] },
          { id: 'tb', start: 1, players: [{ id: 'p3', name: 'Cy', hcp: 0 }, { id: 'p4', name: 'Dee', hcp: 0 }] }],
};
const scores = { ta: { p1: [4, 5, 3], p2: [5, 6, 4] }, tb: { p3: [4, 4, 4], p4: [6, 5, 5] } };

const r = sideGames(ev, scores, ['ta', 'tb'], {
  stableford: { on: true, net: true }, vegas: { on: true, amt: 1, net: true },
  wolf: { on: true, amt: 1, net: true, picks: { 1: 'tb:p3', 2: 'lone' } }, closest: { on: true, amt: 2, picks: { 4: 'tb:p4' } },
});
assert.deepEqual(Object.fromEntries(r.stableford.map((x) => [x.key, x.points])), { 'ta:p1': 7, 'ta:p2': 4, 'tb:p3': 7, 'tb:p4': 3 });
assert.equal(r.stableford[0].thru, 3); ok('Stableford points against par');
assert.ok(!r.vegasNeedsFour);
assert.deepEqual(r.vegas.holes.map((h) => [h.a, h.b]), [[45, 46], [56, 45], [34, 45]]);
assert.equal(r.vegas.total, 1);
assert.deepEqual(r.tally.vegas, { 'ta:p1': 1, 'ta:p2': 1, 'tb:p3': -1, 'tb:p4': -1 }); ok('Vegas numbers and points');
assert.deepEqual(r.wolf.holes.slice(0, 3).map((h) => h.result), ['wolf', 'others', null]);
assert.equal(r.wolf.holes[2].wolf, 'tb:p3');
assert.deepEqual(r.tally.wolf, { 'ta:p1': 3, 'ta:p2': -7, 'tb:p3': 3, 'tb:p4': 1 }); ok('Wolf rotation, partner and lone wolf');
assert.deepEqual(r.closest.map((h) => h.hole), [4, 7, 11, 16]);
assert.equal(r.tally.closest['tb:p4'], 6); ok('closest to the pin on the par 3s');
assert.equal(Object.values(r.ledger).reduce((a, b) => a + b, 0), 0);
assert.equal(r.ledger['tb:p4'], 6); ok('points balance to zero');

const two = sideGames(ev, scores, ['ta'], { vegas: { on: true }, wolf: { on: true }, stableford: { on: true }, skins: { on: true } });
assert.ok(two.vegasNeedsFour); assert.equal(two.wolf, undefined); assert.ok(two.stableford);
const none = sideGames(ev, scores, [], { skins: { on: true }, stableford: { on: true } });
assert.equal(none.skins, undefined); assert.equal(none.stableford, undefined); ok('games wait for enough players');
