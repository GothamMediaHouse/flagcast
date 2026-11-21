// Sign-in helpers for club accounts (clubs.js): passwords, Sign in with Apple and Sign in with Google. No Worker-only imports, so the tests
// run them in Node (test/auth.test.mjs).

// ---- passwords: PBKDF2-SHA256 (Workers' WebCrypto allows up to 100,000 iterations) ----
export const PASS_ITER = 100000;
const enc = new TextEncoder();
const b64 = (u8) => btoa(String.fromCharCode(...new Uint8Array(u8)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const b64url = (s) => unb64(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4));

export async function hashPassword(password, salt = crypto.getRandomValues(new Uint8Array(16)), iter = PASS_ITER) {
  const key = await crypto.subtle.importKey('raw', enc.encode(String(password)), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: iter }, key, 256);
  return { hash: b64(bits), salt: b64(salt), iter };
}
export async function checkPassword(password, rec) {
  if (!rec || !rec.hash || !rec.salt) return false;
  const { hash } = await hashPassword(password, unb64(rec.salt), rec.iter || PASS_ITER);
  const a = enc.encode(hash), b = enc.encode(rec.hash);
  let d = a.length ^ b.length; for (let i = 0; i < Math.max(a.length, b.length); i++) d |= (a[i] || 0) ^ (b[i] || 0);
  return d === 0;
}
/** A password worth keeping: 10+ characters, not all one kind of character. */
export function passwordProblem(p) {
  p = String(p ?? '');
  if (p.length < 10) return 'Use at least 10 characters.';
  if (p.length > 200) return 'That password is too long.';
  if (/^(.)\1+$/.test(p) || /^\d+$/.test(p)) return 'Pick something harder to guess.';
  return null;
}

// ---- Sign in with Apple: the identity token is a JWT signed by Apple (RS256), keys at APPLE_KEYS ----
export const APPLE_KEYS = 'https://appleid.apple.com/auth/keys';
export const APPLE_ISS = 'https://appleid.apple.com';
// the apps that may sign in with Apple (bundle ids; the Mac's debug build too)
export const APPLE_AUDIENCES = ['app.flagcast.manager', 'app.flagcast.manager.debug'];

let keyCache = { at: 0, keys: [] };
export async function appleKeys(fetcher = fetch, now = Date.now()) {
  if (keyCache.keys.length && now - keyCache.at < 3600000) return keyCache.keys;
  const r = await fetcher(APPLE_KEYS);
  if (!r.ok) throw new Error('apple-keys');
  keyCache = { at: now, keys: (await r.json()).keys || [] };
  return keyCache.keys;
}
export function resetAppleKeys() { keyCache = { at: 0, keys: [] }; }

/** Check an Apple identity token: signature against Apple's keys, issuer, audience, expiry. → { sub, email, emailVerified } */
export async function verifyAppleToken(token, { keys, audiences = APPLE_AUDIENCES, now = Date.now() } = {}) {
  return verifyJwt(token, { keys, audiences, issuers: [APPLE_ISS], now });
}

// ---- Sign in with Google: an ID token (JWT, RS256) from Google Identity Services, keys at GOOGLE_KEYS ----
export const GOOGLE_KEYS = 'https://www.googleapis.com/oauth2/v3/certs';
export const GOOGLE_ISS = ['accounts.google.com', 'https://accounts.google.com'];
let gCache = { at: 0, keys: [] };
export async function googleKeys(fetcher = fetch, now = Date.now()) {
  if (gCache.keys.length && now - gCache.at < 3600000) return gCache.keys;
  const r = await fetcher(GOOGLE_KEYS);
  if (!r.ok) throw new Error('google-keys');
  gCache = { at: now, keys: (await r.json()).keys || [] };
  return gCache.keys;
}
/** Check a Google ID token for our client id (env.GOOGLE_CLIENT_ID). → { sub, email, emailVerified } */
export async function verifyGoogleToken(token, { keys, clientId, now = Date.now() } = {}) {
  if (!clientId) throw new Error('Google sign-in isn’t set up yet.');
  return verifyJwt(token, { keys, audiences: [clientId], issuers: GOOGLE_ISS, now, who: 'Google' });
}

async function verifyJwt(token, { keys, audiences, issuers, now = Date.now(), who = 'Apple' }) {
  const parts = String(token || '').split('.');
  if (parts.length !== 3) throw new Error(`That ${who} sign-in didn’t work. Try again.`);
  let head, body;
  try { head = JSON.parse(new TextDecoder().decode(b64url(parts[0]))); body = JSON.parse(new TextDecoder().decode(b64url(parts[1]))); }
  catch { throw new Error(`That ${who} sign-in didn’t work. Try again.`); }
  if (head.alg !== 'RS256') throw new Error(`That ${who} sign-in didn’t work. Try again.`);
  const jwk = (keys || []).find((k) => k.kid === head.kid);
  if (!jwk) throw new Error(`That ${who} sign-in didn’t work. Try again.`);
  const key = await crypto.subtle.importKey('jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true }, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64url(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`));
  if (!ok) throw new Error(`That ${who} sign-in didn’t work. Try again.`);
  if (!issuers.includes(body.iss)) throw new Error(`That ${who} sign-in didn’t work. Try again.`);
  const aud = Array.isArray(body.aud) ? body.aud : [body.aud];
  if (!aud.some((a) => audiences.includes(a))) throw new Error(`That ${who} sign-in is for another app.`);
  if (!body.exp || body.exp * 1000 < now - 60000) throw new Error(`That ${who} sign-in ran out. Try again.`);
  if (!body.sub) throw new Error(`That ${who} sign-in didn’t work. Try again.`);
  return { sub: String(body.sub), email: body.email ? String(body.email).toLowerCase() : '', emailVerified: body.email_verified === true || body.email_verified === 'true' };
}
