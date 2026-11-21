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
//                                 event (make a tournament for a club, no credit used), hide
// Credits: a club makes tournaments while it has credits (each new one uses one); -1 means unlimited (a season deal).
//   POST /golf/api/new            { token, name }  (a signed-in, approved club)  or  { pass, name, club? }  (Flagcast)
//
// Email goes out through Resend: RESEND_API_KEY secret and MAIL_FROM (e.g. "Flagcast <signin@flagcast.app>").
// ADMIN_EMAIL (optional) gets a note when a club asks to join, and signing in with that address (or any in a comma list) unlocks Admin. On localhost with no RESEND_API_KEY the code
// comes back in the answer (devCode) so the pages can be tried without email.
import { DurableObject } from 'cloudflare:workers';
import { SEED, slug } from './courselib.js';
import { hashPassword, checkPassword, passwordProblem, verifyAppleToken, appleKeys, verifyGoogleToken, googleKeys } from './auth.js';

const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
const EMAIL = /^[^\s@<>"',;]{1,64}@[^\s@<>"',;]{1,190}\.[a-z]{2,24}$/i;
const clip = (s, n) => String(s ?? '').trim().slice(0, n);
const rand = (n, abc) => { const b = crypto.getRandomValues(new Uint8Array(n)); return [...b].map((x) => abc[x % abc.length]).join(''); };
const sixDigits = () => String(crypto.getRandomValues(new Uint32Array(1))[0] % 1000000).padStart(6, '0');
const SESSION_DAYS = 90;
const num = (v, lo, hi, d) => { const n = Number(v); return Number.isFinite(n) ? Math.min(hi, Math.max(lo, n)) : d; };
const DAY = 86400000;

// safe string compare for passcodes
function same(a, b) {
  const x = new TextEncoder().encode(String(a ?? '')), y = new TextEncoder().encode(String(b ?? ''));
  let d = x.length ^ y.length; for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] || 0) ^ (y[i] || 0);
  return d === 0;
}
export const isAdmin = (env, pass) => !!env.GOLF_CREATE_PASS && same(pass, env.GOLF_CREATE_PASS);
// Flagcast staff: the emails in ADMIN_EMAIL (comma-separated, set in the Cloudflare dashboard) get Admin when signed in
export const adminEmail = (env, email) => !!email && String(env.ADMIN_EMAIL || '').toLowerCase().split(/[\s,]+/).filter(Boolean).includes(String(email).toLowerCase());

async function sendMail(env, to, subject, text) {
  if (!env.RESEND_API_KEY) throw new Error('nomail');
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST', headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env.MAIL_FROM || 'Flagcast <signin@flagcast.app>', to: [to], subject, text }),
  });
  if (!r.ok) throw new Error(`mail ${r.status}`);
}

// the worker hands every /golf/api/club/* call (and /golf/api/new) to the one directory object
export async function clubs(request, env, op) {
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  const local = /^(localhost|127\.0\.0\.1)$/.test(new URL(request.url).hostname);
  const stub = env.CLUBS.get(env.CLUBS.idFromName('directory'));
  const ip = request.headers.get('CF-Connecting-IP') || '';
  return stub.fetch(new Request(`https://clubs/${op}?local=${local ? 1 : 0}&ip=${encodeURIComponent(ip)}`, { method: 'POST', body: await request.text() }));
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
      CREATE TABLE IF NOT EXISTS fails (k TEXT PRIMARY KEY, n INTEGER, since INTEGER);`);
    // columns added after the first release
    for (const q of ['ALTER TABLE accounts ADD COLUMN google TEXT', 'ALTER TABLE clubs ADD COLUMN notes TEXT', 'ALTER TABLE events ADD COLUMN archived INTEGER DEFAULT 0', 'ALTER TABLE clubs ADD COLUMN course TEXT']) { try { this.sql.exec(q); } catch {} }
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
  // Admin: the passcode, or a sign-in whose email is in ADMIN_EMAIL
  isStaff(b) {
    if (isAdmin(this.env, b.pass)) return true;
    if (!b.token) return false;
    try { return adminEmail(this.env, this.who(b.token).email); } catch { return false; }
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

  async route(op, b, local) {
    const env = this.env, now = Date.now();
    // the course library (only reached from courses.js, never straight from the web)
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
    if (op === 'course') { // only from a tournament (GolfEvent) after its map was saved: the club keeps the latest one
      const e = this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8));
      if (!e || !b.key || !same(b.key, e.key)) this.fail('Not found', 404);
      const s = JSON.stringify(b.map || {}); if (s.length > 200000) this.fail('Too big');
      this.sql.exec('UPDATE clubs SET course = ? WHERE id = ?', s, e.club);
      return json({ ok: true });
    }
    if (op === 'start') {
      const email = clip(b.email, 254).toLowerCase();
      if (!EMAIL.test(email)) this.fail('Type a full email address.');
      const c = this.one('SELECT * FROM codes WHERE email = ?', email);
      if (c && now - c.sent < 30000) this.fail('A code was just sent. Wait half a minute before asking for another.', 429);
      const hour = Math.floor(now / 3600000), hourCount = c && c.hour === hour ? c.hourCount + 1 : 1;
      if (hourCount > 6) this.fail('Too many codes for that email this hour. Try again later.', 429);
      const code = sixDigits();
      this.sql.exec('INSERT OR REPLACE INTO codes (email, code, exp, tries, sent, hour, hourCount) VALUES (?, ?, ?, 0, ?, ?, ?)', email, code, now + 15 * 60000, now, hour, hourCount);
      try { await sendMail(env, email, `${code} is your Flagcast sign-in code`, `Your Flagcast sign-in code is ${code}\n\nIt works for 15 minutes. If you didn't ask for it, you can ignore this email.\n\nFlagcast · flagcast.app`); }
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
    if (op === 'config') return json({ google: env.GOOGLE_CLIENT_ID || '' });
    if (op === 'apple') {
      let id;
      try { id = await verifyAppleToken(b.identityToken, { keys: await appleKeys() }); }
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
    if (op === 'request') {
      const u = this.who(b.token);
      if (u.club) this.fail('You’re already part of a club.');
      const name = clip(b.name, 80); if (!name) this.fail('Type your club’s name.');
      const id = rand(10, 'abcdefghijkmnpqrstuvwxyz23456789');
      this.sql.exec('INSERT INTO clubs (id, name, contact, phone, city, status, created, by) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', id, name, clip(b.contact, 80), clip(b.phone, 40), clip(b.city, 80), 'pending', now, u.email);
      this.sql.exec('INSERT OR REPLACE INTO members (email, club, role, added) VALUES (?, ?, ?, ?)', u.email, id, 'owner', now);
      this.note(u.email, id, `Asked to join: ${name}`);
      if (env.ADMIN_EMAIL) sendMail(env, env.ADMIN_EMAIL, `New club asking for Flagcast: ${name}`, `${name}\n${clip(b.contact, 80)} · ${u.email} · ${clip(b.phone, 40)}\n${clip(b.city, 80)}\n\nApprove it at https://flagcast.app/golf/admin/`).catch(() => {});
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
        sendMail(env, email, `You’ve been added to ${u.club.name} on Flagcast`, `${u.email} added you to ${u.club.name} on Flagcast.\n\nOpen Flagcast Manager (or https://flagcast.app/golf/) and sign in with this email address to see the club’s tournaments.`).catch(() => {});
      } else this.sql.exec('DELETE FROM members WHERE email = ? AND club = ? AND role != ?', email, u.club.id, 'owner');
      this.note(u.email, u.club.id, `${op === 'invite' ? 'Added' : 'Removed'} ${email}`);
      return json(this.me(u));
    }
    if (op === 'hide') {
      const u = this.who(b.token);
      if (!u.club) this.fail('Not found', 404);
      this.sql.exec('UPDATE events SET hidden = 1 WHERE id = ? AND club = ?', clip(b.id, 8), u.club.id);
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
      const r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/init?id=${id}`, { method: 'POST', body: JSON.stringify({ name, club: club?.name || '', map: this.courseOf(club) }) }));
      const j = await r.json();
      if (!r.ok) return json(j, r.status);
      if (club) {
        this.sql.exec('INSERT INTO events (id, club, key, name, created) VALUES (?, ?, ?, ?, ?)', id, club.id, j.key, name || 'New tournament', now);
        this.note(b.pass ? 'Flagcast' : this.who(b.token).email, club.id, `Made tournament ${name || 'New tournament'} (${id.toUpperCase()})`);
        if (!b.pass && club.credits > 0) this.sql.exec('UPDATE clubs SET credits = credits - 1 WHERE id = ?', club.id);
      }
      return json(j);
    }
    if (op === 'admin') {
      if (!this.isStaff(b) && !(local && !env.GOLF_CREATE_PASS)) this.fail('That passcode is not right.', 403);
      const cid = clip(b.club, 10), c = cid ? this.one('SELECT * FROM clubs WHERE id = ?', cid) : null;
      const need = () => { if (!c) this.fail('That club isn’t there any more.', 404); };
      let made = null;
      if (b.op === 'approve' || b.op === 'on') {
        need(); this.sql.exec('UPDATE clubs SET status = ? WHERE id = ?', 'active', cid);
        if (b.op === 'approve' && c.status === 'pending' && c.by) this.mail(c.by, `${c.name} is ready on Flagcast`, `Good news: ${c.name} is approved on Flagcast.\n\nOpen Flagcast Manager (or https://flagcast.app/golf/), sign in with this email address and make your first tournament.`);
      }
      if (b.op === 'off') { need(); this.sql.exec('UPDATE clubs SET status = ? WHERE id = ?', 'off', cid); }
      if (b.op === 'delete') {
        need();
        // only a club with no tournaments (a mistaken or spam request)
        if (this.one('SELECT id FROM events WHERE club = ?', cid)) this.fail('This club has tournaments. Switch it off instead.');
        this.sql.exec('DELETE FROM clubs WHERE id = ?', cid); this.sql.exec('DELETE FROM members WHERE club = ?', cid);
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
          this.mail(email, `${name} is set up on Flagcast`, `Flagcast has set up ${name} for you.\n\nDownload Flagcast Manager at https://flagcast.app, open it and sign in with this email address (we email you a code, no password). Your tournaments will be there.`);
        }
        made = { club: id };
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
          if (!m) this.mail(email, `You’ve been added to ${c.name} on Flagcast`, `Flagcast added you to ${c.name}.\n\nOpen Flagcast Manager (download at https://flagcast.app) and sign in with this email address to see the club’s tournaments.`);
        } else this.sql.exec('DELETE FROM members WHERE email = ? AND club = ?', email, cid);
      }
      if (b.op === 'event') {
        need();
        const id = rand(8, 'abcdefghijkmnpqrstuvwxyz23456789'), name = clip(b.name, 80);
        const r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/init?id=${id}`, { method: 'POST', body: JSON.stringify({ name, club: c.name, map: this.courseOf(c) }) }));
        const j = await r.json(); if (!r.ok) return json(j, r.status);
        this.sql.exec('INSERT INTO events (id, club, key, name, created) VALUES (?, ?, ?, ?, ?)', id, cid, j.key, name || 'New tournament', now);
        made = j;
      }
      if (b.op === 'hide' || b.op === 'unhide') this.sql.exec('UPDATE events SET hidden = ? WHERE id = ?', b.op === 'hide' ? 1 : 0, clip(b.id, 8));
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
      // one tournament: lock or reopen scoring, archive, move to another club, or add an old one by its desk link
      const evRow = b.id ? this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8)) : null;
      if (['lock', 'archive', 'move'].includes(b.op) && !evRow) this.fail('That tournament isn’t on any club’s list.', 404);
      if (b.op === 'lock') await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'lock', locked: !!b.locked });
      if (b.op === 'archive') {
        this.sql.exec('UPDATE events SET archived = ? WHERE id = ?', b.on ? 1 : 0, evRow.id);
        if (b.on) await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'lock', locked: true }).catch(() => {});
      }
      if (b.op === 'move') {
        const to = this.one('SELECT * FROM clubs WHERE id = ?', clip(b.to, 10)); if (!to) this.fail('Pick a club to move it to.');
        this.sql.exec('UPDATE events SET club = ? WHERE id = ?', to.id, evRow.id);
        const ev = await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'get' });
        delete ev.stats; await this.golf(evRow.id, 'desk', { key: evRow.key, op: 'save', setup: { ...ev, club: to.name } }).catch(() => {});
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
      }
      if (b.op && !['events', 'log', 'day'].includes(b.op)) this.note('Flagcast', cid || evRow?.club || '', `Admin: ${b.op}${b.email ? ` ${clip(b.email, 254)}` : ''}${evRow ? ` ${evRow.name}` : ''}${b.op === 'pay' ? ` $${num(b.amount, 0, 1e7, 0)}` : ''}`);
      // screen control for any club's tournament: the same day ops as the desk
      if (b.op === 'day') {
        const row = this.one('SELECT * FROM events WHERE id = ?', clip(b.id, 8)); if (!row) this.fail('That tournament isn’t on any club’s list.', 404);
        const d = b.day || {};
        if (!['screen', 'take', 'flash', 'scene'].includes(d.op)) this.fail('Not allowed');
        await this.golf(row.id, 'desk', { ...d, key: row.key });
        this.note('Flagcast', row.club, `Admin screens: ${d.op}${d.kind ? ` ${d.kind}` : ''}${d.page ? ` ${d.page.k}${d.page.hole ? ` ${d.page.hole}` : ''}` : d.op === 'screen' ? ' playlist' : ''}${d.display ? ` → ${Array.isArray(d.display) ? d.display.join(', ') : d.display}` : ''} · ${row.name}`);
        return json({ ok: true });
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
            return { ...e, name: s.name || e.name, date: s.date || '', teams: (s.teams || []).length, scored, screens: (s.displays || []).length, online, locked: !!s.locked, replays: (s.replays || []).length,
              // for screen control
              displays: (s.displays || []).map((d) => ({ id: d.id, name: d.name, where: d.where || '', group: d.group || '', online: (s.online || {})[d.id] || 0, force: s.live?.force?.[d.id] || null,
                pages: (d.playlist || []).length, list: (d.playlist || []).map((x) => ({ k: x.k, fl: x.fl, hole: x.hole, sponsor: x.sponsor, secs: x.secs })) })),
              p3: (s.course?.holes || []).filter((h) => h.par === 3).map((h) => h.n), sponsors: (s.sponsors || []).map((x) => ({ id: x.id, name: x.name })),
              replayList: (s.replays || []).slice(0, 12).map((r) => ({ id: r.id, hole: r.hole, label: r.label, at: r.at })), take: s.live?.take || null, flash: s.flash || null,
              phone: s.live?.phone || null, scenes: (s.scenes || []).map((x) => ({ id: x.id, name: x.name })), scene: s.live?.scene || '', flights: s.flights || [], fund: !!s.fund?.on, skins: !!s.screens?.skins };
          } catch { return { ...e, gone: true }; }
        }));
        return json({ events: out });
      }
      const seen = Object.fromEntries(this.all('SELECT email, MAX(seen) AS seen FROM sessions GROUP BY email').map((s) => [s.email, s.seen]));
      const clubs = this.all('SELECT * FROM clubs ORDER BY (status = \'pending\') DESC, name COLLATE NOCASE').map((x) => ({
        ...x, members: this.all('SELECT email, role, added FROM members WHERE club = ? ORDER BY role DESC, added', x.id).map((m) => ({ ...m, seen: seen[m.email] || 0 })),
        events: this.all('SELECT id, key, name, created, hidden, archived FROM events WHERE club = ? ORDER BY created DESC', x.id),
        payments: this.all('SELECT * FROM payments WHERE club = ? ORDER BY at DESC', x.id),
      }));
      return json({ clubs, made, mail: !!env.RESEND_API_KEY });
    }
    this.fail('Not found', 404);
  }

  mail(to, subject, text) { sendMail(this.env, to, subject, text).catch(() => {}); }

  me(u) {
    const acct = this.one('SELECT hash, apple, google FROM accounts WHERE email = ?', u.email);
    const out = { email: u.email, role: u.role, admin: adminEmail(this.env, u.email), password: !!acct?.hash, apple: !!acct?.apple, google: !!acct?.google, club: null, members: [], events: [] };
    if (!u.club) return out;
    const { id, name, status, city, credits } = u.club;
    out.club = { id, name, status, city, credits };
    out.members = this.all('SELECT email, role FROM members WHERE club = ? ORDER BY role DESC, added', id);
    out.events = this.all('SELECT id, key, name, created FROM events WHERE club = ? AND hidden = 0 AND archived = 0 ORDER BY created DESC', id);
    return out;
  }
}
