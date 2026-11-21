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
