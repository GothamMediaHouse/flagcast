// Flagcast TV: the club's TVs. The Flagcast TV app (Apple TV, Google TV, Fire TV, Roku) or any TV's browser at
// /golf/tv/ connects once with a code typed in the Manager, then shows the club's tournament of the day by itself.
// The pairing and the club's TV list live in the club directory (clubs.js, tvRoute); this file routes to it and builds
// the feed the native apps draw (Apple TV and Roku can't show web pages, so they get the pages as data).
//
//   POST /golf/api/tv/hello   { kind }                         → { code, pair, exp }   a new TV shows the code
//   POST /golf/api/tv/wait    { code, pair }                   → { waiting } | { tv, token }   once the club typed the code
//   POST /golf/api/tv/now     { token, today, feed? }          → { tv, club, event | null, next | null, check, feed? }
//   POST /golf/api/tv/add     { id, key | token, code, name, where }   the Manager connects a TV to its club
//   POST /golf/api/tv/list    { id, key | token }               → { tvs }
//   POST /golf/api/tv/edit    { id, key | token, tv, name?, where?, event? }   event: always show this tournament ('' = today's)
//   POST /golf/api/tv/remove  { id, key | token, tv }
//   POST /golf/api/tv/demo    { }                              → like now, for the live Demo tournament ("Watch a demo" on
//                                                               the code screen, for app reviewers and clubs looking around)
//   GET  /golf/api/tv/sponsor/<event>/<sponsor>                a sponsor's logo as a file (Roku can't show data: images)
import { clubs } from './clubs.js';
import { tvFeed } from './tvfeed.js';
import { decodeLogo } from './brand.js';

const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const OPS = ['hello', 'wait', 'now', 'add', 'list', 'edit', 'remove'];

export async function tv(request, env) {
  const url = new URL(request.url);
  let m;
  if ((m = url.pathname.match(/^\/golf\/api\/tv\/sponsor\/([a-z0-9]{8})\/([A-Za-z0-9_-]{1,12})$/)) && (request.method === 'GET' || request.method === 'HEAD')) {
    const S = await stateOf(env, m[1]);
    const l = decodeLogo((S?.sponsors || []).find((x) => x.id === m[2])?.logo);
    if (!l) return json({ error: 'No logo' }, 404);
    return new Response(l.bytes, { headers: { 'Content-Type': l.type, 'Cache-Control': 'public, max-age=300', 'Access-Control-Allow-Origin': '*',
      'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; img-src data:" } });
  }
  const op = url.pathname.slice('/golf/api/tv/'.length);
  if (op === 'demo' && request.method === 'POST') return demo(request, env, `${url.protocol}//${url.host}`);
  if (!OPS.includes(op)) return json({ error: 'Not found' }, 404);
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  const body = await request.text();
  const r = await clubs(new Request(request.url, { method: 'POST', headers: request.headers, body }), env, `tv-${op}`);
  if (op !== 'now' || !r.ok) return r;
  let b = {}; try { b = JSON.parse(body || '{}'); } catch {}
  const j = await r.json();
  if (b.feed && j.event) {
    const S = await stateOf(env, j.event.id);
    if (S) j.feed = tvFeed(S, j.tv.id, `${url.protocol}//${url.host}`);
  }
  return json(j);
}

async function stateOf(env, id) {
  const r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/golf/api/${id}/state`));
  return r.ok ? r.json() : null;
}

// "Watch a demo": the tournament Flagcast Admin marked Demo (the same one the player app's "Try a demo" opens), as a
// TV that isn't any club's would show it. No token: it isn't paired, joins no screens list and counts as no TV.
async function demo(request, env, origin) {
  const none = () => json({ error: 'The demo isn’t available right now. Try again later.' }, 404);
  const r = await clubs(new Request(request.url, { method: 'POST', headers: request.headers, body: '{}' }), env, 'demo-find');
  const { id } = await r.json().catch(() => ({}));
  if (!id) return none();
  const S = await stateOf(env, id);
  if (!S?.brand?.marked) return none();
  return json({ tv: { id: 'demo', name: 'Demo' }, club: { name: 'Flagcast', logo: '', accent: '', flagcast: true },
    event: { id: S.id, name: S.name || 'Demo tournament', date: S.date || '' }, next: null, check: 10, feed: tvFeed(S, '', origin) });
}
