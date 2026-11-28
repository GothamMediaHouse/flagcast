// Flagcast club accounts. Many clubs share one Flagcast: each club signs in with email (a 6-digit code, no
// password), sees only its own tournaments on any computer, and Flagcast approves or switches off clubs on the
// admin page (/golf/admin/, unlocked with the GOLF_CREATE_PASS secret).
//
// One Durable Object ("directory") holds every club, member, sign-in code, session and the club's tournaments.
//
//   POST /golf/api/club/start     { email }                        sends a sign-in code
//   POST /golf/api/club/verify    { email, code }                  → { token }
//   POST /golf/api/club/login     { email, password }              → { token }   (after setting a password once)
//   POST /golf/api/club/apple     { identityToken }                → { token }   Sign in with Apple (the Manager apps)
//   POST /golf/api/club/google    { idToken }                      → { token }   Sign in with Google (GOOGLE_CLIENT_ID variable)
//   POST /golf/api/club/setpass   { token, password }              sets or changes your password (signed in)
//   POST /golf/api/club/config    {}                               → { google }   the Google client id, '' when it isn't set up
//   POST /golf/api/club/me        { token }                        → { email, role, club, members, events }
//   POST /golf/api/club/request   { token, name, contact, phone, city }   asks Flagcast for a club (pending)
//   POST /golf/api/club/invite    { token, email }                 adds someone to your club
//   POST /golf/api/club/uninvite  { token, email }
//   POST /golf/api/club/hide      { token, id }                    takes a tournament off the club's list
//   POST /golf/api/club/signout   { token }
//   POST /golf/api/club/admin     { pass | token, op, … }   Flagcast Admin (passcode, or signed in with an ADMIN_EMAIL address): list, approve, on, off, delete, create (a club + its owner),
//                                 credits (tournaments a club may make: a number, or -1 for unlimited), invite, uninvite,
//                                 event (make a tournament for a club, no credit used), hide, staff-add / staff-remove { email } (who gets Admin)
// Credits: a club makes tournaments while it has credits (each new one uses one); -1 means unlimited (a season deal).
//   POST /golf/api/new            { token, name }  (a signed-in, approved club)  or  { pass, name, club? }  (Flagcast)
//
// Email goes out through Resend: RESEND_API_KEY secret and MAIL_FROM (e.g. "Flagcast <signin@flagcast.app>").
// ADMIN_EMAIL (optional) gets a note when a club asks to join, and signing in with that address (or any in a comma list) unlocks Admin. On localhost with no RESEND_API_KEY the code
// comes back in the answer (devCode) so the pages can be tried without email.
import { DurableObject } from 'cloudflare:workers';
import { SEED, slug } from './courselib.js';
import { hashPassword, checkPassword, passwordProblem, verifyAppleToken, appleKeys, APPLE_AUDIENCES, verifyGoogleToken, googleKeys } from './auth.js';
import { cleanLogo, cleanAccent, logoVersion } from './brand.js';
import { mailHtml, mailText, EMAILS } from './mail.js';
import { streamReady, liveInput, inputState, deleteInput, listAll, deleteVideo, oldRecordings } from './stream.js';
import { HIDDEN_DAYS } from './privacy.js';
import { dateNow } from './public/golf/core.js';
const tvDate = (s, now = Date.now()) => dateNow(s, new Date(now - 4 * 3600000).toISOString().slice(0, 10)); // golf.js tvDate

const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const EMAIL = /^[^\s@<>"',;]{1,64}@[^\s@<>"',;]{1,190}\.[a-z]{2,24}$/i;
const clip = (s, n) => String(s ?? '').trim().slice(0, n);
const rand = (n, abc) => { const b = crypto.getRandomValues(new Uint8Array(n)); return [...b].map((x) => abc[x % abc.length]).join(''); };
const sixDigits = () => String(crypto.getRandomValues(new Uint32Array(1))[0] % 1000000).padStart(6, '0');
const SESSION_DAYS = 90;
const num = (v, lo, hi, d) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const DAY = 86400000;
const PURGE_DAYS = 30; // a deleted club waits this long in Admin's Recently deleted before it is wiped

// safe string compare for passcodes
function same(a, b) {
  const x = new TextEncoder().encode(String(a ?? '')), y = new TextEncoder().encode(String(b ?? ''));
  let d = x.length ^ y.length; for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] || 0) ^ (y[i] || 0);
  return d === 0;
}
// the club name typed to confirm a delete: case, spaces and curly quotes don't matter
const sameName = (a, b) => { const f = (x) => String(x || '').toLowerCase().replace(/[’‘`]/g, "'").replace(/\s+/g, ' ').trim(); return !!f(a) && f(a) === f(b); };
export const isAdmin = (env, pass) => !!env.GOLF_CREATE_PASS && same(pass, env.GOLF_CREATE_PASS);
// Flagcast staff: the emails in ADMIN_EMAIL (comma-separated, set in the Cloudflare dashboard) get Admin when signed in,
// and so do the ones added in Admin → Staff (the staff table; FlagcastClubs.staffEmail checks both)
export const adminEmail = (env, email) => !!email && String(env.ADMIN_EMAIL || '').toLowerCase().split(/[\s,]+/).filter(Boolean).includes(String(email).toLowerCase());

// m: one of EMAILS in mail.js; it goes out as HTML (branded) with a plain-text copy
async function sendMail(env, to, m) {
  if (!env.RESEND_API_KEY) throw new Error('nomail');
  const subject = m.subject, text = mailText(m), html = mailHtml(m);
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST', headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env.MAIL_FROM || 'Flagcast <signin@flagcast.app>', to: String(to).split(/[\s,]+/).filter(Boolean), subject, text, html }),
  });
  if (!r.ok) throw new Error(`mail ${r.status}`);
}

// several emails in one call (Resend's batch, up to 100): [{ from, to, m }] (m: one of EMAILS). Throws if Resend says no.
export async function sendBatch(env, list) {
  if (!env.RESEND_API_KEY) throw new Error('nomail');
  const r = await fetch(`${env.RESEND_BASE || 'https://api.resend.com'}/emails/batch`, {
    method: 'POST', headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(list.map(({ from, to, m }) => ({ from, to: [to], subject: m.subject, text: mailText(m), html: mailHtml(m) }))),
  });
  if (!r.ok) throw new Error(`mail ${r.status}`);
}

// for courses.js and contact.js: may this network do k again? (max times in mins minutes; true if the directory can't answer)
export async function allowed(env, k, max, mins) {
  if (!env.CLUBS) return true;
  try {
    const r = await env.CLUBS.get(env.CLUBS.idFromName('directory')).fetch(new Request('https://clubs/limit', { method: 'POST', body: JSON.stringify({ k, max, mins }) }));
    return !!(await r.json()).ok;
  } catch { return true; }
}

// the worker hands every /golf/api/club/* call (and /golf/api/new) to the one directory object
export async function clubs(request, env, op) {
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  const local = /^(localhost|127\.0\.0\.1)$/.test(new URL(request.url).hostname);
  const stub = env.CLUBS.get(env.CLUBS.idFromName('directory'));
  const ip = request.headers.get('CF-Connecting-IP') || '';
  return stub.fetch(new Request(`https://clubs/${op}?local=${local ? 1 : 0}&ip=${encodeURIComponent(ip)}`, { method: 'POST', body: await request.text() }));
}

// a club's scorecard as kept: { name, at, holes: 18 × { n, par, yds, hcp }, tees: [{ name, rating, slope, par }] } (a tournament's
// Setup tidies it again when it starts with it)
const cnum = (v, lo, hi, d) => { const x = Number(v); return Number.isFinite(x) ? Math.min(hi, Math.max(lo, x)) : d; };
export function cleanCard(c) {
  const lat = Number(c?.at?.lat), lng = Number(c?.at?.lng);
  return { name: clip(c?.name, 80), at: Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && (lat || lng) ? { lat, lng } : null,
    holes: Array.from({ length: 18 }, (_, i) => { const h = (Array.isArray(c?.holes) ? c.holes : [])[i] || {};
      return { n: i + 1, par: cnum(h.par, 3, 6, 4), yds: cnum(h.yds, 0, 999, 0), hcp: cnum(h.hcp, 1, 18, i + 1) }; }),
    tees: (Array.isArray(c?.tees) ? c.tees : []).slice(0, 8).map((t) => ({ name: clip(t?.name, 30), rating: Math.round(cnum(t?.rating, 50, 90, 72) * 10) / 10,
      slope: cnum(t?.slope, 55, 155, 113), par: cnum(t?.par, 0, 80, 0) })).filter((t) => t.name) };
}

// where a tournament's course is, for Admin's club and tournament photos: { center: [lat, lng], span: metres } from the
// course map (every hole), else the spot Find the course gave; null when it has neither
export function coursePhoto(s) {
  const pts = Object.values(s?.map?.holes || {}).flatMap((h) => [h.tee, h.m || h.f || h.b]).filter((p) => Array.isArray(p) && p.length === 2);
  if (pts.length >= 2) {
    const la = pts.map((p) => p[0]), lo = pts.map((p) => p[1]), c = [(Math.min(...la) + Math.max(...la)) / 2, (Math.min(...lo) + Math.max(...lo)) / 2];
    const span = Math.max(700, Math.max((Math.max(...la) - Math.min(...la)) * 111000, (Math.max(...lo) - Math.min(...lo)) * 111000 * Math.cos(c[0] * Math.PI / 180)) * 1.15);
    return { center: c, span: Math.round(span) };
  }
  const a = s?.course?.at; return a && Number.isFinite(a.lat) ? { center: [a.lat, a.lng], span: 1400 } : null;
}

export class FlagcastClubs extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS clubs (id TEXT PRIMARY KEY, name TEXT, contact TEXT, phone TEXT, city TEXT, status TEXT, created INTEGER, by TEXT, credits INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS members (email TEXT PRIMARY KEY, club TEXT, role TEXT, added INTEGER);
      CREATE TABLE IF NOT EXISTS codes (email TEXT PRIMARY KEY, code TEXT, exp INTEGER, tries INTEGER, sent INTEGER, hour INTEGER, hourCount INTEGER);
      CREATE TABLE IF NOT EXISTS sessions (token TEXT PRIMARY KEY, email TEXT, created INTEGER, seen INTEGER);
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, club TEXT, key TEXT, name TEXT, created INTEGER, hidden INTEGER DEFAULT 0);
      CREATE TABLE IF NOT EXISTS payments (id TEXT PRIMARY KEY, club TEXT, amount REAL, credits INTEGER, what TEXT, note TEXT, at INTEGER);
      CREATE TABLE IF NOT EXISTS log (n INTEGER PRIMARY KEY AUTOINCREMENT, at INTEGER, who TEXT, club TEXT, what TEXT);
      CREATE TABLE IF NOT EXISTS accounts (email TEXT PRIMARY KEY, hash TEXT, salt TEXT, iter INTEGER, apple TEXT, updated INTEGER);
      CREATE TABLE IF NOT EXISTS fails (k TEXT PRIMARY KEY, n INTEGER, since INTEGER);
      CREATE TABLE IF NOT EXISTS streams (event TEXT, hole INTEGER, uid TEXT, updated INTEGER, PRIMARY KEY (event, hole));
      CREATE TABLE IF NOT EXISTS staff (email TEXT PRIMARY KEY, added INTEGER, by TEXT);
      CREATE TABLE IF NOT EXISTS tvs (id TEXT PRIMARY KEY, club TEXT, name TEXT, place TEXT, kind TEXT, token TEXT, event TEXT, joined TEXT, added INTEGER, seen INTEGER);
      CREATE TABLE IF NOT EXISTS tvcodes (code TEXT PRIMARY KEY, pair TEXT, kind TEXT, exp INTEGER, tv TEXT, token TEXT);`);
    // columns added after the first release
    for (const q of ['ALTER TABLE accounts ADD COLUMN google TEXT', 'ALTER TABLE clubs ADD COLUMN notes TEXT', 'ALTER TABLE events ADD COLUMN archived INTEGER DEFAULT 0', 'ALTER TABLE clubs ADD COLUMN course TEXT',
      'ALTER TABLE clubs ADD COLUMN logo TEXT', 'ALTER TABLE clubs ADD COLUMN accent TEXT', 'ALTER TABLE clubs ADD COLUMN powered INTEGER DEFAULT 0',
      'ALTER TABLE clubs ADD COLUMN deleted INTEGER', 'ALTER TABLE clubs ADD COLUMN was TEXT', 'ALTER TABLE events ADD COLUMN demo INTEGER DEFAULT 0',
      'ALTER TABLE clubs ADD COLUMN card TEXT', 'ALTER TABLE events ADD COLUMN hiddenAt INTEGER']) { try { this.sql.exec(q); } catch {} }
    // the Flagcast course library (courselib.js): courses any club can pick in Find the course
    this.sql.exec('CREATE TABLE IF NOT EXISTS library (id TEXT PRIMARY KEY, name TEXT, city TEXT, state TEXT, data TEXT, club TEXT, updated INTEGER)');
    for (const c of SEED) if (!this.one('SELECT id FROM library WHERE id = ?', c.id)) this.libPut(c, '', 0);
  }
  libPut(c, club, at) {
    this.sql.exec('INSERT OR REPLACE INTO library (id, name, city, state, data, club, updated) VALUES (?, ?, ?, ?, ?, ?, ?)',
      c.id, c.name, c.city || '', c.state || '', JSON.stringify({ ...c, by: club || c.by || '', updated: at || c.updated || 0 }), club || '', at || 0);
  }
  note(who, club, what) {
    this.sql.exec('INSERT INTO log (at, who, club, what) VALUES (?, ?, ?, ?)', Date.now(), who || '', club || '', String(what).slice(0, 200));
    this.sql.exec('DELETE FROM log WHERE n < (SELECT MAX(n) FROM log) - 3000');
  }
  // talk to one tournament (GolfEvent) directly
  async golf(id, path, body) {
    const r = await this.env.GOLF.get(this.env.GOLF.idFromName(id)).fetch(new Request(`https://golf/${path}`, body ? { method: 'POST', body: JSON.stringify(body) } : {}));
    const j = await r.json().catch(() => ({})); if (!r.ok) throw Object.assign(new Error(j.error || 'That tournament didn’t answer.'), { status: r.status }); return j;
  }
  // Flagcast staff: an email in ADMIN_EMAIL (Cloudflare) or one added in Admin → Staff
  staffEmail(email) { return adminEmail(this.env, email) || (!!email && !!this.one('SELECT email FROM staff WHERE email = ?', String(email).toLowerCase())); }
  // Admin: the passcode, or a sign-in whose email is staff
  isStaff(b) {
    // the passcode: 5 wrong from one network and 20 in all in 15 minutes, then a wait (saved in the fails table)
    if (b.pass !== undefined && b.pass !== '' && this.env.GOLF_CREATE_PASS) {
      const keys = [[`pass:${this.ip}`, 5], ['pass:*', 20]], now = Date.now();
      for (const [k, max] of keys) { const f = this.one('SELECT * FROM fails WHERE k = ?', k); if (f && now - f.since < 15 * 60000 && f.n >= max) this.fail('Too many wrong passcodes. Wait 15 minutes, or sign in with your staff email.', 429); }
      if (isAdmin(this.env, b.pass)) return true;
      this.failed(keys);
    }
    if (!b.token) return false;
    try { return this.staffEmail(this.who(b.token).email); } catch { return false; }
  }
  staffList() {
    const fixed = String(this.env.ADMIN_EMAIL || '').toLowerCase().split(/[\s,]+/).filter(Boolean);
    const seen = Object.fromEntries(this.all('SELECT email, MAX(seen) AS seen FROM sessions GROUP BY email').map((s) => [s.email, s.seen]));
    return [...fixed.map((email) => ({ email, fixed: true, added: 0, by: '' })),
      ...this.all('SELECT * FROM staff ORDER BY added').filter((r) => !fixed.includes(r.email)).map((r) => ({ ...r, fixed: false }))].map((r) => ({ ...r, seen: seen[r.email] || 0 }));
  }
  // club branding (brand.js): what its tournaments show instead of the Flagcast logo
  brandOf(c) { return { logo: c?.logo || '', accent: c?.accent || '', powered: !!c?.powered }; }
  logoURL(c) { return c?.logo ? `/golf/api/club/logo/${c.id}?v=${logoVersion(c.logo)}` : ''; }
  async pushBrand(cid) {
    const c = this.one('SELECT * FROM clubs WHERE id = ?', cid); if (!c) return 0;
    const evs = this.all('SELECT id FROM events WHERE club = ?', cid);
    await Promise.all(evs.map((e) => this.golf(e.id, 'brand', { club: this.brandOf(c) }).catch(() => {})));
    return evs.length;
  }
  setBrand(cid, b) {
    const c = this.one('SELECT * FROM clubs WHERE id = ?', cid); if (!c) this.fail('That club isn’t there any more.', 404);
    let logo = c.logo || '';
    if (b.logo !== undefined) { try { logo = cleanLogo(b.logo); } catch (e) { this.fail(e.message, e.status || 400); } }
    const accent = b.accent !== undefined ? cleanAccent(b.accent) : (c.accent || '');
    this.sql.exec('UPDATE clubs SET logo = ?, accent = ? WHERE id = ?', logo, accent, cid);
  }
  one(q, ...a) { return this.sql.exec(q, ...a).toArray()[0] || null; }
  all(q, ...a) { return this.sql.exec(q, ...a).toArray(); }

  async fetch(request) {
    const url = new URL(request.url), op = url.pathname.slice(1), local = url.searchParams.get('local') === '1';
    let b = {}; try { b = JSON.parse(await request.text() || '{}'); } catch {}
    this.ip = url.searchParams.get('ip') || '';
    try { return await this.route(op, b, local); }
    catch (e) { return json({ error: e.status ? e.message : 'Something went wrong. Try again.' }, e.status || 500); }
  }

  who(token) {
    const s = token && this.one('SELECT * FROM sessions WHERE token = ?', String(token));
    if (!s || Date.now() - s.created > SESSION_DAYS * DAY) throw Object.assign(new Error('Please sign in again.'), { status: 401 });
    if (Date.now() - s.seen > DAY) this.sql.exec('UPDATE sessions SET seen = ? WHERE token = ?', Date.now(), s.token);
    const m = this.one('SELECT * FROM members WHERE email = ?', s.email);
    const club = m && this.one('SELECT * FROM clubs WHERE id = ?', m.club);
    return { email: s.email, role: m?.role || null, club };
  }
  fail(msg, status = 400) { throw Object.assign(new Error(msg), { status }); }

  // a new session for a signed-in email (code, password or Apple)
  session(email, how) {
    const now = Date.now(), token = rand(40, 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
    this.sql.exec('INSERT INTO sessions (token, email, created, seen) VALUES (?, ?, ?, ?)', token, email, now, now);
    this.note(email, this.one('SELECT club FROM members WHERE email = ?', email)?.club, `Signed in${how ? ` (${how})` : ''}`);
    this.sql.exec('DELETE FROM sessions WHERE created < ?', now - SESSION_DAYS * DAY);
    return token;
  }
  // failed password sign-ins: 5 per email and 30 per network in 15 minutes, then a wait
  tooMany(keys) {
    const now = Date.now();
    for (const [k, max] of keys) {
      const f = this.one('SELECT * FROM fails WHERE k = ?', k);
      if (f && now - f.since < 15 * 60000 && f.n >= max) this.fail('Too many tries. Wait 15 minutes, or sign in with an emailed code.', 429);
    }
  }
  // a general limit: true while k has been used fewer than max times in this window (and counts this use)
  limit(k, max, win) {
    const now = Date.now(), f = this.one('SELECT * FROM fails WHERE k = ?', k);
    if (!f || now - f.since >= win) { this.sql.exec('INSERT OR REPLACE INTO fails (k, n, since) VALUES (?, 1, ?)', k, now); return true; }
    if (f.n >= max) return false;
    this.sql.exec('UPDATE fails SET n = n + 1 WHERE k = ?', k); return true;
  }
  failed(keys) {
    const now = Date.now();
    for (const [k] of keys) {
      const f = this.one('SELECT * FROM fails WHERE k = ?', k);
      if (!f || now - f.since >= 15 * 60000) this.sql.exec('INSERT OR REPLACE INTO fails (k, n, since) VALUES (?, 1, ?)', k, now);
      else this.sql.exec('UPDATE fails SET n = n + 1 WHERE k = ?', k);
    }
    this.sql.exec('DELETE FROM fails WHERE since < ?', now - DAY);
  }

  // the club's course map (hole GPS) for a new tournament
  courseOf(club) { try { return club?.course ? JSON.parse(club.course) : null; } catch { return null; } }
  // the club's scorecard (name, spot, holes, tees) for a new tournament: from Admin's Add club, or its latest tournament
  cardOf(club) { try { return club?.card ? JSON.parse(club.card) : null; } catch { return null; } }
  // what a new tournament starts with: the club's name, its course map and its scorecard
  initBody(name, club) { return JSON.stringify({ name, club: club?.name || '', map: this.courseOf(club), card: this.cardOf(club) }); }
  // keep a club's course: card { name, at, holes, tees } and/or map { holes, src } (left out = stays as it is)
  keepCourse(id, card, map) {
    if (card) { const t = JSON.stringify(cleanCard(card)); if (t.length > 20000) this.fail('Too big'); this.sql.exec('UPDATE clubs SET card = ? WHERE id = ?', t, id); }
    if (map) { const t = JSON.stringify(map); if (t.length > 200000) this.fail('Too big'); this.sql.exec('UPDATE clubs SET course = ? WHERE id = ?', t, id); }
  }

  async route(op, b, local) {
    const env = this.env, now = Date.now();
    if (op.startsWith('tv-')) return this.tvRoute(op.slice(3), b, now);
    // the course library (only reached from courses.js, never straight from the web)
    // is this live input one of Flagcast's cameras? (golf.js, before serving its playlists; never from the web)
    // limits for the other parts of the worker (courses.js, contact.js): { k, max, mins } → { ok }. Never from the web
    if (op === 'limit') return json({ ok: this.limit(`lim:${clip(b.k, 120)}`, num(b.max, 1, 10000, 10), num(b.mins, 1, 1440, 60) * 60000) });
    // "Try a demo" in the player and TV apps (golf.js GET /golf/api/demo): the newest tournament Admin marked Demo that
    // isn't archived → { id } (Apple's reviewers have no tournament code). Demo marks made before the events.demo column
    // existed are found once by asking each tournament.
    if (op === 'demo-find') {
      if (!(await this.ctx.storage.get('demoScanned'))) {
        const rows = this.all('SELECT id FROM events WHERE COALESCE(archived, 0) = 0 ORDER BY created DESC LIMIT 300');
        await Promise.all(rows.map(async (e) => { try { const s = await this.golf(e.id, 'state'); if (s.brand?.marked) this.sql.exec('UPDATE events SET demo = 1 WHERE id = ?', e.id); } catch {} }));
        await this.ctx.storage.put('demoScanned', Date.now());
      }
      const row = this.one("SELECT e.id FROM events e LEFT JOIN clubs c ON c.id = e.club WHERE e.demo = 1 AND COALESCE(e.archived, 0) = 0 AND COALESCE(c.status, '') NOT IN ('deleted', 'purged') ORDER BY e.created DESC LIMIT 1");
      return json({ id: row?.id || '' });
    }
    // the worker's daily cron (worker.js scheduled). Never from the web
    if (op === 'tidy') return json(await this.tidy(now));
    if (op === 'streamok') return json({ ok: !!this.one('SELECT hole FROM streams WHERE uid = ?', clip(b.uid, 40)) });
    if (op === 'lib-search') {
      const words = clip(b.q, 80).toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 1).slice(0, 5);
      if (!words.length) return json({ courses: [] });
      const rows = this.all('SELECT id, name, city, state FROM library').filter((r) => { const t = `${r.name} ${r.city} ${r.state}`.toLowerCase(); return words.every((w) => t.includes(w)); });
      return json({ courses: rows.slice(0, 10).map((r) => ({ id: r.id, name: r.name, city: r.city, state: r.state, library: true })) });
    }
    if (op === 'lib-get') {
      const r = this.one('SELECT data FROM library WHERE id = ?', clip(b.id, 60));
      return r ? json({ ...JSON.parse(r.data), library: true }) : json({ error: 'That course isn’t in the Flagcast library.' }, 404);
    }
    if (op === 'lib-save') { // from a tournament's desk: its course (scorecard, tees, location, hole map) goes in the library
      const e = this.one('SELECT * FROM events WHERE id = ?', clip(b.event, 8));
      const admin = this.isStaff(b);
      if (!admin && !b.key) this.fail('This desk link is not right.', 403);
      if (!/^[a-z0-9]{8}$/.test(String(b.event || ''))) this.fail('Not found', 404);
      // the tournament itself checks the desk key
      const ev = await this.golf(b.event, 'desk', { key: b.key || e?.key, op: 'get' });
      const c = ev.course || {}, name = clip(c.name, 80);
      if (!name) this.fail('Type the course name in Setup first.');
      const id = slug(name), old = this.one('SELECT club FROM library WHERE id = ?', id);
      if (old && !(e?.club && old.club === e.club) && !admin) this.fail('That course is already in the Flagcast library. Ask Flagcast to update it.', 409);
      const holes = (c.holes || []).map((h) => ({ par: h.par, yds: h.yds || null, hcp: h.hcp }));
      const par = holes.reduce((a, h) => a + (h.par || 0), 0), yards = holes.reduce((a, h) => a + (h.yds || 0), 0) || null;
      const entry = { id, name, club: clip(ev.club, 80), course: '', city: clip(b.city, 60), state: clip(b.state, 30), at: c.at || null,
        tees: (c.tees || []).map((t) => ({ name: t.name, women: /\(women\)|\(w\)/i.test(t.name), rating: t.rating, slope: t.slope, par: t.par || par, yards, holes })),
        map: ev.map && ev.map.holes && Object.keys(ev.map.holes).length ? { holes: ev.map.holes, src: ev.map.src || '' } : null, src: `Saved from ${clip(ev.name, 60)}` };
      if (JSON.stringify(entry).length > 250000) this.fail('Too big');
      this.libPut(entry, e?.club || '', now);
      this.note(admin ? 'admin' : 'desk', e?.club || '', `Course library: saved ${name}`);
      return json({ ok: true, id });
    }
    // Go live from an iPhone at the hole (golf.js day op 'golive', from the desk, Admin or a pro's PIN): the hole's live
    // input, the same one an NDI camera would use (made once, reused, recorded), for the phone to send to.
    // Only from the tournament itself (it passes its desk key). → { uid, srt, rtmps, playback, state }
    if (op === 'golive') {
      const tid = String(b.id || '').toLowerCase();
      if (!/^[a-z0-9]{8}$/.test(tid) || !b.key) this.fail('Not found', 404);
      // a club's tournament is on the list; one Flagcast made without a club isn't, so ask the tournament itself
      let e = this.one('SELECT * FROM events WHERE id = ?', tid);
      if (!e) { const d = await this.golf(tid, 'desk', { key: String(b.key), op: 'get' }).catch(() => null); if (d && d.key) e = { id: tid, key: d.key, name: d.name || '', club: '' }; }
      if (!e || !same(String(b.key), e.key)) this.fail('Not found', 404);
      if (!streamReady(this.env)) this.fail('Live video isn’t switched on for Flagcast yet. Ask Flagcast to set up Cloudflare Stream.', 409);
      const hole = num(b.hole, 0, 18, -1); if (hole < 0) this.fail('Pick a hole.'); // 0: the clubhouse
      const old = this.one('SELECT uid FROM streams WHERE event = ? AND hole = ?', e.id, hole);
      const input = await liveInput(this.env, fetch, { uid: old?.uid, name: `${clip(b.name || e.name, 80)} · ${hole ? `hole ${hole}` : 'clubhouse'}` }).catch((x) => this.fail(x.message, 502));
      this.sql.exec('INSERT OR REPLACE INTO streams (event, hole, uid, updated) VALUES (?, ?, ?, ?)', e.id, hole, input.uid, Date.now());
      const state = old ? await inputState(this.env, fetch, input.uid) : 'disconnected';
      if (!old) this.note(clip(b.by, 40) || 'Desk', e.club || '', `Go live: ${hole ? `hole ${hole}` : 'clubhouse'} camera from an iPhone · ${clip(b.name || e.name, 80)}`);
      return json({ ok: true, hole, uid: input.uid, srt: input.srt, rtmps: input.rtmps, playback: input.playback, state });
    }
    if (op === 'course') { // only from a tournament (GolfEvent) after its map or Setup was saved: the club keeps the latest one
      const e = this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8));
      if (!e || !b.key || !same(b.key, e.key)) this.fail('Not found', 404);
      // the map when it was saved; the scorecard when the tournament's Setup was saved with a course name
      this.keepCourse(e.club, b.card && b.card.name ? b.card : null, b.map || (b.card ? null : {}));
      return json({ ok: true });
    }
    if (op === 'start') {
      const email = clip(b.email, 254).toLowerCase();
      if (!EMAIL.test(email)) this.fail('Type a full email address.');
      // codes from one network: 10 an hour (so a script can't make Flagcast email lots of people)
      if (this.ip && !this.limit(`start:${this.ip}`, 10, 3600000)) this.fail('Too many sign-in codes from this network. Try again in an hour, or use a password.', 429);
      const c = this.one('SELECT * FROM codes WHERE email = ?', email);
      if (c && now - c.sent < 30000) this.fail('A code was just sent. Wait half a minute before asking for another.', 429);
      const hour = Math.floor(now / 3600000), hourCount = c && c.hour === hour ? c.hourCount + 1 : 1;
      if (hourCount > 6) this.fail('Too many codes for that email this hour. Try again later.', 429);
      const code = sixDigits();
      this.sql.exec('INSERT OR REPLACE INTO codes (email, code, exp, tries, sent, hour, hourCount) VALUES (?, ?, ?, 0, ?, ?, ?)', email, code, now + 15 * 60000, now, hour, hourCount);
      try { await sendMail(env, email, EMAILS.code(code)); }
      catch (e) {
        if (e.message === 'nomail' && local) return json({ ok: true, devCode: code });
        this.sql.exec('DELETE FROM codes WHERE email = ?', email);
        this.fail(e.message === 'nomail' ? 'Sign-in email isn’t set up yet. Contact hello@flagcast.app.' : 'The email didn’t send. Try again in a minute.', 503);
      }
      return json({ ok: true });
    }
    if (op === 'verify') {
      const email = clip(b.email, 254).toLowerCase(), code = clip(b.code, 12).replace(/\D/g, '');
      const c = this.one('SELECT * FROM codes WHERE email = ?', email);
      if (!c || c.exp < now) this.fail('That code has run out. Ask for a new one.');
      if (c.tries >= 5) { this.sql.exec('DELETE FROM codes WHERE email = ?', email); this.fail('Too many tries. Ask for a new code.'); }
      if (!same(code, c.code)) { this.sql.exec('UPDATE codes SET tries = tries + 1 WHERE email = ?', email); this.fail('That code isn’t right.'); }
      this.sql.exec('DELETE FROM codes WHERE email = ?', email);
      return json({ token: this.session(email) });
    }
    if (op === 'login') {
      const email = clip(b.email, 254).toLowerCase(), keys = [[`e:${email}`, 5], [`ip:${this.ip}`, 30]];
      if (!EMAIL.test(email)) this.fail('Type a full email address.');
      this.tooMany(keys);
      const a = this.one('SELECT * FROM accounts WHERE email = ?', email);
      if (!a || !a.hash || !(await checkPassword(b.password, a))) {
        this.failed(keys);
        this.fail(a && a.hash ? 'That password isn’t right.' : 'There’s no password for that email yet. Sign in with an emailed code, then set one in Settings.', 401);
      }
      this.sql.exec('DELETE FROM fails WHERE k = ?', `e:${email}`);
      return json({ token: this.session(email, 'password') });
    }
    if (op === 'setpass') {
      const u = this.who(b.token), problem = passwordProblem(b.password);
      if (problem) this.fail(problem);
      const h = await hashPassword(b.password);
      const old = this.one('SELECT * FROM accounts WHERE email = ?', u.email);
      if (old) this.sql.exec('UPDATE accounts SET hash = ?, salt = ?, iter = ?, updated = ? WHERE email = ?', h.hash, h.salt, h.iter, now, u.email);
      else this.sql.exec('INSERT INTO accounts (email, hash, salt, iter, apple, google, updated) VALUES (?, ?, ?, ?, ?, ?, ?)', u.email, h.hash, h.salt, h.iter, '', '', now);
      this.note(u.email, u.club?.id, old?.hash ? 'Changed password' : 'Set a password');
      return json({ ok: true });
    }
    // which sign-ins are switched on: Google (its client id), and Sign in with Apple on the web, Mac and Windows (the
    // Services ID; the iPhone app signs in with Apple natively without it)
    if (op === 'config') return json({ google: env.GOOGLE_CLIENT_ID || '', apple: env.APPLE_SERVICE_ID || '' });
    if (op === 'apple') {
      let id;
      try { id = await verifyAppleToken(b.identityToken, { keys: await appleKeys(), audiences: [...APPLE_AUDIENCES, ...(env.APPLE_SERVICE_ID ? [env.APPLE_SERVICE_ID] : [])] }); }
      catch (e) { this.fail(e.message === 'apple-keys' ? 'Apple didn’t answer. Try again in a minute.' : e.message, 401); }
      // the account linked to this Apple ID, or the verified email Apple shares (linked from now on)
      let a = this.one('SELECT * FROM accounts WHERE apple = ?', id.sub);
      if (!a) {
        if (!id.email || !id.emailVerified) this.fail('Apple didn’t share an email. Sign in with an emailed code once, then Sign in with Apple works.', 401);
        a = this.one('SELECT * FROM accounts WHERE email = ?', id.email);
        if (a) this.sql.exec('UPDATE accounts SET apple = ?, updated = ? WHERE email = ?', id.sub, now, id.email);
        else this.sql.exec('INSERT INTO accounts (email, hash, salt, iter, apple, google, updated) VALUES (?, ?, ?, ?, ?, ?, ?)', id.email, '', '', 0, id.sub, '', now);
        a = { email: id.email };
      }
      return json({ token: this.session(a.email, 'Apple') });
    }
    if (op === 'google') {
      let id;
      try { id = await verifyGoogleToken(b.idToken, { keys: await googleKeys(), clientId: env.GOOGLE_CLIENT_ID }); }
      catch (e) { this.fail(e.message === 'google-keys' ? 'Google didn’t answer. Try again in a minute.' : e.message, 401); }
      let a = this.one('SELECT * FROM accounts WHERE google = ?', id.sub);
      if (!a) {
        if (!id.email || !id.emailVerified) this.fail('Google didn’t share a verified email. Sign in with an emailed code instead.', 401);
        a = this.one('SELECT * FROM accounts WHERE email = ?', id.email);
        if (a) this.sql.exec('UPDATE accounts SET google = ?, updated = ? WHERE email = ?', id.sub, now, id.email);
        else this.sql.exec('INSERT INTO accounts (email, hash, salt, iter, apple, google, updated) VALUES (?, ?, ?, ?, ?, ?, ?)', id.email, '', '', 0, '', id.sub, now);
        a = { email: id.email };
      }
      return json({ token: this.session(a.email, 'Google') });
    }
    if (op === 'signout') { this.sql.exec('DELETE FROM sessions WHERE token = ?', String(b.token || '')); return json({ ok: true }); }
    if (op === 'me') return json(this.me(this.who(b.token)));
    // the club's logo and colour, from its own Manager app (any of its members)
    if (op === 'brand') {
      const u = this.who(b.token); if (!u.club) this.fail('Set up your club first.', 403);
      this.setBrand(u.club.id, b);
      const n = await this.pushBrand(u.club.id);
      this.note(u.email, u.club.id, `Branding: ${b.logo === '' ? 'logo removed' : b.logo !== undefined ? 'new logo' : 'colour'}${n ? ` · ${n} tournaments` : ''}`);
      return json(this.me(this.who(b.token)));
    }
    if (op === 'logo-get') return json({ logo: this.one('SELECT logo FROM clubs WHERE id = ?', clip(b.club, 10))?.logo || '' }); // golf.js serves it
    if (op === 'request') {
      const u = this.who(b.token);
      if (u.club) this.fail('You’re already part of a club.');
      const name = clip(b.name, 80); if (!name) this.fail('Type your club’s name.');
      if (!this.limit(`request:${u.email}`, 3, DAY)) this.fail('You’ve asked a few times today. Flagcast will be in touch.', 429);
      const id = rand(10, 'abcdefghijkmnpqrstuvwxyz23456789');
      this.sql.exec('INSERT INTO clubs (id, name, contact, phone, city, status, created, by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', id, name, clip(b.contact, 80), clip(b.phone, 40), clip(b.city, 80), 'pending', now, u.email);
      this.sql.exec('INSERT OR REPLACE INTO members (email, club, role, added) VALUES (?, ?, ?, ?)', u.email, id, 'owner', now);
      this.note(u.email, id, `Asked to join: ${name}`);
      if (env.ADMIN_EMAIL) sendMail(env, env.ADMIN_EMAIL, EMAILS.newClub(name, [clip(b.contact, 80), u.email, clip(b.phone, 40), clip(b.city, 80)])).catch(() => {});
      return json(this.me(this.who(b.token)));
    }
    if (op === 'invite' || op === 'uninvite') {
      const u = this.who(b.token);
      if (!u.club || u.role !== 'owner') this.fail('Only the person who set up the club can change who’s in it.', 403);
      const email = clip(b.email, 254).toLowerCase();
      if (!EMAIL.test(email)) this.fail('Type a full email address.');
      if (email === u.email) this.fail('That’s you.');
      if (op === 'invite') {
        const m = this.one('SELECT * FROM members WHERE email = ?', email);
        if (m && m.club !== u.club.id) this.fail('That email already belongs to another club.');
        this.sql.exec('INSERT OR REPLACE INTO members (email, club, role, added) VALUES (?, ?, ?, ?)', email, u.club.id, 'staff', now);
        sendMail(env, email, EMAILS.added(u.club.name, u.email)).catch(() => {});
      } else this.sql.exec('DELETE FROM members WHERE email = ? AND club = ? AND role != ?', email, u.club.id, 'owner');
      this.note(u.email, u.club.id, `${op === 'invite' ? 'Added' : 'Removed'} ${email}`);
      return json(this.me(u));
    }
    if (op === 'hide') {
      const u = this.who(b.token);
      if (!u.club) this.fail('Not found', 404);
      // a club's Delete Tournament: off its list now, wiped for good HIDDEN_DAYS later by the daily tidy (Admin can bring it back till then)
      this.sql.exec('UPDATE events SET hidden = 1, hiddenAt = ? WHERE id = ? AND club = ?', now, clip(b.id, 8), u.club.id);
      return json(this.me(u));
    }
    if (op === 'new') {
      const name = clip(b.name, 80);
      let club = null;
      if (b.pass !== undefined && b.pass !== '') {
        if (!this.isStaff(b) && !(local && !env.GOLF_CREATE_PASS)) this.fail('That passcode is not right.', 403);
        if (b.club) club = this.one('SELECT * FROM clubs WHERE id = ?', clip(b.club, 10));
      } else if (b.token) {
        const u = this.who(b.token);
        if (!u.club) this.fail('Set up your club first.', 403);
        if (u.club.status === 'pending') this.fail('Your club is waiting for Flagcast to approve it. We’ll email you when it’s ready.', 403);
        if (u.club.status !== 'active') this.fail('This club is switched off. Contact hello@flagcast.app.', 403);
        if (u.club.credits === 0) this.fail('Your club has no tournaments left to make. Contact hello@flagcast.app to add more.', 402);
        club = u.club;
      } else if (local && !env.GOLF_CREATE_PASS) {
        // local dev: anyone can make one
      } else this.fail('Sign in with your club’s account to make a tournament.', 401);
      const id = rand(8, 'abcdefghijkmnpqrstuvwxyz23456789');
      // take the credit before making it (two quick taps on the last credit can't both get one), and give it back if making fails
      const paid = !b.pass && club && club.credits > 0;
      if (paid) {
        // (no await since the check above, so nothing else ran in between)
        this.sql.exec('UPDATE clubs SET credits = credits - 1 WHERE id = ? AND credits > 0', club.id);
      }
      let r, j;
      try { r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/init?id=${id}`, { method: 'POST', body: this.initBody(name, club) })); j = await r.json(); }
      catch { r = { ok: false, status: 502 }; j = { error: 'That didn’t work. Try again.' }; }
      if (!r.ok) { if (paid) this.sql.exec('UPDATE clubs SET credits = credits + 1 WHERE id = ?', club.id); return json(j, r.status); }
      if (club) {
        this.sql.exec('INSERT INTO events (id, club, key, name, created) VALUES (?, ?, ?, ?, ?)', id, club.id, j.key, name || 'New tournament', now);
        this.note(b.pass ? 'Flagcast' : this.who(b.token).email, club.id, `Made tournament ${name || 'New tournament'} (${id.toUpperCase()})`);
        if (club.logo || club.accent) await this.golf(id, 'brand', { club: this.brandOf(club) }).catch(() => {});
      }
      return json(j);
    }
    if (op === 'admin') {
      if (!this.isStaff(b) && !(local && !env.GOLF_CREATE_PASS)) this.fail('That passcode is not right.', 403);
      const cid = clip(b.club, 10), c = cid ? this.one('SELECT * FROM clubs WHERE id = ?', cid) : null;
      const need = () => { if (!c) this.fail('That club isn’t there any more.', 404); };
      if (c && ['deleted', 'purged'].includes(c.status) && !['restore', 'purge'].includes(b.op)) this.fail(c.status === 'deleted' ? 'That club is in Recently deleted. Restore it first.' : 'That club was deleted.', 410);
      if (b.op === 'staffcheck') return json({ ok: true }); // the worker asks before it looks a course up (golf.js adminWithCourse)
      let made = null;
      if (b.op === 'approve' || b.op === 'on') {
        need(); this.sql.exec('UPDATE clubs SET status = ? WHERE id = ?', 'active', cid);
        if (b.op === 'approve' && c.status === 'pending' && c.by) this.mail(c.by, EMAILS.approved(c.name));
      }
      if (b.op === 'off') { need(); this.sql.exec('UPDATE clubs SET status = ? WHERE id = ?', 'off', cid); }
      if (b.op === 'delete') {
        need();
        // a mistaken or spam request (no tournaments), or a test club: with tournaments, only after typing the club's name.
        // Nothing is wiped yet: the club goes to Recently deleted for 30 days (Restore puts it back), its people lose access
        // and its tournaments are locked and taken off lists. After 30 days (or Delete now) they are wiped for good.
        const evs = this.all('SELECT id, name FROM events WHERE club = ?', cid);
        if (c.status === 'deleted') this.fail('That club is already in Recently deleted.');
        if (evs.length && !sameName(b.confirm, c.name)) this.fail(`This club has ${evs.length === 1 ? 'a tournament' : `${evs.length} tournaments`}. Type the club’s name to delete it and its tournaments.`);
        const cam = this.one(`SELECT s.hole, e.name FROM streams s JOIN events e ON e.id = s.event WHERE e.club = ?`, cid);
        if (cam) this.fail(`${cam.name} still streams hole ${cam.hole}. Stop that camera in Cameras first.`, 409);
        const members = this.all('SELECT * FROM members WHERE club = ?', cid);
        for (const e of evs) await this.golf(e.id, 'desk', { key: this.one('SELECT key FROM events WHERE id = ?', e.id).key, op: 'lock', locked: true }).catch(() => {});
        this.sql.exec('UPDATE events SET hidden = 1 WHERE club = ? AND hidden = 0', cid); // (marked so Restore shows them again)
        this.sql.exec('UPDATE clubs SET status = ?, deleted = ?, was = ? WHERE id = ?', 'deleted', now, JSON.stringify({ status: c.status, members, hid: evs.map((e) => e.id) }), cid);
        this.sql.exec('DELETE FROM members WHERE club = ?', cid);
        this.note('Flagcast', cid, `Admin: deleted club ${c.name}${evs.length ? ` and ${evs.length === 1 ? 'its tournament' : `its ${evs.length} tournaments`} (${evs.map((e) => e.name).join(', ')})` : ''} · Restore in Recently deleted for 30 days`);
        await this.ctx.storage.setAlarm(now + PURGE_DAYS * DAY).catch(() => {});
      }
      // Recently deleted: put a club back with its people and tournaments, or wipe it now (type its name)
      if (b.op === 'restore') {
        need(); if (c.status !== 'deleted') this.fail('That club isn’t deleted.');
        let was = {}; try { was = JSON.parse(c.was || '{}'); } catch {}
        const back = [];
        for (const m of was.members || []) if (!this.one('SELECT email FROM members WHERE email = ?', m.email)) { this.sql.exec('INSERT INTO members (email, club, role, added) VALUES (?, ?, ?, ?)', m.email, cid, m.role, m.added); back.push(m.email); }
        for (const id of was.hid || []) this.sql.exec('UPDATE events SET hidden = 0 WHERE id = ? AND club = ?', id, cid);
        this.sql.exec('UPDATE clubs SET status = ?, deleted = NULL, was = NULL WHERE id = ?', was.status && was.status !== 'deleted' ? was.status : 'off', cid);
        this.note('Flagcast', cid, `Admin: restored club ${c.name} (${back.length} people back; tournaments stay locked until the desk unlocks them)`);
      }
      if (b.op === 'purge') {
        need(); if (c.status !== 'deleted') this.fail('Delete the club first; it then waits 30 days in Recently deleted.');
        if (!sameName(b.confirm, c.name)) this.fail('Type the club’s name to wipe it for good.');
        const left = await this.purge(c);
        if (left) this.fail(`${left} of its tournaments didn’t answer, so they weren’t wiped. Try again in a minute.`, 502);
      }
      if (b.op === 'create') {
        const name = clip(b.name, 80), email = clip(b.email, 254).toLowerCase();
        if (!name) this.fail('Type the club’s name.');
        if (email && !EMAIL.test(email)) this.fail('Type a full email address for the owner, or leave it blank.');
        if (email && this.one('SELECT club FROM members WHERE email = ?', email)) this.fail('That email already belongs to a club.');
        const id = rand(10, 'abcdefghijkmnpqrstuvwxyz23456789'), credits = Math.trunc(num(b.credits, -1, 999, 0));
        this.sql.exec('INSERT INTO clubs (id, name, contact, phone, city, status, created, by, credits) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', id, name, clip(b.contact, 80), clip(b.phone, 40), clip(b.city, 80), 'active', now, email || null, credits);
        if (email) {
          this.sql.exec('INSERT INTO members (email, club, role, added) VALUES (?, ?, ?, ?)', email, id, 'owner', now);
          this.mail(email, EMAILS.setUp(name));
        }
        // the course picked in Add club (the worker looked it up: golf.js adminWithCourse)
        this.keepCourse(id, b.card, b.map);
        if (b.card) this.note('Flagcast', id, `Course: ${clip(b.card.name, 80)}${b.map ? ' with its hole map' : ''}`);
        made = { club: id };
      }
      if (b.op === 'setcourse') { // a club's course, picked again in Admin: its next tournaments start with it
        need(); if (!b.card) this.fail('Pick the course from the list.');
        this.keepCourse(cid, b.card, b.map);
        this.note('Flagcast', cid, `Course: ${clip(b.card.name, 80)}${b.map ? ' with its hole map' : ''}`);
      }
      if (b.op === 'credits') {
        need();
        const v = b.add !== undefined ? (c.credits < 0 ? -1 : Math.max(0, c.credits + Math.trunc(num(b.add, -999, 999, 0)))) : Math.trunc(num(b.set, -1, 999, 0));
        this.sql.exec('UPDATE clubs SET credits = ? WHERE id = ?', Math.min(999, v), cid);
      }
      if (b.op === 'invite' || b.op === 'uninvite') {
        need();
        const email = clip(b.email, 254).toLowerCase();
        if (!EMAIL.test(email)) this.fail('Type a full email address.');
        if (b.op === 'invite') {
          const m = this.one('SELECT * FROM members WHERE email = ?', email);
          if (m && m.club !== cid) this.fail('That email already belongs to another club.');
          const role = this.one('SELECT email FROM members WHERE club = ? AND role = ?', cid, 'owner') ? 'staff' : 'owner';
          this.sql.exec('INSERT OR REPLACE INTO members (email, club, role, added) VALUES (?, ?, ?, ?)', email, cid, m?.role || role, now);
          if (!m) this.mail(email, EMAILS.added(c.name));
        } else this.sql.exec('DELETE FROM members WHERE email = ? AND club = ?', email, cid);
      }
      if (b.op === 'event') {
        need();
        const id = rand(8, 'abcdefghijkmnpqrstuvwxyz23456789'), name = clip(b.name, 80);
        const r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/init?id=${id}`, { method: 'POST', body: this.initBody(name, c) }));
        const j = await r.json(); if (!r.ok) return json(j, r.status);
        this.sql.exec('INSERT INTO events (id, club, key, name, created) VALUES (?, ?, ?, ?, ?)', id, cid, j.key, name || 'New tournament', now);
        made = j;
      }
      // hidden = deleted: wiped HIDDEN_DAYS later by the daily tidy, unless it's shown again first
      if (b.op === 'hide' || b.op === 'unhide') this.sql.exec('UPDATE events SET hidden = ?, hiddenAt = ? WHERE id = ?', b.op === 'hide' ? 1 : 0, b.op === 'hide' ? now : null, clip(b.id, 8));
      // the daily tidy now (Flagcast staff, or the tests on this computer: { now } pretends it's later)
      if (b.op === 'tidy') return json(await this.tidy(local && Number(b.now) ? Number(b.now) : now));
      // someone asked Flagcast to delete their information: { q: their name or email } finds them in every tournament,
      // { apply: true } removes their name, email and GHIN number (scores stay, unnamed)
      if (b.op === 'forget') {
        const q = clip(b.q, 254); if (q.trim().length < 3) this.fail('Type their full name or email address.');
        const rows = this.all('SELECT e.id, e.club, c.name AS clubName FROM events e LEFT JOIN clubs c ON c.id = e.club ORDER BY e.created DESC LIMIT 2000');
        const hits = [];
        for (const e of rows) {
          try { const j = await this.golf(e.id, 'forget', { q, apply: !!b.apply }); if (j.found?.length) hits.push({ id: e.id, name: j.name, date: j.date, club: e.clubName || '', players: j.found }); } catch {}
        }
        if (b.apply && hits.length) this.note('Flagcast', '', `Admin: removed a person’s details from ${hits.length === 1 ? '1 tournament' : `${hits.length} tournaments`}`);
        return json({ ok: true, applied: !!b.apply, tournaments: hits });
      }
      if (b.op === 'edit') {
        need();
        const name = clip(b.name, 80) || c.name;
        this.sql.exec('UPDATE clubs SET name = ?, contact = ?, phone = ?, city = ?, notes = ? WHERE id = ?', name, clip(b.contact, 80), clip(b.phone, 40), clip(b.city, 80), clip(b.notes, 2000), cid);
      }
      if (b.op === 'pay') {
        need();
        const credits = Math.trunc(num(b.credits, -1, 999, 0)), amount = num(b.amount, 0, 1e7, 0);
        this.sql.exec('INSERT INTO payments (id, club, amount, credits, what, note, at) VALUES (?, ?, ?, ?, ?, ?, ?)', rand(8, 'abcdefghijkmnpqrstuvwxyz23456789'), cid, amount, credits, clip(b.what, 80), clip(b.note, 300), b.at ? num(b.at, 0, 4e12, now) : now);
        if (credits < 0) this.sql.exec('UPDATE clubs SET credits = -1 WHERE id = ?', cid);
        else if (credits > 0 && c.credits >= 0) this.sql.exec('UPDATE clubs SET credits = MIN(999, credits + ?) WHERE id = ?', credits, cid);
        if (c.status === 'pending') this.sql.exec('UPDATE clubs SET status = ? WHERE id = ?', 'active', cid);
      }
      if (b.op === 'unpay') this.sql.exec('DELETE FROM payments WHERE id = ?', clip(b.id, 8));
      if (b.op === 'role') {
        need();
        const email = clip(b.email, 254).toLowerCase();
        if (!this.one('SELECT email FROM members WHERE email = ? AND club = ?', email, cid)) this.fail('That person isn’t in this club.');
        if (b.role === 'owner') this.sql.exec('UPDATE members SET role = ? WHERE club = ? AND role = ?', 'staff', cid, 'owner');
        this.sql.exec('UPDATE members SET role = ? WHERE email = ?', b.role === 'owner' ? 'owner' : 'staff', email);
      }
      if (b.op === 'signout') this.sql.exec('DELETE FROM sessions WHERE email = ?', clip(b.email, 254).toLowerCase());
      // Staff: who else gets Admin when they sign in (ADMIN_EMAIL ones stay; they're set in Cloudflare)
      if (b.op === 'staff-add' || b.op === 'staff-remove') {
        const email = clip(b.email, 254).toLowerCase();
        let me = ''; try { me = b.token ? this.who(b.token).email : ''; } catch {}
        if (b.op === 'staff-add') {
          if (!EMAIL.test(email)) this.fail('Type a full email address.');
          if (!this.staffEmail(email)) this.sql.exec('INSERT INTO staff (email, added, by) VALUES (?, ?, ?)', email, Date.now(), me || 'passcode');
        } else {
          if (adminEmail(env, email)) this.fail('That email is set in Cloudflare (ADMIN_EMAIL). Take it off there.');
          if (me && email === me) this.fail('You can’t take yourself off. Ask another admin.');
          this.sql.exec('DELETE FROM staff WHERE email = ?', email);
        }
      }
      // a club's branding: logo, colour, and a small "Powered by Flagcast" (off unless Flagcast turns it on)
      if (b.op === 'brand') {
        need(); this.setBrand(cid, b);
        if (b.powered !== undefined) this.sql.exec('UPDATE clubs SET powered = ? WHERE id = ?', b.powered ? 1 : 0, cid);
        await this.pushBrand(cid);
      }
      // one tournament: lock or reopen scoring, archive, move to another club, or add an old one by its desk link
      const evRow = b.id ? this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8)) : null;
      if (['lock', 'archive', 'move', 'demo'].includes(b.op) && !evRow) this.fail('That tournament isn’t on any club’s list.', 404);
      if (b.op === 'lock') await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'lock', locked: !!b.locked });
      // Demo: the tournament shows the Flagcast logo whatever its club has (for showing Flagcast to a club)
      if (b.op === 'demo') await this.golf(evRow.id, 'brand', { demo: !!b.on });
      if (b.op === 'demo') this.sql.exec('UPDATE events SET demo = ? WHERE id = ?', b.on ? 1 : 0, evRow.id);
      if (b.op === 'archive') {
        this.sql.exec('UPDATE events SET archived = ? WHERE id = ?', b.on ? 1 : 0, evRow.id);
        if (b.on) await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'lock', locked: true }).catch(() => {});
        if (b.on) await this.golf(evRow.id, 'tidy', { spots: true }).catch(() => {}); // the map's group spots go now
      }
      if (b.op === 'move') {
        const to = this.one('SELECT * FROM clubs WHERE id = ?', clip(b.to, 10)); if (!to) this.fail('Pick a club to move it to.');
        this.sql.exec('UPDATE events SET club = ? WHERE id = ?', to.id, evRow.id);
        const ev = await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'get' });
        delete ev.stats; await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'save', setup: { ...ev, club: to.name } }).catch(() => {});
        await this.golf(evRow.id, 'brand', { club: this.brandOf(to) }).catch(() => {});
      }
      if (b.op === 'claim') {
        need();
        const m = String(b.link || '').match(/\/g\/([a-z0-9]{8})\/desk#([a-z0-9]{16,40})/i);
        if (!m) this.fail('Paste the full desk link. It looks like …/g/abcd2345/desk#longkey');
        const id = m[1].toLowerCase(), key = m[2];
        const ev = await this.golf(id, 'desk', { key, op: 'get' });
        const had = this.one('SELECT club FROM events WHERE id = ?', id);
        if (had && had.club !== cid) this.fail('That tournament belongs to another club. Use Move instead.');
        this.sql.exec('INSERT OR REPLACE INTO events (id, club, key, name, created, hidden, archived) VALUES (?, ?, ?, ?, ?, 0, 0)', id, cid, key, clip(ev.name, 80) || 'Tournament', ev.created || now);
        await this.golf(id, 'brand', { club: this.brandOf(c) }).catch(() => {});
      }
      if (b.op && !['events', 'log', 'day', 'cams', 'stream', 'streams', 'unstream', 'streamlist'].includes(b.op)) this.note('Flagcast', cid || evRow?.club || '', `Admin: ${b.op}${b.email ? ` ${clip(b.email, 254)}` : ''}${evRow ? ` ${evRow.name}` : ''}${b.op === 'pay' ? ` $${num(b.amount, 0, 1e7, 0)}` : ''}`);
      // screen control for any club's tournament: the same day ops as the desk
      if (b.op === 'day') {
        const row = this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8)); if (!row) this.fail('That tournament isn’t on any club’s list.', 404);
        const d = b.day || {};
        if (!['screen', 'take', 'flash', 'scene'].includes(d.op)) this.fail('Not allowed');
        await this.golf(row.id, 'desk', { ...d, key: row.key });
        this.note('Flagcast', row.club, `Admin screens: ${d.op}${d.kind ? ` ${d.kind}` : ''}${d.page ? ` ${d.page.k}${d.page.hole ? ` ${d.page.hole}` : ''}` : d.op === 'screen' ? ' playlist' : ''}${d.display ? ` → ${Array.isArray(d.display) ? d.display.join(', ') : d.display}` : ''} · ${row.name}`);
        return json({ ok: true });
      }
      // the par 3 camera links for any club's tournament (club desks can't change them)
      if (b.op === 'cams') {
        const tid = String(b.id || '').toLowerCase(); if (!/^[a-z0-9]{8}$/.test(tid)) this.fail('Pick a tournament.');
        const row = this.one('SELECT * FROM events WHERE id = ?', tid); // Flagcast can also set up a tournament no club owns yet
        const j = await this.golf(tid, 'cams', { cams: b.cams || {}, ...(b.live ? { live: b.live } : {}) });
        this.note('Flagcast', row?.club || '', `Admin cameras: ${Object.keys(j.cams || {}).length ? Object.keys(j.cams).map((h) => (h === "0" ? "clubhouse" : `hole ${h}`)).join(', ') : 'none'} · ${row?.name || tid.toUpperCase()}`);
        return json({ ok: true, cams: j.cams });
      }
      // NDI cameras sent to Cloudflare Stream by the Mac: the hole's live input (made once, reused) for the Mac to push
      // to, and the hole's camera link set to its playback address so phones, the live page and replays use it
      if (b.op === 'stream') {
        if (!streamReady(env)) this.fail('Cloudflare Stream isn’t set up yet: add CF_ACCOUNT_ID and CF_STREAM_TOKEN to the flagcast worker.', 409);
        const tid = String(b.id || '').toLowerCase(), hole = num(b.hole, 0, 18, -1); // 0: the clubhouse
        if (!/^[a-z0-9]{8}$/.test(tid) || hole < 0) this.fail('Pick a tournament and a hole.');
        const st = await this.golf(tid, 'state');
        const old = this.one('SELECT uid FROM streams WHERE event = ? AND hole = ?', tid, hole);
        const input = await liveInput(env, fetch, { uid: old?.uid, name: `${clip(st.name, 80)} · ${hole ? `hole ${hole}` : 'clubhouse'}` }).catch((e) => this.fail(e.message, 502));
        this.sql.exec('INSERT OR REPLACE INTO streams (event, hole, uid, updated) VALUES (?, ?, ?, ?)', tid, hole, input.uid, now);
        if ((st.cams || {})[hole] !== input.playback) await this.golf(tid, 'cams', { cams: { ...(st.cams || {}), [hole]: input.playback } });
        if (!old) this.note('Flagcast', this.one('SELECT club FROM events WHERE id = ?', tid)?.club || '', `Admin cameras: ${hole ? `hole ${hole}` : 'clubhouse'} streams from NDI · ${clip(st.name, 80)}`);
        return json({ ok: true, hole, uid: input.uid, rtmps: input.rtmps, playback: input.playback });
      }
      // stop using Stream for a hole: delete its live input and recordings, and take the camera link off
      if (b.op === 'unstream') {
        if (!streamReady(env)) this.fail('Cloudflare Stream isn’t set up.', 409);
        const tid = String(b.id || '').toLowerCase(), hole = num(b.hole, 0, 18, -1);
        const row = this.one('SELECT uid FROM streams WHERE event = ? AND hole = ?', tid, hole); if (!row) this.fail('That hole isn’t streaming.', 404);
        const removed = await deleteInput(env, fetch, row.uid).catch((e) => this.fail(e.message, 502));
        this.sql.exec('DELETE FROM streams WHERE event = ? AND hole = ?', tid, hole);
        const st = await this.golf(tid, 'state'); const cams = { ...(st.cams || {}) }; delete cams[hole];
        await this.golf(tid, 'cams', { cams });
        return json({ ok: true, recordings: removed });
      }
      // everything on the Stream account, each live input marked with the tournament hole using it (to find leftovers)
      if (b.op === 'streamlist') {
        if (!streamReady(env)) this.fail('Cloudflare Stream isn’t set up.', 409);
        const all = await listAll(env, fetch).catch((e) => this.fail(e.message, 502));
        const used = Object.fromEntries(this.all('SELECT uid, event, hole FROM streams').map((r) => [r.uid, { event: r.event, hole: r.hole }]));
        return json({ inputs: all.inputs.map((i) => ({ ...i, use: used[i.uid] || null })), videos: all.videos });
      }
      // delete a leftover: a live input no tournament uses (with its recordings), or one recording
      if (b.op === 'streamdelete') {
        if (!streamReady(env)) this.fail('Cloudflare Stream isn’t set up.', 409);
        const input = /^[0-9a-f]{32}$/.test(b.input || '') ? b.input : '', video = /^[0-9a-f]{32}$/.test(b.video || '') ? b.video : '';
        if (!input && !video) this.fail('Pick a live input or a recording.');
        if (input && this.one('SELECT hole FROM streams WHERE uid = ?', input)) this.fail('A tournament hole uses that camera. Remove it from the hole instead.', 409);
        if (input) return json({ ok: true, recordings: await deleteInput(env, fetch, input).catch((e) => this.fail(e.message, e.status === 501 ? 409 : 502)) });
        await deleteVideo(env, fetch, video).catch((e) => this.fail(e.message, e.status === 501 ? 409 : 502));
        return json({ ok: true });
      }
      // is each streamed hole's camera sending? → { holes: { 7: 'connected' } }
      if (b.op === 'streams') {
        const tid = String(b.id || '').toLowerCase();
        if (!streamReady(env)) return json({ ready: false, holes: {} });
        const rows = this.all('SELECT hole, uid FROM streams WHERE event = ?', tid);
        const holes = Object.fromEntries(await Promise.all(rows.map(async (r) => [r.hole, await inputState(env, fetch, r.uid)])));
        return json({ ready: true, holes });
      }
      if (b.op === 'log') return json({ log: this.all('SELECT * FROM log ORDER BY n DESC LIMIT 400') });
      if (b.op === 'events') {
        // every tournament on every club's list, with how it's going
        const rows = this.all('SELECT e.id, e.key, e.name, e.created, e.hidden, e.archived, e.club, c.name AS clubName FROM events e LEFT JOIN clubs c ON c.id = e.club ORDER BY e.created DESC LIMIT 300');
        const out = await Promise.all(rows.map(async (e) => {
          try {
            const s = await this.golf(e.id, 'state');
            const scored = Object.values(s.scores || {}).reduce((n, pl) => n + Object.values(pl).reduce((m, arr) => m + arr.filter((v) => v != null).length, 0), 0);
            const online = Object.values(s.online || {}).reduce((n, v) => n + v, 0);
            const lasts = Object.values(s.lastAt || {}), soon = Date.now() - 20 * 60000;
            return { ...e, name: s.name || e.name, date: tvDate(s), rounds: (s.rounds || []).length, round: s.round || 0, demo: !!s.brand?.marked, brand: s.brand || null, photo: coursePhoto(s),
              lastScore: lasts.length ? Math.max(...lasts) : 0, scoringNow: lasts.filter((a) => a > soon).length, teams: (s.teams || []).length, scored, screens: (s.displays || []).length, online, locked: !!s.locked, replays: (s.replays || []).length,
              // for screen control
              displays: (s.displays || []).map((d) => ({ id: d.id, name: d.name, where: d.where || '', group: d.group || '', online: (s.online || {})[d.id] || 0, force: s.live?.force?.[d.id] || null,
                pages: (d.playlist || []).length, list: (d.playlist || []).map((x) => ({ k: x.k, fl: x.fl, hole: x.hole, sponsor: x.sponsor, secs: x.secs })) })),
              p3: (s.course?.holes || []).filter((h) => h.par === 3).map((h) => h.n), cams: s.cams || {},
              // where Admin offers a camera link: the clubhouse (0), par 3s, contest holes, the 18th green, and any hole that has one
              camHoles: [...new Set([0, ...(s.course?.holes || []).filter((h) => h.par === 3).map((h) => h.n), ...(s.contests || []).map((c) => c.hole), ...((s.course?.holes || []).length >= 18 ? [18] : []), ...Object.keys(s.cams || {}).map(Number)])].filter((n) => Number.isInteger(n) && n >= 0 && n <= 18).sort((x, y) => x - y),
              contestHoles: Object.fromEntries((s.contests || []).map((c) => [c.hole, c.label || (c.kind === 'ld' ? 'Long drive' : 'Closest to the pin')])), sponsors: (s.sponsors || []).map((x) => ({ id: x.id, name: x.name })),
              replayList: (s.replays || []).slice(0, 12).map((r) => ({ id: r.id, hole: r.hole, label: r.label, at: r.at })), take: s.live?.take || null, flash: s.flash || null,
              phone: s.live?.phone || null, scenes: (s.scenes || []).map((x) => ({ id: x.id, name: x.name })), scene: s.live?.scene || '', flights: s.flights || [], fund: !!s.fund?.on, skins: !!s.screens?.skins };
          } catch { return { ...e, gone: true }; }
        }));
        return json({ events: out });
      }
      const seen = Object.fromEntries(this.all('SELECT email, MAX(seen) AS seen FROM sessions GROUP BY email').map((s) => [s.email, s.seen]));
      const deleted = this.all("SELECT id, name, city, deleted FROM clubs WHERE status = 'deleted' ORDER BY deleted DESC").map((x) => ({ ...x, wipes: x.deleted + PURGE_DAYS * DAY,
        events: this.one('SELECT COUNT(*) AS n FROM events WHERE club = ?', x.id).n }));
      const gone = Object.fromEntries(this.all("SELECT id, name FROM clubs WHERE status IN ('deleted', 'purged')").map((x) => [x.id, x.name]));
      const clubs = this.all('SELECT * FROM clubs WHERE status NOT IN (\'deleted\', \'purged\') ORDER BY (status = \'pending\') DESC, name COLLATE NOCASE').map(({ logo, was, card, course, ...x }) => ({
        ...x, powered: !!x.powered, courseName: this.cardOf({ card })?.name || '', mapped: Object.keys(this.courseOf({ course })?.holes || {}).length, logo: this.logoURL({ id: x.id, logo }), members: this.all('SELECT email, role, added FROM members WHERE club = ? ORDER BY role DESC, added', x.id).map((m) => ({ ...m, seen: seen[m.email] || 0 })),
        events: this.all('SELECT id, key, name, created, hidden, archived, demo FROM events WHERE club = ? ORDER BY created DESC', x.id),
        payments: this.all('SELECT * FROM payments WHERE club = ? ORDER BY at DESC', x.id),
      }));
      // payments of deleted clubs still count in the totals
      const oldPays = this.all(`SELECT * FROM payments WHERE club IN (${Object.keys(gone).map(() => '?').join(',') || "''"}) ORDER BY at DESC`, ...Object.keys(gone)).map((p) => ({ ...p, clubName: `${gone[p.club]} (deleted)` }));
      return json({ clubs, deleted, oldPays, made, mail: !!env.RESEND_API_KEY, staff: this.staffList() });
    }
    this.fail('Not found', 404);
  }

  mail(to, m) { sendMail(this.env, to, m).catch(() => {}); }

  // ---- the club's TVs (tv.js): the Flagcast TV app on Apple TV, Google TV, Fire TV and Roku, or any TV browser ----
  // A new TV asks for a 6-letter code (hello) and shows it; someone at the club types it in the Manager (add, with a
  // tournament's desk key or a club sign-in); the TV, which keeps asking (wait), gets its own token. From then on the TV
  // asks what to show (now): the tournament that's on today (it joins that tournament's screens), else the club's idle
  // screen with the next tournament. Removing the TV in the Manager takes its token away and it shows a new code.
  tvClub(b) {
    if (b.token) { const u = this.who(b.token); if (!u.club) this.fail('Your email isn’t in a club yet.', 403); return u.club; }
    const ev = this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8));
    if (!ev || !b.key || !same(b.key, ev.key)) this.fail('This desk link is not right.', 403);
    const c = this.one('SELECT * FROM clubs WHERE id = ?', ev.club); if (!c) this.fail('This tournament has no club.', 404);
    return c;
  }
  tvRow(t) { return { id: t.id, name: t.name, where: t.place || '', kind: t.kind || '', event: t.event || '', eventName: t.event ? this.one('SELECT name FROM events WHERE id = ?', t.event)?.name || '' : '', added: t.added, seen: t.seen || 0, on: Date.now() - (t.seen || 0) < 3 * 60000 }; }
  async tvRoute(op, b, now) {
    const ABC = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', KINDS = ['appletv', 'androidtv', 'firetv', 'roku', 'web'];
    if (op === 'hello') { // a TV that isn't connected: a new code (10 minutes), 30 an hour from one network
      const k = [[`tvh:${this.ip}`, 30]];
      try { this.tooMany(k); } catch { this.fail('Too many new codes from this network. Wait 15 minutes.', 429); }
      this.failed(k);
      this.sql.exec('DELETE FROM tvcodes WHERE exp < ?', now);
      let code; do code = rand(6, ABC); while (this.one('SELECT code FROM tvcodes WHERE code = ?', code));
      const pair = rand(32, 'abcdefghijkmnpqrstuvwxyz23456789');
      this.sql.exec('INSERT INTO tvcodes (code, pair, kind, exp, tv, token) VALUES (?, ?, ?, ?, ?, ?)', code, pair, KINDS.includes(b.kind) ? b.kind : 'web', now + 10 * 60000, '', '');
      return json({ code, pair, exp: now + 10 * 60000 });
    }
    if (op === 'wait') { // the TV checks every few seconds; the token is handed over once
      const c = this.one('SELECT * FROM tvcodes WHERE code = ?', clip(b.code, 6).toUpperCase());
      if (!c || !same(b.pair, c.pair) || c.exp < now) return json({ error: 'That code ran out.', expired: true }, 410);
      if (!c.token) return json({ waiting: true, exp: c.exp });
      this.sql.exec('DELETE FROM tvcodes WHERE code = ?', c.code);
      return json({ tv: c.tv, token: c.token });
    }
    if (op === 'add') {
      const club = this.tvClub(b), code = clip(b.code, 8).toUpperCase().replace(/[^A-Z0-9]/g, '');
      const k = [[`tva:${club.id}`, 10]];
      try { this.tooMany(k); } catch { this.fail('Too many wrong TV codes. Wait 15 minutes.', 429); }
      const c = this.one('SELECT * FROM tvcodes WHERE code = ?', code);
      if (!c || c.exp < now || c.token) { this.failed(k); this.fail('That code isn’t on a TV right now. Check the code on the TV, or restart the Flagcast app on it for a new one.', 404); }
      if (this.one('SELECT COUNT(*) AS n FROM tvs WHERE club = ?', club.id).n >= 40) this.fail('Your club already has 40 TVs. Remove one first.', 409);
      const id = rand(8, 'abcdefghijkmnpqrstuvwxyz23456789'), token = rand(40, 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
      const name = clip(b.name, 40) || `TV ${this.one('SELECT COUNT(*) AS n FROM tvs WHERE club = ?', club.id).n + 1}`;
      this.sql.exec('INSERT INTO tvs (id, club, name, place, kind, token, event, joined, added, seen) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', id, club.id, name, clip(b.where, 40), c.kind, token, '', '', now, 0);
      this.sql.exec('UPDATE tvcodes SET tv = ?, token = ? WHERE code = ?', id, token, code);
      this.note(b.token ? this.who(b.token).email : 'Manager', club.id, `Added a TV: ${name}`);
      let added = 0;
      if (!b.token) try { added = (await this.golf(clip(b.id, 8), 'tvjoin', { tv: { id, name, where: clip(b.where, 40) } })).added || 0; } catch {}
      return json({ ok: true, added, tv: this.tvRow(this.one('SELECT * FROM tvs WHERE id = ?', id)), tvs: this.all('SELECT * FROM tvs WHERE club = ? ORDER BY added', club.id).map((t) => this.tvRow(t)) });
    }
    if (op === 'list' || op === 'edit' || op === 'remove') {
      const club = this.tvClub(b), t = b.tv ? this.one('SELECT * FROM tvs WHERE id = ? AND club = ?', clip(b.tv, 12), club.id) : null;
      if (op !== 'list' && !t) this.fail('That TV isn’t in your club.', 404);
      // the tournaments a TV may be one of the screens of: the club's latest ones, the one it joined, the one asking
      const where = async () => [...new Set([...(await this.tvEvents(club.id, now)).map((e) => e.id), t?.joined, b.token ? '' : clip(b.id, 8)].filter(Boolean))];
      if (op === 'edit') {
        const ev = b.event === undefined ? t.event : (b.event && this.one('SELECT id FROM events WHERE id = ? AND club = ?', clip(b.event, 8), club.id) ? clip(b.event, 8) : '');
        const name = clip(b.name ?? t.name, 40) || t.name, place = clip(b.where ?? t.place, 40);
        this.sql.exec('UPDATE tvs SET name = ?, place = ?, event = ? WHERE id = ?', name, place, ev, t.id);
        if (name !== t.name || place !== (t.place || '')) await Promise.all((await where()).map((id) => this.golf(id, 'tvjoin', { only: true, tv: { id: t.id, name, where: place } }).catch(() => {})));
      }
      if (op === 'remove') {
        this.sql.exec('DELETE FROM tvs WHERE id = ?', t.id);
        await Promise.all((await where()).map((id) => this.golf(id, 'tvleave', { tv: t.id }).catch(() => {})));
        this.note('Manager', club.id, `Removed a TV: ${t.name}`);
      }
      const tvs = this.all('SELECT * FROM tvs WHERE club = ? ORDER BY added', club.id);
      // a Manager with this tournament open: every club TV is one of its screens, so it gets a card with its own list
      let added = 0;
      if (op !== 'remove' && !b.token && tvs.length) {
        try { added = (await this.golf(clip(b.id, 8), 'tvjoin', { tvs: tvs.map((x) => ({ id: x.id, name: x.name, where: x.place || '' })) })).added || 0; } catch {}
      }
      return json({ tvs: tvs.map((x) => this.tvRow(x)), added });
    }
    if (op === 'now') { // a connected TV: what it shows now
      const t = b.token && this.one('SELECT * FROM tvs WHERE token = ?', clip(b.token, 60));
      if (!t || !same(b.token, t.token)) return json({ error: 'This TV isn’t connected to a club.', unpaired: true }, 401);
      const club = this.one('SELECT * FROM clubs WHERE id = ?', t.club);
      if (!club) return json({ error: 'This TV isn’t connected to a club.', unpaired: true }, 401);
      if (now - (t.seen || 0) > 60000) this.sql.exec('UPDATE tvs SET seen = ? WHERE id = ?', now, t.id);
      const today = /^\d{4}-\d{2}-\d{2}$/.test(b.today || '') ? b.today : new Date(now).toISOString().slice(0, 10);
      const list = await this.tvEvents(club.id, now);
      // a tournament the club picked for this TV; else today's (or one scored in the last three hours); else none
      const pinned = t.event && list.find((e) => e.id === t.event);
      const live = pinned || list.filter((e) => e.date === today || e.last > now - 3 * 3600000).sort((a, b2) => (b2.date === today) - (a.date === today) || b2.created - a.created)[0] || null;
      const next = live ? null : list.filter((e) => e.date > today).sort((a, b2) => a.date.localeCompare(b2.date))[0] || null;
      if (live && t.joined !== live.id) {
        try { await this.golf(live.id, 'tvjoin', { tv: { id: t.id, name: t.name, where: t.place || '' } }); this.sql.exec('UPDATE tvs SET joined = ? WHERE id = ?', live.id, t.id); }
        catch { /* the tournament is full of screens: the TV still plays the board, with the usual pages */ }
      }
      const logo = this.logoURL(club);
      return json({ tv: { id: t.id, name: t.name, where: t.place || '' },
        club: { name: club.name, city: club.city || '', logo, accent: club.accent || '', flagcast: !logo },
        event: live ? { id: live.id, name: live.name, date: live.date } : null,
        next: next ? { id: next.id, name: next.name, date: next.date } : null, check: live ? 30 : 60 });
    }
    this.fail('Not found', 404);
  }
  // the club's latest tournaments with their dates, kept for a minute (every TV at the club asks every minute)
  async tvEvents(cid, now) {
    this.tvCache = this.tvCache || new Map();
    const hit = this.tvCache.get(cid); if (hit && now - hit.at < 60000) return hit.list;
    const rows = this.all('SELECT id, name, created FROM events WHERE club = ? AND hidden = 0 AND archived = 0 ORDER BY created DESC LIMIT 8', cid);
    const list = (await Promise.all(rows.map(async (e) => {
      try { const i = await this.golf(e.id, 'tvinfo', {}); return { id: e.id, name: i.name || e.name, date: i.date || '', locked: !!i.locked, last: i.last || 0, created: e.created || 0 }; } catch { return null; }
    }))).filter(Boolean);
    if (this.tvCache.size > 200) this.tvCache.clear();
    this.tvCache.set(cid, { at: now, list }); return list;
  }
  // the daily tidy (privacy.js): every tournament tidies itself (spots, emails, old replays); ones a club deleted
  // HIDDEN_DAYS ago, or past KEEP_DAYS_ALL, are wiped; and camera recordings past their days go. → what it did
  async tidy(now = Date.now()) {
    const out = { tournaments: 0, personal: 0, erased: 0, recordings: 0 };
    // tournaments hidden before deletes were timed get their HIDDEN_DAYS from now
    this.sql.exec('UPDATE events SET hiddenAt = ? WHERE hidden = 1 AND hiddenAt IS NULL', now);
    this.sql.exec('DELETE FROM fails WHERE since < ?', now - DAY); // rate-limit counts (some keyed by internet address): a day at most
    for (const e of this.all('SELECT id, hidden, hiddenAt, demo FROM events ORDER BY created LIMIT 2000')) {
      let j = null;
      try { j = await this.golf(e.id, 'tidy', { now }); out.tournaments++; if (j.personal) out.personal++; } catch { continue; }
      if ((e.hidden && e.hiddenAt && now - e.hiddenAt > HIDDEN_DAYS * DAY) || (j.expired && !e.demo)) { if (await this.erase(e.id)) out.erased++; }
    }
    if (streamReady(this.env)) out.recordings = await oldRecordings(this.env, fetch, now).catch(() => 0);
    return out;
  }
  // wipe one tournament for good: its cameras (and their recordings), everything it kept, and its row. → done?
  async erase(id) {
    const row = this.one('SELECT e.id, e.name, e.club FROM events e WHERE e.id = ?', id); if (!row) return false;
    for (const s of this.all('SELECT uid FROM streams WHERE event = ?', id)) {
      if (streamReady(this.env)) { try { await deleteInput(this.env, fetch, s.uid); } catch { return false; } }
      this.sql.exec('DELETE FROM streams WHERE uid = ?', s.uid);
    }
    try { await this.golf(id, 'wipe', {}); } catch { return false; }
    this.sql.exec('DELETE FROM events WHERE id = ?', id);
    this.note('Flagcast', row.club || '', `Wiped tournament ${row.name} (${id.toUpperCase()}) for good`);
    return true;
  }
  // wipe a deleted club's tournaments for good. One that doesn't answer stays (and so does the club) for the next try.
  // The club row stays as 'purged' (name only) so its payments still show whose they were. → how many are left
  async purge(c) {
    let left = 0;
    for (const e of this.all('SELECT id FROM events WHERE club = ?', c.id)) {
      try { await this.golf(e.id, 'wipe', {}); this.sql.exec('DELETE FROM events WHERE id = ?', e.id); } catch { left++; }
    }
    if (!left) {
      this.sql.exec("UPDATE clubs SET status = 'purged', was = NULL, logo = NULL, course = NULL, card = NULL, contact = '', phone = '', notes = '' WHERE id = ?", c.id);
      this.note('Flagcast', c.id, `Wiped deleted club ${c.name} and its tournaments`);
    }
    return left;
  }
  // 30 days after a delete: wipe the clubs that are due, and wake again for the next one
  async alarm() {
    const now = Date.now();
    let retry = false;
    for (const c of this.all("SELECT * FROM clubs WHERE status = 'deleted' AND deleted < ?", now - PURGE_DAYS * DAY)) if (await this.purge(c)) retry = true;
    const next = this.one("SELECT MIN(deleted) AS d FROM clubs WHERE status = 'deleted'")?.d;
    if (retry) await this.ctx.storage.setAlarm(now + 3600000);
    else if (next) await this.ctx.storage.setAlarm(Math.max(now + 60000, next + PURGE_DAYS * DAY));
  }

  me(u) {
    const acct = this.one('SELECT hash, apple, google FROM accounts WHERE email = ?', u.email);
    const out = { email: u.email, role: u.role, admin: this.staffEmail(u.email), password: !!acct?.hash, apple: !!acct?.apple, google: !!acct?.google, club: null, members: [], events: [] };
    if (!u.club) return out;
    const { id, name, status, city, credits } = u.club;
    out.club = { id, name, status, city, credits, logo: this.logoURL(u.club), accent: u.club.accent || '' };
    out.members = this.all('SELECT email, role FROM members WHERE club = ? ORDER BY role DESC, added', id);
    out.events = this.all('SELECT id, key, name, created FROM events WHERE club = ? AND hidden = 0 AND archived = 0 ORDER BY created DESC', id);
    return out;
  }
}
