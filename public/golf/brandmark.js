// Club branding on the golfer pages and the TVs (brand.js on the server): the club's logo where the Flagcast logo
// would be, the club's colour as a thin line, and "Powered by Flagcast" only when Flagcast Admin turns it on.
// A tournament with no logo, or marked Demo in Admin, keeps the Flagcast logo.
const FLAGCAST = '/golf/brand/wide-on-dark.svg';

/** update every <img data-brand> (data-brand="club": only a club logo, no Flagcast fallback) and [data-powered] from the live state */
export function applyBrand(s, root = document) {
  const b = (s && s.brand) || {};
  const src = b.logo || FLAGCAST;
  for (const img of root.querySelectorAll('img[data-brand]')) {
    if (img.dataset.brand === 'club' && !b.logo) { img.hidden = true; continue; } // only ever the club's (the scorecard)
    if (img.getAttribute('src') !== src) img.setAttribute('src', src);
    img.alt = b.logo ? (b.club || 'Club logo') : 'Flagcast';
    img.classList.toggle('clublogo', !!b.logo);
    img.hidden = false;
  }
  for (const el of root.querySelectorAll('[data-powered]')) el.hidden = !b.powered;
  const html = document.documentElement;
  if (b.accent) html.style.setProperty('--club', b.accent); else html.style.removeProperty('--club');
  html.classList.toggle('has-club', !!b.logo);
}

/** Any picture the person picks (PNG, JPEG, SVG…) as a PNG data: URI the server takes: at most 1000 px on its
 *  longest side, transparency kept, under about 280 KB. Throws with a message for the person. */
export async function fileToLogo(file) {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = () => no(new Error('That file isn’t a picture this browser can read. Try a PNG.')); i.src = url; });
    let side = 1000;
    for (let k = 0; k < 6; k++) {
      const w0 = img.naturalWidth || 1000, h0 = img.naturalHeight || 300, f = side / Math.max(w0, h0);
      const vector = /svg/i.test(file.type || file.name);
      const s = vector ? f : Math.min(1, f);
      const c = document.createElement('canvas'); c.width = Math.max(1, Math.round(w0 * s)); c.height = Math.max(1, Math.round(h0 * s));
      c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
      const uri = c.toDataURL('image/png');
      if (uri.length < 380_000) return uri;
      side *= 0.8;
    }
    throw new Error('That picture is too detailed to use as a logo. Try a simpler PNG.');
  } finally { URL.revokeObjectURL(url); }
}
