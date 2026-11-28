// Pace of play (public/golf/core.js paceOf): the round clock, the hole clock and ahead/behind the goal, from the times
// the server keeps (ev.pace), and the demo's made-up teams (demogroups.js demoPace).  node --test test/pace.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { paceOf, paceOrder, paceGoal, paceWord, fmtClock, PACE_GOAL } from '../public/golf/core.js';
import { demoPace } from '../demogroups.js';

const M = 60000, T0 = Date.UTC(2026, 10, 28, 13);
const teams = [{ id: 'a', start: 10, players: [] }, { id: 'b', start: 1, players: [] }];

test('the order a group plays: from its start hole round', () => {
  assert.deepEqual(paceOrder({ teams }, teams[0]).slice(0, 10), [10, 11, 12, 13, 14, 15, 16, 17, 18, 1]);
  assert.deepEqual(paceOrder({ teams, format: { nine: 'back' } }, { start: 14 }), [14, 15, 16, 17, 18, 10, 11, 12, 13]);
  assert.equal(paceGoal({}), PACE_GOAL); assert.equal(paceGoal({ paceGoal: 240 }), 240); assert.equal(paceGoal({ paceGoal: 30 }), PACE_GOAL);
});

test('clocks during the round, and ahead or behind the goal', () => {
  // 4:15 goal = 14.17 min a hole. Started T0, finished 10, 11, 12 at 14, 30, 50 minutes
  const ev = { teams, pace: { a: { s: T0, d: { 10: T0 + 14 * M, 11: T0 + 30 * M, 12: T0 + 50 * M } } } };
  const p = paceOf(ev, 'a', T0 + 60 * M);
  assert.equal(p.hole, 13); assert.equal(p.done, 3); assert.equal(p.elapsed, 60 * M); assert.equal(p.onHole, 10 * M);
  assert.deepEqual(p.times, { 10: 14 * M, 11: 16 * M, 12: 20 * M });
  assert.equal(Math.round(p.vs / M), Math.round(50 - 3 * 255 / 18)); // 7.5 behind after three holes
  assert.equal(p.level, 'amber'); assert.equal(paceWord(p), '+8 min');
  assert.equal(paceOf(ev, 'b', T0), null, 'not started');
  // a long time on the hole they're on counts as soon as it's over the goal for one hole
  assert.equal(paceOf(ev, 'a', T0 + 75 * M).level, 'red');
});

test('the GPS seeing them reach the hole starts its clock sooner', () => {
  const ev = { teams, pace: { a: { s: T0, d: { 10: T0 + 20 * M }, g: { h: 11, at: T0 + 16 * M } } } };
  assert.equal(paceOf(ev, 'a', T0 + 30 * M).onHole, 14 * M);
  ev.pace.a.g = { h: 10, at: T0 + 2 * M }; // an older hole: ignored
  assert.equal(paceOf(ev, 'a', T0 + 30 * M).onHole, 10 * M);
});

test('a finished round', () => {
  const d = {}; paceOrder({ teams }, teams[1]).forEach((h, i) => { d[h] = T0 + (i + 1) * 13 * M; });
  const p = paceOf({ teams, pace: { b: { s: T0, d } } }, 'b', T0 + 600 * M);
  assert.ok(p.fin); assert.equal(p.hole, 0); assert.equal(p.elapsed, 18 * 13 * M); assert.equal(fmtClock(p.elapsed), '3:54');
  assert.equal(paceWord(p), '21 min under');
  assert.equal(fmtClock(9 * M + 32000, true), '9:32'); assert.equal(fmtClock(102 * M + 5000, true), '1:42');
});

test('times still to come are left out', () => {
  const ev = { teams, pace: { a: { s: T0, d: { 10: T0 + 14 * M, 11: T0 + 28 * M } } } };
  assert.equal(paceOf(ev, 'a', T0 + 20 * M).hole, 11);
});

test('demo teams: clocks to match their scores, some behind, some ahead', () => {
  const many = Array.from({ length: 20 }, (_, i) => ({ id: `t${i}`, start: (i % 18) + 1, players: [{ id: 'p' }] }));
  const scores = {}; many.forEach((t, i) => { if (i === 19) return; const arr = Array(18).fill(null);
    paceOrder({}, t).slice(0, i === 18 ? 18 : 6 + (i % 8)).forEach((h) => { arr[h - 1] = 4; }); scores[t.id] = { p: arr }; });
  const ev = { demo: true, teams: many }, now = T0 + 37 * M, pace = demoPace(ev, scores, now);
  assert.equal(pace.t19, undefined, 'no scores: not started');
  const ev2 = { ...ev, pace }, levels = new Set();
  many.slice(0, 18).forEach((t, i) => {
    const p = paceOf(ev2, t.id, now), thru = 6 + (i % 8);
    assert.equal(p.done, thru); assert.equal(p.hole, paceOrder({}, t)[thru]);
    assert.ok(p.onHole >= 0 && p.onHole <= 13 * M, `${t.id} on the hole a few minutes`);
    levels.add(p.level);
  });
  assert.ok(paceOf(ev2, 't18', now).fin);
  assert.ok(levels.has('ok') && levels.has('red'), [...levels].join());
  assert.deepEqual(demoPace(ev, scores, now + 5 * M), demoPace(ev, scores, now + 5 * M));
  assert.equal(demoPace(ev, scores, now, new Set(['t0'])).t0, undefined, 'a team with its own times is skipped');
});
