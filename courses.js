// Course lookup for the desk: find a course by name and fill in its par, yardage, stroke index and each set of
// tees' course rating and slope. Data from GolfCourseAPI (golfcourseapi.com), with the key in the
// GOLF_COURSE_API_KEY secret (Cloudflare dashboard → flagcast → Settings → Variables and Secrets).
//   GET /golf/api/courses?q=<name or town>  → { courses: [{ id, name, club, city, state }] }
//   GET /golf/api/courses/fc-<name>         → a Flagcast library course (courselib.js), same shape plus map and library:true
//   POST /golf/api/courses/library {event,key} → save that tournament's course to the library
//   GET /golf/api/courses/<id>              → { id, name, club, city, state, tees: [{ name, women, rating, slope, par, yards, holes: [{ par, yds, hcp }] }] }
import { allowed } from './clubs.js';
const API = 'https://api.golfcourseapi.com/v1';
const DAY = 86400;

const json = (o, s = 200, cache = 0) => new Response(JSON.stringify(o), { status: s, headers: {
  'Content-Type': 'application/json', 'Cache-Control': cache ? `max-age=${cache}` : 'no-store' } });
const num = (v) => (v === null || v === undefined || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));

function shape(c) {
  const loc = c.location || {};
  const name = [c.club_name, c.course_name].filter(Boolean).filter((x, i, a) => a.indexOf(x) === i).join(' · ');
  const tees = [];
  // search results give a count of tees (a number), a course gives the lists
  for (const [side, women] of [['male', false], ['female', true]]) for (const t of [].concat(Array.isArray((c.tees || {})[side]) ? c.tees[side] : [])) {
    tees.push({ name: String(t.tee_name || 'Tees'), women, rating: num(t.course_rating), slope: num(t.slope_rating), par: num(t.par_total),
      yards: num(t.total_yards), holes: (t.holes || []).map((h) => ({ par: num(h.par), yds: num(h.yardage), hcp: num(h.handicap) })) });
  }
  const lat = num(loc.latitude), lng = num(loc.longitude);
  return { id: c.id, name: name || 'Course', club: c.club_name || '', course: c.course_name || '', city: loc.city || '', state: loc.state || '', at: lat != null && lng != null ? { lat, lng } : null, tees };
}

const COMMON = new Set(['the', 'at', 'of', 'and', 'golf', 'club', 'country', 'cc', 'gc', 'g&cc', 'course', 'courses', 'links', 'resort', 'preserve', 'national', 'estates', 'village']);
export function altQueries(q) {
  const words = q.toLowerCase().replace(/[^a-z0-9& ]+/g, ' ').split(/\s+/).filter(Boolean);
  const keep = words.filter((w) => !COMMON.has(w) && w.length > 2);
  const out = [];
  if (keep.length && keep.join(' ') !== words.join(' ')) out.push(keep.join(' '));
  const longest = [...keep].sort((x, y) => y.length - x.length)[0];
  if (longest && longest.length >= 4 && !out.includes(longest) && longest !== words.join(' ')) out.push(longest);
  return out.slice(0, 2);
}

// the Flagcast course library lives in the club directory (clubs.js, courselib.js)
const lib = async (env, op, body) => {
  if (!env.CLUBS) return null;
  const r = await env.CLUBS.get(env.CLUBS.idFromName('directory')).fetch(new Request(`https://clubs/${op}`, { method: 'POST', body: JSON.stringify(body) }));
  return { status: r.status, body: await r.json().catch(() => ({})) };
};

export async function courses(request, env, ctx) {
  const url = new URL(request.url);
  // POST /golf/api/courses/library { event, key } → save that tournament's course to the library for every club
  if (url.pathname === '/golf/api/courses/library') {
    if (request.method !== 'POST') return json({ error: 'POST only' }, 405);
    let b = {}; try { b = await request.json(); } catch {}
    const r = await lib(env, 'lib-save', { event: b.event, key: b.key, pass: b.pass, city: b.city, state: b.state });
    return r ? json(r.body, r.status) : json({ error: 'The course library isn’t available.' }, 501);
  }
  const libId = url.pathname.match(/^\/golf\/api\/courses\/(fc-[a-z0-9-]{1,40})$/)?.[1];
  if (libId) { const r = await lib(env, 'lib-get', { id: libId }); return r ? json(r.body, r.status) : json({ error: 'Not found' }, 404); }
  const id = url.pathname.match(/^\/golf\/api\/courses\/([A-Za-z0-9_-]{1,32})$/)?.[1]; // GolfCourseAPI ids are letters and numbers
  const q = (url.searchParams.get('q') || '').trim().slice(0, 80);
  if (!id && q.length < 3) return json({ error: 'Type at least 3 letters of the course name.' }, 400);
  // search: Flagcast library courses first, then GolfCourseAPI
  const mine = !id ? ((await lib(env, 'lib-search', { q }).catch(() => null))?.body?.courses || []) : [];
  if (!env.GOLF_COURSE_API_KEY) {
    if (mine.length) return json({ courses: mine });
    return json({ error: 'Course lookup isn’t switched on yet. Type the par, rating and slope from the club’s scorecard for now.', off: true }, 501);
  }
  const target = id ? `${API}/courses/${id}` : `${API}/search?search_query=${encodeURIComponent(q)}`;
  const cache = caches.default, key = new Request(`https://flagcast.app/_cache/courses/${id ? `c${id}` : `q/${encodeURIComponent(q.toLowerCase())}`}`);
  const withLib = async (res) => { // library courses go first; the API answer stays cached on its own
    if (id || !mine.length) return res;
    const j = await res.clone().json().catch(() => ({}));
    const seen = new Set(mine.map((c) => c.name.toLowerCase()));
    return json({ courses: [...mine, ...(j.courses || []).filter((c) => !seen.has(String(c.club || c.name).toLowerCase()))] });
  };
  const hit = await cache.match(key); if (hit) return withLib(hit);
  // GolfCourseAPI allows 35 lookups a day on its free plan: 6 an hour and 12 a day from one network, so nobody can use them all
  const ip = request.headers.get('CF-Connecting-IP') || '';
  if (ip && !((await allowed(env, `course-h:${ip}`, 6, 60)) && (await allowed(env, `course-d:${ip}`, 10, 1440)))) {
    return mine.length ? json({ courses: mine }) : json({ error: 'Too many course lookups from this network. Type the numbers from the scorecard, or try again later.' }, 429);
  }
  const ask = async (t) => {
    let r;
    try { r = await fetch(t, { headers: { Authorization: `Key ${env.GOLF_COURSE_API_KEY}`, Accept: 'application/json' } }); }
    catch { return { err: json({ error: 'The course lookup didn’t answer. Try again in a minute.' }, 502) }; }
    if (r.status === 404) return id ? { err: json({ error: 'That course wasn’t found.' }, 404) } : { d: { courses: [] } };
    if (r.status === 429) return { err: json({ error: 'Too many lookups today. Type the numbers from the scorecard, or try again tomorrow.' }, 429) };
    if (!r.ok) return { err: json({ error: `The course lookup had a problem (${r.status}).` }, 502) };
    return { d: await r.json() };
  };
  let a = await ask(target);
  if (a.err) return mine.length ? json({ courses: mine }) : a.err;
  // Clubs get renamed ("The Preserve at Ironhorse" is listed as "Ironhorse Country Club"), so when a name finds
  // nothing, try again with only its distinctive words, then its longest word (at most 2 more lookups).
  if (!id && !(a.d.courses || []).length) {
    for (const alt of altQueries(q)) {
      const b = await ask(`${API}/search?search_query=${encodeURIComponent(alt)}`);
      if (b.err) break;
      if ((b.d.courses || []).length) { a = b; break; }
    }
  }
  const d = a.d;
  const out = id ? shape(d.course || d) : { courses: (d.courses || []).slice(0, 15).map((c) => { const s = shape(c); delete s.tees; return s; }) };
  const res = json(out, 200, DAY);
  ctx?.waitUntil ? ctx.waitUntil(cache.put(key, res.clone())) : await cache.put(key, res.clone());
  return withLib(res);
}
