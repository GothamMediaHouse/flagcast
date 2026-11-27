// Player invites by email: emails stay off the public state, a Save from an app that doesn't send emails keeps them,
// Send goes once to each player (and again only to new ones), Resend has a limit, and a test copy goes to the club.
// Resend is a stand-in on this computer, so no real email goes out.
// Run against `npx wrangler dev` started with RESEND_API_KEY=test, RESEND_BASE=http://127.0.0.1:8795
//   node test/invites.test.mjs [http://127.0.0.1:8787] [8795]   (npm test does all of that)
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const MOCK_PORT = Number(process.argv[3] || 8795);
const got = []; let fail = false;
const mock = createServer((req, res) => {
  let body = ''; req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const send = (o, status = 200) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.headers.authorization !== 'Bearer test' || req.url !== '/emails/batch' || req.method !== 'POST') return send({ message: 'no' }, 403);
    if (fail) return send({ message: 'down' }, 500);
    const list = JSON.parse(body); got.push(...list);
    send({ data: list.map((_, i) => ({ id: `e${got.length + i}` })) });
  });
});
await new Promise((r) => mock.listen(MOCK_PORT, '127.0.0.1', r));

const post = async (path, body, okOnly = true) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json(); if (okOnly && !r.ok) throw new Error(`${path} ${r.status} ${JSON.stringify(j)}`); return { ...j, status: r.status };
};
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
try {
  const { id, key } = await post('/golf/api/new', { name: 'Invite test', pass: 'local' });
  const desk = (op, b = {}, o) => post(`/golf/api/${id}/desk`, { key, op, ...b }, o);
  let cur = await desk('get');
  await desk('save', { setup: { ...cur, club: 'Lakeside "GC" <x>', date: '2026-12-05', schedule: [{ time: '8:30 AM', what: 'Shotgun start' }],
    teams: [{ id: 'teama', name: 'A', cart: '12', start: 7, players: [{ id: 'pa', name: 'Pat Reilly', email: ' Pat@Example.com ' }, { id: 'pb', name: 'Sam Okafor', email: 'not an email' }] },
      { id: 'teamb', name: 'B', players: [{ id: 'pc', name: 'Cy', email: 'cy@example.com' }, { id: 'pd', name: 'Dee' }] }] } });
  cur = await desk('get');
  assert.deepEqual(cur.teams.flatMap((t) => t.players.map((p) => p.email)), ['pat@example.com', '', 'cy@example.com', '']);
  ok('emails are tidied, and one that isn’t an email is left out');
  const pub = await (await fetch(`${BASE}/golf/api/${id}/state`)).json();
  assert.ok(!JSON.stringify(pub).includes('example.com') && !('invites' in pub));
  ok('the public state has no emails');

  // an older Manager saves without the email field: the emails stay. Sending '' clears one.
  const strip = (s) => ({ ...s, teams: s.teams.map((t) => ({ ...t, players: t.players.map(({ email, ...p }) => p) })) });
  await desk('save', { setup: strip(cur) });
  assert.equal((await desk('get')).teams[0].players[0].email, 'pat@example.com');
  ok('a Save without emails keeps them');

  const pv = await desk('invite', { preview: true });
  assert.match(pv.subject, /Invite test/); assert.match(pv.html, /Open my scorecard/); assert.match(pv.html, new RegExp(`/g/${id}/s/[A-Z0-9]{6}`));
  assert.equal(got.length, 0);
  ok('preview sends nothing');

  let r = await desk('invite', { send: 'new' });
  assert.equal(r.sent, 2); assert.equal(got.length, 2);
  assert.deepEqual(got.map((x) => x.to[0]).sort(), ['cy@example.com', 'pat@example.com']);
  assert.match(got[0].from, /^Lakeside GC x via Flagcast <signin@flagcast\.app>$/);
  const pat = got.find((x) => x.to[0] === 'pat@example.com');
  assert.match(pat.text, /Cart 12/); assert.match(pat.text, /Hole 7/); assert.match(pat.text, /8:30 AM/); assert.match(pat.text, /Sam Okafor/);
  assert.ok(r.invites.pa.at && r.invites.pa.n === 1);
  ok('Send emails each player with an email once, from the club');

  r = await desk('invite', { send: 'new' });
  assert.equal(r.sent, 0); assert.equal(got.length, 2);
  cur = await desk('get');
  cur.teams[1].players[1].email = 'dee@example.com';
  await desk('save', { setup: cur });
  r = await desk('invite', { send: 'new' });
  assert.equal(r.sent, 1); assert.equal(got.at(-1).to[0], 'dee@example.com');
  ok('Send again only goes to players added since');

  for (let i = 0; i < 3; i++) await desk('invite', { send: ['pa'] });
  r = await desk('invite', { send: ['pa'] }, false);
  assert.equal(r.status, 429); assert.equal((await desk('get')).invites.pa.n, 4);
  ok('Resend stops after 4 emails to one player');

  fail = true;
  cur = await desk('get'); cur.teams[0].players[1].email = 'sam@example.com'; await desk('save', { setup: cur });
  r = await desk('invite', { send: 'new' });
  assert.equal(r.failed, 1); assert.ok(r.error); assert.ok(!r.invites.pb);
  fail = false;
  r = await desk('invite', { send: 'new' }); assert.equal(r.sent, 1);
  ok('a failed send can be sent again');

  const before = got.length;
  r = await desk('invite', { test: 'pro@lakeside.com' });
  assert.equal(got.length, before + 1); assert.match(got.at(-1).subject, /^Test: /); assert.equal(got.at(-1).to[0], 'pro@lakeside.com');
  assert.equal((await desk('invite', { test: 'nope' }, false)).status, 400);
  ok('a test copy goes to the address typed');

  assert.equal((await post(`/golf/api/${id}/desk`, { key: 'wrong', op: 'invite', send: 'new' }, false)).status, 403);
  ok('only the desk can send');
} finally { mock.close(); }
