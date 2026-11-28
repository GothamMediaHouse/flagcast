// Flagcast (golf): live scoring for golf tournaments. One Durable Object per tournament holds the
// setup and every score, and pushes each change to the open pages over a WebSocket. The scoring math lives in
// public/golf/core.js and runs in the pages, so this file only checks who may change what and stores it.
//
//   POST /golf/api/new                    { token, name } or { pass, name } → { id, key }   (club accounts: see clubs.js)
//   GET  /golf/api/<id>/state              the public state (setup without codes, scores, contests…)
//   GET  /golf/api/<id>/ws                 WebSocket: { t: 'state', s } on connect and after every change
//   POST /golf/api/<id>/cart               { code } → { teams: [ids] }   which teams a cart's QR code scores for
//   POST /golf/api/<id>/score              { code, team, list: [{ p, h, v, at }] }   p = player id or 'T'
//   POST /golf/api/<id>/desk               { key, op, … }   the tournament desk (see desk() below)
//   POST /golf/api/<id>/pro                { pin, op, … }   a golf pro or marshal with a PIN from the Manager (see pro() below)
//   POST /golf/api/<id>/where              { code, team, at?: [lat, lng], acc, hole, hide? }   a group's spot, from a scorecard with GPS on
//                                          → { groups }   where the other groups are, for the golfers' course map
//   POST /golf/api/<id>/live               { code, team, token, env, player? } | { code, team, token, end: true }   the lock screen live view (liveact.js)
//   GET  /golf/api/<id>/photo/<slot>       a photo the club added: cover, h<n> (a hole), s-<sponsor id> (a banner)
//   POST /golf/api/<id>/enter              { code, team, contest, player, dist, at?: [lat, lng], acc? }   a golfer's own long drive / closest to the pin
//                                          (only when the contest lets golfers enter; at = where the phone is, for a GPS drive from the tee)
//   POST /golf/api/<id>/hit                { list: [{ s: sponsorId, k: 'view'|'tap'|'secs', n }] }   sponsor counts for the report
//   GET  /golf/api/demo                    → { id, name, code, team }   "Try a demo": the newest Demo tournament and its sample cart
//
// Pages: /g/<id> live page · /g/<id>/board screens · /g/<id>/desk#<key> desk · /g/<id>/map#<key> course map · /g/<id>/s/<code> cart · /g/<id>/cards QR cards
import { DurableObject } from 'cloudflare:workers';
import { defaultHoles, courseHcp, leaderboard, contestNeedsOk, teamBall, CLIP_BACK, paceGoal, paceOrder } from './public/golf/core.js';
import { trackingOn, cleanPin, yds, holeMap } from './public/golf/gps.js';
import { demoGroups, demoPace } from './demogroups.js';
import { same, pinProblem, mergeTeams, stamp, keepMatch, PIN_WAIT, PIN_TRIES_IP, PIN_TRIES_ALL } from './setup.js';
import { clubs, sendBatch } from './clubs.js';
import { EMAILS, mailHtml, mailText, cleanEmail } from './mail.js';
import { clubCourse } from './clubcourse.js';
import { resultsRows, ghinRows } from './report.js';
import { camPlaylist } from './stream.js';
import { tv } from './tv.js';
import { liveCard, cardKey, livePayload, sendLive, TOKEN, LIVE_MAX, LIVE_HOURS } from './liveact.js';
import { brandFor, logoOf, cleanLogo, decodeLogo, cleanPhoto, photoLinks, PHOTO_SLOT } from './brand.js';

const ID = /^[a-z0-9]{8}$/;
const CODE = /^[A-HJ-NP-Z2-9]{6}$/;
const rand = (n, abc) => { const b = crypto.getRandomValues(new Uint8Array(n)); return [...b].map((x) => abc[x % abc.length]).join(''); };
const newId = () => rand(8, 'abcdefghijkmnpqrstuvwxyz23456789');
export const newCode = () => rand(6, 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789');
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
// the Flagcast phone app runs its pages from the phone itself, so the API answers those origins too
const APP_ORIGINS = new Set(['capacitor://localhost', 'https://localhost', 'http://localhost', 'ionic://localhost']);
const cors = (request, r) => {
  const o = request.headers.get('Origin');
  if (!o || !APP_ORIGINS.has(o) || r.status === 101) return r;
  const h = new Headers(r.headers); h.set('Access-Control-Allow-Origin', o); h.set('Vary', 'Origin');
  return new Response(r.body, { status: r.status, headers: h });
};
const preflight = (request) => new Response(null, { status: 204, headers: {
  'Access-Control-Allow-Origin': APP_ORIGINS.has(request.headers.get('Origin')) ? request.headers.get('Origin') : 'null',
  'Access-Control-Allow-Methods': 'GET, POST', 'Access-Control-Allow-Headers': 'Content-Type', 'Access-Control-Max-Age': '86400', Vary: 'Origin' } });

const PAGES = { '': '/golf/live/', board: '/golf/board/', desk: '/golf/desk/', cards: '/golf/cards/', map: '/golf/map/' };

// which live inputs are Flagcast's cameras, remembered for a while so playlist reloads (every 2 s per viewer) don't
// all go to the directory
const camOK = new Map();
async function isCam(env, uid) {
  const c = camOK.get(uid); if (c && Date.now() - c.at < (c.ok ? 600e3 : 30e3)) return c.ok;
  const r = await env.CLUBS.get(env.CLUBS.idFromName('directory')).fetch(new Request('https://clubs/streamok', { method: 'POST', body: JSON.stringify({ uid }) }));
  const ok = !!(await r.json().catch(() => ({}))).ok;
  if (camOK.size > 500) camOK.clear();
  camOK.set(uid, { ok, at: Date.now() }); return ok;
}

// Admin's "create" (a new club) and "setcourse" (a club's course) with a course picked: { course: { id, tee } }. The worker
// looks it up (the directory can't reach the course lookup itself) and sends the directory the finished scorecard and
// hole map; a card or map sent by the app itself is never kept. The answer says what was filled in (courseNote).
export async function adminWithCourse(request, env, find = clubCourse) {
  const text = await request.text();
  let b; try { b = JSON.parse(text); } catch { return clubs(new Request(request.url, { method: 'POST', headers: request.headers, body: text }), env, 'admin'); }
  delete b.card; delete b.map;
  let note = '';
  if ((b.op === 'create' || b.op === 'setcourse') && b.course && b.course.id) {
    // only for Flagcast staff: check who's asking before using a lookup
    const ok = await clubs(new Request(request.url, { method: 'POST', headers: request.headers, body: JSON.stringify({ ...b, op: 'staffcheck' }) }), env, 'admin');
    if (!ok.ok) return ok;
    try { const got = await find(env, b.course); b.card = got.card; b.map = got.map; note = got.note; }
    catch (e) {
      if (b.op === 'setcourse') return json({ error: e.message || 'The course lookup didn’t work.' }, 502);
      note = `The club is set up, but its course wasn’t added: ${e.message || 'the lookup didn’t work.'}`;
    }
  }
  delete b.course;
  const r = await clubs(new Request(request.url, { method: 'POST', headers: request.headers, body: JSON.stringify(b) }), env, 'admin');
  if (!note || !r.ok) return r;
  const j = await r.json().catch(() => null);
  return j ? json({ ...j, courseNote: note }) : r;
}

export async function golf(request, env) {
  const url = new URL(request.url);
  let m;
  if (request.method === 'OPTIONS' && url.pathname.startsWith('/golf/api/')) return preflight(request);
  // "Try a demo" in the player and TV apps: the live Demo tournament and its sample cart, no code or sign-in
  if (url.pathname === '/golf/api/demo' && (request.method === 'GET' || request.method === 'HEAD')) {
    const none = () => cors(request, json({ error: 'The demo isn’t available right now. Try again later.' }, 404));
    const r = await env.CLUBS.get(env.CLUBS.idFromName('directory')).fetch(new Request('https://clubs/demo-find', { method: 'POST', body: '{}' }));
    const { id } = await r.json().catch(() => ({}));
    if (!id) return none();
    const t = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/golf/api/${id}/try`, { method: 'POST', body: '{}' }));
    if (!t.ok) return none();
    return cors(request, json(await t.json()));
  }
  // making a tournament and the club accounts go through the club directory (clubs.js)
  if (url.pathname === '/golf/api/new') return cors(request, await clubs(request, env, 'new'));
  // Admin adding a club with its course: look the course up (scorecard, tees, hole map) here, then the directory keeps it
  if (url.pathname === '/golf/api/club/admin' && request.method === 'POST') return cors(request, await adminWithCourse(request, env));
  if ((m = url.pathname.match(/^\/golf\/api\/club\/(start|verify|login|apple|google|config|setpass|me|request|invite|uninvite|hide|signout|admin|brand)$/))) return cors(request, await clubs(request, env, m[1]));
  // a club's logo, for the Manager apps and Admin (its tournaments serve their own at /golf/api/<id>/logo)
  if ((m = url.pathname.match(/^\/golf\/api\/club\/logo\/([a-z0-9]{4,10})$/)) && request.method === 'GET') {
    const r = await env.CLUBS.get(env.CLUBS.idFromName('directory')).fetch(new Request(`https://clubs/logo-get`, { method: 'POST', body: JSON.stringify({ club: m[1] }) }));
    const j = await r.json().catch(() => ({})); const l = decodeLogo(j.logo);
    if (!l) return json({ error: 'This club has no logo yet.' }, 404);
    return new Response(l.bytes, { headers: { 'Content-Type': l.type, 'Cache-Control': 'public, max-age=86400', 'Access-Control-Allow-Origin': '*',
      'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; img-src data:" } });
  }
  // Sign in with Google from the Manager apps: Google posts the ID token here (form, with its double-submit CSRF
  // cookie), and the app's sign-in sheet gets the Flagcast session back on flagcastmanager://signin
  // Sign in with Apple on the web, Mac and Windows (Apple's JS, form_post): Apple posts the ID token here with the state
  // the sign-in page made (and kept in a cookie, so nobody else's page can post a sign-in in). The apps get the session
  // on flagcastmanager://signin; the website on /golf/#signin=… (the fragment never reaches a server)
  if (url.pathname === '/golf/api/club/apple-web' && request.method === 'POST') {
    const f = await request.formData().catch(() => null);
    const state = String(f?.get('state') || ''), cookie = (request.headers.get('Cookie') || '').match(/(?:^|;\s*)fc_apple_state=([^;]+)/)?.[1];
    const mode = state.split('.')[1] || 'web';
    const back = (q) => mode === 'app' ? Response.redirect(`flagcastmanager://signin?${q}`, 302)
      : new Response(null, { status: 302, headers: { Location: `/golf/${mode === 'admin' ? 'admin/' : ''}#${q.replace(/^token=/, 'signin=')}`, 'Set-Cookie': 'fc_apple_state=; Path=/golf/; Max-Age=0; Secure; SameSite=None' } });
    if (!f || !cookie || !state || state !== decodeURIComponent(cookie)) return back('error=' + encodeURIComponent('That Apple sign-in didn’t work. Try again.'));
    const r = await clubs(new Request(request.url, { method: 'POST', body: JSON.stringify({ identityToken: f.get('id_token') }) }), env, 'apple');
    const j = await r.json().catch(() => ({}));
    return back(j.token ? `token=${encodeURIComponent(j.token)}` : `error=${encodeURIComponent(j.error || 'That Apple sign-in didn’t work.')}`);
  }
  if (url.pathname === '/golf/api/club/google-app' && request.method === 'POST') {
    const f = await request.formData().catch(() => null);
    const cookies = request.headers.get('Cookie') || '';
    const cookie = cookies.match(/(?:^|;\s*)g_csrf_token=([^;]+)/)?.[1];
    // where the sign-in page said to send the session: the apps (the default), the website or Admin
    const mode = cookies.match(/(?:^|;\s*)fc_google_mode=(app|web|admin)(?:;|$)/)?.[1] || 'app';
    const back = (q) => mode === 'app' ? Response.redirect(`flagcastmanager://signin?${q}`, 302)
      : new Response(null, { status: 302, headers: { Location: `/golf/${mode === 'admin' ? 'admin/' : ''}#${q.replace(/^token=/, 'signin=')}`, 'Set-Cookie': 'fc_google_mode=; Path=/golf/; Max-Age=0; Secure; SameSite=None' } });
    if (!f || !cookie || f.get('g_csrf_token') !== cookie) return back('error=' + encodeURIComponent('That Google sign-in didn’t work. Try again.'));
    const r = await clubs(new Request(request.url, { method: 'POST', body: JSON.stringify({ idToken: f.get('credential') }) }), env, 'google');
    const j = await r.json().catch(() => ({}));
    return back(j.token ? `token=${encodeURIComponent(j.token)}` : `error=${encodeURIComponent(j.error || 'That Google sign-in didn’t work.')}`);
  }
  // the Flagcast TV apps and the TV page (tv.js)
  if (url.pathname.startsWith('/golf/api/tv/')) return cors(request, await tv(request, env));
  // NDI cameras on Cloudflare Stream: Flagcast's own HLS for them, with a rewind window and replay clips (stream.js).
  // Only for live inputs Flagcast made (the directory's streams table), so this can't relay anyone else's video.
  if ((m = url.pathname.match(/^\/golf\/api\/cam\/([0-9a-f]{32})\/(video|[va][0-9]{1,12})\.m3u8$/))) {
    if (request.method !== 'GET' && request.method !== 'HEAD') return json({ error: 'Use GET' }, 405);
    if (!(await isCam(env, m[1]))) return json({ error: 'There is no Flagcast camera at this address.' }, 404);
    return camPlaylist(fetch, m[1], m[2], url.searchParams);
  }
  // the photos a club added for its golfers (brand.js): GET only
  if ((m = url.pathname.match(/^\/golf\/api\/([a-z0-9]{8})\/photo\/([a-z0-9-]{1,14})$/)) && (request.method === 'GET' || request.method === 'HEAD')) {
    return cors(request, await env.GOLF.get(env.GOLF.idFromName(m[1])).fetch(request));
  }
  if ((m = url.pathname.match(/^\/golf\/api\/([a-z0-9]{8})\/(state|ws|cart|score|desk|pro|hit|where|live|logo|enter|clip)$/))) {
    const stub = env.GOLF.get(env.GOLF.idFromName(m[1]));
    return cors(request, await stub.fetch(request));
  }
  if ((m = url.pathname.match(/^\/g\/([a-z0-9]{8})(?:\/(board|desk|cards|map|s\/[A-HJ-NP-Z2-9]{6}))?\/?$/)) && request.method === 'GET') {
    const page = m[2]?.startsWith('s/') ? '/golf/score/' : PAGES[m[2] || ''];
    const r = await env.ASSETS.fetch(new Request(new URL(page, url), request));
    const h = new Headers(r.headers); h.set('Cache-Control', 'no-cache'); h.set('X-Robots-Tag', 'noindex'); h.set('Referrer-Policy', 'no-referrer');
    return new Response(r.body, { status: r.status, headers: h });
  }
  return null;
}

const clip = (s, n) => String(s ?? '').slice(0, n);
// "Try a demo": a Demo tournament's last cart is the one the button opens (see score() and op 'try')
const TRY_RESET = 3 * 3600000;
const tryTeam = (ev) => [...(ev.teams || [])].reverse().find((t) => t.code) || null;
const isTryTeam = (ev, team) => !!ev.demo && tryTeam(ev)?.id === team.id;
// sponsor spots: title (everywhere), leaderboard, hole (scorecard + the hole's page), cam (bug on a par 3 camera),
// contest (closest to the pin / long drive on its holes), turn (card after the 9th), ace (hole-in-one take-over), slide (big-screen slide)
export const SPOTS = ['title', 'leaderboard', 'hole', 'cam', 'contest', 'turn', 'ace', 'slide'];
// what a screen's playlist can hold
// (cam = one hole's camera, full frame)
export const PAGE_KINDS = ['lb', 'matches', 'indiv', 'p3', 'cam', 'contests', 'skins', 'fund', 'sponsors', 'sponsor', 'schedule'];
// changes made on the day (desk or a pro's PIN); marshals only post contest results
const INVITE_MAX = 4, INVITE_TOTAL = 1500; // emails per player (the first and 3 resends), and per tournament
const DAY_OPS = new Set(['fix', 'ctp', 'contest', 'check', 'flash', 'nudge', 'screen', 'take', 'lock', 'fund', 'stats', 'replay', 'scene', 'map', 'groups', 'pinsheet', 'report', 'team', 'move', 'notes', 'golive', 'camshow', 'pace']);
// marshals post contest results and replays of shots at their hole
const MARSHAL_OPS = new Set(['ctp', 'check', 'replay']);
// a replay with no clip link replays the hole's live camera from this many seconds before it was marked
export const REPLAY_BACK = 25;
const num = (v, lo, hi, d) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
// what golfers see of the other groups on the course (POST …/where): name, hole and spot, no codes. Hidden
// groups and spots older than 15 minutes are left out; your own group is marked me (even when hidden).
export const GOLFER_SPOT_MINS = 15;
// the notes golfers can send another group from the course map: ready-made only, so nothing rude gets typed.
// The desk can turn them off (day op 'notes'). Index in this list is what a phone sends.
export const GOLFER_NOTES = ['Nice round! 👏', 'Want to play through?', 'See you at the turn', 'We found a ball. Is it yours?'];
export const GOLFER_NOTE_GAP = 60000; // one note a minute from each group
export function golferGroups(ev, wh, mine, now = Date.now()) {
  const name = (t) => t.name || t.players.map((p) => String(p.name || '').split(' ').slice(-1)[0]).join(' / ');
  return ev.teams.filter((t) => { const w = wh[t.id]; return w && w.at && (t.id === mine || (!w.hide && now - w.t <= GOLFER_SPOT_MINS * 60000)); })
    .map((t) => ({ team: t.id, name: name(t), hole: wh[t.id].hole || 0, at: wh[t.id].at, acc: wh[t.id].acc || 0, t: wh[t.id].t, since: wh[t.id].since || wh[t.id].t, ...(t.id === mine ? { me: true } : {}) }))
    .concat(ev.demo ? sampleGroups(ev, wh, mine, now).map(({ start, ...g }) => g) : []);
}
// a Demo tournament: sample groups walk the course (demogroups.js) so the maps aren't empty. Teams with a real
// phone on the map (and your own) are left to that phone.
export function sampleGroups(ev, wh, mine, now = Date.now()) {
  const real = new Set(ev.teams.filter((t) => t.id === mine || (wh[t.id] && now - wh[t.id].t <= GOLFER_SPOT_MINS * 60000)).map((t) => t.id));
  return demoGroups(ev, now, real);
}

// the course map for hole GPS: per hole the tee, the front, middle and back of the green, and hazards
// (p = where you reach it, c = what carries it). Points are [lat, lng]. Shared by every tournament at the club.
const pt = (a) => (Array.isArray(a) && a.length === 2 && Math.abs(a[0]) <= 90 && Math.abs(a[1]) <= 180 && Number.isFinite(+a[0]) && Number.isFinite(+a[1])
  ? [Math.round(+a[0] * 1e6) / 1e6, Math.round(+a[1] * 1e6) / 1e6] : null);
export const HAZARDS = ['bunker', 'water', 'trees', 'layup', 'other'];
export function cleanMap(m) {
  const holes = {};
  for (let n = 1; n <= 18; n++) {
    const h = m?.holes?.[n] || m?.holes?.[String(n)]; if (!h) continue;
    const o = { tee: pt(h.tee), f: pt(h.f), m: pt(h.m), b: pt(h.b),
      // the hole's line between the tee and the green (doglegs): where the flyover and course view turn
      line: (Array.isArray(h.line) ? h.line : []).slice(0, 12).map(pt).filter(Boolean),
      hz: (Array.isArray(h.hz) ? h.hz : []).slice(0, 12).map((z) => ({ id: clip(z.id, 8) || rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'),
        k: HAZARDS.includes(z.k) ? z.k : 'other', n: clip(z.n, 40), p: pt(z.p), c: pt(z.c) })).filter((z) => z.p) };
    if (o.tee || o.f || o.m || o.b || o.hz.length) holes[n] = o;
  }
  return { holes, src: m?.src === 'osm' ? 'osm' : '' }; // osm: made from OpenStreetMap (credit shown with it)
}

// the setup as the desk sends it, tidied so nothing odd gets stored
// a Manager saves the whole setup, and one that loaded it before a club TV joined doesn't know that TV: keep the club's
// TVs (removing one is done from the club's TV list, tv.js), and keep them marked as TVs whatever the app sends back
function keepTVs(s, before) {
  const tvs = (before || []).filter((d) => d.tv);
  // only the club directory adds a club TV (tvjoin): one the server doesn't have was removed since the app loaded it
  s.displays = s.displays.filter((d) => !d.tv || tvs.some((t) => t.id === d.id));
  for (const d of s.displays) if (tvs.some((t) => t.id === d.id)) d.tv = true;
  for (const t of tvs) if (!s.displays.some((d) => d.id === t.id) && s.displays.length < 20) s.displays.push(t);
}

function cleanSetup(s, old) {
  const holes = Array.from({ length: 18 }, (_, i) => {
    const h = (s.course?.holes || [])[i] || old.course.holes[i] || {};
    return { n: i + 1, par: num(h.par, 3, 6, 4), yds: num(h.yds, 0, 999, 0), hcp: num(h.hcp, 1, 18, i + 1) };
  });
  // tees for handicaps: slope and course rating (par only when it differs from the card)
  const tees = (Array.isArray(s.course?.tees) ? s.course.tees : (old.course?.tees || [])).slice(0, 8).map((x) => ({
    id: /^[a-z0-9]{2,12}$/.test(x.id || '') ? x.id : rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'), name: clip(x.name, 30),
    slope: num(x.slope, 55, 155, 113), rating: Math.round(num(x.rating, 50, 90, 72) * 10) / 10, par: num(x.par, 0, 80, 0) || 0,
  })).filter((x) => x.name);
  const par = holes.reduce((a, h) => a + h.par, 0);
  const codes = new Map((old.teams || []).map((t) => [t.id, t.code]));
  // players' emails (for invites): a Manager from before invites doesn't send them, so a player sent without one keeps theirs
  const mails = new Map((old.teams || []).flatMap((t) => (t.players || []).map((p) => [p.id, p.email || ''])));
  const teams = (Array.isArray(s.teams) ? s.teams : []).slice(0, 200).map((t) => {
    const id = /^[a-z0-9]{4,12}$/.test(t.id || '') ? t.id : rand(6, 'abcdefghijkmnpqrstuvwxyz23456789');
    return {
      id, code: codes.get(id) || newCode(), name: clip(t.name, 60), flight: clip(t.flight, 12), start: num(t.start, 1, 18, 1),
      hcp: num(t.hcp, -10, 54, 0), cart: clip(t.cart, 12),
      side: ['A', 'B'].includes(t.side) ? t.side : '', // match play team cup: which side the team plays for
      players: (Array.isArray(t.players) ? t.players : []).slice(0, 4).map((p) => ({
        id: /^[a-z0-9]{2,12}$/.test(p.id || '') ? p.id : rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'),
        name: clip(p.name, 50), hcp: num(p.hcp, -10, 54, 0), guest: !!p.guest,
        // GHIN number and Handicap Index: with a tee, the course handicap is worked out from them
        ghin: String(p.ghin || '').replace(/\D/g, '').slice(0, 11),
        index: p.index === null || p.index === '' || p.index === undefined || !Number.isFinite(Number(p.index)) ? null : Math.round(num(p.index, -10, 54, 0) * 10) / 10,
        tee: clip(p.tee, 12),
        email: p.email === undefined ? mails.get(p.id) || '' : cleanEmail(p.email),
      })).map((p) => {
        if (p.index == null) return p;
        const tee = tees.find((x) => x.id === p.tee) || tees[0];
        if (!tee) return p;
        return { ...p, tee: tee.id, hcp: courseHcp(p.index, tee, par) };
      }),
    };
  });
  const f = s.format || {};
  return {
    name: clip(s.name, 80), club: clip(s.club, 80), date: clip(s.date, 20), course: { name: clip(s.course?.name, 80), holes, tees,
      // where the course is (from Find the course), so the course map opens on it
      at: (() => { const a = s.course?.at || old.course?.at; const lat = Number(a?.lat), lng = Number(a?.lng);
        return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && (lat || lng) ? { lat, lng } : null; })() },
    format: { type: ['bestball', 'shamble', 'stroke', 'scramble', 'stableford', 'match'].includes(f.type) ? f.type : 'bestball',
      count: num(f.count, 1, 4, 1), allowance: num(f.allowance, 0, 100, 100), show: f.show === 'gross' ? 'gross' : 'net',
      nine: ['front', 'back'].includes(f.nine) ? f.nine : '', // '' = all 18 holes
      // match play: singles, four-ball (best ball a side) or scramble (one ball a side); cup = two sides playing for points
      match: ['singles', 'fourball', 'scramble'].includes(f.match) ? f.match : 'fourball',
      cup: { on: !!f.cup?.on, a: clip(f.cup?.a, 20) || 'Reds', b: clip(f.cup?.b, 20) || 'Blues' },
      // a leaderboard of every player on their own (club championships): shown next to the team board
      indiv: !!f.indiv },
    // match play pairings: team a v team b (each team once)
    matches: (() => {
      const ids = new Set(teams.map((t) => t.id)), used = new Set();
      return (Array.isArray(s.matches) ? s.matches : []).slice(0, 100).map((m) => ({
        id: /^[a-z0-9]{3,12}$/.test(m?.id || '') ? m.id : rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'), a: String(m?.a || ''), b: String(m?.b || '') }))
        .filter((m) => m.a !== m.b && ids.has(m.a) && ids.has(m.b) && !used.has(m.a) && !used.has(m.b) && used.add(m.a) && used.add(m.b));
    })(),
    sideGames: s.sideGames !== false, // each cart's own side games on the scorecard, for points only (no money)
    flights: (Array.isArray(s.flights) ? s.flights : []).slice(0, 12).map((x) => clip(x, 12)).filter(Boolean),
    teams,
    screens: { title: clip(s.screens?.title, 80), ticker: clip(s.screens?.ticker, 300), seconds: num(s.screens?.seconds, 5, 60, 12),
      skins: !!s.screens?.skins, rows: num(s.screens?.rows, 5, 20, 10) },
    cams: Object.fromEntries(Object.entries(s.cams || {}).filter(([h, u]) => Number.isInteger(Number(h)) && Number(h) >= 0 && Number(h) <= 18 && /^https:\/\//.test(u || '')).map(([h, u]) => [Number(h), clip(u, 500)])),
    // spot: where the sponsor shows (see SPOTS). holes: which holes, for hole, camera and contest spots
    sponsors: (Array.isArray(s.sponsors) ? s.sponsors : []).slice(0, 60).map((x) => {
      const holes = (Array.isArray(x.holes) ? x.holes : []).map(Number).filter((h) => h >= 1 && h <= 18);
      return {
        id: clip(x.id, 12) || rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'), name: clip(x.name, 60), line: clip(x.line, 120),
        spot: SPOTS.includes(x.spot) ? x.spot : (holes.length ? 'hole' : 'slide'), holes,
        logo: typeof x.logo === 'string' && x.logo.startsWith('data:image/') && x.logo.length < 200000 ? x.logo : '',
        url: /^https:\/\//.test(x.url || '') ? clip(x.url, 300) : '', offer: clip(x.offer, 200),
      };
    }),
    schedule: (Array.isArray(s.schedule) ? s.schedule : []).slice(0, 20).map((x) => ({ time: clip(x.time, 20), what: clip(x.what, 80) })).filter((x) => x.what),
    // golf pros and marshals sign in to the phone app with these. Never sent to the public pages
    pins: (Array.isArray(s.pins) ? s.pins : []).slice(0, 20).map((x) => ({
      id: /^[a-z0-9]{3,12}$/.test(x.id || '') ? x.id : rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'),
      name: clip(x.name, 40), role: x.role === 'marshal' ? 'marshal' : 'pro', pin: String(x.pin || '').replace(/\D/g, '').slice(0, 8),
    })).filter((x) => x.name && x.pin.length >= 4),
    // each TV or LED wall at the club and what it plays (a board page opened with ?screen=<id>)
    displays: (Array.isArray(s.displays) ? s.displays : []).slice(0, 20).map((d) => ({
      id: /^[a-z0-9]{3,12}$/.test(d.id || '') ? d.id : rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'), name: clip(d.name, 40),
      where: clip(d.where, 40), group: clip(d.group, 24), // where it hangs ("Clubhouse bar") and a group to send to together ("Clubhouse")
      ...(d.tv ? { tv: true } : {}), // one of the club's TVs (the Flagcast TV app, tv.js): it joins each tournament by itself
      playlist: (Array.isArray(d.playlist) ? d.playlist : []).slice(0, 30).filter((x) => PAGE_KINDS.includes(x.k)).map((x) => ({
        k: x.k, fl: clip(x.fl, 12), hole: num(x.hole, 0, 18, 0), sponsor: clip(x.sponsor, 12), secs: num(x.secs, 4, 300, 12) })),
    })),
    fund: { on: !!s.fund?.on, label: clip(s.fund?.label, 80), goal: num(s.fund?.goal, 0, 1e9, 0), raised: num(s.fund?.raised, 0, 1e9, 0), give: /^https:\/\//.test(s.fund?.give || '') ? clip(s.fund.give, 300) : '' },
    contests: (Array.isArray(s.contests) ? s.contests : []).slice(0, 30).map(cleanContest),
  };
}

// a long drive or closest to the pin contest. self: golfers enter their own results on the contest hole (default on).
// check: which golfer entries wait for a pro's OK before they count on the TVs: 'top' (any that would make the top 3,
// the default), 'all' or 'none' (trust golfers). prize: points for the winner, 0 = none (points only, never money).
// An entry: { name, dist, ok, by, team?, player?, gps?, at?, okBy? }. dist is yards (long drive) or feet (closest);
// ok false = waiting for a check (phones show it with a clock, TVs leave it off); gps = yards from the tee the phone measured.
export function cleanContest(c) {
  c = c || {};
  return {
    id: clip(c.id, 12) || rand(5, 'abcdefghijkmnpqrstuvwxyz23456789'), kind: c.kind === 'ld' ? 'ld' : 'ctp', hole: num(c.hole, 1, 18, 1),
    label: clip(c.label, 60), sponsor: clip(c.sponsor, 60),
    self: c.self !== false, check: ['all', 'none'].includes(c.check) ? c.check : 'top', prize: Math.round(num(c.prize, 0, 100000, 0)),
    entries: (Array.isArray(c.entries) ? c.entries : []).slice(0, 200).map(cleanEntry).filter((e) => e.name),
  };
}
const cleanEntry = (e) => {
  e = e || {};
  const out = { name: clip(e.name, 50).trim(), dist: Math.round(num(e.dist, 0, 999, 0) * 100) / 100, ok: e.ok !== false, by: clip(e.by, 40) };
  if (e.team) out.team = clip(e.team, 12);
  if (e.player) out.player = clip(e.player, 12);
  if (Number(e.gps) > 0) out.gps = Math.round(num(e.gps, 0, 999, 0));
  if (Number(e.at) > 0) out.at = Number(e.at);
  if (e.okBy) out.okBy = clip(e.okBy, 40);
  return out;
};
// the same player: by player id when both have one, else by name
const samePlayer = (a, b) => (a.player && b.player ? a.player === b.player : a.name.toLowerCase() === b.name.toLowerCase());
// a golfer's distance must look like golf: a long drive of 50 to 450 yards, a closest to the pin under 200 feet
export const contestRange = (c) => (c.kind === 'ld' ? [50, 450] : [0.01, 200]);
// every contest change (golfer entries, checks, fixes) for the desk; never in the public state
const contestLog = (ev, x) => { ev.clog = [...(ev.clog || []), { at: Date.now(), ...x }].slice(-300); };

export class GolfEvent extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async load() {
    if (!this.ev) this.ev = await this.ctx.storage.get('event');
    return this.ev;
  }
  async scores() {
    if (!this.sc) {
      this.sc = {};
      for (const [k, v] of await this.ctx.storage.list({ prefix: 's:' })) this.sc[k.slice(2)] = v;
    }
    return this.sc;
  }

  // what anyone can see: the setup without the cart codes or the desk key
  async publicState() {
    const ev = await this.load(), sc = await this.scores();
    const { key, pins, log, clog, logo, clubBrand, demo, photos, removed, invites, ...rest } = ev; // logos and photos go by address, not in the state

    const teams = ev.teams.map(({ code, sv, ...t }) => ({ ...t, players: t.players.map(({ ghin, email, ...p }) => p) })); // GHIN numbers and emails stay with the desk
    const online = Object.fromEntries((ev.displays || []).map((d) => [d.id, this.ctx.getWebSockets(`d:${d.id}`).length]));
    const scores = {}, lastAt = {};
    for (const t of ev.teams) {
      const s = sc[t.id]; if (!s) continue;
      scores[t.id] = Object.fromEntries(Object.entries(s).map(([p, arr]) => [p, arr.map((x) => (x ? x.v : null))]));
      // when each cart last entered a score (the Manager's "Day of" check and Admin's event-day view)
      const at = Math.max(0, ...Object.values(s).flatMap((arr) => arr.map((x) => (x ? x.at || 0 : 0))));
      if (at) lastAt[t.id] = at;
    }
    // the round and hole clocks (core.js paceOf); a Demo tournament's made-up teams get clocks to match their scores
    const real = await this.paceData();
    // (not the "Try a demo" cart: its clock starts when the scorecard opens, see the scorecard's myPace)
    const pace = demo ? { ...demoPace(ev, scores, Date.now(), new Set([...Object.keys(real), tryTeam(ev)?.id])), ...real } : real;
    return { ...rest, teams, scores, lastAt, online, pace, paceGoal: paceGoal(ev), brand: brandFor(ev), photos: photoLinks(ev) };
  }

  // ---- pace of play: ev.pace in the public state (see core.js paceOf), kept under its own key ----
  async paceData() {
    if (!this.pc) this.pc = (await this.ctx.storage.get('pace')) || {};
    return this.pc;
  }
  // a cart's first score on each hole is when the group finished it. The round starts when the GPS first puts the group
  // on its first hole (see where), or with no GPS, one hole's worth of the goal before its first score. Later changes
  // to a score don't move the time, and the desk's fixes (often a whole card after the round) aren't counted.
  async paceScored(team, holes, now, start = 0) {
    if (!holes.length) return false;
    const pc = await this.paceData(), p = pc[team.id] = pc[team.id] || { d: {} }, ev = this.ev;
    const per = paceGoal(ev) * 60000 / 18, first = paceOrder(ev, team)[0];
    let changed = false;
    for (const h of holes) if (!p.d[h]) { p.d[h] = now; changed = true; }
    if (!changed) return false;
    // "Try a demo": the phone says when its scorecard opened (within the 3 hours a demo round lasts)
    const st = Number(start) || 0;
    if (!p.s) p.s = isTryTeam(ev, team) && st <= now && now - st < TRY_RESET ? st : now - per;
    // GPS on the first tee long before the shotgun: the round started no more than two holes' worth before its first score
    if (p.d[first] && p.d[first] - p.s > 2 * per) p.s = p.d[first] - per;
    await this.ctx.storage.put('pace', pc);
    return true;
  }

  async broadcast() {
    const s = JSON.stringify({ t: 'state', s: await this.publicState() });
    for (const w of this.ctx.getWebSockets()) { try { w.send(s); } catch {} }
    this.ctx.waitUntil(this.liveUpdate().catch(() => {}));
  }

  // ---- the golfers' lock screen live view (liveact.js): one Apple push token per phone, for its team ----
  async liveTokens() {
    if (!this.la) this.la = (await this.ctx.storage.get('la')) || {};
    return this.la;
  }
  async live(b) {
    const ev = this.ev, team = ev.teams.find((t) => t.id === b.team);
    if (!team || team.code !== String(b.code || '').toUpperCase()) return json({ error: 'Not your scorecard' }, 403);
    const token = String(b.token || '').toLowerCase();
    if (!TOKEN.test(token)) return json({ error: 'Bad token' }, 400);
    const la = await this.liveTokens(), now = Date.now();
    if (b.end) delete la[token];
    else {
      const was = la[token];
      la[token] = { team: team.id, env: b.env === 'dev' ? 'dev' : 'prod', player: String(b.player || '').slice(0, 12), at: now,
        last: was && was.team === team.id ? was.last : '', msgAt: was && was.team === team.id ? was.msgAt || 0 : 0 };
      const old = Object.entries(la).filter(([, x]) => now - x.at > LIVE_HOURS * 3600e3).map(([k]) => k);
      for (const k of old) delete la[k];
      const keys = Object.keys(la); if (keys.length > LIVE_MAX) for (const k of keys.sort((x, y) => la[x].at - la[y].at).slice(0, keys.length - LIVE_MAX)) delete la[k];
    }
    await this.ctx.storage.put('la', la);
    if (!b.end) this.ctx.waitUntil(this.liveUpdate().catch(() => {}));
    return json({ ok: true, card: b.end ? null : liveCard(ev, (await this.publicState()).scores, team.id, la[token].player, now) });
  }
  // after every change: each registered phone whose card changed gets it from Apple. One run at a time;
  // a change during a run makes it go round again.
  async liveUpdate() {
    if (this.laBusy) { this.laAgain = true; return; }
    if (!this.env.APNS_KEY || !this.env.APNS_KEY_ID) return;
    const la = await this.liveTokens(); if (!Object.keys(la).length) return;
    this.laBusy = true;
    try {
      do {
        this.laAgain = false;
        const ev = await this.load(); if (!ev) return;
        const { scores } = await this.publicState(), now = Date.now();
        const board = leaderboard(ev, scores);
        let dirty = false;
        await Promise.all(Object.entries(la).map(async ([token, x]) => {
          const card = liveCard(ev, scores, x.team, x.player, now, board);
          if (!card) { delete la[token]; dirty = true; return; }
          const key = cardKey(card); if (key === x.last) return;
          const loud = !!card.msg && card.msgAt > (x.msgAt || 0);
          const r = await sendLive(this.env, token, x.env, livePayload(card, { alert: loud, now }), loud || card.final ? 10 : 5);
          if (r === 'gone' || (r === 'ok' && card.final)) { delete la[token]; dirty = true; return; }
          if (r === 'ok') { x.last = key; if (loud) x.msgAt = card.msgAt; dirty = true; }
        }));
        if (dirty) await this.ctx.storage.put('la', la);
      } while (this.laAgain);
    } finally { this.laBusy = false; }
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/init') {
      if (await this.load()) return json({ error: 'Taken' }, 409);
      const b = await request.json();
      // the club's course (scorecard, tees, where it is), when Admin's Add club or an earlier tournament set it
      const card = b.card && typeof b.card === 'object' && Array.isArray(b.card.holes) ? b.card : null;
      const s = cleanSetup({ name: b.name || 'Golf tournament', club: b.club || '', format: { type: 'bestball', count: 1, allowance: 85 }, flights: ['A', 'B'],
        screens: { seconds: 12, rows: 10 }, ...(card ? { course: card } : {}) }, { course: { holes: defaultHoles() }, teams: [] });
      this.ev = { ...s, id: url.searchParams.get('id'), key: rand(24, 'abcdefghijkmnpqrstuvwxyz23456789'), locked: false, aces: [], created: Date.now(), v: 1 };
      if (b.map) this.ev.map = { ...cleanMap(b.map), at: Date.now(), by: 'Club course map' }; // the club's course, mapped at an earlier tournament
      await this.ctx.storage.put('event', this.ev);
      return json({ id: this.ev.id, key: this.ev.key });
    }
    const ev = await this.load();
    if (!ev) return json({ error: 'There is no tournament at this address.' }, 404);
    // a photo the club added (brand.js), with a long cache: its address changes when the photo does
    const pm = url.pathname.match(/\/photo\/([a-z0-9-]{1,14})$/);
    if (pm) {
      const ph = PHOTO_SLOT.test(pm[1]) && ev.photos?.[pm[1]] ? await this.ctx.storage.get(`p:${pm[1]}`) : null;
      if (!ph) return json({ error: 'There is no photo here.' }, 404);
      return new Response(ph.bytes, { headers: { 'Content-Type': ph.type, 'Cache-Control': 'public, max-age=31536000, immutable', 'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'" } });
    }
    const op = url.pathname.split('/').pop();
    if (op === 'state') return json(await this.publicState());
    // the logo golfers and the TVs see (the tournament's own, else its club's); none when it shows Flagcast's
    if (op === 'logo') {
      const l = logoOf(ev); if (!l) return json({ error: 'This tournament shows the Flagcast logo.' }, 404);
      return new Response(l.bytes, { headers: { 'Content-Type': l.type, 'Cache-Control': 'public, max-age=86400', 'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; img-src data:" } });
    }
    if (op === 'ws') {
      if (request.headers.get('Upgrade') !== 'websocket') return new Response('Use a WebSocket', { status: 426 });
      if (this.ctx.getWebSockets().length > 900) return new Response('Too many viewers', { status: 503 });
      const [client, server] = Object.values(new WebSocketPair());
      const disp = url.searchParams.get('screen') || '';
      this.ctx.acceptWebSocket(server, /^[a-z0-9]{3,12}$/.test(disp) ? [`d:${disp}`] : []);
      server.send(JSON.stringify({ t: 'state', s: await this.publicState() }));
      if (disp) this.ctx.waitUntil(this.broadcast()); // the Manager and pro phones see the screen come on
      return new Response(null, { status: 101, webSocket: client });
    }
    if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
    let b; try { b = await request.json(); } catch { return json({ error: 'Bad request' }, 400); }
    if (op === 'cart') {
      const code = String(b.code || '').toUpperCase();
      const teams = ev.teams.filter((t) => t.code === code).map((t) => t.id);
      if (!teams.length) return json({ error: 'That scorecard code isn’t in this tournament. Check the code on your cart card.' }, 404);
      return json({ teams });
    }
    if (op === 'score') return this.score(b);
    if (op === 'desk') {
      if (!b.key || !same(b.key, ev.key)) return json({ error: 'This desk link is not right. Open the link you were given when the tournament was made.' }, 403);
      return this.desk(b);
    }
    // the par 3 camera links: only from Flagcast Admin (clubs.js admin op 'cams'). Never routed from the web
    // (the worker only forwards state|ws|cart|score|desk|pro|hit|where|live|logo), so only the directory object reaches it.
    // the club's branding, from the club directory (clubs.js) when it changes or the tournament is made or moved,
    // and Admin's Demo switch (Flagcast's logo whatever the club has). Never routed from the web.
    if (op === 'brand') {
      if (b.club !== undefined) ev.clubBrand = { logo: b.club?.logo || '', accent: b.club?.accent || '', powered: !!b.club?.powered };
      if (b.demo !== undefined) ev.demo = !!b.demo;
      await this.ctx.storage.put('event', ev);
      await this.broadcast();
      return json({ ok: true, brand: brandFor(ev) });
    }
    // the club's TVs (tv.js through the club directory). Never routed from the web.
    // tvinfo: what a TV needs to pick today's tournament. tvjoin { tv: { id, name, where } }: the TV becomes one of this
    // tournament's screens (so the Manager's screen controls and playlists work for it). tvleave { tv: id }: it's gone
    if (op === 'tvinfo') return json({ name: ev.name, date: ev.date || '', locked: !!ev.locked, created: ev.created || 0, last: Math.max(0, ...Object.values(await this.scores()).flatMap((p) => Object.values(p).flatMap((arr) => arr.map((x) => (x ? x.at || 0 : 0))))) });
    // tvjoin also takes { tvs: [...] } (every club TV at once, when a Manager opens this tournament) and { only: true }
    // (rename the TV where it already is, don't add it). It answers { added }: how many TVs are new here.
    if (op === 'tvjoin' || op === 'tvleave') {
      ev.displays = ev.displays || [];
      const list = op === 'tvleave' ? [b.tv] : Array.isArray(b.tvs) ? b.tvs.slice(0, 40) : [b.tv || {}];
      let changed = false, added = 0, full = false;
      for (const t of list) {
        const id = op === 'tvjoin' ? t?.id : t;
        if (!/^[a-z0-9]{3,12}$/.test(id || '')) return json({ error: 'Bad TV' }, 400);
        const have = ev.displays.find((d) => d.id === id);
        if (op === 'tvleave') { if (have) { ev.displays = ev.displays.filter((d) => d.id !== id); changed = true; } continue; }
        if (have) {
          const w = b.only ? clip(t.where || '', 40) : clip(t.where, 40) || have.where || '';
          if (!t.name || (have.name === clip(t.name, 40) && have.tv && (have.where || '') === w)) { if (!have.tv) { have.tv = true; changed = true; } continue; }
          have.name = clip(t.name, 40); have.tv = true; have.where = w; changed = true;
        } else if (!b.only) {
          if (ev.displays.length >= 20) { full = true; continue; }
          ev.displays.push({ id, name: clip(t.name, 40) || 'TV', where: clip(t.where, 40), group: '', tv: true, playlist: [] }); added++; changed = true;
        }
      }
      if (changed) {
        ev.v = (ev.v || 0) + 1;
        await this.ctx.storage.put('event', ev);
        await this.broadcast();
      }
      if (full && list.length === 1) return json({ error: 'This tournament already has 20 screens.' }, 409);
      return json({ ok: true, added });
    }
    // the club was deleted in Flagcast Admin (clubs.js admin op 'delete'): wipe everything. Never routed from the web.
    if (op === 'wipe') {
      for (const w of this.ctx.getWebSockets()) { try { w.close(1000, 'Deleted'); } catch {} }
      await this.ctx.storage.deleteAll(); this.ev = null; this.sc = null;
      return json({ ok: true });
    }
    if (op === 'cams') {
      ev.cams = cleanSetup({ cams: b.cams || {} }, ev).cams;
      // a Demo tournament can show "Live from the pro" without a phone really sending: { live: { [hole]: name } }
      // marks those cameras as a pro's Go live feed (they stay on when it's taken off). Only for Demo tournaments.
      if (b.live && typeof b.live === 'object' && ev.demo) {
        for (const [h, g] of Object.entries(ev.golive || {})) if (g && g.sample) delete ev.golive[h];
        for (const [h, by] of Object.entries(b.live)) {
          const n = Number(h); if (!Number.isInteger(n) || n < 0 || n > 18 || !ev.cams[n] || !by) continue;
          (ev.golive ||= {})[n] = { by: clip(by, 40), at: Date.now(), had: true, sample: true };
        }
      }
      await this.ctx.storage.put('event', ev);
      await this.broadcast();
      return json({ ok: true, cams: ev.cams });
    }
    // "Try a demo" (GET /golf/api/demo, through the club directory's demo-find): this Demo tournament and its sample
    // cart's code. Only for a tournament marked Demo; never routed from the web.
    if (op === 'try') {
      const t = tryTeam(ev);
      if (!ev.demo || !t) return json({ error: 'The demo isn’t available right now.' }, 404);
      return json({ id: ev.id, name: ev.name, code: t.code, team: t.id });
    }
    if (op === 'pro') return this.pro(b, request.headers.get('CF-Connecting-IP') || '');
    if (op === 'hit') return this.hit(b, request.headers.get('CF-Connecting-IP') || '');
    if (op === 'where') return this.where(b);
    if (op === 'enter') return this.enter(b);
    if (op === 'clip') return this.clip(b);
    if (op === 'live') return this.live(b);
    return json({ error: 'Not found' }, 404);
  }

  // a cart sends scores: only for its own team, and not after the results are locked.
  // Each score carries the time it was typed, so a phone that was out of signal can send late without undoing newer fixes.
  async score(b) {
    const ev = this.ev, code = String(b.code || '').toUpperCase();
    const team = ev.teams.find((t) => t.id === b.team && (t.code === code || b.desk === ev.key));
    if (!team) return json({ error: 'This scorecard can’t enter scores for that team.' }, 403);
    if (ev.locked && b.desk !== ev.key) return json({ error: 'Scoring is closed. The results are final.' }, 423);
    const sc = await this.scores();
    // "Try a demo" scores on one sample cart of a Demo tournament (tryCart): they clear after 3 hours with no scoring,
    // and a 1 there is no hole-in-one take-over, so the demo a club is shown stays tidy
    const trial = isTryTeam(ev, team);
    const last = Math.max(0, ...Object.values(sc[team.id] || {}).flatMap((arr) => arr.map((x) => (x ? x.at || 0 : 0))));
    const mine = trial && last && Date.now() - last > TRY_RESET ? {} : (sc[team.id] || {});
    const ids = new Set(teamBall(ev) ? ['T'] : team.players.map((p) => p.id));
    const now = Date.now(); let changed = false; const aces = [], scored = new Set();
    for (const e of (Array.isArray(b.list) ? b.list : []).slice(0, 200)) {
      if (!ids.has(e.p)) continue;
      const h = Number(e.h); if (!(h >= 1 && h <= 18)) continue;
      const v = e.v === null ? null : Number(e.v);
      if (v !== null && !(Number.isInteger(v) && v >= 0 && v <= 15)) continue;
      const at = Math.min(Number(e.at) || now, now);
      const arr = mine[e.p] || Array(18).fill(null);
      const old = arr[h - 1];
      if (old && old.at > at) continue; // a newer change is already here
      arr[h - 1] = v === null ? null : { v, at };
      mine[e.p] = arr; changed = true;
      if (v !== null) scored.add(h);
      if (v === 1 && (!old || old.v !== 1) && !trial) {
        const p = team.players.find((x) => x.id === e.p);
        aces.push({ hole: h, name: p ? p.name : team.name, team: team.name, at: now });
      }
    }
    if (trial && mine !== sc[team.id] && sc[team.id]) { const pc = await this.paceData(); delete pc[team.id]; } // the demo cart starts again
    const paced = b.desk === ev.key ? false : await this.paceScored(team, [...scored], now, b.start);
    if (changed || paced || (trial && mine !== sc[team.id] && sc[team.id])) {
      sc[team.id] = mine;
      await this.ctx.storage.put(`s:${team.id}`, mine);
      if (aces.length) { ev.aces = [...(ev.aces || []), ...aces].slice(-20); await this.ctx.storage.put('event', ev); }
      await this.broadcast();
    }
    return json({ ok: true });
  }

  // the desk: { op: 'get' } (the full setup with codes, PINs and sponsor counts) | 'save' (setup) | 'clear' { team } | 'ace' { remove: at }
  // plus every day op (see dayOp): lock, contest, ctp, fund, flash, nudge, fix, screen, take, stats, pinsheet
  async desk(b) {
    const ev = this.ev;
    if (b.op === 'get') return json({ ...ev, photos: photoLinks(ev), stats: await this.getStats() });
    // a photo for golfers: { slot: 'cover' | 'h<n>' | 's-<sponsor id>', image: data: URI, or '' to take it off }
    if (b.op === 'photo') {
      const slot = String(b.slot || '');
      if (!PHOTO_SLOT.test(slot)) return json({ error: 'That photo spot isn’t right.' }, 400);
      ev.photos = { ...(ev.photos || {}) };
      if (b.image) {
        let ph; try { ph = cleanPhoto(b.image); } catch (e) { return json({ error: e.message }, e.status || 400); }
        await this.ctx.storage.put(`p:${slot}`, { type: ph.type, bytes: ph.bytes });
        ev.photos[slot] = ph.v;
      } else { delete ev.photos[slot]; await this.ctx.storage.delete(`p:${slot}`); }
      await this.ctx.storage.put('event', ev);
      await this.broadcast();
      return json({ ok: true, photos: photoLinks(ev) });
    }
    if (DAY_OPS.has(b.op)) return this.dayOp(b, 'Desk');
    if (b.op === 'invite') return this.invite(b);
    if (b.op === 'save') {
      // the tournament's own logo (instead of the club's): '' takes it off; left out, it stays as it is
      let logo = ev.logo || '';
      if (b.setup?.logo !== undefined) { try { logo = cleanLogo(b.setup.logo); } catch (e) { return json({ error: e.message }, e.status || 400); } }
      // contest results only change through their own ops (golfers, marshals, the desk's results), so a Save made from an
      // older copy never wipes them; a Manager that doesn't know a contest setting yet keeps what's there
      if (b.setup && Array.isArray(b.setup.contests)) b.setup = { ...b.setup, contests: b.setup.contests.map((c) => {
        const was = (ev.contests || []).find((x) => x.id === c?.id);
        return was ? { self: was.self, check: was.check, prize: was.prize, ...c, entries: was.entries } : { ...c, entries: [] };
      }) };
      // a Manager from before match play doesn't send the pairings, the match settings or each team's cup side: keep them
      if (b.setup) b.setup = keepMatch(b.setup, ev);
      const s = cleanSetup(b.setup || {}, ev);
      keepTVs(s, ev.displays);
      const pp = pinProblem(s.pins, ev.pins || []); if (pp) return json({ error: pp }, 400);
      s.cams = ev.cams || {};
      s.logo = logo; // camera links are Flagcast staff's (op 'cams' from Admin): a desk key can't change them
      const v = (ev.v || 0) + 1, sc = await this.scores();
      s.teams = mergeTeams(ev.teams, s.teams, b.setup?.v, v, sc);
      const was = ev.teams;
      Object.assign(ev, s, { v });
      // teams that were removed: set aside with their scores for 30 days (desk op 'restore' brings one back)
      const keep = new Set(ev.teams.map((t) => t.id));
      ev.removed = (ev.removed || []).filter((r) => Date.now() - r.at < 30 * 86400000 && !keep.has(r.team.id));
      for (const t of was) if (!keep.has(t.id)) {
        ev.removed = [...ev.removed.filter((r) => r.team.id !== t.id), { team: t, at: Date.now() }].slice(-60);
        if (sc[t.id]) { await this.ctx.storage.put(`x:${t.id}`, sc[t.id]); delete sc[t.id]; await this.ctx.storage.delete(`s:${t.id}`); }
      }
      for (const id of Object.keys(sc)) if (!keep.has(id)) { delete sc[id]; await this.ctx.storage.delete(`s:${id}`); }
      // the club keeps the course from its latest Setup (with a course name), so its next tournament starts with it
      if (this.env.CLUBS && ev.course?.name) this.ctx.waitUntil(this.env.CLUBS.get(this.env.CLUBS.idFromName('directory')).fetch(new Request('https://clubs/course', { method: 'POST',
        body: JSON.stringify({ id: ev.id, key: ev.key, card: { name: ev.course.name, at: ev.course.at, holes: ev.course.holes, tees: ev.course.tees } }) })).catch(() => {}));
      for (const k of (await this.ctx.storage.list({ prefix: 'x:' })).keys()) if (!ev.removed.some((r) => `x:${r.team.id}` === k)) await this.ctx.storage.delete(k);
      // banners of sponsors that were removed go too
      const sps = new Set(ev.sponsors.map((x) => `s-${x.id}`));
      for (const k of Object.keys(ev.photos || {})) if (k.startsWith('s-') && !sps.has(k)) { delete ev.photos[k]; await this.ctx.storage.delete(`p:${k}`); }
    } else if (b.op === 'restore') { // a team taken off by a Save (kept 30 days), back with its scores
      const r = (ev.removed || []).find((x) => x.team.id === b.team); if (!r) return json({ error: 'That team isn’t in the removed list any more.' }, 404);
      if (ev.teams.length >= 200) return json({ error: 'That’s the most teams a tournament can have.' }, 400);
      ev.v = (ev.v || 0) + 1;
      ev.teams = [...ev.teams, { ...r.team, sv: ev.v }];
      ev.removed = ev.removed.filter((x) => x !== r);
      const x = await this.ctx.storage.get(`x:${r.team.id}`);
      if (x) { const sc = await this.scores(); sc[r.team.id] = x; await this.ctx.storage.put(`s:${r.team.id}`, x); await this.ctx.storage.delete(`x:${r.team.id}`); }
    } else if (b.op === 'ace') ev.aces = (ev.aces || []).filter((a) => a.at !== b.remove);
    else if (b.op === 'clear') {
      const sc = await this.scores(); delete sc[b.team]; await this.ctx.storage.delete(`s:${b.team}`);
      const pc = await this.paceData(); if (pc[b.team]) { delete pc[b.team]; await this.ctx.storage.put('pace', pc); }
    } else return json({ error: 'Unknown change' }, 400);
    await this.ctx.storage.put('event', ev);
    await this.broadcast();
    return json(b.op === 'save' ? { ...ev, photos: photoLinks(ev) } : { ok: true });
  }

  // ---- player invites by email (optional): the club adds players' emails on the Teams tab and sends each one email with
  // their group, start and a link to their cart's scorecard. ev.invites[player id] = { to, at, n } (n = times sent).
  //   { op: 'invite', send: 'new' }               every player with an email who hasn't had one (or whose email changed since)
  //   { op: 'invite', send: [player ids] }        one or a few players again (Resend), at most INVITE_MAX times each
  //   { op: 'invite', test: 'me@club.com' }       a test copy (the first player's) to the club, marked Test
  //   { op: 'invite', preview: true }             → { html, subject } of the first player's email, sends nothing
  // → { sent, failed, invites }
  inviteMail(team, player) {
    const ev = this.ev, br = brandFor(ev), logo = logoOf(ev);
    // Gmail and Outlook don't show SVG: an SVG club logo shows the club's name instead
    const brand = br.demo ? { demo: true } : { logo: logo && logo.type !== 'image/svg+xml' ? `https://flagcast.app${br.logo}` : '', accent: br.accent, demo: false };
    return EMAILS.invite({ ev, team, player, brand });
  }
  async invite(b) {
    const ev = this.ev, inv = { ...(ev.invites || {}) }, now = Date.now();
    const all = ev.teams.flatMap((t) => t.players.map((p) => ({ t, p })));
    const sample = all.find((x) => x.p.email) || all[0];
    if (b.preview) {
      if (!sample) return json({ error: 'Add a team with players first.' }, 400);
      const m = this.inviteMail(sample.t, sample.p);
      return json({ subject: m.subject, html: mailHtml(m), text: mailText(m) });
    }
    if (!this.env.RESEND_API_KEY) return json({ error: 'Email isn’t set up on the server yet. Ask Flagcast.' }, 503);
    const from = (this.env.MAIL_FROM || 'Flagcast <signin@flagcast.app>').replace(/^.*<([^>]+)>.*$/, '$1');
    const name = String(ev.club || 'Flagcast').replace(/["<>\r\n,;\\]/g, '').trim().slice(0, 60);
    const sender = `${name}${name === 'Flagcast' ? '' : ' via Flagcast'} <${from}>`;
    if (b.test !== undefined) {
      const to = cleanEmail(b.test);
      if (!to) return json({ error: 'Type the email address to send the test to.' }, 400);
      if (!sample) return json({ error: 'Add a team with players first.' }, 400);
      const tests = (ev.inviteTests || []).filter((t) => now - t < 86400e3);
      if (tests.length >= 5) return json({ error: 'That’s 5 tests today. Try again tomorrow.' }, 429);
      const m = this.inviteMail(sample.t, sample.p); m.subject = `Test: ${m.subject}`;
      try { await sendBatch(this.env, [{ from: sender, to, m }]); } catch { return json({ error: 'The test didn’t send. Try again in a minute.' }, 502); }
      ev.inviteTests = [...tests, now]; await this.ctx.storage.put('event', ev);
      return json({ sent: 1, failed: 0, invites: inv });
    }
    let list;
    if (b.send === 'new') list = all.filter(({ p }) => p.email && (!inv[p.id] || inv[p.id].to !== p.email));
    else if (Array.isArray(b.send)) {
      const ids = new Set(b.send.slice(0, 20).map(String));
      list = all.filter(({ p }) => ids.has(p.id) && p.email);
      const over = list.find(({ p }) => inv[p.id] && inv[p.id].to === p.email && inv[p.id].n >= INVITE_MAX);
      if (over) return json({ error: `${over.p.name} has had ${INVITE_MAX} emails already.` }, 429);
    } else return json({ error: 'Say who to send to.' }, 400);
    if (!list.length) return json({ sent: 0, failed: 0, invites: inv });
    const total = Object.values(inv).reduce((a, x) => a + (x.n || 0), 0);
    if (total + list.length > INVITE_TOTAL) return json({ error: `A tournament can send ${INVITE_TOTAL} invites in all.` }, 429);
    let sent = 0, failed = 0;
    for (let i = 0; i < list.length; i += 100) { // Resend takes 100 emails a call
      const part = list.slice(i, i + 100);
      try {
        await sendBatch(this.env, part.map(({ t, p }) => ({ from: sender, to: p.email, m: this.inviteMail(t, p) })));
        for (const { p } of part) inv[p.id] = { to: p.email, at: now, n: (inv[p.id] && inv[p.id].to === p.email ? inv[p.id].n || 0 : 0) + 1 };
        sent += part.length;
      } catch { failed += part.length; }
    }
    ev.invites = inv;
    await this.ctx.storage.put('event', ev);
    return json({ sent, failed, invites: inv, ...(failed ? { error: `${failed} email${failed === 1 ? '' : 's'} didn’t send. Press Send again to try those.` } : {}) });
  }

  // a golf pro or marshal signs in with the PIN the Manager gave them. Pros run the day; marshals post contest results.
  async pro(b, ip = '') {
    const ev = this.ev, now = Date.now();
    // wrong PINs: 8 from one network and 40 in all in 15 minutes, then a wait. Saved, so it holds when the tournament sleeps
    const pf = ((await this.ctx.storage.get('pinfails')) || []).filter((f) => now - f.t < PIN_WAIT);
    if (pf.filter((f) => f.ip === ip).length >= PIN_TRIES_IP || pf.length >= PIN_TRIES_ALL) return json({ error: 'Too many wrong PINs. Wait 15 minutes, or ask the tournament desk.' }, 429);
    const who = (ev.pins || []).find((x) => x.pin && same(x.pin, String(b.pin || '')));
    if (!who) { await this.ctx.storage.put('pinfails', [...pf, { t: now, ip }].slice(-200)); return json({ error: 'That PIN is not right.' }, 403); }
    if (b.op === 'hello') return json({ name: who.name, role: who.role });
    if (!(who.role === 'pro' ? DAY_OPS : MARSHAL_OPS).has(b.op)) return json({ error: 'Your PIN can’t make that change. Ask the golf pro.' }, 403);
    if (who.role !== 'pro') { delete b.screens; delete b.remove; } // marshals save replays; the pro puts them on the screens or removes them
    delete b.pin; // that was their PIN, not a pin position (a pro's pin sheet change sends it as spot)
    return this.dayOp(b, who.name);
  }

  // changes made on the day, by the desk (Manager) or a pro's phone
  async dayOp(b, by) {
    const ev = this.ev, now = Date.now();
    ev.live = ev.live || { force: {}, take: null };
    // a timed send (Send now for 5 or 15 minutes) is over: the screen is back on its playlist
    for (const [id, f] of Object.entries(ev.live.force || {})) if (f && f.until && f.until <= now) delete ev.live.force[id];
    if (b.op === 'stats') return json({ stats: await this.getStats(), log: ev.log || [], clog: ev.clog || [] });
    if (b.op === 'report') { // the results and GHIN posting files (rows; the app makes the CSV)
      const S = await this.publicState();
      return json({ name: ev.name || 'Tournament', results: resultsRows(S), ghin: ghinRows(ev, S) });
    }
    if (b.op === 'team') { // fix a team on the day: its name and players ({ team, name?, players }), or a late group ({ team: 'new', ... })
      const isNew = b.team === 'new', old = isNew ? null : ev.teams.find((t) => t.id === b.team);
      if (!isNew && !old) return json({ error: 'No such team' }, 404);
      if (isNew && ev.teams.length >= 200) return json({ error: 'That’s the most teams a tournament can have.' }, 400);
      const was = new Map((old ? old.players : []).map((p) => [p.id, p]));
      const players = (Array.isArray(b.players) ? b.players : (old ? old.players : [])).slice(0, 4)
        .map((p) => ({ ...(was.get(p && p.id) || {}), ...p, ghin: (was.get(p && p.id) || {}).ghin || p.ghin })) // keep what the pro's phone doesn't send (GHIN numbers)
        .filter((p) => String(p.name || '').trim());
      if (!players.length) return json({ error: 'A team needs at least one player.' }, 400);
      const t = { ...(old || { start: num(b.start, 1, 18, 1), flight: clip(b.flight, 12) }), name: b.name !== undefined ? b.name : (old ? old.name : ''), players };
      const next = isNew ? [...ev.teams, t] : ev.teams.map((x) => (x.id === old.id ? t : x));
      const ids = new Set(ev.teams.map((x) => x.id));
      ev.v = (ev.v || 0) + 1;
      ev.teams = stamp(cleanSetup({ ...ev, teams: next }, ev).teams, ev.teams, isNew ? null : old.id, ev.v);
      if (isNew) { const nt = ev.teams.find((x) => !ids.has(x.id)); if (nt) nt.sv = ev.v; }
      const made = isNew ? ev.teams.find((x) => !ids.has(x.id)) : ev.teams.find((x) => x.id === old.id);
      await this.ctx.storage.put('event', ev);
      await this.broadcast();
      return json({ ok: true, team: made.id, code: made.code }); // the new cart's code, for the pro to hand out
    }
    if (b.op === 'move') { // move a player to another cart ({ player, to }); their scores go with them
      const from = ev.teams.find((t) => t.players.some((p) => p.id === b.player)), to = ev.teams.find((t) => t.id === b.to);
      if (!from || !to) return json({ error: 'No such player or team' }, 404);
      if (from.id === to.id) return json({ ok: true });
      if (to.players.length >= 4) return json({ error: 'That team already has four players.' }, 400);
      const p = from.players.find((x) => x.id === b.player);
      from.players = from.players.filter((x) => x.id !== p.id); to.players = [...to.players, p];
      ev.v = (ev.v || 0) + 1; from.sv = ev.v; to.sv = ev.v; // a Save made from an older copy keeps this move
      const sc = await this.scores();
      if (sc[from.id] && sc[from.id][p.id]) {
        sc[to.id] = sc[to.id] || {};
        if (!sc[to.id][p.id]) sc[to.id][p.id] = sc[from.id][p.id];
        delete sc[from.id][p.id];
        await this.ctx.storage.put(`s:${from.id}`, sc[from.id]); await this.ctx.storage.put(`s:${to.id}`, sc[to.id]);
      }
      await this.ctx.storage.put('event', ev);
      await this.broadcast();
      return json({ ok: true });
    }
    if (b.op === 'groups') {
      if (!trackingOn(ev)) {
        if (Object.keys(await this.spots()).length) await this.wipeSpots(); // the day is over: wipe them
        return json({ now, on: false, date: ev.date, locked: !!ev.locked, groups: [] });
      }
      const wh = await this.spots();
      const real = ev.teams.filter((t) => wh[t.id]).map((t) => ({ team: t.id, name: t.name || t.players.map((p) => p.name.split(' ').slice(-1)[0]).join(' / '), start: t.start, ...wh[t.id] }));
      return json({ now, on: true, groups: ev.demo ? real.concat(sampleGroups(ev, wh, null, now)) : real });
    }
    if (b.op === 'fix') {
      const team = ev.teams.find((t) => t.id === b.team); if (!team) return json({ error: 'No such team' }, 404);
      const sc = await this.scores(), h = Number(b.h);
      const before = ((sc[team.id] || {})[b.p] || [])[h - 1];
      const r = await this.score({ team: team.id, desk: ev.key, list: [{ p: b.p, h, v: b.v, at: now }] });
      if (r.status !== 200) return r;
      const pl = team.players.find((x) => x.id === b.p);
      ev.log = [...(ev.log || []), { at: now, by: clip(by, 40), team: team.name, player: pl ? pl.name : 'Team', h, from: before ? before.v : null, to: b.v === null ? null : Number(b.v) }].slice(-300);
      await this.ctx.storage.put('event', ev);
      return json({ ok: true });
    }
    if (b.op === 'ctp') { // a marshal or the pro at the hole: one result (checked), replacing that player's earlier one
      const c = ev.contests.find((x) => x.id === b.id); if (!c) return json({ error: 'No such contest' }, 404);
      const name = clip(b.name, 50).trim(); if (!name) return json({ error: 'Who was it?' }, 400);
      const was = c.entries.find((e) => e.name.toLowerCase() === name.toLowerCase());
      const e = cleanEntry({ ...(was || {}), name, dist: b.dist, ok: true, by: clip(by, 40), okBy: clip(by, 40), at: now });
      c.entries = [...c.entries.filter((x) => x !== was), e];
      contestLog(ev, { by: clip(by, 40), id: c.id, name, did: 'entered', dist: e.dist });
    } else if (b.op === 'contest') { // the desk's whole list of results (an entry that's there already keeps its check and who sent it)
      const c = ev.contests.find((x) => x.id === b.id); if (!c) return json({ error: 'No such contest' }, 404);
      c.entries = (Array.isArray(b.entries) ? b.entries : []).slice(0, 200).map((x) => {
        const n = cleanEntry(x), was = c.entries.find((e) => e.name.toLowerCase() === n.name.toLowerCase());
        if (was && was.dist === n.dist) return was;
        return cleanEntry({ ...(was || {}), ...n, ok: true, by: was ? was.by : clip(by, 40), okBy: clip(by, 40), at: now });
      }).filter((e) => e.name);
      contestLog(ev, { by: clip(by, 40), id: c.id, did: 'results' });
    } else if (b.op === 'check') { // a golfer's entry: OK it, change its distance (that OKs it too) or take it off
      const c = ev.contests.find((x) => x.id === b.id); if (!c) return json({ error: 'No such contest' }, 404);
      const name = clip(b.name, 50).trim().toLowerCase(), e = c.entries.find((x) => x.name.toLowerCase() === name);
      if (!e) return json({ error: 'That entry isn’t there any more.' }, 404);
      if (b.do === 'remove') c.entries = c.entries.filter((x) => x !== e);
      else if (b.do === 'change' || b.do === 'ok') {
        if (b.do === 'change') { const d = num(b.dist, 0, 999, 0); if (!(d > 0)) return json({ error: 'Type the distance.' }, 400); e.dist = Math.round(d * 100) / 100; }
        e.ok = true; e.okBy = clip(by, 40);
      } else return json({ error: 'OK, change or remove?' }, 400);
      contestLog(ev, { by: clip(by, 40), id: c.id, name: e.name, did: b.do, dist: e.dist });
    } else if (b.op === 'flash') {
      ev.flash = b.text ? { text: clip(b.text, 140), at: now } : null;
      if (b.text) ev.news = [...(ev.news || []), { text: clip(b.text, 140), at: now, by: clip(by, 40) }].slice(-30);
    } else if (b.op === 'pace') { // the pace of play goal, minutes for 18 holes ({ goal }; 0 or none = Flagcast's 4:15)
      const g = Number(b.goal);
      if (!g) delete ev.paceGoal; else if (g >= 120 && g <= 420) ev.paceGoal = Math.round(g); else return json({ error: 'Pick a goal between 2 and 7 hours.' }, 400);
    } else if (b.op === 'notes') { // golfers' ready-made notes to other groups from the course map: on (default) or off
      if (b.off) ev.notesOff = true; else delete ev.notesOff;
    } else if (b.op === 'nudge') {
      // to one cart ({ team }), one golfer on it ({ team, player }: their phone if they picked their name, else the cart), or everyone ({ team: '*' })
      const all = b.team === '*', team = all ? null : ev.teams.find((t) => t.id === b.team); if (!all && !team) return json({ error: 'No such team' }, 404);
      const player = team && b.player ? team.players.find((p) => p.id === b.player) : null; if (b.player && !player) return json({ error: 'No such player' }, 404);
      ev.nudges = [...(ev.nudges || []), { team: all ? '*' : team.id, ...(player ? { player: player.id } : {}), text: clip(b.text || 'Please keep up the pace of play. Thank you!', 140), at: now }].slice(-50);
    } else if (b.op === 'screen') { // route a page to one screen, several (a list) or all ('*'), or send them back to their playlists (page: null)
      const all = (ev.displays || []).map((d) => d.id), want = Array.isArray(b.display) ? b.display : [b.display];
      // 'phones': every player's phone gets a banner pointing at this page (live leaderboard page and scorecards)
      if (want.includes('phones')) ev.live.phone = b.page && PAGE_KINDS.includes(b.page.k) ? { k: b.page.k, fl: clip(b.page.fl, 12), hole: num(b.page.hole, 0, 18, 0), sponsor: clip(b.page.sponsor, 12), text: clip(b.text, 140), at: now } : null;
      const ids = b.display === '*' ? all : want.filter((x) => all.includes(x));
      if (!ids.length && !want.includes('phones')) return json({ error: 'No such screen' }, 404);
      for (const id of ids) {
        // mins (optional): only for that long, then back to its playlist (the board watches `until` itself)
        const mins = num(b.mins, 0, 600, 0);
        if (b.page && PAGE_KINDS.includes(b.page.k)) ev.live.force[id] = { k: b.page.k, fl: clip(b.page.fl, 12), hole: num(b.page.hole, 0, 18, 0), sponsor: clip(b.page.sponsor, 12), at: now, ...(mins ? { until: now + mins * 60000 } : {}) };
        else delete ev.live.force[id];
      }
    } else if (b.op === 'golive') {
      // Go live from an iPhone at the hole (desk, Admin or a pro): { hole } → the hole's live input to send to, and the
      // hole's camera link points at it, so the TVs, the Cameras tab, the live page and replays play it like any
      // camera. { hole, stop: true } when the phone stops: the camera link comes off again (unless the hole had a
      // camera before), and screens and phones pointed at it go back.
      // hole 0 is the clubhouse (a phone on the patio or the putting green)
      const hole = Number(b.hole);
      if (!Number.isInteger(hole) || hole < 0 || (hole > 0 && !ev.course.holes[hole - 1])) return json({ error: 'Pick a hole' }, 400);
      ev.golive = ev.golive || {}; ev.cams = ev.cams || {};
      const was = ev.golive[hole];
      if (b.stop) {
        if (!was) return json({ ok: true });
        delete ev.golive[hole];
        if (!was.had) delete ev.cams[hole];
        if (ev.live.phone && ['cam', 'p3'].includes(ev.live.phone.k) && ev.live.phone.hole === hole) ev.live.phone = null;
        for (const [id, f] of Object.entries(ev.live.force || {})) if (f && f.k === 'cam' && f.hole === hole) delete ev.live.force[id];
      } else {
        if (!this.env.CLUBS) return json({ error: 'Live video isn’t switched on here.' }, 409);
        const r = await this.env.CLUBS.get(this.env.CLUBS.idFromName('directory')).fetch(new Request('https://clubs/golive', { method: 'POST', body: JSON.stringify({ id: ev.id, key: ev.key, hole, name: ev.name, by: clip(by, 40) }) }));
        const j = await r.json().catch(() => ({}));
        if (!r.ok) return json({ error: j.error || 'Flagcast couldn’t start the live video. Try again.' }, r.status || 502);
        // someone's camera is already sending on this hole: don't cut it off from another phone
        if (j.state === 'connected' && !b.take) return json({ error: `${hole ? `Hole ${hole}` : 'The clubhouse'}’s camera is already live${was ? ` from ${was.by}’s phone` : ''}. Stop that one first.`, live: true, by: was?.by || '' }, 409);
        ev.golive[hole] = { by: clip(by, 40), at: now, had: was ? !!was.had : !!ev.cams[hole] };
        ev.cams[hole] = j.playback;
        await this.ctx.storage.put('event', ev);
        await this.broadcast();
        return json({ ok: true, hole, playback: j.playback, srt: j.srt, rtmps: j.rtmps });
      }
    } else if (b.op === 'camshow') {
      // which cameras golfers see (the Cameras tab, the live page): { off: [holes, 0 = clubhouse] } hides those;
      // { clips: false } takes "Save your shot" off the scorecards. The TVs show whatever the desk routes to them.
      if (Array.isArray(b.off)) ev.camsOff = [...new Set(b.off.map(Number).filter((n) => Number.isInteger(n) && n >= 0 && n <= 18))].sort((x, y) => x - y);
      if (b.clips !== undefined) ev.clipsOff = !b.clips;
    } else if (b.op === 'scene') { // saved routings: save what every screen shows now, put one back, or delete one
      ev.scenes = ev.scenes || [];
      if (b.save) {
        const name = clip(b.save, 40).trim(); if (!name) return json({ error: 'Name the scene' }, 400);
        const map = Object.fromEntries((ev.displays || []).map((d) => [d.id, ev.live.force[d.id] ? { ...ev.live.force[d.id], at: undefined, until: undefined } : null]));
        ev.scenes = [...ev.scenes.filter((s) => s.name.toLowerCase() !== name.toLowerCase()), { id: rand(6, 'abcdefghijkmnpqrstuvwxyz23456789'), name, map }].slice(-20);
      } else if (b.remove) ev.scenes = ev.scenes.filter((s) => s.id !== b.remove);
      else if (b.apply) {
        const sc = ev.scenes.find((s) => s.id === b.apply); if (!sc) return json({ error: 'That scene is gone' }, 404);
        for (const d of ev.displays || []) { const f = sc.map[d.id]; if (f) ev.live.force[d.id] = { ...f, at: now }; else delete ev.live.force[d.id]; }
        ev.live.scene = sc.id;
      } else return json({ error: 'Unknown change' }, 400);
    } else if (b.op === 'take') { // take over every screen: an ace, an announcement, a sponsor moment, or clear back to the playlists
      if (b.kind === 'clear') { ev.live = { force: {}, take: null }; }
      else if (b.kind === 'replay') {
        const r = (ev.replays || []).find((x) => x.id === b.replay); if (!r) return json({ error: 'That replay is gone' }, 404);
        ev.live.take = { kind: 'replay', replay: r.id, text: r.label, at: now, secs: num(b.secs, 8, 120, r.url ? 30 : r.back + 5) };
      } else if (['ace', 'msg', 'sponsor'].includes(b.kind)) ev.live.take = { kind: b.kind, text: clip(b.text, 140), sponsor: clip(b.sponsor, 12), at: now, secs: num(b.secs, 5, 120, 25) };
      else return json({ error: 'Unknown take-over' }, 400);
    } else if (b.op === 'replay') { // par 3 replays: a clip link (.mp4 or .m3u8), or a mark on the live camera to play back
      if (b.remove) ev.replays = (ev.replays || []).filter((r) => r.id !== b.remove);
      else {
        const hole = num(b.hole, 1, 18, 0);
        const h = ev.course.holes[hole - 1]; if (!h) return json({ error: 'Pick a hole' }, 400);
        const url = /^https:\/\//.test(b.url || '') ? clip(b.url, 500) : '';
        if (!url && !ev.cams[hole]) return json({ error: `Hole ${hole} has no camera. Paste a clip link instead.` }, 400);
        if (!url && !/\.m3u8(\?|$)/.test(ev.cams[hole])) return json({ error: `Hole ${hole}’s camera can’t be replayed from the live feed (it isn’t an HLS .m3u8 link). Paste a clip link instead.` }, 400);
        const r = { id: rand(6, 'abcdefghijkmnpqrstuvwxyz23456789'), hole, label: clip(b.label, 80), url, at: now, back: url ? 0 : num(b.back, 5, 120, REPLAY_BACK), by: clip(by, 40) };
        ev.replays = [r, ...(ev.replays || [])].slice(0, 60);
        if (b.screens) ev.live.take = { kind: 'replay', replay: r.id, text: r.label, at: now, secs: num(b.secs, 8, 120, url ? 30 : r.back + 5) };
      }
    } else if (b.op === 'map') { // hole GPS: the whole course map, from the map page (desk link or a pro walking the course)
      ev.map = { ...cleanMap(b.map), at: now, by: clip(by, 40) };
      // the club keeps it, so its next tournament starts mapped
      if (this.env.CLUBS) this.ctx.waitUntil(this.env.CLUBS.get(this.env.CLUBS.idFromName('directory')).fetch(new Request('https://clubs/course', { method: 'POST', body: JSON.stringify({ id: ev.id, key: ev.key, map: ev.map }) })).catch(() => {}));
    } else if (b.op === 'pinsheet') { // where the pins are today: one hole { hole, pin } (or spot; null takes it off), or every hole { all: { '<n>': pin } }
      const sheet = {};
      if (b.all && typeof b.all === 'object') {
        for (const [k, p] of Object.entries(b.all)) { const n = Number(k), c = cleanPin(p); if (Number.isInteger(n) && n >= 1 && n <= 18 && c) sheet[n] = c; }
      } else {
        const n = num(b.hole, 0, 18, 0); if (n < 1) return json({ error: 'Pick a hole' }, 400);
        Object.assign(sheet, ev.pinsheet || {});
        const c = cleanPin(b.spot !== undefined ? b.spot : b.pin);
        if (c) sheet[n] = c; else delete sheet[n];
      }
      ev.pinsheet = sheet;
    } else if (b.op === 'lock') {
      ev.locked = !!b.locked;
      if (ev.locked) await this.wipeSpots(); // results are final: group spots are wiped
    }
    else if (b.op === 'fund') ev.fund.raised = num(b.raised, 0, 1e9, ev.fund.raised);
    else return json({ error: 'Unknown change' }, 400);
    await this.ctx.storage.put('event', ev);
    await this.broadcast();
    return json({ ok: true });
  }

  // where each group is on the course: scorecards with GPS on send their spot. The desk, pros and Admin see every
  // group; golfers see the others' recent spots (golferGroups) unless a group hides.
  async spots() {
    // one load even when several phones report at once. Each group is its own key, written every time:
    // the object can be put to sleep between reports, so nothing is kept only in memory
    if (!this.wh) this.wh = this.whLoad || (this.whLoad = this.ctx.storage.list({ prefix: 'w:' }).then((m) => (this.wh = Object.fromEntries([...m].map(([k, v]) => [k.slice(2), v])))));
    return this.wh;
  }
  async wipeSpots() {
    const keys = [...(await this.ctx.storage.list({ prefix: 'w:' })).keys()];
    if (keys.length) await this.ctx.storage.delete(keys);
    this.wh = {}; this.whLoad = null;
  }
  // a scorecard sends its group's spot (at) and/or asks where the other groups are. Golfers see the other groups'
  // names, holes and spots (never their codes), only while the tournament is on, and only spots from the last
  // 15 minutes. A group can hide from the other golfers (hide: true); the desk and pros still see it for pace of play.
  async where(b) {
    const ev = this.ev, team = ev.teams.find((t) => t.id === b.team);
    if (!team || team.code !== String(b.code || '').toUpperCase()) return json({ error: 'Not your scorecard' }, 403);
    const at = b.at == null ? null : Array.isArray(b.at) && b.at.length === 2 ? b.at.map(Number) : [NaN];
    if (at && (!at.every(Number.isFinite) || Math.abs(at[0]) > 90 || Math.abs(at[1]) > 180)) return json({ error: 'Bad spot' }, 400);
    if (!trackingOn(ev)) return json({ error: 'Group tracking is only on during the tournament.', off: true, date: ev.date, locked: !!ev.locked, groups: [] }, 409);
    const wh = await this.spots(), now = Date.now(), was = wh[team.id];
    const hide = b.hide === undefined ? !!was?.hide : !!b.hide;
    // since: when the group got to this hole (how long it's been on it, for pace of play)
    if (at) { const hole = num(b.hole, 0, 18, 0); wh[team.id] = { at: at.map((x) => Math.round(x * 1e6) / 1e6), acc: num(b.acc, 0, 9999, 0), hole, t: now, since: was && was.hole === hole && was.since ? was.since : now, ...(hide ? { hide: true } : {}) }; }
    else if (was && hide !== !!was.hide) { wh[team.id] = { ...was }; if (hide) wh[team.id].hide = true; else delete wh[team.id].hide; }
    if (wh[team.id] !== was) await this.ctx.storage.put(`w:${team.id}`, wh[team.id]);
    if (at && wh[team.id].hole && (!was || was.hole !== wh[team.id].hole)) { // a new hole: the hole clock (and the round's start) for pace of play
      const pc = await this.paceData(), p = pc[team.id] = pc[team.id] || { d: {} }, hole = wh[team.id].hole;
      p.g = { h: hole, at: now };
      if (!p.s && hole === paceOrder(ev, team)[0]) p.s = now;
      await this.ctx.storage.put('pace', pc);
      await this.broadcast();
    }
    let sent;
    if (b.note != null) { // a ready-made note to another group (GOLFER_NOTES)
      const k = Number(b.note), text = GOLFER_NOTES[k], to = String(b.to || '');
      if (ev.notesOff) return json({ error: 'The tournament desk has turned off notes between groups.' }, 403);
      if (!Number.isInteger(k) || !text || to === team.id) return json({ error: 'Pick a note to send.' }, 400);
      const target = ev.teams.find((t) => t.id === to);
      if (!target && !(ev.demo && /^sample\d+$/.test(to))) return json({ error: 'No such group' }, 404);
      const last = (ev.nudges || []).filter((n) => n.fromTeam === team.id).pop();
      if (last && now - last.at < GOLFER_NOTE_GAP) return json({ error: 'You just sent a note. Try again in a minute.' }, 429);
      if (target) {
        const from = team.name || team.players.map((p) => String(p.name || '').split(' ').slice(-1)[0]).join(' / ');
        ev.nudges = [...(ev.nudges || []), { team: target.id, text, at: now, from: clip(from, 60), fromTeam: team.id }].slice(-50);
        await this.ctx.storage.put('event', ev);
        await this.broadcast();
      }
      sent = true;
    }
    return json({ ok: true, now, on: true, hide, groups: golferGroups(ev, wh, team.id, now), notes: ev.notesOff ? [] : GOLFER_NOTES, ...(sent ? { sent } : {}) });
  }

  // a golfer's own long drive or closest to the pin, from the cart's scorecard on the contest hole. One entry a player
  // a contest: sending again replaces it until a pro has checked it. Whether it waits for a check: see cleanContest.
  async enter(b) {
    const ev = this.ev, team = ev.teams.find((t) => t.id === b.team), now = Date.now();
    if (!team || team.code !== String(b.code || '').toUpperCase()) return json({ error: 'Not your scorecard' }, 403);
    if (ev.locked) return json({ error: 'The results are final.' }, 423);
    const c = (ev.contests || []).find((x) => x.id === b.contest);
    if (!c) return json({ error: 'That contest isn’t in this tournament any more.' }, 404);
    if (!c.self) return json({ error: 'A marshal or the golf pro enters the results for this one.' }, 403);
    const p = team.players.find((x) => x.id === b.player);
    if (!p) return json({ error: 'Pick who hit it.' }, 400);
    // a GPS drive: yards from the hole's tee (on the course map) to where the phone is
    let gps = 0;
    const at = Array.isArray(b.at) && b.at.length === 2 ? b.at.map(Number) : null;
    if (c.kind === 'ld' && at && at.every(Number.isFinite) && Math.abs(at[0]) <= 90 && Math.abs(at[1]) <= 180) {
      const tee = holeMap(ev, c.hole)?.tee;
      if (tee) gps = Math.round(yds(tee, at));
    }
    const dist = Number(b.dist) > 0 ? Number(b.dist) : gps, [lo, hi] = contestRange(c);
    if (!(dist >= lo && dist <= hi)) return json({ error: c.kind === 'ld' ? 'A long drive has to be between 50 and 450 yards.' : 'Closest to the pin has to be under 200 feet.' }, 400);
    const me = { name: p.name, player: p.id }, was = c.entries.find((e) => samePlayer(e, me));
    if (was && was.okBy) return json({ error: `${p.name}’s ${c.kind === 'ld' ? 'drive' : 'shot'} has been checked. Ask the golf pro to change it.` }, 409);
    // too many tries from one cart: 12 in all per contest
    const tries = (ev.clog || []).filter((x) => x.id === c.id && x.team === team.id && x.did === 'golfer').length;
    if (tries >= 12) return json({ error: 'That’s a lot of changes. Ask the golf pro.' }, 429);
    const others = c.entries.filter((e) => e !== was);
    const e = cleanEntry({ name: p.name, player: p.id, team: team.id, dist, by: 'golfer', at: now, ...(gps ? { gps } : {}) });
    e.ok = !contestNeedsOk(c, others, e);
    c.entries = [...others, e];
    contestLog(ev, { by: p.name, team: team.id, id: c.id, name: p.name, did: 'golfer', dist: e.dist, ...(gps ? { gps } : {}) });
    await this.ctx.storage.put('event', ev);
    await this.broadcast();
    return json({ ok: true, entry: e });
  }

  // "Save your shot" from a golfer's scorecard on a camera hole: a replay of the club's camera from CLIP_BACK seconds
  // before they tapped (like a marshal's replay mark). Only the club's cameras: golfers never send video.
  // One per group per hole (tapping again moves it to now), and not when the desk turned it off or hid the camera.
  async clip(b) {
    const ev = this.ev, team = ev.teams.find((t) => t.id === b.team), now = Date.now();
    if (!team || team.code !== String(b.code || '').toUpperCase()) return json({ error: 'Not your scorecard' }, 403);
    const hole = num(b.hole, 0, 18, 0), url = (ev.cams || {})[hole];
    if (!hole || !url || (ev.camsOff || []).includes(hole)) return json({ error: 'There’s no camera on this hole.' }, 404);
    if (ev.clipsOff) return json({ error: 'Saving shots is off for this tournament.' }, 403);
    if (!/\.m3u8(\?|$)/.test(url)) return json({ error: 'This hole’s camera can’t save shots.' }, 400);
    const was = (ev.replays || []).find((r) => r.team === team.id && r.hole === hole && r.by === 'golfer');
    if (was && now - was.at < 20000) return json({ ok: true, replay: was }); // a double tap
    const r = { id: rand(6, 'abcdefghijkmnpqrstuvwxyz23456789'), hole, label: `${clip(team.name || team.players.map((p) => p.name.trim().split(/\s+/).pop()).join(' / '), 50)} · ${ev.course.holes[hole - 1]?.par === 3 || (ev.contests || []).some((c) => c.hole === hole) ? 'tee shot' : 'shot'}`,
      url: '', at: now, back: CLIP_BACK, by: 'golfer', team: team.id };
    // golfers' clips don't push out the desk's and marshals' replays: at most 40 of them
    const rest = (ev.replays || []).filter((x) => x !== was);
    const mine = rest.filter((x) => x.by === 'golfer').slice(0, 39).map((x) => x.id);
    ev.replays = [r, ...rest.filter((x) => x.by !== 'golfer' || mine.includes(x.id))].slice(0, 100);
    await this.ctx.storage.put('event', ev);
    await this.broadcast();
    return json({ ok: true, replay: r });
  }

  // sponsor counts for the report: app views and taps, and seconds on the big screens
  async getStats() {
    if (!this.st) this.st = (await this.ctx.storage.get('stats')) || {};
    return this.st;
  }
  async hit(b, ip = '') {
    const ev = this.ev, st = await this.getStats(), ids = new Set(ev.sponsors.map((x) => x.id)), now = Date.now();
    // one phone or screen sends a batch every little while: more than 40 batches in 10 minutes from one network are left out,
    // so nobody can pump up a sponsor's numbers in the report
    this.hits = this.hits && this.hits.size < 5000 ? this.hits : new Map();
    const h = this.hits.get(ip); if (h && now - h.t < 600000) { if (++h.n > 40 * Math.max(1, ev.displays?.length || 1)) return json({ ok: true }); } else this.hits.set(ip, { t: now, n: 1 });
    let n = 0;
    for (const e of (Array.isArray(b.list) ? b.list : []).slice(0, 50)) {
      if (!ids.has(e.s) || !['view', 'tap', 'secs'].includes(e.k)) continue;
      const row = st[e.s] || (st[e.s] = { view: 0, tap: 0, secs: 0 });
      row[e.k] += e.k === 'secs' ? num(e.n, 0, 600, 0) : 1; n++;
    }
    if (n) await this.ctx.storage.put('stats', st);
    return json({ ok: true });
  }

  async webSocketMessage() {}
  async webSocketClose(ws) { try { ws.close(); } catch {} }
  async webSocketError() {}
}
