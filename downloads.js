// One-click installs and updates for the desktop apps (Flagcast Manager, Flagcast Admin).
// Builds live as GitHub releases on GothamMediaHouse/flagcast, tagged <app>-v<version>
// (e.g. manager-v1.2.0), made by "Publish Flagcast Manager.command" on the Mac.
//   /download/<app>              → the right installer for this computer (Mac .dmg or Windows .exe)
//   /download/<app>/<mac|win>    → that platform's installer
//   /api/<app>/latest            → { version, date, notes, mac, win } (null when nothing is published)
//   /updates/<app>/<file>        → electron-updater "generic" feed: latest*.yml served, other files redirect to the release
const REPO = 'GothamMediaHouse/flagcast';
const APPS = { manager: 'Flagcast Manager', admin: 'Flagcast Admin' };
const TTL = 300; // seconds a GitHub answer is reused

const ver = (t) => (t.match(/-v(\d+)\.(\d+)\.(\d+)/) || []).slice(1).map(Number);
const newer = (a, b) => { for (let i = 0; i < 3; i++) if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) - (b[i] || 0); return 0; };

async function releases(ctx) {
  const key = new Request(`https://flagcast.app/_cache/releases`);
  const cache = caches.default;
  const hit = await cache.match(key);
  if (hit) return hit.json();
  const r = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=50`, {
    headers: { 'User-Agent': 'flagcast-downloads', Accept: 'application/vnd.github+json' },
  });
  if (!r.ok) throw new Error(`GitHub ${r.status}`);
  const list = (await r.json()).filter((x) => !x.draft && !x.prerelease).map((x) => ({
    tag: x.tag_name, date: x.published_at, notes: x.body || '',
    assets: (x.assets || []).map((a) => ({ name: a.name, url: a.browser_download_url, size: a.size })),
  }));
  const res = new Response(JSON.stringify(list), { headers: { 'Content-Type': 'application/json', 'Cache-Control': `max-age=${TTL}` } });
  const put = cache.put(key, res.clone());
  if (ctx && ctx.waitUntil) ctx.waitUntil(put); else await put;
  return list;
}

async function latest(app, ctx) {
  const mine = (await releases(ctx)).filter((x) => x.tag.startsWith(`${app}-v`) && ver(x.tag).length === 3);
  mine.sort((a, b) => newer(ver(b.tag), ver(a.tag)));
  return mine[0] || null;
}

function pick(rel, platform) {
  if (!rel) return null;
  const a = rel.assets;
  if (platform === 'win') return a.find((x) => /\.exe$/i.test(x.name)) || null;
  // Mac: one universal .dmg (runs on Apple silicon and Intel); fall back to arm64, then any .dmg
  return a.find((x) => /universal.*\.dmg$/i.test(x.name)) || a.find((x) => /arm64.*\.dmg$/i.test(x.name)) || a.find((x) => /\.dmg$/i.test(x.name)) || null;
}

const platformOf = (ua) => (/Windows/i.test(ua) ? 'win' : /Macintosh|Mac OS X/i.test(ua) && !/iPhone|iPad/i.test(ua) ? 'mac' : null);
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' } });

export async function downloads(request, env, ctx) {
  const url = new URL(request.url);
  const p = url.pathname.split('/').filter(Boolean);
  try {
    if (p[0] === 'download' && APPS[p[1]]) {
      const platform = p[2] || platformOf(request.headers.get('User-Agent') || '');
      if (platform !== 'mac' && platform !== 'win') return Response.redirect(`${url.origin}/download/`, 302);
      const file = pick(await latest(p[1], ctx), platform);
      if (!file) return Response.redirect(`${url.origin}/download/?soon=${p[1]}`, 302);
      return Response.redirect(file.url, 302);
    }
    if (p[0] === 'api' && APPS[p[1]] && p[2] === 'latest') {
      const rel = await latest(p[1], ctx);
      if (!rel) return json({ app: p[1], version: null });
      const m = pick(rel, 'mac'), w = pick(rel, 'win');
      return json({ app: p[1], name: APPS[p[1]], version: ver(rel.tag).join('.'), date: rel.date, notes: rel.notes,
        mac: m && { file: m.name, size: m.size, url: `${url.origin}/download/${p[1]}/mac` },
        win: w && { file: w.name, size: w.size, url: `${url.origin}/download/${p[1]}/win` } });
    }
    if (p[0] === 'updates' && APPS[p[1]] && p[2]) {
      const name = decodeURIComponent(p.slice(2).join('/'));
      const rel = await latest(p[1], ctx);
      const file = rel && rel.assets.find((x) => x.name === name);
      if (!file) return new Response('Not found', { status: 404 });
      if (/\.ya?ml$/i.test(name)) {
        const r = await fetch(file.url, { headers: { 'User-Agent': 'flagcast-downloads' } });
        return new Response(await r.text(), { status: r.status, headers: { 'Content-Type': 'text/yaml; charset=utf-8', 'Cache-Control': 'no-store' } });
      }
      return Response.redirect(file.url, 302);
    }
  } catch (e) {
    return json({ error: 'Downloads are busy, try again in a minute.' }, 503);
  }
  return null;
}
