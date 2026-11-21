// Sign-in: passwords and Sign in with Apple.
//   node test/auth.test.mjs                         unit tests (auth.js), no server needed
//   node test/auth.test.mjs http://127.0.0.1:8787   plus the club API on `npx wrangler dev` (local, no email key)
import assert from 'node:assert/strict';
import { hashPassword, checkPassword, passwordProblem, verifyAppleToken, appleKeys, resetAppleKeys, APPLE_ISS } from '../auth.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const b64url = (buf) => Buffer.from(buf).toString('base64url');

// ---- passwords ----
const rec = await hashPassword('correct horse battery');
assert.ok(await checkPassword('correct horse battery', rec));
assert.ok(!(await checkPassword('correct horse batterY', rec)));
assert.ok(!(await checkPassword('x', null)));
assert.notEqual((await hashPassword('correct horse battery')).hash, rec.hash, 'salted');
ok('passwords hash with a salt and check');
assert.ok(passwordProblem('short')); assert.ok(passwordProblem('1234567890123')); assert.ok(passwordProblem('aaaaaaaaaaaa')); assert.equal(passwordProblem('green flag 18'), null);
ok('weak passwords are refused');

// ---- Apple identity tokens, against a made-up Apple key ----
const { publicKey, privateKey } = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
const jwk = { ...(await crypto.subtle.exportKey('jwk', publicKey)), kid: 'TESTKID', alg: 'RS256', use: 'sig' };
const keys = [jwk];
const now = Date.now();
async function token(body, head = { alg: 'RS256', kid: 'TESTKID' }, key = privateKey) {
  const h = b64url(JSON.stringify(head)), p = b64url(JSON.stringify(body));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${h}.${p}`));
  return `${h}.${p}.${b64url(sig)}`;
}
const good = { iss: APPLE_ISS, aud: 'app.flagcast.manager', sub: '001234.abc', email: 'Pro@Example.com', email_verified: 'true', exp: Math.floor(now / 1000) + 600 };
const id = await verifyAppleToken(await token(good), { keys, now });
assert.deepEqual(id, { sub: '001234.abc', email: 'pro@example.com', emailVerified: true });
ok('a good Apple token gives the Apple ID and email');
await assert.rejects(verifyAppleToken(await token({ ...good, aud: 'com.someone.else' }), { keys, now }), /another app/);
await assert.rejects(verifyAppleToken(await token({ ...good, iss: 'https://evil.example' }), { keys, now }));
await assert.rejects(verifyAppleToken(await token({ ...good, exp: Math.floor(now / 1000) - 600 }), { keys, now }), /ran out/);
await assert.rejects(verifyAppleToken(await token(good, { alg: 'RS256', kid: 'OTHER' }), { keys, now }));
await assert.rejects(verifyAppleToken(await token(good, { alg: 'none', kid: 'TESTKID' }), { keys, now }));
const other = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign']);
await assert.rejects(verifyAppleToken(await token(good, undefined, other.privateKey), { keys, now }));
const t = await token(good); const [h, p] = t.split('.');
await assert.rejects(verifyAppleToken(`${h}.${b64url(JSON.stringify({ ...good, sub: 'someone-else' }))}.${t.split('.')[2]}`, { keys, now }));
await assert.rejects(verifyAppleToken('not.a.token', { keys, now }));
ok('wrong app, issuer, expired, unknown key, alg none, wrong signer, changed body and junk are all refused');
resetAppleKeys();
let fetched = 0;
const fake = async () => { fetched++; return { ok: true, json: async () => ({ keys }) }; };
assert.deepEqual(await appleKeys(fake, now), keys); await appleKeys(fake, now + 1000); assert.equal(fetched, 1);
await appleKeys(fake, now + 3700000); assert.equal(fetched, 2);
ok('Apple’s keys are fetched once an hour');

// ---- the club API (local dev server) ----
const BASE = process.argv[2];
if (BASE) {
  const call = async (op, body) => { const r = await fetch(`${BASE}/golf/api/club/${op}`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }); return { status: r.status, j: await r.json() }; };
  const email = `pw-${Date.now()}@example.com`;
  const s = await call('start', { email }); assert.ok(s.j.devCode, 'local dev gives the code back');
  const v = await call('verify', { email, code: s.j.devCode }); assert.ok(v.j.token);
  let r = await call('login', { email, password: 'green flag 18' }); assert.equal(r.status, 401); assert.match(r.j.error, /no password/);
  r = await call('setpass', { token: v.j.token, password: 'short' }); assert.equal(r.status, 400);
  r = await call('setpass', { token: v.j.token, password: 'green flag 18' }); assert.equal(r.status, 200);
  r = await call('me', { token: v.j.token }); assert.equal(r.j.password, true); assert.equal(r.j.apple, false);
  ok('sign in with a code, then set a password (refused if weak)');
  r = await call('login', { email: email.toUpperCase(), password: 'green flag 18' }); assert.equal(r.status, 200); assert.ok(r.j.token && r.j.token !== v.j.token);
  r = await call('me', { token: r.j.token }); assert.equal(r.j.email, email);
  ok('email + password gives a new session (email in any case)');
  for (let i = 0; i < 5; i++) { r = await call('login', { email, password: `wrong ${i} password` }); assert.equal(r.status, 401); }
  r = await call('login', { email, password: 'green flag 18' }); assert.equal(r.status, 429);
  ok('five wrong passwords lock that email for 15 minutes, even with the right one');
  r = await call('setpass', { token: 'nope', password: 'green flag 18' }); assert.equal(r.status, 401);
  r = await call('apple', { identityToken: await token(good) }); assert.equal(r.status, 401);
  r = await call('apple', { identityToken: 'junk' }); assert.equal(r.status, 401);
  ok('setpass needs a session; a token not signed by Apple is refused');
}
console.log(`\n${n} passed`);
