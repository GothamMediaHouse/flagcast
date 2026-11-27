// A new club's course, set up when Flagcast staff add the club in Admin: they pick the course (Find the course: the
// Flagcast course list or GolfCourseAPI) and this gets its scorecard (par, yards, stroke index), every set of tees
// with rating and slope, where it is, and its hole map (tee, green, hazards, doglegs) from OpenStreetMap. The club
// keeps it (clubs.card and clubs.course), so each of its new tournaments starts with the course already in.
//   clubCourse(env, { id, tee }) → { card: { name, at, holes, tees }, map: { holes, src } | null, note }
import { fetchGolf, buildMap, OSM_CREDIT } from './public/golf/osm.js';

const ID = /^(fc-[a-z0-9-]{1,40}|[A-Za-z0-9_-]{1,32})$/;
const n = (v, lo, hi) => { const x = Number(v); return Number.isFinite(x) && x >= lo && x <= hi ? x : null; };

// the tees a club's tournaments play by default: the men's set nearest 6,400 yards (most clubs' member tees);
// the desk can still pick other tees for a tournament
export function pickTee(tees, want) {
  const T = (tees || []).filter((t) => (t.holes || []).length >= 9);
  if (!T.length) return null;
  if (Number.isInteger(want) && T.includes(tees[want])) return tees[want];
  const men = T.filter((t) => !t.women), pool = men.length ? men : T;
  return pool.slice().sort((a, b) => Math.abs((a.yards || 6400) - 6400) - Math.abs((b.yards || 6400) - 6400))[0];
}

// the course as a tournament's Setup takes it: 18 holes (a 9-hole card fills 1–9), and every set of tees with a rating and slope
export function cardFrom(c, want) {
  const t = pickTee(c.tees, want);
  if (!t) return null;
  const holes = Array.from({ length: 18 }, (_, i) => {
    const h = t.holes[i] || {};
    return { n: i + 1, par: n(h.par, 3, 6) || 4, yds: n(h.yds, 0, 999) || 0, hcp: n(h.hcp, 1, 18) || i + 1 };
  });
  const par = holes.reduce((a, h) => a + h.par, 0);
  const tees = c.tees.filter((x) => x.rating && x.slope).map((x) => ({ name: `${x.name}${x.women ? ' (women)' : ''}`.slice(0, 30),
    rating: x.rating, slope: x.slope, par: x.par && x.par !== par ? x.par : 0, first: x === t }));
  tees.sort((a, b) => b.first - a.first); // the tees picked go first, so players without tees set use them
  const at = c.at && n(c.at.lat, -90, 90) != null && n(c.at.lng, -180, 180) != null ? { lat: +c.at.lat, lng: +c.at.lng } : null;
  return { name: String(c.name || '').slice(0, 80), at, holes, tees: tees.slice(0, 8).map(({ first, ...x }) => x), tee: t.name, nine: t.holes.length <= 9 };
}

// the box to ask OpenStreetMap about: about 1.8 km each way from the course's spot (a big course fits)
export function boxAround({ lat, lng }, km = 1.8) {
  const dLat = km / 110.574, dLng = km / (111.32 * Math.cos((lat * Math.PI) / 180));
  return [lat - dLat, lng - dLng, lat + dLat, lng + dLng];
}

// look: the course lookup (courses.js, loaded here so the tests can run it without the worker); osm: OpenStreetMap
export async function clubCourse(env, ref, { look, osm = fetchGolf } = {}) {
  look = look || (await import('./courses.js')).courses;
  const id = String(ref?.id || '');
  if (!ID.test(id)) throw new Error('Pick the course from the list.');
  const r = await look(new Request(`https://flagcast.app/golf/api/courses/${encodeURIComponent(id)}`), env);
  const c = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(c.error || 'The course lookup didn’t work. Try again.');
  const card = cardFrom(c, Number.isInteger(ref.tee) ? ref.tee : null);
  if (!card) throw new Error('That course has no scorecard in the lookup. Add the club without it, and type the numbers in a tournament’s Setup.');
  const nine = card.nine ? ' (a 9-hole card: holes 1–9)' : '';
  // a Flagcast course-list course brings its own hole map
  if (c.map?.holes && Object.keys(c.map.holes).length) return { card, map: c.map, note: `Course added: ${card.name}, ${card.tee} tees${nine}, with its hole map from the Flagcast course list.` };
  if (!card.at) return { card, map: null, note: `Course added: ${card.name}, ${card.tee} tees${nine}. The lookup doesn’t say where it is, so map the holes in Course map.` };
  let got;
  try { got = buildMap(await osm(boxAround(card.at)), [card.at.lat, card.at.lng]); }
  catch { return { card, map: null, note: `Course added: ${card.name}, ${card.tee} tees${nine}. The map service didn’t answer, so open Course map and press Fill In the Holes.` }; }
  if (!got.found.length) return { card, map: null, note: `Course added: ${card.name}, ${card.tee} tees${nine}. Its holes aren’t on OpenStreetMap, so map them by hand in Course map.` };
  const missing = Array.from({ length: card.nine ? 9 : 18 }, (_, i) => i + 1).filter((k) => !got.found.includes(k));
  return { card, map: { holes: got.holes, src: 'osm' },
    note: `Course added: ${card.name}, ${card.tee} tees${nine}, and ${got.found.length} holes mapped from OpenStreetMap.${missing.length ? ` Not on the map: ${missing.join(', ')}. Place those in Course map.` : ''} Check each hole. ${OSM_CREDIT}.` };
}
