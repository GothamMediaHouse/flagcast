// Add club with its course: the scorecard, tees and hole map a new club gets (clubcourse.js)
//   node test/clubcourse.test.mjs                        the course and map, with the lookups faked
//   node test/clubcourse.test.mjs http://127.0.0.1:8787  plus: a club's course reaches its new tournaments (npx wrangler dev)
import assert from 'node:assert/strict';
import { pickTee, cardFrom, boxAround, clubCourse } from '../clubcourse.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const holes = (par, yds) => Array.from({ length: 18 }, (_, i) => ({ par: par[i % par.length], yds: yds + i, hcp: ((i * 7) % 18) + 1 }));
const course = {
  id: 1234, name: 'Willow Creek CC', city: 'Rye', state: 'NY', at: { lat: 40.98, lng: -73.68 },
  tees: [
    { name: 'Black', women: false, rating: 74.1, slope: 138, par: 72, yards: 7100, holes: holes([4, 5, 3], 400) },
    { name: 'Blue', women: false, rating: 71.9, slope: 131, par: 72, yards: 6450, holes: holes([4, 5, 3], 360) },
    { name: 'Red', women: true, rating: 70.2, slope: 122, par: 73, yards: 5300, holes: holes([4, 5, 3], 290) },
    { name: 'Gold', women: false, rating: null, slope: null, par: 72, yards: 6000, holes: [] },
  ],
};

assert.equal(pickTee(course.tees).name, 'Blue');
assert.equal(pickTee(course.tees, 0).name, 'Black');
assert.equal(pickTee(course.tees, 3).name, 'Blue', 'tees with no holes can’t be picked');
assert.equal(pickTee([{ name: 'X', holes: [] }]), null);
ok('the club’s tees: the men’s set nearest 6,400 yards, unless one is asked for');

const card = cardFrom(course);
assert.equal(card.holes.length, 18);
assert.deepEqual(card.holes[0], { n: 1, par: 4, yds: 360, hcp: 1 });
assert.deepEqual(card.tees.map((t) => t.name), ['Blue', 'Black', 'Red (women)']);
assert.equal(card.tees.find((t) => t.name === 'Red (women)').par, 73);
assert.equal(card.tees[0].par, 0, 'par only when it differs from the card');
assert.deepEqual(card.at, { lat: 40.98, lng: -73.68 });
const nine = cardFrom({ ...course, tees: [{ name: 'White', rating: 34, slope: 110, yards: 3000, holes: holes([4], 300).slice(0, 9) }] });
assert.equal(nine.nine, true); assert.equal(nine.holes[12].par, 4);
ok('the scorecard: 18 holes, every set of tees with a rating and slope, the picked tees first');

const [s, w, nn, e] = boxAround({ lat: 40, lng: -74 });
assert.ok(Math.abs((nn - s) * 110.574 - 3.6) < 0.01 && Math.abs((e - w) * 111.32 * Math.cos((40 * Math.PI) / 180) - 3.6) < 0.01);
ok('the map box: about 1.8 km each way from the course');

// OpenStreetMap, faked: holes 1 and 2 drawn as tee→green lines with their greens
const way = (tags, pts) => ({ type: 'way', tags, geometry: pts.map(([lat, lon]) => ({ lat, lon })) });
const sq = (lat, lng, d = 0.0001) => [[lat - d, lng - d], [lat - d, lng + d], [lat + d, lng + d], [lat + d, lng - d], [lat - d, lng - d]];
const osm = [
  way({ golf: 'hole', ref: '1' }, [[40.98, -73.68], [40.983, -73.68]]), way({ golf: 'green' }, sq(40.983, -73.68)),
  way({ golf: 'hole', ref: '2' }, [[40.983, -73.681], [40.981, -73.682]]), way({ golf: 'green' }, sq(40.981, -73.682)),
];
const look = async (req) => {
  const id = new URL(req.url).pathname.split('/').pop();
  if (id === '1234') return Response.json(course);
  if (id === 'fc-lib') return Response.json({ ...course, id: 'fc-lib', map: { holes: { 1: { tee: [1, 2] } }, src: '' }, library: true });
  return Response.json({ error: 'That course wasn’t found.' }, { status: 404 });
};
let asked = null;
const got = await clubCourse({}, { id: '1234' }, { look, osm: async (box) => { asked = box; return osm; } });
assert.deepEqual(asked, boxAround(course.at));
assert.equal(got.card.name, 'Willow Creek CC');
assert.equal(got.map.src, 'osm');
assert.deepEqual(Object.keys(got.map.holes), ['1', '2']);
assert.ok(Math.abs(got.map.holes[1].tee[0] - 40.98) < 1e-6 && Math.abs(got.map.holes[1].m[0] - 40.983) < 1e-5);
assert.match(got.note, /Blue tees, and 2 holes mapped from OpenStreetMap\. Not on the map: 3, 4, .*18\. Place those in Course map/);
assert.match(got.note, /OpenStreetMap contributors/);
ok('a course: its scorecard, and the holes OpenStreetMap has, with the ones it hasn’t named');

const lib = await clubCourse({}, { id: 'fc-lib' }, { look, osm: async () => { throw new Error('not asked'); } });
assert.deepEqual(lib.map.holes[1].tee, [1, 2]); assert.match(lib.note, /Flagcast course list/);
ok('a Flagcast course-list course brings its own hole map');

const none = await clubCourse({}, { id: '1234' }, { look, osm: async () => [] });
assert.equal(none.map, null); assert.match(none.note, /aren’t on OpenStreetMap/);
const busy = await clubCourse({}, { id: '1234' }, { look, osm: async () => { throw new Error('busy'); } });
assert.equal(busy.map, null); assert.ok(busy.card); assert.match(busy.note, /Fill In the Holes/);
const nowhere = await clubCourse({}, { id: '1234' }, { look: async () => Response.json({ ...course, at: null }), osm: async () => { throw new Error('not asked'); } });
assert.equal(nowhere.map, null); assert.match(nowhere.note, /doesn’t say where it is/);
await assert.rejects(clubCourse({}, { id: '999' }, { look }), /wasn’t found/);
await assert.rejects(clubCourse({}, { id: '../x' }, { look }), /Pick the course/);
await assert.rejects(clubCourse({}, { id: '1234' }, { look: async () => Response.json({ ...course, tees: [] }) }), /no scorecard/);
ok('no map, a busy map service, no spot, a wrong id or no scorecard: said plainly');

const BASE = process.argv[2];
if (BASE) {
  const PASS = process.env.GOLF_CREATE_PASS || 'local';
  const post = async (path, body) => { const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { r, j: await r.json() }; };
  // an app can't send its own scorecard or map to Add club: only a course picked from the lookup is kept
  const { j: made } = await post('/golf/api/club/admin', { pass: PASS, op: 'create', name: `Course test ${Date.now()}`, credits: 1, card: { name: 'Fake', holes: [{ par: 6 }] }, map: { holes: { 1: { tee: [1, 1] } } } });
  const cid = made.made.club, row = made.clubs.find((c) => c.id === cid);
  assert.equal(row.courseName, ''); assert.equal(row.mapped, 0); assert.equal(row.card, undefined); assert.equal(row.course, undefined);
  ok('Add club keeps no scorecard or map the app made up');
  // a tournament's Setup with a course name: the club keeps that course, and its next tournament starts with it
  const { j: ev } = await post('/golf/api/club/admin', { pass: PASS, op: 'event', club: cid, name: 'First' });
  const setup = await (await fetch(`${BASE}/golf/api/${ev.made.id}/state`)).json();
  const holes18 = setup.course.holes.map((h, i) => ({ ...h, par: i === 0 ? 5 : h.par, yds: 300 + i }));
  const { r: sr } = await post(`/golf/api/${ev.made.id}/desk`, { key: ev.made.key, op: 'save', setup: { ...setup, course: { name: 'Willow Creek CC', holes: holes18, tees: [{ name: 'Blue', rating: 71.9, slope: 131 }], at: { lat: 40.98, lng: -73.68 } } } });
  assert.ok(sr.ok);
  await new Promise((r) => setTimeout(r, 400));
  const { j: after } = await post('/golf/api/club/admin', { pass: PASS });
  assert.equal(after.clubs.find((c) => c.id === cid).courseName, 'Willow Creek CC');
  const { j: ev2 } = await post('/golf/api/club/admin', { pass: PASS, op: 'event', club: cid, name: 'Second' });
  const s2 = await (await fetch(`${BASE}/golf/api/${ev2.made.id}/state`)).json();
  assert.equal(s2.course.name, 'Willow Creek CC'); assert.equal(s2.course.holes[0].par, 5); assert.equal(s2.course.holes[3].yds, 303);
  assert.equal(s2.course.tees[0].name, 'Blue'); assert.equal(s2.course.tees[0].slope, 131); assert.deepEqual(s2.course.at, { lat: 40.98, lng: -73.68 });
  ok('a club’s next tournament starts with the course from its last Setup');
  // setcourse with a course that isn't there: a plain error, nothing changed
  const { r: bad, j: badj } = await post('/golf/api/club/admin', { pass: PASS, op: 'setcourse', club: cid, course: { id: 'fc-not-a-course' } });
  assert.ok(!bad.ok); assert.ok(badj.error);
  if (process.env.GOLF_CREATE_PASS) { // (wrangler dev with no passcode lets anyone be staff)
    const { r: no, j: noj } = await post('/golf/api/club/admin', { pass: 'wrong', op: 'setcourse', club: cid, course: { id: 'fc-the-preserve-at-ironhorse' } });
    assert.equal(no.status, 403); assert.ok(noj.error);
  }
  // the Flagcast course list's Ironhorse: scorecard and tees (and its map, when the list has one)
  const { j: lib2 } = await post('/golf/api/club/admin', { pass: PASS, op: 'setcourse', club: cid, course: { id: 'fc-the-preserve-at-ironhorse' } });
  assert.match(lib2.courseNote || '', /The Preserve at Ironhorse/);
  const { j: ev3 } = await post('/golf/api/club/admin', { pass: PASS, op: 'event', club: cid, name: 'Third' });
  const s3 = await (await fetch(`${BASE}/golf/api/${ev3.made.id}/state`)).json();
  assert.equal(s3.course.name, 'The Preserve at Ironhorse'); assert.ok(s3.course.tees.length >= 1);
  ok('Admin picks a club’s course from the Flagcast course list; staff only');
  await post('/golf/api/club/admin', { pass: PASS, op: 'delete', club: cid, confirm: after.clubs.find((c) => c.id === cid).name });
}
