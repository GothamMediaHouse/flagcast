// The Cameras tab's list (core.js camList): each camera once, the pro's phone first, then contest holes, par 3s,
// around the club (the clubhouse is camera 0, hole 18 is the 18th green), and the ones staff hid left out.
// And what the TV apps get for a camera page (tvfeed.js): its label, the pro, and a contest's leader.
import test from 'node:test';
import assert from 'node:assert/strict';
import { camList, camTitle } from '../public/golf/core.js';
import { tvFeed } from '../tvfeed.js';

const holes = Array.from({ length: 18 }, (_, i) => ({ n: i + 1, par: [3, 7, 12, 16].includes(i + 1) ? 3 : 4, yds: 150 + i, hcp: i + 1 }));
const ev = () => ({
  id: 'abcdefgh', name: 'Cams', course: { holes }, teams: [], scores: {}, sponsors: [],
  cams: { 0: 'https://x/club.m3u8', 7: 'https://x/7.m3u8', 9: 'https://x/9.m3u8', 12: 'https://x/12.m3u8', 18: 'https://x/18.m3u8', 5: 'https://x/5.m3u8', 3: 'https://player.example/3' },
  golive: { 9: { by: 'Dave' } },
  contests: [{ id: 'c1', hole: 7, kind: 'ctp', entries: [{ name: 'Reyes', dist: 4.2, ok: true }, { name: 'Kim', dist: 9 }] }, { id: 'c2', hole: 9, kind: 'ld', entries: [] }],
});

test('cameras come in the Cameras tab order, each once', () => {
  const l = camList(ev());
  assert.deepEqual(l.map((c) => [c.n, c.kind]), [[9, 'pro'], [7, 'contest'], [3, 'par3'], [12, 'par3'], [0, 'club'], [18, 'club'], [5, 'hole']]);
  assert.equal(l[0].by, 'Dave');
  assert.equal(l[0].sub, 'Long drive · Par 4 · 158 yds', 'the pro’s hole still says it’s the long drive');
  assert.equal(l.find((c) => c.n === 0).title, 'Clubhouse');
  assert.equal(l.find((c) => c.n === 18).title, '18th green');
  assert.equal(l.find((c) => c.n === 3).hls, false, 'a web player link is marked not HLS');
});

test('staff can hide cameras from golfers; the desk still lists them', () => {
  const e = { ...ev(), camsOff: [0, 7] };
  assert.deepEqual(camList(e).map((c) => c.n), [9, 3, 12, 18, 5]);
  const all = camList(e, { all: true });
  assert.equal(all.length, 7); assert.equal(all.find((c) => c.n === 7).off, true);
});

test('a camera on a hole the course doesn’t have is left out; no cameras is an empty list', () => {
  const e = { ...ev(), cams: { 19: 'https://x/19.m3u8', 4: '' }, course: { holes: holes.slice(0, 9) } };
  assert.deepEqual(camList(e), []);
  assert.deepEqual(camList({}), []);
});

test('camera titles for the TVs', () => {
  assert.equal(camTitle(ev(), 7), 'Hole 7 · Closest to the pin');
  assert.equal(camTitle(ev(), 0), 'Clubhouse');
  assert.equal(camTitle(ev(), 18), '18th green');
  assert.equal(camTitle(ev(), 2), 'Hole 2');
});

test('the TV apps get the camera’s label, the pro and the contest leader; the clubhouse works too', () => {
  const S = { ...ev(), displays: [{ id: 'tv', name: 'Bar' }], live: { force: { tv: { k: 'cam', hole: 7 } } } };
  let p = tvFeed(S, 'tv').pages[0];
  assert.equal(p.k, 'cam'); assert.equal(p.label, 'Hole 7 · Closest to the pin'); assert.equal(p.leader, 'Reyes · 4 ft 2 in'); assert.equal(p.pro, '');
  S.live.force.tv = { k: 'cam', hole: 9 }; p = tvFeed(S, 'tv').pages[0];
  assert.equal(p.pro, 'Dave'); assert.equal(p.leader, '');
  S.live.force.tv = { k: 'cam', hole: 0 }; p = tvFeed(S, 'tv').pages[0];
  assert.equal(p.hole, 0); assert.equal(p.label, 'Clubhouse'); assert.equal(p.url, 'https://x/club.m3u8');
});
