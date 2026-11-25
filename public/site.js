// flagcast.app: gentle motion. Content is fully visible without this script or with reduced motion.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (reduce || !('IntersectionObserver' in window)) return;
  document.documentElement.classList.add('anim');

  // 1. Ease sections in as they scroll into view, siblings one after another
  const groups = [
    '.steps > *', '.feat > .f', '.modes > .mode', '.pk > *', '.fgrid > li', '.hubcards > a', '.nlinks > a',
    '.plats > div', '.tvlist > li', '.ticks > li', '.mock .mr', '.pins > div', '.codes > div', '.sh-r', '.cb-r',
    '.gtable > div', '.fv-ld .row', '.split > *', '.addons'
  ];
  const singles = ['section h2', 'section .lede', '.rvis', '.show', '.clubtv', '.mgr-vis', '.app-grid .phones', '.thermo', '.photo-pair', '.photo-band'];
  const seen = new Set();
  for (const sel of groups) document.querySelectorAll(sel).forEach((el) => {
    if (seen.has(el)) return; seen.add(el);
    const i = [...el.parentNode.children].indexOf(el);
    el.classList.add('rv'); el.style.setProperty('--d', Math.min(i, 8) * 70 + 'ms');
  });
  for (const sel of singles) document.querySelectorAll(sel).forEach((el) => { if (!seen.has(el) && !el.closest('.phero,.fhero,.hero')) { seen.add(el); el.classList.add('rv'); } });
  const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }), { rootMargin: '0px 0px -8% 0px' });
  document.querySelectorAll('.rv').forEach((el) => io.observe(el));

  // run fn while el is on screen
  const whileSeen = (el, start, stop) => {
    let on = false;
    new IntersectionObserver(([e]) => { if (e.isIntersecting && !on) { on = true; start(); } else if (!e.isIntersecting && on) { on = false; stop && stop(); } }).observe(el);
  };
  const NS = 'http://www.w3.org/2000/svg';

  // 2. Fly the hole: a ball flies the line of play, tee to green
  document.querySelectorAll('.fv-fly svg').forEach((svg, k) => {
    const path = svg.querySelector('path[stroke-dasharray]'); if (!path) return;
    path.id = path.id || 'flyline' + k;
    const ball = document.createElementNS(NS, 'circle');
    ball.setAttribute('r', '7'); ball.setAttribute('fill', '#fff'); ball.setAttribute('stroke', '#e8c547'); ball.setAttribute('stroke-width', '3');
    const mo = document.createElementNS(NS, 'animateMotion');
    mo.setAttribute('dur', '4.5s'); mo.setAttribute('repeatCount', 'indefinite'); mo.setAttribute('keyPoints', '0;1;1'); mo.setAttribute('keyTimes', '0;.8;1'); mo.setAttribute('calcMode', 'spline'); mo.setAttribute('keySplines', '.45 0 .25 1;0 0 1 1');
    const mp = document.createElementNS(NS, 'mpath'); mp.setAttribute('href', '#' + path.id);
    mo.appendChild(mp); ball.appendChild(mo); svg.appendChild(ball);
  });

  // 3. Everyone on the map: groups creep round the course
  document.querySelectorAll('.fv-map svg').forEach((svg) => {
    const e = svg.querySelector('ellipse'); if (!e) return;
    const cx = +e.getAttribute('cx'), cy = +e.getAttribute('cy'), rx = +e.getAttribute('rx'), ry = +e.getAttribute('ry');
    const dots = [...svg.querySelectorAll('g[transform^="translate"]')].map((g) => {
      const [x, y] = g.getAttribute('transform').match(/-?[\d.]+/g).map(Number);
      return { g, a: Math.atan2((y - cy) / ry, (x - cx) / rx) };
    });
    let raf, t0;
    const step = (t) => {
      t0 ??= t; const da = (t - t0) / 1000 * 0.05;
      for (const d of dots) d.g.setAttribute('transform', `translate(${(cx + rx * Math.cos(d.a + da)).toFixed(1)} ${(cy + ry * Math.sin(d.a + da)).toFixed(1)})`);
      raf = requestAnimationFrame(step);
    };
    whileSeen(svg, () => { raf = requestAnimationFrame((t) => { t0 = null; step(t); }); }, () => cancelAnimationFrame(raf));
  });

  // 4. Yards to the pin count down as you walk up
  document.querySelectorAll('.fv-green svg, .hp svg').forEach((svg) => {
    const texts = [...svg.querySelectorAll('text')];
    const big = texts.find((t) => /^\d+$/.test(t.textContent.trim()));
    const back = texts.find((t) => /^BACK \d+/.test(t.textContent)), front = texts.find((t) => /^FRONT \d+/.test(t.textContent));
    if (!big) return;
    const end = { big: +big.textContent, back: back && +back.textContent.split(' ')[1], front: front && +front.textContent.split(' ')[1] };
    const run = () => {
      const from = 60, t0 = performance.now(), dur = 2200;
      const tick = (t) => {
        const p = Math.min(1, (t - t0) / dur), add = Math.round(from * (1 - (1 - p) ** 3));
        const off = from - add;
        big.textContent = end.big + off;
        if (back) back.textContent = 'BACK ' + (end.back + off);
        if (front) front.textContent = 'FRONT ' + (end.front + off);
        if (p < 1) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    };
    let done = false; whileSeen(svg, () => { if (!done) { done = true; run(); } });
  });

  // 5. Long drive entry: "With the pro" turns into "Checked"
  document.querySelectorAll('.fv-ld').forEach((box) => {
    const pill = box.querySelector('.wait'); if (!pill) return;
    let iv; const flip = () => { const ok = pill.classList.toggle('wait'); pill.textContent = ok ? 'With the pro' : 'Checked'; pill.classList.add('pop'); setTimeout(() => pill.classList.remove('pop'), 400); };
    whileSeen(box, () => { iv = setInterval(flip, 2600); }, () => clearInterval(iv));
  });

  // 6. Lock screen: the score moves as the group plays
  document.querySelectorAll('.fv-lock').forEach((box) => {
    const sc = box.querySelector('.sc'), b = box.querySelector('.la b'), sm = box.querySelector('.la small'); if (!sc || !b) return;
    const st = [['−4', 'Through 11 · 3rd', 'Net flight · Hole 12 next'], ['−5', 'Through 12 · 2nd', 'Net flight · Hole 13 next'], ['−5', 'Through 13 · T2', 'Net flight · Hole 14 next'], ['−6', 'Through 14 · 1st', 'Net flight · Hole 15 next']];
    let i = 0, iv;
    const go = () => { i = (i + 1) % st.length; const [s, l1, l2] = st[i]; sc.firstChild.textContent = s; b.textContent = l1; sm.textContent = l2; const la = box.querySelector('.la'); la.classList.remove('bump'); void la.offsetWidth; la.classList.add('bump'); };
    whileSeen(box, () => { iv = setInterval(go, 2800); }, () => clearInterval(iv));
  });

  // 7. Side games: a new hole changes the standings
  document.querySelectorAll('.fv-games .gtable').forEach((tb) => {
    const em = [...tb.querySelectorAll('em')]; if (em.length < 3) return;
    const base = em.map((e) => parseInt(e.textContent, 10)); let k = 0, iv;
    const go = () => { k = (k + 1) % 4; em.forEach((e, j) => { const v = base[j] + [0, 1, 2, 2][k] * [2, 3, 2][j]; e.textContent = v + ' pts'; }); tb.classList.remove('bump'); void tb.offsetWidth; tb.classList.add('bump'); };
    whileSeen(tb, () => { iv = setInterval(go, 2400); }, () => { clearInterval(iv); });
  });

  // 8. App screens: swap the phone pictures for live screens that move (the picture stays underneath until it loads)
  const SCREENS = { 'app-scorecard.jpg': 'score', 'app-leaderboard.jpg': 'leaders', 'app-par3.jpg': 'cams', 'app-course.jpg': 'course' };
  document.querySelectorAll('.ph2 img, .ph img').forEach((img) => {
    const name = SCREENS[(img.getAttribute('src') || '').split('/').pop()]; if (!name) return;
    const box = document.createElement('span'); box.className = 'scrn';
    img.replaceWith(box); box.appendChild(img);
    const f = document.createElement('iframe');
    f.src = '/app-screens/' + name + '.html'; f.loading = 'lazy'; f.title = img.alt || 'The Flagcast app'; f.tabIndex = -1; f.setAttribute('aria-hidden', 'true'); f.scrolling = 'no';
    f.onload = () => f.classList.add('ok');
    box.appendChild(f);
    const fit = () => { f.style.transform = `scale(${box.clientWidth / 393})`; };
    new ResizeObserver(fit).observe(box); fit();
  });
})();
