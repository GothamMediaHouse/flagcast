// The website's contact form: POST /api/contact (JSON) emails the note to Flagcast through Resend,
// with Reply-To set to the sender so a reply goes straight back to them.
// Sends to CONTACT_TO (comma list), else hello@flagcast.app. Needs RESEND_API_KEY; From is MAIL_FROM.
// On localhost with no RESEND_API_KEY it answers ok without sending, so the page can be tried.

import { allowed } from './clubs.js';
const EMAIL = /^[^\s@<>"',;]{1,64}@[^\s@<>"',;]{1,190}\.[a-z]{2,24}$/i;
const clip = (s, n) => String(s ?? '').replace(/\r/g, '').trim().slice(0, n);
const json = (o, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
export const EVENT_TYPES = ['Member-guest', 'Charity outing', 'Club championship', 'Corporate day', 'Pro-am', 'Something else'];
export const PACKAGES = ['Par', 'Birdie', 'Eagle', 'Not sure yet'];

export async function contact(request, env) {
  if (request.method !== 'POST') return json({ error: 'Use POST' }, 405);
  if (!/^application\/json/.test(request.headers.get('Content-Type') || '')) return json({ error: 'Send JSON' }, 415);
  let b;
  try { b = JSON.parse((await request.text()).slice(0, 20000)); } catch { return json({ error: 'Bad request' }, 400); }
  // a hidden field people never fill in; bots do
  if (b.website) return json({ ok: true });
  const f = {
    name: clip(b.name, 80), club: clip(b.club, 120), email: clip(b.email, 200), phone: clip(b.phone, 40),
    date: clip(b.date, 20), players: clip(b.players, 10), type: EVENT_TYPES.includes(b.type) ? b.type : '',
    pkg: PACKAGES.includes(b.pkg) ? b.pkg : '', message: clip(b.message, 4000),
  };
  if (!f.name) return json({ error: 'Please add your name.', field: 'name' }, 400);
  if (!EMAIL.test(f.email)) return json({ error: 'Please check your email address.', field: 'email' }, 400);
  if (!f.club && !f.message) return json({ error: 'Tell us the club or add a note.', field: 'message' }, 400);

  const local = /^(localhost|127\.0\.0\.1)$/.test(new URL(request.url).hostname);
  const ip = request.headers.get('CF-Connecting-IP') || '';
  if (ip && !(await allowed(env, `contact:${ip}`, 5, 60))) return json({ error: 'Thanks, we have your notes. Email hello@flagcast.app if it’s urgent.' }, 429);
  if (!env.RESEND_API_KEY) return local ? json({ ok: true, dev: true }) : json({ error: 'nomail' }, 503);
  const to = String(env.CONTACT_TO || 'hello@flagcast.app').split(/[\s,]+/).filter(Boolean);
  const details = [`Name: ${f.name}`, `Email: ${f.email}`, f.phone && `Phone: ${f.phone}`, f.club && `Club / course: ${f.club}`,
    f.type && `Event: ${f.type}`, f.date && `Date: ${f.date}`, f.players && `Players: ${f.players}`, f.pkg && `Package: ${f.pkg}`].filter(Boolean);
  const text = [...details, '', f.message || '(no note)', '', '— sent from the contact form on flagcast.app'].join('\n');
  const subject = `Flagcast enquiry: ${f.club || f.name}${f.date ? ` · ${f.date}` : ''}`;
  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST', headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env.MAIL_FROM || 'Flagcast <signin@flagcast.app>', to, reply_to: f.email, subject, text }),
  });
  if (!r.ok) return json({ error: 'nomail' }, 502);
  return json({ ok: true });
}
