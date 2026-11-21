// Club branding: the club's logo (and an optional accent colour) shows to golfers and on the TVs instead of the
// Flagcast logo. Flagcast's own logo is for demos: a club with no logo yet, or a tournament Flagcast Admin marks Demo.
//
// A club's logo is set in Admin → Clubs → Branding or by the club in its settings (clubs.js), and copied into each of
// its tournaments (GolfEvent op 'brand'). A tournament can use its own logo instead (Setup, `logo`). The logo itself
// never rides in the live state (it goes to every phone on every score): the state carries its address,
// /golf/api/<id>/logo?v=<version>, served by golf.js with a long cache.
// No Worker-only imports: test/brand.test.mjs runs it in Node.

export const LOGO_MAX = 400_000; // characters of data: URI (about 290 KB of image); the apps shrink logos before sending
const TYPES = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/svg+xml': 'svg' };

const b64decode = (s) => (typeof atob === 'function' ? Uint8Array.from(atob(s), (c) => c.charCodeAt(0)) : new Uint8Array(Buffer.from(s, 'base64')));

/** The logo's bytes and type from a data: URI, or null */
export function decodeLogo(uri) {
  const m = String(uri || '').match(/^data:(image\/(?:png|jpeg|webp|svg\+xml));base64,([A-Za-z0-9+/=\s]+)$/);
  if (!m) return null;
  try { return { type: m[1], bytes: b64decode(m[2].replace(/\s/g, '')) }; } catch { return null; }
}

// SVG can carry script; only plain drawings are taken (and golf.js serves logos with a locked-down CSP as well)
const SVG_BAD = /<script|<foreignObject|<iframe|<embed|<object|\son[a-z]+\s*=|javascript:|(?:xlink:)?href\s*=\s*["'](?!#|data:image\/)/i;

/**
 * A logo as sent by an app or page: '' removes it, a PNG/JPEG/WebP/SVG data: URI is kept.
 * → the cleaned data: URI ('' for none). Throws an Error with a message for the person when it can't be used.
 */
export function cleanLogo(v) {
  if (v === '' || v === null) return '';
  const s = String(v || '');
  if (s.length > LOGO_MAX) throw Object.assign(new Error('That logo is too big. Use a PNG under 250 KB (about 1000 pixels wide is plenty).'), { status: 413 });
  const d = decodeLogo(s);
  if (!d || !d.bytes.length) throw Object.assign(new Error('Use a PNG, JPEG, WebP or SVG image for the logo.'), { status: 400 });
  const head = d.bytes.slice(0, 12);
  const is = { 'image/png': head[0] === 0x89 && head[1] === 0x50, 'image/jpeg': head[0] === 0xff && head[1] === 0xd8,
    'image/webp': String.fromCharCode(...head.slice(8, 12)) === 'WEBP', 'image/svg+xml': true }[d.type];
  if (!is) throw Object.assign(new Error('That file isn’t the image it says it is. Save it again as a PNG and try again.'), { status: 400 });
  if (d.type === 'image/svg+xml') {
    const text = new TextDecoder().decode(d.bytes);
    if (!/<svg[\s>]/i.test(text) || SVG_BAD.test(text)) throw Object.assign(new Error('That SVG has scripts or links in it. Export it as a PNG instead.'), { status: 400 });
  }
  return s.replace(/\s/g, '');
}

/** '#1a6b3c' style colour, or '' */
export const cleanAccent = (v) => (/^#[0-9a-f]{6}$/i.test(String(v || '').trim()) ? String(v).trim().toLowerCase() : '');

/** a short version tag for a logo, so its address changes when it does */
export function logoVersion(uri) {
  let h = 0x811c9dc5; const s = String(uri || '');
  for (let i = 0; i < s.length; i += Math.max(1, Math.floor(s.length / 4096))) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; }
  return (h >>> 0).toString(36) + s.length.toString(36);
}

/**
 * What a tournament shows: its own logo, else its club's. Flagcast's logo (logo '') when there's none or the
 * tournament is a demo. → { logo: address or '', accent, demo (shows Flagcast's), marked (Admin set Demo), powered, club }
 */
export function brandFor(ev) {
  const club = ev.clubBrand || {};
  const own = ev.logo || '', uri = own || club.logo || '';
  const demo = !!ev.demo || !uri;
  return {
    logo: demo ? '' : `/golf/api/${ev.id}/logo?v=${logoVersion(uri)}`,
    accent: demo ? '' : cleanAccent(club.accent),
    demo, marked: !!ev.demo, powered: !demo && !!club.powered, club: ev.club || '',
  };
}

/** the logo a tournament serves at /golf/api/<id>/logo (null when it shows Flagcast's) */
export const logoOf = (ev) => (ev.demo ? null : decodeLogo(ev.logo || ev.clubBrand?.logo || ''));
