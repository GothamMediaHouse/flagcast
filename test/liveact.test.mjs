// The lock screen live view (liveact.js): what each team's card shows, and the Apple push it sends.
// Plain unit tests: node --test test/liveact.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { liveCard, cardKey, cardMessage, livePayload, sendLive, apnsJWT, LIVE_TOPIC } from '../liveact.js';
import { defaultHoles } from '../public/golf/core.js';

const ev = {
  name: 'Sample Member-Guest', format: { type: 'bestball', count: 1, allowance: 100, show: 'gross' },
  course: { holes: defaultHoles().map((h, i) => ({ ...h, yds: 300 + i })) },
  teams: [
    { id: 'a', name: '', start: 1, hcp: 0, players: [{ id: 'p1', name: 'Matt Fox', hcp: 0 }, { id: 'p2', name: 'Ana Rivera', hcp: 0 }] },
    { id: 'b', name: 'Park / Chen', start: 10, hcp: 0, players: [{ id: 'p3', name: 'Jo Park', hcp: 0 }] },
    { id: 'c', name: 'Third', start: 1, hcp: 0, players: [{ id: 'p4', name: 'Sam Lee', hcp: 0 }] },
  ],
  nudges: [],
};
const par = (h) => ev.course.holes[h - 1].par;
const card = (vals) => Array.from({ length: 18 }, (_, i) => (vals[i + 1] ?? null));
// team a: birdie on 1 and 2, par on 3 (−2 thru 3); team b: eagle on 10 (−2 thru 1); team c nothing yet
const scores = {
  a: { p1: card({ 1: par(1) - 1, 2: par(2) - 1, 3: par(3) }), p2: card({ 1: par(1), 2: par(2), 3: par(3) + 1 }) },
  b: { p3: card({ 10: par(10) - 2 }) },
};

test('a team card: score, thru, place, the hole they are on, the leader', () => {
  const c = liveCard(ev, scores, 'a', '', 1000);
  assert.equal(c.team, 'Fox / Rivera');
  assert.equal(c.score, '−2'); assert.equal(c.tone, -1);
  assert.equal(c.thru, '3'); assert.equal(c.played, 3); assert.equal(c.holes, 18);
  assert.equal(c.hole, 4); assert.equal(c.par, par(4)); assert.equal(c.yds, 303);
  assert.equal(c.of, 3);
  assert.match(c.pos, /^T?[12]$/);
  assert.equal(c.final, false);
});

test('a shotgun start plays from its own hole; no score yet shows dashes', () => {
  const b = liveCard(ev, scores, 'b');
  assert.equal(b.hole, 11); assert.equal(b.played, 1);
  const c = liveCard(ev, scores, 'c');
  assert.equal(c.score, '—'); assert.equal(c.pos, '—'); assert.equal(c.tone, 0); assert.equal(c.hole, 1);
  assert.equal(liveCard(ev, scores, 'nope'), null);
});

test('pro shop messages: to everyone, to the team, to one golfer, only for 30 minutes', () => {
  const now = 10_000_000;
  const e = { ...ev, nudges: [{ team: '*', text: 'Lunch at the turn', at: now - 40 * 60000 }, { team: 'a', player: 'p2', text: 'For Ana', at: now - 60000 }] };
  assert.equal(cardMessage(e, 'a', 'p1', now), null);
  assert.equal(cardMessage(e, 'a', 'p2', now).text, 'For Ana');
  assert.equal(cardMessage(e, 'a', '', now).text, 'For Ana'); // a phone that hasn't said who holds it sees the team's
  assert.equal(cardMessage(e, 'b', '', now), null); // the one to everyone is too old
  const c = liveCard(e, scores, 'a', 'p2', now);
  assert.equal(c.msg, 'For Ana'); assert.equal(c.from, 'Pro shop');
});

test('the card only counts as changed when something on it changes', () => {
  assert.equal(cardKey(liveCard(ev, scores, 'a', '', 1)), cardKey(liveCard(ev, scores, 'a', '', 2)));
  const more = { ...scores, a: { ...scores.a, p1: card({ 1: 3, 2: 3, 3: 4, 4: 3 }) } };
  assert.notEqual(cardKey(liveCard(ev, scores, 'a')), cardKey(liveCard(ev, more, 'a')));
});

test('locked results end the live view; messages buzz', () => {
  const c = liveCard({ ...ev, locked: true }, scores, 'a');
  assert.equal(c.final, true);
  const p = livePayload(c, { now: 1_000_000 });
  assert.equal(p.aps.event, 'end'); assert.ok(p.aps['dismissal-date'] > p.aps.timestamp);
  const m = livePayload({ ...liveCard(ev, scores, 'a'), msg: 'Keep up', from: 'Pro shop' }, { alert: true });
  assert.equal(m.aps.event, 'update'); assert.equal(m.aps.alert.body, 'Keep up'); assert.equal(m.aps['content-state'].msg, 'Keep up');
});

test('Apple push: ES256 token and liveactivity headers; a dead token is reported gone', async () => {
  const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', kp.privateKey)).toString('base64');
  const env = { APNS_KEY: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----`, APNS_KEY_ID: 'ABC123DEFG' };
  const jwt = await apnsJWT(env);
  const [h, b, s] = jwt.split('.');
  const dec = (x) => JSON.parse(Buffer.from(x, 'base64url').toString());
  assert.deepEqual(dec(h), { alg: 'ES256', kid: 'ABC123DEFG' }); assert.equal(dec(b).iss, 'C8KXPB4QNA');
  assert.ok(await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, kp.publicKey, Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${b}`)));
  let seen;
  const ok = await sendLive(env, 'ab'.repeat(32), 'dev', { aps: {} }, 5, async (u, o) => { seen = { u, o }; return new Response('', { status: 200 }); });
  assert.equal(ok, 'ok');
  assert.equal(seen.u, `https://api.sandbox.push.apple.com/3/device/${'ab'.repeat(32)}`);
  assert.equal(seen.o.headers['apns-push-type'], 'liveactivity'); assert.equal(seen.o.headers['apns-topic'], LIVE_TOPIC);
  const gone = await sendLive(env, 'ab'.repeat(32), 'prod', { aps: {} }, 5, async () => new Response(JSON.stringify({ reason: 'Unregistered' }), { status: 410 }));
  assert.equal(gone, 'gone');
});
