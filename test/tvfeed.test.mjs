// The native TV apps' feed (tvfeed.js): the board's pages as data for one screen. Plain Node: node --test test/tvfeed.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { tvFeed } from '../tvfeed.js';
import { defaultHoles } from '../public/golf/core.js';

const holes = defaultHoles();
const p3 = holes.find((h) => h.par === 3).n;
const base = () => ({
  id: 'abcdefgh', name: 'Member-Guest', date: '2026-11-24', format: { type: 'bestball', count: 1, allowance: 85 }, flights: ['A'],
  course: { name: 'Test', holes, tees: [] }, screens: { seconds: 10, rows: 2, ticker: 'Lunch at 1' },
  teams: [1, 2, 3].map((i) => ({ id: `t${i}`, name: `Team ${i}`, flight: 'A', players: [{ id: `p${i}`, name: `Player ${i}`, hcp: 0 }] })),
  scores: { t1: { p1: [3, 4, null] }, t2: { p2: [5, 5, null] } }, sponsors: [{ id: 's1', name: 'Acme', spot: 'slide', holes: [], logo: 'data:image/png;base64,AAAA' }],
  cams: { [p3]: 'https://flagcast.app/golf/api/cam/0123456789abcdef0123456789abcdef/video.m3u8' }, displays: [], live: { force: {}, take: null }, brand: { logo: '/golf/api/abcdefgh/logo?v=1', accent: '#123456', demo: false },
});

test('usual pages: leaderboard pages, the phone QR after them, camera, sponsors', () => {
  const f = tvFeed(base(), 'tv1');
  const kinds = f.pages.map((p) => p.k);
  assert.deepEqual(kinds.slice(0, 3), ['lb', 'lb', 'phone']);
  assert.ok(kinds.includes('cam') && kinds.includes('sponsors') && kinds.includes('sponsor'));
  assert.equal(f.pages[0].rows.length, 2);
  assert.equal(f.pages[0].rows[0].name.includes('1'), true);
  assert.equal(f.ticker, 'Lunch at 1');
  assert.equal(f.logo, 'https://flagcast.app/golf/api/abcdefgh/logo?v=1');
  assert.equal(f.flagcast, false);
  const sp = f.pages.find((p) => p.k === 'sponsor');
  assert.equal(sp.logo, 'https://flagcast.app/golf/api/tv/sponsor/abcdefgh/s1'); // never the data: URI
  assert.ok(!JSON.stringify(f).includes('data:image'));
});

test('a screen playlist and a forced page win', () => {
  const S = base();
  S.displays = [{ id: 'tv1', name: 'Bar', tv: true, playlist: [{ k: 'cam', hole: p3, secs: 20 }] }];
  let f = tvFeed(S, 'tv1');
  assert.deepEqual(f.pages.map((p) => p.k), ['cam']);
  assert.equal(f.pages[0].secs, 20);
  S.live.force.tv1 = { k: 'sponsor', sponsor: 's1', at: Date.now() };
  f = tvFeed(S, 'tv1');
  assert.deepEqual(f.pages.map((p) => p.k), ['sponsor']);
  S.live.force.tv1.until = Date.now() - 1; // a timed send that's over
  assert.deepEqual(tvFeed(S, 'tv1').pages.map((p) => p.k), ['cam']);
});

test('non-HLS cameras are left out; Demo shows Flagcast; takeovers time out', () => {
  const S = base();
  S.cams[p3] = 'https://example.com/embed';
  S.brand = { logo: '', accent: '', demo: true };
  S.live.take = { kind: 'ace', text: 'Hole in one!', at: Date.now(), secs: 25 };
  const f = tvFeed(S, 'x');
  assert.ok(!f.pages.some((p) => p.k === 'cam'));
  assert.equal(f.flagcast, true);
  assert.equal(f.take.text, 'Hole in one!');
  S.live.take.at = Date.now() - 60000;
  assert.equal(tvFeed(S, 'x').take, null);
});

test('nothing to show yet', () => {
  const S = base(); S.teams = []; S.scores = {}; S.sponsors = []; S.cams = {};
  assert.deepEqual(tvFeed(S, 'x').pages.map((p) => p.k), ['empty']);
});
