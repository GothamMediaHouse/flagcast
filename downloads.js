// One-click installs and updates for the desktop app (Flagcast Manager).
// Builds live as GitHub releases on GothamMediaHouse/flagcast, tagged <app>-v<version>
// (e.g. manager-v1.2.0), made by "Publish Flagcast Manager.command" on the Mac.
//   /download/<app>              → the right installer for this computer (Mac .dmg or Windows .exe)
//   /download/<app>/<mac|win>    → that platform's installer
//   /api/<app>/latest            → { version, date, notes, mac, win } (null when nothing is published)
//   /updates/<app>/<file>        → update feeds: latest*.yml (electron-updater) and appcast.xml (Sparkle) served, other files redirect to the release
const REPO = 'GothamMediaHouse/flagcast';
// (Flagcast Admin is retired: Admin lives inside Manager, so /download/admin and its update feed are gone)
const APPS = { manager: 'Flagcast Manager' };
const TTL = 300; // seconds a GitHub answer is reused

const ver = (t) => (t.match(/-v(\d+)\.(\d+)\.(\d+)/) || []).slice(1).map(Number);
const newer = (a, b) => { for (let i = 0; i < 3; i++) if ((a[i] || 0) !== (b[i] || 0)) return (a[i] || 0) - (b[i] || 0); return 0; };

// newest releases, as [{ tag, date, notes, assets: [{ name, url, size }] }]. The GitHub API is tried first (with
// GITHUB_TOKEN when set); Cloudflare's shared addresses often hit its unsigned rate limit, so when it refuses, the
// public releases feed gives the tags and the asset names come from how the Publish scripts name the files.
async function releases(ctx, env) {
  const key = new Request(`https://flagcast.app/_cache/releases`);
  const cache = caches.default;
  const hit = await cache.match(key);
  if (hit) return hit.json();
  let list = null;
  try {
    const h = { 'User-Agent': 'flagcast-downloads', Accept: 'application/vnd.github+json' };
    if (env && env.GITHUB_TOKEN) h.Authorization = `Bearer ${env.GITHUB_TOKEN}`;
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases?per_page=50`, { headers: h });
    if (r.ok) list = (await r.json()).filter((x) => !x.draft && !x.prerelease).map((x) => ({
      tag: x.tag_name, date: x.published_at, notes: x.body || '',
      assets: (x.assets || []).map((a) => ({ name: a.name, url: a.browser_download_url, size: a.size })),
    }));
  } catch { /* fall through to the feed */ }
  if (!list) {
    const r = await fetch(`https://github.com/${REPO}/releases.atom`, { headers: { 'User-Agent': 'flagcast-downloads' } });
    if (!r.ok) throw new Error(`GitHub feed ${r.status}`);
    const xml = await r.text();
    list = [...xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)].map((m) => {
      const tag = decodeURIComponent((m[1].match(/releases\/tag\/([^"<]+)/) || [])[1] || '');
      const date = (m[1].match(/<updated>([^<]+)/) || [])[1] || '';
      return { tag, date, notes: '', assets: guessAssets(tag) };
    }).filter((x) => x.tag);
  }
  const res = new Response(JSON.stringify(list), { headers: { 'Content-Type': 'application/json', 'Cache-Control': `max-age=${TTL}` } });
  const put = cache.put(key, res.clone());
  if (ctx && ctx.waitUntil) ctx.waitUntil(put); else await put;
  return list;
}

// the files a Publish script uploads for <app>-v<ver> (used when only the feed answered)
function guessAssets(tag) {
  const m = tag.match(/^([a-z]+)-v(\d+\.\d+\.\d+)$/); if (!m || !APPS[m[1]]) return [];
  const n = APPS[m[1]].replace(/ /g, '-'), v = m[2], base = `https://github.com/${REPO}/releases/download/${tag}/`;
  return [`${n}-${v}-universal.dmg`, `${n}-${v}-universal-mac.zip`, `${n}-${v}-universal-mac.zip.blockmap`, `${n}-Setup-${v}.exe`,
    `${n}-Setup-${v}.exe.blockmap`, 'latest-mac.yml', 'latest.yml', 'appcast.xml'].map((name) => ({ name, url: base + name, size: 0 }));
}

async function latest(app, ctx, env) {
  const mine = (await releases(ctx, env)).filter((x) => x.tag.startsWith(`${app}-v`) && ver(x.tag).length === 3);
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
      const file = pick(await latest(p[1], ctx, env), platform);
      if (!file) return Response.redirect(`${url.origin}/download/?soon=${p[1]}`, 302);
      return Response.redirect(file.url, 302);
    }
    if (p[0] === 'api' && APPS[p[1]] && p[2] === 'latest') {
      const rel = await latest(p[1], ctx, env);
      if (!rel) return json({ app: p[1], version: null });
      const m = pick(rel, 'mac'), w = pick(rel, 'win');
      return json({ app: p[1], name: APPS[p[1]], version: ver(rel.tag).join('.'), date: rel.date, notes: rel.notes,
        mac: m && { file: m.name, size: m.size, url: `${url.origin}/download/${p[1]}/mac` },
        win: w && { file: w.name, size: w.size, url: `${url.origin}/download/${p[1]}/win` } });
    }
    if (p[0] === 'updates' && APPS[p[1]] && p[2]) {
      const name = decodeURIComponent(p.slice(2).join('/'));
      const rel = await latest(p[1], ctx, env);
      const file = rel && rel.assets.find((x) => x.name === name);
      if (!file) return new Response('Not found', { status: 404 });
      if (/\.(ya?ml|xml)$/i.test(name)) { // update feeds: latest*.yml (Electron) and appcast.xml (Sparkle, native Mac apps)
        const r = await fetch(file.url, { headers: { 'User-Agent': 'flagcast-downloads' } });
        const type = /\.xml$/i.test(name) ? 'text/xml' : 'text/yaml';
        return new Response(await r.text(), { status: r.status, headers: { 'Content-Type': `${type}; charset=utf-8`, 'Cache-Control': 'no-store' } });
      }
      return Response.redirect(file.url, 302);
    }
  } catch (e) {
    console.log('downloads', e && e.message);
    if (p[0] === 'api') return json({ app: p[1], version: null, busy: true });
    if (p[0] === 'download') return Response.redirect(`${url.origin}/download/?soon=${p[1]}`, 302);
    return json({ error: 'Downloads are busy, try again in a minute.' }, 503);
  }
  return null;
}
