// The pin sheet (public/golf/gps.js): cleaning what the desk sends, the labels golfers see, and the yards to the pin.
// Run: node --test test/pins.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { cleanPin, pinLabel, pinPaces, pinYards, pinOf } from '../public/golf/gps.js';

test('cleanPin keeps a good pin and drops junk', () => {
  assert.deepEqual(cleanPin({ d: 'B', s: 'R', on: 26, off: 4 }), { d: 'B', s: 'R', on: 26, off: 4 });
  assert.deepEqual(cleanPin({ d: 'M', s: 'C', off: 5 }), { d: 'M', s: 'C' }); // no side paces on a center pin
  assert.deepEqual(cleanPin({ d: 'F', s: 'X', on: 999 }), { d: 'F', s: 'C', on: 60 });
  assert.deepEqual(cleanPin({ d: 'F', on: -3, off: 'x' }), { d: 'F', s: 'C' });
  assert.equal(cleanPin({ d: 'Z' }), null);
  assert.equal(cleanPin(null), null);
  assert.equal(cleanPin('B'), null);
});

test('labels', () => {
  assert.equal(pinLabel({ d: 'B', s: 'R' }), 'Back right');
  assert.equal(pinLabel({ d: 'M', s: 'C' }), 'Middle');
  assert.equal(pinLabel({ d: 'F', s: 'L' }), 'Front left');
  assert.equal(pinLabel(null), '');
  assert.equal(pinPaces({ d: 'B', s: 'R', on: 26, off: 4 }), '26 on · 4 R');
  assert.equal(pinPaces({ d: 'M', s: 'C', on: 15 }), '15 on');
  assert.equal(pinPaces({ d: 'M', s: 'C' }), '');
});

test('yards to the pin', () => {
  const y = { f: 472, m: 491, b: 508 };
  assert.equal(pinYards(y, { d: 'B', s: 'R', on: 26 }), 498); // front + paces
  assert.equal(pinYards(y, { d: 'B', s: 'R' }), 500); // halfway from the middle to the back (499.5 rounds up)
  assert.equal(pinYards(y, { d: 'F', s: 'C' }), 482);
  assert.equal(pinYards(y, { d: 'M', s: 'L' }), 491);
  assert.equal(pinYards({ f: null, m: 150, b: null }, { d: 'B', s: 'C', on: 20 }), 150);
  assert.equal(pinYards(y, null), null);
});

test('pinOf reads number or string keys', () => {
  assert.deepEqual(pinOf({ pinsheet: { 7: { d: 'F', s: 'C' } } }, 7), { d: 'F', s: 'C' });
  assert.deepEqual(pinOf({ pinsheet: { '7': { d: 'F', s: 'C' } } }, '7'), { d: 'F', s: 'C' });
  assert.equal(pinOf({}, 7), null);
});
