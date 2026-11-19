// "Routed to phones": Flagcast Admin, the desk or a golf pro can point every player's phone at something
// (a par 3 camera, the leaderboard, contests, a sponsor). The live page and the scorecard show a banner for it.
import { esc } from '/golf/client.js';

const LABEL = { lb: 'Leaderboard', contests: 'Contests', skins: 'Skins', fund: 'Fundraising', sponsors: 'Our sponsors', schedule: 'Schedule' };
export function phoneTitle(S, r) {
  if (r.k === 'cam' || r.k === 'p3') return `Live now: hole ${r.hole} camera`;
  if (r.k === 'sponsor') { const sp = (S.sponsors || []).find((x) => x.id === r.sponsor); return sp ? sp.name : 'Our sponsor'; }
  if (r.k === 'lb' && r.fl) return `Leaderboard · Flight ${r.fl}`;
  return LABEL[r.k] || 'Have a look';
}

let el = null;
// onGo(route) runs when the player taps the banner's button
export function phoneBanner(S, onGo) {
  const r = S && S.live && S.live.phone;
  const key = `flagcast:phone:${S && S.id}`;
  let seen = 0; try { seen = Number(sessionStorage.getItem(key)) || 0; } catch {}
  if (!r || r.at <= seen || Date.now() - r.at > 20 * 60000) { if (el && (!r || r.at <= seen)) el.hidden = true; return; }
  if (!el) {
    el = document.createElement('div'); el.className = 'phonecast';
    el.style.cssText = 'position:fixed;left:12px;right:12px;bottom:calc(12px + env(safe-area-inset-bottom,0px));z-index:50;background:#123628;color:#eef3ec;border:1px solid rgba(255,255,255,.18);border-radius:14px;padding:12px 14px;display:flex;gap:12px;align-items:center;box-shadow:0 10px 30px rgba(0,0,0,.35);max-width:560px;margin:0 auto';
    document.body.appendChild(el);
  }
  const sp = r.k === 'sponsor' ? (S.sponsors || []).find((x) => x.id === r.sponsor) : null;
  const btn = sp ? (sp.url ? 'Open' : '') : (r.k === 'cam' || r.k === 'p3') ? 'Watch' : 'See it';
  el.innerHTML = `${sp && sp.logo ? `<img src="${esc(sp.logo)}" alt="" style="height:34px;max-width:70px;object-fit:contain;background:#fff;border-radius:6px;padding:3px">` : `<span style="font:700 .62rem 'IBM Plex Mono',monospace;letter-spacing:.12em;background:${r.k === 'cam' || r.k === 'p3' ? '#c8312b' : '#e8c547'};color:${r.k === 'cam' || r.k === 'p3' ? '#fff' : '#1a1a10'};padding:3px 7px;border-radius:3px">${r.k === 'cam' || r.k === 'p3' ? 'LIVE' : 'NOW'}</span>`}
    <div style="flex:1;min-width:0"><b style="display:block;font-size:.98rem">${esc(phoneTitle(S, r))}</b>${r.text || (sp && (sp.offer || sp.line)) ? `<small style="color:#a9bdb0">${esc(r.text || sp.offer || sp.line)}</small>` : ''}</div>
    ${btn ? `<button data-pc-go style="background:#e8c547;color:#1a1a10;border:0;border-radius:8px;padding:9px 14px;font-weight:700">${btn}</button>` : ''}
    <button data-pc-x aria-label="Close" style="background:none;border:0;color:#a9bdb0;font-size:1.2rem;padding:4px 6px">✕</button>`;
  el.hidden = false;
  const done = () => { try { sessionStorage.setItem(key, String(r.at)); } catch {} el.hidden = true; };
  el.querySelector('[data-pc-x]').onclick = done;
  const go = el.querySelector('[data-pc-go]');
  if (go) go.onclick = () => { done(); if (sp && sp.url) { window.open(sp.url, '_blank', 'noopener'); return; } onGo(r); };
}
