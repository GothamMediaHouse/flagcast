// Flagcast club accounts. Many clubs share one Flagcast: each club signs in with email (a 6-digit code, no
// password), sees only its own tournaments on any computer, and Flagcast approves or switches off clubs on the
// admin page (/golf/admin/, unlocked with the GOLF_CREATE_PASS secret).
//
// One Durable Object ("directory") holds every club, member, sign-in code, session and the club's tournaments.
//
//   POST /golf/api/club/start     { email }                        sends a sign-in code
//   POST /golf/api/club/verify    { email, code }                  → { token }
//   POST /golf/api/club/me        { token }                        → { email, role, club, members, events }
//   POST /golf/api/club/request   { token, name, contact, phone, city }   asks Flagcast for a club (pending)
//   POST /golf/api/club/invite    { token, email }                 adds someone to your club
//   POST /golf/api/club/uninvite  { token, email }
//   POST /golf/api/club/hide      { token, id }                    takes a tournament off the club's list
//   POST /golf/api/club/signout   { token }
//   POST /golf/api/club/admin     { pass, op, … }   Flagcast Admin: list, approve, on, off, delete, create (a club + its owner),
//                                 credits (tournaments a club may make: a number, or -1 for unlimited), invite, uninvite,
//                                 event (make a tournament for a club, no credit used), hide
// Credits: a club makes tournaments while it has credits (each new one uses one); -1 means unlimited (a season deal).
//   POST /golf/api/new            { token, name }  (a signed-in, approved club)  or  { pass, name, club? }  (Flagcast)
//
// Email goes out through Resend: RESEND_API_KEY secret and MAIL_FROM (e.g. "Flagcast <signin@flagcast.app>").
// ADMIN_EMAIL (optional) gets a note when a club asks to join. On localhost with no RESEND_API_KEY the code
// comes back in the answer (devCode) so the pages can be tried without email.
import { DurableObject } from 'cloudflare:workers';

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
  return stub.fetch(new Request(`https://clubs/${op}?local=${local ? 1 : 0}`, { method: 'POST', body: await request.text() }));
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
      CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, club TEXT, key TEXT, name TEXT, created INTEGER, hidden INTEGER DEFAULT 0);`);
  }
  one(q, ...a) { return this.sql.exec(q, ...a).toArray()[0] || null; }
  all(q, ...a) { return this.sql.exec(q, ...a).toArray(); }

  async fetch(request) {
    const url = new URL(request.url), op = url.pathname.slice(1), local = url.searchParams.get('local') === '1';
    let b = {}; try { b = JSON.parse(await request.text() || '{}'); } catch {}
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

  async route(op, b, local) {
    const env = this.env, now = Date.now();
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
      const token = rand(40, 'abcdefghijkmnpqrstuvwxyz23456789ABCDEFGHJKLMNPQRSTUVWXYZ');
      this.sql.exec('INSERT INTO sessions (token, email, created, seen) VALUES (?, ?, ?, ?)', token, email, now, now);
      this.sql.exec('DELETE FROM sessions WHERE created < ?', now - SESSION_DAYS * DAY);
      return json({ token });
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
        if (!isAdmin(env, b.pass) && !(local && !env.GOLF_CREATE_PASS)) this.fail('That passcode is not right.', 403);
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
      const r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/init?id=${id}`, { method: 'POST', body: JSON.stringify({ name, club: club?.name || '' }) }));
      const j = await r.json();
      if (!r.ok) return json(j, r.status);
      if (club) {
        this.sql.exec('INSERT INTO events (id, club, key, name, created) VALUES (?, ?, ?, ?, ?)', id, club.id, j.key, name || 'New tournament', now);
        if (!b.pass && club.credits > 0) this.sql.exec('UPDATE clubs SET credits = credits - 1 WHERE id = ?', club.id);
      }
      return json(j);
    }
    if (op === 'admin') {
      if (!isAdmin(env, b.pass) && !(local && !env.GOLF_CREATE_PASS)) this.fail('That passcode is not right.', 403);
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
        const r = await env.GOLF.get(env.GOLF.idFromName(id)).fetch(new Request(`https://golf/init?id=${id}`, { method: 'POST', body: JSON.stringify({ name, club: c.name }) }));
        const j = await r.json(); if (!r.ok) return json(j, r.status);
        this.sql.exec('INSERT INTO events (id, club, key, name, created) VALUES (?, ?, ?, ?, ?)', id, cid, j.key, name || 'New tournament', now);
        made = j;
      }
      if (b.op === 'hide' || b.op === 'unhide') this.sql.exec('UPDATE events SET hidden = ? WHERE id = ?', b.op === 'hide' ? 1 : 0, clip(b.id, 8));
      const clubs = this.all('SELECT * FROM clubs ORDER BY (status = \'pending\') DESC, name COLLATE NOCASE').map((x) => ({
        ...x, members: this.all('SELECT email, role FROM members WHERE club = ? ORDER BY role DESC, added', x.id),
        events: this.all('SELECT id, key, name, created, hidden FROM events WHERE club = ? ORDER BY created DESC', x.id),
      }));
      return json({ clubs, made, mail: !!env.RESEND_API_KEY });
    }
    this.fail('Not found', 404);
  }

  mail(to, subject, text) { sendMail(this.env, to, subject, text).catch(() => {}); }

  me(u) {
    const out = { email: u.email, role: u.role, club: null, members: [], events: [] };
    if (!u.club) return out;
    const { id, name, status, city, credits } = u.club;
    out.club = { id, name, status, city, credits };
    out.members = this.all('SELECT email, role FROM members WHERE club = ? ORDER BY role DESC, added', id);
    out.events = this.all('SELECT id, key, name, created FROM events WHERE club = ? AND hidden = 0 ORDER BY created DESC', id);
    return out;
  }
}
