import test from 'node:test';
import assert from 'node:assert/strict';
import { mailHtml, mailText, EMAILS } from '../mail.js';

test('sign-in code email shows the code in HTML and text', () => {
  const m = EMAILS.code('123456');
  assert.equal(m.subject, '123456 is your Flagcast sign-in code');
  assert.match(mailHtml(m), /123456/);
  assert.match(mailText(m), /123456/);
  assert.match(mailHtml(m), /email-logo\.png/);
});

test('club names are escaped in HTML', () => {
  const h = mailHtml(EMAILS.approved('<b>Bad & Co</b>'));
  assert.ok(!h.includes('<b>Bad'));
  assert.match(h, /&lt;b&gt;Bad &amp; Co/);
});

test('every email has a subject, title and text', () => {
  for (const m of [EMAILS.code('1'), EMAILS.added('C', 'a@b.co'), EMAILS.added('C'), EMAILS.approved('C'), EMAILS.setUp('C'), EMAILS.newClub('C', ['x', ''])]) {
    assert.ok(m.subject && m.title);
    assert.ok(mailText(m).includes(m.title));
  }
});

test('player invite: club logo on its colour, group details and the scorecard link', () => {
  const ev = { id: 'abcdefgh', name: 'Member-Guest', club: 'Lakeside GC', date: '2026-12-05', schedule: [{ time: '7:30 AM', what: 'Breakfast' }, { time: '8:30 AM', what: 'Shotgun start' }], course: { name: 'North' } };
  const team = { name: 'A', cart: '12', code: 'ABC234', start: 7, players: [{ name: 'Pat Reilly' }, { name: 'Sam Okafor' }] };
  const m = EMAILS.invite({ ev, team, player: team.players[0], brand: { demo: false, logo: 'https://flagcast.app/golf/api/abcdefgh/logo?v=1', accent: '#1d3b5a' } });
  assert.equal(m.title, 'You’re in, Pat');
  const h = mailHtml(m), t = mailText(m);
  assert.match(h, /golf\/api\/abcdefgh\/logo/); assert.ok(!h.includes('email-logo.png')); assert.match(h, /#1d3b5a/);
  assert.match(t, /Saturday, December 5/); assert.match(t, /8:30 AM · Shotgun start/); assert.match(t, /Cart 12/); assert.match(t, /Hole 7/);
  assert.match(t, /Playing with: Sam Okafor/); assert.ok(!/Playing with:.*Pat/.test(t));
  assert.match(t, /https:\/\/flagcast\.app\/g\/abcdefgh\/s\/ABC234/);
});

test('player invite: a Demo tournament shows the Flagcast logo, an SVG-only club its name', () => {
  const ev = { id: 'abcdefgh', name: 'X', club: 'Demo Club' }, team = { name: 'A', code: 'ABC234', players: [{ name: 'Pat' }] };
  assert.match(mailHtml(EMAILS.invite({ ev, team, player: team.players[0], brand: { demo: true } })), /email-logo\.png/);
  const h = mailHtml(EMAILS.invite({ ev, team, player: team.players[0], brand: { demo: false, logo: '', accent: '' } }));
  assert.ok(!h.includes('email-logo.png')); assert.match(h, />Demo Club</);
});

test('emails are tidied or refused', async () => {
  const { cleanEmail } = await import('../mail.js');
  assert.equal(cleanEmail(' Pat <Pat@Example.com> '), 'pat@example.com');
  for (const bad of ['', 'nope', 'a@b', 'a b@c.com', 'x@y.com, z@w.com']) assert.equal(cleanEmail(bad), '');
});
