// The hole GPS on the scorecard: a yardage card (front / middle / back, hazards) and a full-screen course view.
// mount(slot) puts the one card into the page after each render; update(S, hole) changes what it shows.
import { esc } from '/golf/client.js';
import { trackingOn, holeMap, middle, mapped, origin, yardages, startGps, stopGps, gpsWanted, position, onGps, holeView, HZ_LABEL } from '/golf/gps.js';

const css = `
.gps { margin-top: 12px; background: var(--green); color: var(--on-green); border-radius: 12px; padding: 12px 14px; }
.gps .top { display: flex; align-items: center; gap: 12px; }
.gps .mid { font: 800 2.6rem/1 var(--f-display); }
.gps .mid small { font: 600 .7rem var(--f-mono); letter-spacing: .1em; color: var(--on-green-muted); display: block; margin-top: 3px; text-transform: uppercase; }
.gps .fb { font-family: var(--f-mono); font-size: .82rem; color: var(--on-green-muted); line-height: 1.5; }
.gps .fb b { color: var(--on-green); }
.gps .go { margin-left: auto; display: grid; gap: 6px; }
.gps .go button { border: 0; border-radius: 8px; padding: 8px 12px; font-weight: 700; font-size: .88rem; }
.gps .go .cv { background: var(--flag); color: var(--on-flag); }
.gps .go .on { background: rgba(255,255,255,.12); color: var(--on-green); }
.gps .hzs { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 10px; }
.gps .hzs span { font-size: .78rem; background: rgba(255,255,255,.1); border-radius: 999px; padding: 3px 9px; }
.gps .hzs b { font-family: var(--f-mono); }
.gps .msg { font-size: .82rem; color: var(--on-green-muted); margin-top: 8px; }
.cview { position: fixed; inset: 0; z-index: 60; background: #0b1a12; color: #fff; display: flex; flex-direction: column; }
.cview canvas { flex: 1; width: 100%; min-height: 0; display: block; touch-action: manipulation; }
.cview .cv-bar { display: flex; align-items: center; gap: 10px; padding: calc(10px + env(safe-area-inset-top, 0px)) 14px 10px; background: rgba(11,26,18,.92); }
.cview .cv-bar h3 { font: 800 1.6rem/1 var(--f-display); text-transform: uppercase; margin: 0; }
.cview .cv-bar small { color: #a9bdb0; font-family: var(--f-mono); font-size: .75rem; }
.cview .cv-bar button, .cview .cv-foot button { background: rgba(255,255,255,.12); color: #fff; border: 0; border-radius: 8px; padding: 8px 12px; font-weight: 700; }
.cview .yd { position: absolute; right: 12px; top: calc(70px + env(safe-area-inset-top, 0px)); background: rgba(11,26,18,.85); border-radius: 12px; padding: 10px 12px; text-align: right; font-family: var(--f-mono); font-size: .8rem; color: #a9bdb0; pointer-events: none; }
.cview .yd .m { font: 800 2.4rem/1 var(--f-display); color: #fff; }
.cview .yd b { color: #fff; }
.cview .cv-foot { display: flex; align-items: center; gap: 10px; padding: 10px 14px calc(10px + env(safe-area-inset-bottom, 0px)); background: rgba(11,26,18,.92); font-size: .86rem; color: #cfdcd3; }
.cview .cv-foot span { flex: 1; min-width: 0; }
`;

export function gpsCard({ onHole } = {}) {
  if (!document.getElementById('gps-css')) { const st = document.createElement('style'); st.id = 'gps-css'; st.textContent = css; document.head.appendChild(st); }
  const el = document.createElement('div'); el.className = 'gps';
  let S = null, hole = 1, err = '', view = null, ov = null, measure = null;
  onGps((f) => { err = f.error || ''; paint(); });
  if (gpsWanted()) startGps();

  function paint() {
    const h = holeMap(S, hole);
    el.hidden = !mapped(S);
    if (!h || !middle(h)) { el.innerHTML = `<div class="msg" style="margin:0">Hole ${hole} isn’t on the course map yet.</div>`; if (ov) paintView(); return; }
    const me = position(), o = origin(h, me && me.at), y = yardages(h, o && o.at), on = gpsWanted();
    const far = me && !o?.me;
    el.innerHTML = `<div class="top">
        <div class="mid">${y && y.m != null ? y.m : '—'}<small>${o?.me ? 'to the middle' : 'middle, from the tee'}</small></div>
        <div class="fb">${y && y.f != null ? `Front <b>${y.f}</b><br>` : ''}${y && y.b != null ? `Back <b>${y.b}</b>` : ''}</div>
        <div class="go"><button class="cv" data-cv>Course view</button>${on ? '' : '<button class="on" data-on>Use my GPS</button>'}</div></div>
      ${y && y.hz.length ? `<div class="hzs">${y.hz.slice(0, 6).map((z) => `<span>${esc(z.name)} <b>${z.reach}</b>${z.carry ? `–<b>${z.carry}</b>` : ''}</span>`).join('')}</div>` : ''}
      <div class="msg">${err ? esc(err) : !on ? `Yards from the tee. Turn on GPS for yards from where you are${trackingOn(S) ? ' (during the tournament the desk sees where your group is)' : ''}.` : !me ? 'Finding your spot…' : far ? `You’re not on hole ${hole} yet, so these are from the tee.` : `GPS to within ${me.acc} yds.${trackingOn(S) ? ' The tournament desk can see where your group is until the results are final.' : ''} <button data-off style="background:none;border:0;color:inherit;text-decoration:underline;padding:0;font-size:inherit">Turn off</button>`}</div>`;
    if (ov) paintView();
  }

  function paintView() {
    const h = holeMap(S, hole), me = position();
    const o = h ? origin(h, me && me.at) : null, y = h ? yardages(h, o && o.at) : null, H = S.course.holes[hole - 1];
    ov.querySelector('h3').textContent = `Hole ${hole}`;
    ov.querySelector('.cv-bar small').textContent = `Par ${H.par}${H.yds ? ` · ${H.yds} yds` : ''}`;
    ov.querySelector('.yd').innerHTML = y && y.m != null ? `<div class="m">${y.m}</div>${o?.me ? 'to the middle' : 'from the tee'}${y.f != null || y.b != null ? `<br>${[y.f != null ? `Front <b>${y.f}</b>` : '', y.b != null ? `Back <b>${y.b}</b>` : ''].filter(Boolean).join(' · ')}` : ''}` : 'Not mapped yet';
    ov.querySelector('.cv-foot span').textContent = measure ? `${measure.to} yds there, then ${measure.left} to the middle. Tap it again to clear.` : 'Tap anywhere to measure: how far there, and what’s left to the green.';
    if (h && middle(h)) view.draw(h, me && me.at, S.map && S.map.src === 'osm'); else view.draw(null);
  }

  function open() {
    ov = document.createElement('div'); ov.className = 'cview';
    ov.innerHTML = `<div class="cv-bar"><button data-x aria-label="Close">✕</button><div style="flex:1"><h3></h3><small></small></div><button data-p aria-label="Previous hole">‹</button><button data-n aria-label="Next hole">›</button></div>
      <canvas aria-label="Satellite view of the hole"></canvas><div class="yd"></div><div class="cv-foot"><span></span>${gpsWanted() ? '' : '<button data-on>Use my GPS</button>'}</div>`;
    document.body.appendChild(ov); document.body.style.overflow = 'hidden';
    view = holeView(ov.querySelector('canvas'));
    ov.querySelector('canvas').addEventListener('measure', (e) => { measure = e.detail; paintView(); });
    ov.addEventListener('click', (e) => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.hasAttribute('data-x')) close();
      if (b.hasAttribute('data-on')) { startGps(); b.remove(); }
      if (b.hasAttribute('data-p') || b.hasAttribute('data-n')) { measure = null; onHole && onHole(b.hasAttribute('data-n') ? 1 : -1); }
    });
    paintView();
  }
  function close() { if (!ov) return; view.destroy(); ov.remove(); ov = null; view = null; measure = null; document.body.style.overflow = ''; }

  el.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.hasAttribute('data-cv')) open();
    if (b.hasAttribute('data-on')) { err = ''; startGps(); paint(); }
    if (b.hasAttribute('data-off')) { stopGps(); paint(); }
  });

  return {
    el,
    update(s, n) { const moved = n !== hole; S = s; hole = n; if (moved) measure = null; paint(); },
    mount(slot) { if (slot) slot.replaceWith(el); },
    close,
  };
}
export { HZ_LABEL };
