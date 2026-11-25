// Contest standings and checks (public/golf/core.js, the same as Core.swift): who leads, which golfer entries wait
// for a pro's OK, and the warnings next to an entry that looks wrong.   node test/contests.test.mjs
import assert from 'node:assert/strict';
import { contestLeader, contestNeedsOk, contestFlag, fmtDist } from '../public/golf/core.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const ld = { kind: 'ld', entries: [{ name: 'Al', dist: 280, ok: true }, { name: 'Bo', dist: 301, ok: false }, { name: 'Cy', dist: 250 }] };
assert.deepEqual(contestLeader(ld).map((e) => e.name), ['Bo', 'Al', 'Cy']);
assert.deepEqual(contestLeader(ld, true).map((e) => e.name), ['Al', 'Cy']); ok('long drive: longest first; TVs leave out waiting entries (old entries count)');
const ctp = { kind: 'ctp', entries: [{ name: 'Di', dist: 6.25 }, { name: 'Ed', dist: 3.5 }] };
assert.deepEqual(contestLeader(ctp).map((e) => e.name), ['Ed', 'Di']); assert.equal(fmtDist(ctp, 6.25), '6 ft 3 in'); ok('closest: shortest first, feet and inches');

const field = [{ dist: 290 }, { dist: 280 }, { dist: 270 }, { dist: 200 }];
assert.equal(contestNeedsOk({ kind: 'ld', check: 'top' }, field, { dist: 275 }), true);
assert.equal(contestNeedsOk({ kind: 'ld', check: 'top' }, field, { dist: 260 }), false);
assert.equal(contestNeedsOk({ kind: 'ld' }, [], { dist: 150 }), true);
assert.equal(contestNeedsOk({ kind: 'ctp', check: 'top' }, [{ dist: 2 }, { dist: 3 }, { dist: 4 }], { dist: 5 }), false);
assert.equal(contestNeedsOk({ kind: 'ctp', check: 'top' }, [{ dist: 2 }, { dist: 3 }, { dist: 4 }], { dist: 3.5 }), true);
assert.equal(contestNeedsOk({ kind: 'ld', check: 'all' }, field, { dist: 100 }), true);
assert.equal(contestNeedsOk({ kind: 'ld', check: 'none' }, field, { dist: 400 }), false); ok('top 3 waits for a check, the rest go straight up; every entry; trust golfers');

const g = { name: 'Zed', dist: 341, by: 'golfer' };
assert.match(contestFlag({ kind: 'ld', entries: [{ name: 'A', dist: 290 }, { name: 'B', dist: 280 }, g] }, g), /51 yds past everyone/);
assert.match(contestFlag({ kind: 'ld', entries: [] }, { name: 'Y', dist: 300, gps: 255, by: 'golfer' }), /GPS from the tee said 255/);
assert.equal(contestFlag({ kind: 'ld', entries: [] }, { name: 'Y', dist: 300, gps: 290, by: 'golfer' }), '');
assert.equal(contestFlag({ kind: 'ld', entries: [{ name: 'A', dist: 290 }, { name: 'B', dist: 280 }, g] }, { ...g, by: 'Pro' }), '');
assert.equal(contestFlag({ kind: 'ctp', entries: [] }, { name: 'Y', dist: 0.3, by: 'golfer' }), 'Under 6 inches'); ok('warnings: far past everyone, GPS disagrees, tiny closest; never on staff entries');
