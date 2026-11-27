// Draws a made-up parkland course from above (fairways, greens, bunkers, trees, a pond)
// and walks the sample groups along their holes. No map tiles: nothing to license.
(() => {
  const NS = 'http://www.w3.org/2000/svg';
  const svg = document.getElementById('course');
  const el = (tag, at, parent) => { const e = document.createElementNS(NS, tag); for (const k in at) e.setAttribute(k, at[k]); (parent || svg).appendChild(e); return e; };
  let seed = 1867; const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

  // Each hole: tee to green through its bend. w = fairway width.
  const HOLES = [
    { n: 1, p: [[62, 470], [40, 352], [72, 240]], w: 30 },
    { n: 2, p: [[104, 214], [146, 112]], w: 22 },
    { n: 3, p: [[186, 92], [234, 172], [222, 272]], w: 30 },
    { n: 4, p: [[186, 300], [132, 392]], w: 22 },
    { n: 5, p: [[176, 440], [262, 410], [296, 318]], w: 30 },
    { n: 6, p: [[318, 294], [326, 196], [300, 128]], w: 28 },
    { n: 7, p: [[280, 96], [214, 34]], w: 24 },
    { n: 8, p: [[364, 96], [374, 230], [368, 330]], w: 26 },
    { n: 9, p: [[366, 372], [330, 470]], w: 26 },
  ];
  const BUNKERS = [[58, 300, 9, 6, 20], [92, 228, 7, 5, -30], [130, 100, 8, 5, 10], [160, 120, 6, 5, 0], [252, 178, 9, 6, 60], [206, 262, 8, 5, 30], [238, 282, 6, 4, 0], [120, 380, 6, 5, 20], [146, 402, 7, 5, 0], [240, 398, 10, 6, -20], [312, 312, 8, 5, 40], [282, 330, 6, 4, 0], [310, 210, 7, 5, -10], [286, 120, 8, 5, 20], [228, 28, 7, 5, 0], [386, 220, 7, 5, 0], [384, 336, 8, 6, 0], [318, 468, 8, 5, 0]];
  const POND = { x: 252, y: 236, rx: 26, ry: 18 };

  // Geometry helpers
  const segDist = (x, y, [ax, ay], [bx, by]) => { const dx = bx - ax, dy = by - ay, t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy))); return Math.hypot(x - ax - t * dx, y - ay - t * dy); };
  const holeDist = (x, y, h) => { let d = 1e9; for (let i = 1; i < h.p.length; i++) d = Math.min(d, segDist(x, y, h.p[i - 1], h.p[i])); return d; };
  const curve = (p) => p.length === 2 ? `M${p[0]}L${p[1]}` : `M${p[0]}Q${p[1]} ${p[2]}`;
  const along = (h, t) => { // point on the hole's curve at 0..1
    const [a, b, c] = h.p; if (!c) return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];
    const u = 1 - t; return [u * u * a[0] + 2 * u * t * b[0] + t * t * c[0], u * u * a[1] + 2 * u * t * b[1] + t * t * c[1]];
  };

  // Textures
  const defs = el('defs', {});
  defs.innerHTML = `
    <filter id="grain" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".9" numOctaves="2" seed="4"/><feColorMatrix values="0 0 0 0 .12  0 0 0 0 .2  0 0 0 0 .08  0 0 0 .55 0"/><feComposite in2="SourceGraphic" operator="in"/></filter>
    <filter id="mottle" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".018" numOctaves="3" seed="9"/><feColorMatrix values="0 0 0 0 .2  0 0 0 0 .32  0 0 0 0 .12  0 0 0 .9 -.2"/></filter>
    <filter id="soft"><feGaussianBlur stdDeviation="1.6"/></filter>
    <pattern id="stripes" width="22" height="22" patternUnits="userSpaceOnUse" patternTransform="rotate(28)"><rect width="22" height="22" fill="#7ab457"/><rect width="11" height="22" fill="#6fa64d"/></pattern>
    <pattern id="gstripes" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(-20)"><rect width="6" height="6" fill="#8cc66a"/><rect width="3" height="6" fill="#84bd62"/></pattern>
    <radialGradient id="water" cx=".45" cy=".4"><stop offset="0" stop-color="#3f7684"/><stop offset=".8" stop-color="#2b5866"/><stop offset="1" stop-color="#5c7f56"/></radialGradient>
    <radialGradient id="tree" cx=".38" cy=".35"><stop offset="0" stop-color="#4d7f3d"/><stop offset=".6" stop-color="#2f5a2c"/><stop offset="1" stop-color="#21452a"/></radialGradient>
    <radialGradient id="tree2" cx=".38" cy=".35"><stop offset="0" stop-color="#5f8a3a"/><stop offset=".6" stop-color="#3c6a2e"/><stop offset="1" stop-color="#284f27"/></radialGradient>`;

  // Ground: rough with a mottled, grainy look
  el('rect', { width: 393, height: 798, fill: '#466f36' });
  el('rect', { width: 393, height: 798, filter: 'url(#mottle)', opacity: .55 });

  // Light rough around each hole, then the striped fairway on top
  for (const h of HOLES) el('path', { d: curve(h.p), fill: 'none', stroke: '#5d8c45', 'stroke-width': h.w + 26, 'stroke-linecap': 'round', filter: 'url(#soft)' });
  const mask = el('mask', { id: 'fw' }, defs);
  for (const h of HOLES) {
    const [a] = h.p, t = along(h, .2); // fairway starts a little past the tee
    const p2 = [...h.p]; p2[0] = t; el('path', { d: curve(p2), fill: 'none', stroke: '#fff', 'stroke-width': h.w, 'stroke-linecap': 'round' }, mask);
  }
  el('rect', { width: 393, height: 798, fill: 'url(#stripes)', mask: 'url(#fw)' });

  // Cart path winding between holes
  el('path', { d: 'M150 470C120 430 104 400 108 330S96 250 128 210 170 160 176 120 200 70 236 64 300 80 304 110 350 150 352 250 356 330 350 380', fill: 'none', stroke: '#c9c3ad', 'stroke-width': 2.4, opacity: .7, 'stroke-linecap': 'round' });

  // Pond
  el('ellipse', { cx: POND.x, cy: POND.y, rx: POND.rx + 3, ry: POND.ry + 3, fill: '#3e6a3a', filter: 'url(#soft)' });
  el('path', { d: `M${POND.x - POND.rx} ${POND.y}c2-14 18-20 30-18s24 6 22 18-10 18-26 17-28-6-26-17z`, fill: 'url(#water)' });

  // Trees: clumps everywhere that is not a hole, the pond or the clubhouse
  const trees = [];
  for (let i = 0; i < 2600 && trees.length < 420; i++) {
    const x = rnd() * 420 - 14, y = rnd() * 520 - 10, r = 4 + rnd() * 6;
    if (HOLES.some((h) => holeDist(x, y, h) < h.w / 2 + 16 + r)) continue;
    if (Math.hypot((x - POND.x) / (POND.rx + 10), (y - POND.y) / (POND.ry + 10)) < 1) continue;
    if (trees.some((t) => Math.hypot(t.x - x, t.y - y) < (t.r + r) * .62)) continue;
    trees.push({ x, y, r });
  }
  trees.sort((a, b) => a.y - b.y);
  const shade = el('g', { opacity: .45 }); const crowns = el('g', {});
  for (const t of trees) {
    el('circle', { cx: t.x + t.r * .5, cy: t.y + t.r * .55, r: t.r, fill: '#0e2414' }, shade);
    el('circle', { cx: t.x, cy: t.y, r: t.r, fill: rnd() < .3 ? 'url(#tree2)' : 'url(#tree)' }, crowns);
  }

  // Tees, greens, bunkers
  for (const h of HOLES) {
    const [tx, ty] = h.p[0], [nx, ny] = h.p[1], ang = Math.atan2(ny - ty, nx - tx) * 180 / Math.PI;
    el('rect', { x: -7, y: -5, width: 14, height: 10, rx: 2, fill: '#7db35b', stroke: '#5b8d45', 'stroke-width': 1, transform: `translate(${tx} ${ty}) rotate(${ang + 90})` });
    const [gx, gy] = h.p[h.p.length - 1];
    el('ellipse', { cx: gx, cy: gy, rx: 17, ry: 14, fill: '#6fa451', transform: `rotate(${ang} ${gx} ${gy})` });
    el('ellipse', { cx: gx, cy: gy, rx: 13, ry: 10.5, fill: 'url(#gstripes)', transform: `rotate(${ang} ${gx} ${gy})` });
    el('circle', { cx: gx + 2, cy: gy - 1, r: 1.6, fill: '#fff' });
  }
  for (const [x, y, rx, ry, a] of BUNKERS) {
    el('ellipse', { cx: x + 1, cy: y + 1.5, rx: rx + 1, ry: ry + 1, fill: '#3e6630', opacity: .6, transform: `rotate(${a} ${x} ${y})` });
    el('ellipse', { cx: x, cy: y, rx, ry, fill: '#e9dcbc', transform: `rotate(${a} ${x} ${y})` });
  }
  // Sun-grain over everything for an aerial-photo feel
  el('rect', { width: 393, height: 798, fill: '#fff', filter: 'url(#grain)', opacity: .35 });

  // Small hole numbers by each tee
  for (const h of HOLES) {
    const [tx, ty] = h.p[0], [nx, ny] = h.p[1], d = Math.hypot(nx - tx, ny - ty), ox = -(nx - tx) / d * 14, oy = -(ny - ty) / d * 14;
    const g = el('g', { transform: `translate(${tx + ox} ${ty + oy})`, opacity: .9 });
    el('circle', { r: 7.5, fill: 'rgba(8,24,16,.7)', stroke: 'rgba(255,255,255,.7)', 'stroke-width': 1 }, g);
    el('text', { y: 3.5, fill: '#fff', 'font-family': 'Inter', 'font-weight': 700, 'font-size': 9.5, 'text-anchor': 'middle' }, g).textContent = h.n;
  }

  // Groups on the course. t = how far along their hole they are.
  const GROUPS = [{ n: 'Hughes', h: 2, t: .55 }, { n: 'Lopez', h: 3, t: .62, left: true }, { n: 'Rossi', h: 4, t: .35 }, { n: 'Nguyen', h: 6, t: .45 }, { n: 'Patel', h: 8, t: .62 }, { n: 'Ortiz', h: 9, t: .5 }];
  const ME = { h: 5, t: .55 };
  const pins = el('g', {});
  const mk = (gr) => {
    const g = el('g', {}, pins), w = gr.n.length * 7.6 + 18;
    el('circle', { r: 15, fill: '#3b82f6', stroke: '#fff', 'stroke-width': 3 }, g);
    el('text', { y: 5, fill: '#fff', 'font-family': 'Inter', 'font-weight': 700, 'font-size': 14, 'text-anchor': 'middle' }, g).textContent = gr.h;
    const r = el('rect', { y: -13, rx: 13, width: w, height: 26, fill: '#0b1a13', opacity: .85 }, g);
    const tx = el('text', { y: 5, fill: '#fff', 'font-family': 'Inter', 'font-weight': 600, 'font-size': 13 }, g); tx.textContent = gr.n;
    return { ...gr, g, r, tx, w, hole: HOLES[gr.h - 1] };
  };
  const all = GROUPS.map(mk);
  const me = el('g', {}, pins); el('circle', { r: 20, fill: '#f0cf55', opacity: .3 }, me); el('circle', { r: 9, fill: '#f0cf55', stroke: '#fff', 'stroke-width': 3 }, me);
  const meHole = HOLES[ME.h - 1];

  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const SPAN = .22, LOOP = 45; // each group walks about a fifth of its hole, then the loop restarts
  let t0;
  function step(now) {
    t0 ??= now; const k = ((now - t0) / 1000 / LOOP) % 1, fade = Math.min(1, k * 12, (1 - k) * 12);
    for (const d of all) {
      const [x, y] = along(d.hole, d.t + k * SPAN), L = d.left || x > 290;
      d.g.setAttribute('transform', `translate(${x.toFixed(1)} ${y.toFixed(1)})`); d.g.setAttribute('opacity', reduce ? 1 : fade.toFixed(2));
      d.r.setAttribute('x', L ? -(d.w + 19) : 19); d.tx.setAttribute('x', L ? -(d.w + 10) : 28);
    }
    const [mx, my] = along(meHole, ME.t + k * SPAN); me.setAttribute('transform', `translate(${mx.toFixed(1)} ${my.toFixed(1)})`); me.setAttribute('opacity', reduce ? 1 : fade.toFixed(2));
    if (!reduce) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
})();
