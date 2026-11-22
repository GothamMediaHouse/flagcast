// The course in 3D on the web, and "Fly the hole" / "Fly every hole" (the Mac Manager's Course map). MapLibre GL draws
// the same satellite pictures as the flat map (Esri) on free terrain heights (Mapzen Terrarium on AWS), and the camera
// follows flypath.js, the same line as the players' app. Loaded only when 3D is switched on.
import { TILES, TILE_CREDIT } from '/golf/gps.js';
import { makePath, holePath, green, C } from '/golf/flypath.js';

const LIB = 'https://cdnjs.cloudflare.com/ajax/libs/maplibre-gl/4.7.1/maplibre-gl.min.js';
const CSS = 'https://cdnjs.cloudflare.com/ajax/libs/maplibre-gl/4.7.1/maplibre-gl.min.css';
const DEM = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png';
let loading;
function load() {
  if (window.maplibregl) return Promise.resolve(window.maplibregl);
  if (!loading) loading = new Promise((ok, no) => {
    const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = CSS; document.head.appendChild(l);
    const s = document.createElement('script'); s.src = LIB; s.onload = () => ok(window.maplibregl); s.onerror = () => no(new Error('The 3D map didn’t load. Check the internet connection.')); document.head.appendChild(s);
  });
  return loading;
}
const ll = (p) => [p[1], p[0]];
const FOV = 36.87; // MapLibre's camera field of view (degrees)

/**
 * open3D(box, { holes: () => map holes, card: (n) => ({ par, yds }), onHole(n) })
 * → { show(n), flyHole(n), flyEvery(list), stop(), flying, destroy() }
 */
export async function open3D(box, opt) {
  const ml = await load();
  const map = new ml.Map({
    container: box, maxPitch: 85, attributionControl: { compact: true },
    style: { version: 8, sources: {
      sat: { type: 'raster', tiles: [TILES], tileSize: 256, maxzoom: 19, attribution: TILE_CREDIT },
      dem: { type: 'raster-dem', tiles: [DEM], tileSize: 256, maxzoom: 14, encoding: 'terrarium', attribution: 'Terrain: Mapzen, AWS' },
    }, layers: [{ id: 'sat', type: 'raster', source: 'sat' }], terrain: { source: 'dem', exaggeration: 1 } },
    center: [-98.35, 39.5], zoom: 3, pitch: 60,
  });
  map.addControl(new ml.NavigationControl({ visualizePitch: true }), 'top-right');
  await new Promise((r) => map.once('load', r));
  map.addSource('hole', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
  map.addLayer({ id: 'hole', type: 'line', source: 'hole', paint: { 'line-color': '#ffffff', 'line-width': 2, 'line-opacity': 0.85 } });
  map.addLayer({ id: 'pts', type: 'circle', source: 'hole', filter: ['==', '$type', 'Point'], paint: { 'circle-radius': 6, 'circle-color': ['get', 'c'], 'circle-stroke-color': '#fff', 'circle-stroke-width': 2 } });

  // the hole's name card, bottom left, while the camera leaves the tee
  const card = document.createElement('div');
  card.style.cssText = 'position:absolute;left:28px;bottom:34px;color:#fff;font-family:Georgia,serif;font-style:italic;text-shadow:0 1px 8px rgba(0,0,0,.55);opacity:0;transition:opacity .6s,transform .6s;transform:translateX(-14px);pointer-events:none;z-index:2';
  box.appendChild(card);
  const showCard = (n) => {
    const c = opt.card(n) || {}; const h = opt.holes()[n]; const g = green(h);
    const y = c.yds || (h?.tee && g ? Math.round(makePath(h).totalYds) : 0);
    card.innerHTML = `<div style="font-size:40px;font-weight:700;line-height:1.1">Hole ${n}</div>${y ? `<div style="font-size:17px;font-weight:600">${y} Yards</div>` : ''}${c.par ? `<div style="font-size:17px;font-weight:600">Par ${c.par}</div>` : ''}`;
    card.style.opacity = '1'; card.style.transform = 'none';
  };
  const hideCard = () => { card.style.opacity = '0'; card.style.transform = 'translateX(-14px)'; };

  function drawHole(n) {
    const h = opt.holes()[n], g = green(h), f = [];
    if (h?.tee && g) f.push({ type: 'Feature', geometry: { type: 'LineString', coordinates: holePath(h, h.tee, g).map(ll) } });
    if (h?.tee) f.push({ type: 'Feature', properties: { c: '#e8c547' }, geometry: { type: 'Point', coordinates: ll(h.tee) } });
    if (g) f.push({ type: 'Feature', properties: { c: '#c8312b' }, geometry: { type: 'Point', coordinates: ll(g) } });
    map.getSource('hole').setData({ type: 'FeatureCollection', features: f });
  }
  // MapLibre places its camera by zoom: the zoom that puts it `metres` from what it looks at
  const zoomFor = (lat, metres) => {
    const H = map.getCanvas().clientHeight || 600, half = Math.tan(FOV / 2 * Math.PI / 180);
    return Math.log2(40075016.686 * Math.cos(lat * Math.PI / 180) * (H / 2) / (half * 512 * metres));
  };
  const cam = (c) => ({ center: ll(c.at), bearing: c.heading, pitch: c.pitch, zoom: zoomFor(c.at[0], c.metres) });

  /** the whole hole, from behind the tee, pulled back */
  function show(n) {
    drawHole(n);
    const p = makePath(opt.holes()[n]); if (!p) return;
    const mid = p.path[Math.floor(p.path.length / 2)];
    map.easeTo({ center: ll(mid), bearing: makePath(opt.holes()[n]).camera(0).heading, pitch: 55, zoom: zoomFor(mid[0], Math.max(350, p.totalYds * 1.3)), duration: 1200 });
  }

  let run = 0, timers = [];
  const clearCard = () => { timers.forEach(clearTimeout); timers = []; hideCard(); };
  const api = { flying: false };
  const frame = (fn) => new Promise((r) => requestAnimationFrame((t) => r(fn(t))));
  async function fly(n, cut) {
    const me = run; clearCard();
    const h = opt.holes()[n], p = makePath(h); if (!p) return;
    drawHole(n); opt.onHole?.(n);
    const tee = p.camera(0);
    if (cut) { map.jumpTo(cam(tee)); await new Promise((r) => setTimeout(r, 600)); }
    else { map.easeTo({ ...cam(tee), duration: 1800, easing: (t) => t * t * (3 - 2 * t) }); await new Promise((r) => setTimeout(r, 1850)); }
    if (me !== run) return;
    timers.push(setTimeout(() => showCard(n), 500), setTimeout(hideCard, 6000));
    const begin = performance.now();
    while (me === run) {
      const t = (performance.now() - begin) / 1000;
      if (t > p.totalSecs) break;
      await frame(() => map.jumpTo(cam(p.camera(t))));
    }
    if (me === run) clearCard();
  }
  api.show = show;
  api.flyHole = async (n) => { const me = ++run; api.flying = true; await fly(n, false); if (me === run) api.flying = false; };
  api.flyEvery = async (list) => {
    const me = ++run; api.flying = true;
    for (const n of list) { if (me !== run) break; await fly(n, true); }
    if (me === run) { api.flying = false; show(list[list.length - 1]); }
  };
  api.stop = () => { run++; api.flying = false; clearCard(); };
  api.destroy = () => { run++; map.remove(); };
  api.C = C;
  return api;
}
