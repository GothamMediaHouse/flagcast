// Cloudflare Stream Live for NDI cameras: the Mac Manager (Flagcast Admin) receives a par 3 camera over NDI on the
// club's network and pushes it here by RTMPS, so phones, the live page and replays get it too (clubhouse TVs play the
// Mac's local copy first). One live input per tournament hole, reused, recorded (DVR for replays).
//
// Needs two worker secrets Flagcast adds in the Cloudflare dashboard: CF_ACCOUNT_ID and CF_STREAM_TOKEN (an API token
// with Stream:Edit). Without them the apps say Stream isn't set up and keep using camera links.
// No Worker-only imports: test/stream.test.mjs runs it in Node with the Stream API mocked.

const API = 'https://api.cloudflare.com/client/v4';

export const streamReady = (env) => !!(env.CF_ACCOUNT_ID && env.CF_STREAM_TOKEN);

async function call(env, fetcher, method, path, body) {
  const r = await fetcher(`${API}/accounts/${env.CF_ACCOUNT_ID}/stream${path}`, {
    method, headers: { Authorization: `Bearer ${env.CF_STREAM_TOKEN}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.success === false) {
    const e = new Error((j.errors && j.errors[0] && j.errors[0].message) || `Cloudflare Stream answered ${r.status}`);
    e.status = r.status; throw e;
  }
  return j.result;
}

/**
 * The HLS address phones and the live page play for a live input: Flagcast's own (see camPlaylist), because
 * Cloudflare's live HLS only keeps the last ~16 seconds, too short to rewind or replay a par 3 shot.
 */
export const playbackURL = (uid, origin = 'https://flagcast.app') => `${origin}/golf/api/cam/${uid}/video.m3u8`;
/** the live input id in one of those addresses, or null */
export const camUid = (url) => (String(url || '').match(/\/golf\/api\/cam\/([0-9a-f]{32})\/video\.m3u8(?:\?|$)/) || [])[1] || null;

/**
 * The live input for one tournament hole: the one we made before (uid) if it still exists, else a new one, recorded.
 * → { uid, rtmps: { url, streamKey }, playback }
 */
export async function liveInput(env, fetcher, { uid, name }) {
  let input = null;
  if (uid) {
    try { input = await call(env, fetcher, 'GET', `/live_inputs/${encodeURIComponent(uid)}`); }
    catch (e) { if (e.status !== 404) throw e; }
  }
  if (!input) {
    input = await call(env, fetcher, 'POST', '/live_inputs', {
      meta: { name: String(name || 'Flagcast camera').slice(0, 120) },
      recording: { mode: 'automatic', timeoutSeconds: 0, requireSignedURLs: false },
    });
  }
  return { uid: input.uid, rtmps: { url: input.rtmps?.url || '', streamKey: input.rtmps?.streamKey || '' }, playback: playbackURL(input.uid) };
}

/** Is the camera sending? → 'connected' | 'disconnected' | 'unknown' */
export async function inputState(env, fetcher, uid) {
  try {
    const i = await call(env, fetcher, 'GET', `/live_inputs/${encodeURIComponent(uid)}`);
    const s = i.status?.current?.state || i.status?.current?.ingestProtocol && 'connected';
    return s === 'connected' ? 'connected' : s ? 'disconnected' : 'unknown';
  } catch { return 'unknown'; }
}

/** Remove a hole's live input and its recordings (they use Stream storage minutes). */
export async function deleteInput(env, fetcher, uid) {
  let videos = [];
  try { videos = await call(env, fetcher, 'GET', `/live_inputs/${encodeURIComponent(uid)}/videos`); } catch (e) { if (e.status !== 404) throw e; }
  // a recording Cloudflare is still finishing (the camera stopped seconds ago) can't be deleted yet: it answers 501
  for (const v of videos || []) { try { await call(env, fetcher, 'DELETE', `/${encodeURIComponent(v.uid)}`); } catch (e) { if (e.status === 501) throw Object.assign(new Error('Cloudflare is still finishing this camera’s last recording. Try again in a minute.'), { status: 501 }); if (e.status !== 404) throw e; } }
  try { await call(env, fetcher, 'DELETE', `/live_inputs/${encodeURIComponent(uid)}`); } catch (e) { if (e.status !== 404) throw e; }
  return (videos || []).length;
}

/** Everything on the Stream account, for Flagcast Admin to find leftovers: live inputs and recordings */
export async function listAll(env, fetcher) {
  const [inputs, videos] = await Promise.all([call(env, fetcher, 'GET', '/live_inputs'), call(env, fetcher, 'GET', '')]);
  return {
    inputs: (inputs || []).map((i) => ({ uid: i.uid, name: i.meta?.name || '', created: i.created || '', state: i.status?.current?.state || '' })),
    videos: (videos || []).map((v) => ({ uid: v.uid, name: v.meta?.name || '', input: v.liveInput || '', created: v.created || '', secs: Math.round(v.duration || 0), state: v.status?.state || '' })),
  };
}
/** delete one recording */
export async function deleteVideo(env, fetcher, uid) {
  try { await call(env, fetcher, 'DELETE', `/${encodeURIComponent(uid)}`); }
  catch (e) { if (e.status === 501) throw Object.assign(new Error('Cloudflare is still finishing this recording. Try again in a minute.'), { status: 501 }); if (e.status !== 404) throw e; }
}

// ---- Flagcast's HLS for a Stream camera --------------------------------------------------------------------------
// Cloudflare's DASH manifest for a live input lists the whole broadcast from segment 1 with exact timing, and every
// segment stays fetchable, though its HLS only lists the last few. So Flagcast serves HLS made from the DASH manifest:
//   live:  the last WINDOW seconds, with the wall clock on segments (EXT-X-PROGRAM-DATE-TIME), so phones can go back
//          30 s and a replay mark plays from the right moment;
//   clip:  ?from=<ms>&len=<s> → that stretch of the broadcast on its own (replays of any age while it's still going).
// Segments are fetched from Cloudflare directly (they allow any origin and are cached for days).

export const WINDOW = 150; // seconds of live picture to rewind into (replays reach back up to 120 s)
const MPD = (uid) => `https://videodelivery.net/${uid}/manifest/video.mpd`;
const attr = (tag, name) => { const m = tag.match(new RegExp(`\\s${name}="([^"]*)"`)); return m ? m[1].replace(/&amp;/g, '&') : ''; };

/** The tracks in a live DASH manifest: { start (ms), tracks: [{ kind, id, bw, codecs, w, h, fps, init, segs: [{ n, t, d, url }] }] } */
export function parseMpd(xml, base) {
  const start = Date.parse(attr(xml.match(/<MPD[^>]*>/)?.[0] || '', 'availabilityStartTime'));
  const tracks = [];
  for (const set of xml.split(/<AdaptationSet/).slice(1)) {
    const kind = /mimeType="audio/.test(set) ? 'audio' : /mimeType="video/.test(set) ? 'video' : '';
    if (!kind) continue;
    for (const rep of set.split(/<Representation/).slice(1)) {
      const head = '<r' + rep.slice(0, rep.indexOf('>') + 1), tpl = rep.match(/<SegmentTemplate[^>]*>/)?.[0] || '';
      const scale = +attr(tpl, 'timescale') || 1, first = +attr(tpl, 'startNumber') || 1, media = attr(tpl, 'media');
      const segs = []; let n = first, t = 0;
      for (const s of rep.match(/<S\s[^>]*>/g) || []) {
        if (attr(s, 't')) t = +attr(s, 't');
        const d = +attr(s, 'd'); for (let i = 0; i <= (+attr(s, 'r') || 0); i++) { segs.push({ n, t: t / scale, d: d / scale, url: new URL(media.replace('$Number$', n), base).href }); n++; t += d; }
      }
      const fr = attr(head, 'frameRate').split('/');
      tracks.push({ kind, id: attr(head, 'id'), bw: +attr(head, 'bandwidth') || 0, codecs: attr(head, 'codecs'), w: +attr(head, 'width') || 0, h: +attr(head, 'height') || 0,
        fps: fr[0] ? +fr[0] / (+fr[1] || 1) : 0, init: new URL(attr(tpl, 'initialization'), base).href, segs });
    }
  }
  return { start, tracks };
}

const q = (o) => (o.from ? `?from=${o.from}&len=${o.len}` : '');

/** the master playlist: every picture size, and the camera's sound */
export function masterPlaylist(mpd, o = {}) {
  const audio = mpd.tracks.find((t) => t.kind === 'audio');
  const out = ['#EXTM3U', '#EXT-X-VERSION:7', '#EXT-X-INDEPENDENT-SEGMENTS'];
  if (audio) out.push(`#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="Camera",DEFAULT=YES,AUTOSELECT=YES,URI="a${audio.id}.m3u8${q(o)}"`);
  for (const v of mpd.tracks.filter((t) => t.kind === 'video').sort((a, b) => b.bw - a.bw)) {
    out.push(`#EXT-X-STREAM-INF:BANDWIDTH=${v.bw + (audio?.bw || 0)},RESOLUTION=${v.w}x${v.h},CODECS="${[v.codecs, audio?.codecs].filter(Boolean).join(',')}"${v.fps ? `,FRAME-RATE=${v.fps.toFixed(3)}` : ''}${audio ? ',AUDIO="a"' : ''}`, `v${v.id}.m3u8${q(o)}`);
  }
  return out.join('\n') + '\n';
}

/** one track's playlist: live (the last WINDOW seconds) or a clip. → { body, done } or null when that stretch isn't there */
export function mediaPlaylist(mpd, track, o = {}) {
  let segs = track.segs, clip = !!o.from;
  if (clip) {
    const a = (o.from - mpd.start) / 1000, b = a + o.len;
    if (!segs.length || a < segs[0].t - 1 || a > segs[segs.length - 1].t + segs[segs.length - 1].d) return null;
    segs = segs.filter((s) => s.t + s.d > a && s.t < b);
  } else {
    const end = segs.length ? segs[segs.length - 1].t + segs[segs.length - 1].d : 0;
    segs = segs.filter((s) => s.t + s.d > end - WINDOW);
  }
  if (!segs.length) return null;
  const last = segs[segs.length - 1], done = clip && last.t + last.d >= (o.from - mpd.start) / 1000 + o.len - 0.05;
  const out = ['#EXTM3U', '#EXT-X-VERSION:7', `#EXT-X-TARGETDURATION:${Math.ceil(Math.max(...segs.map((s) => s.d)))}`, `#EXT-X-MEDIA-SEQUENCE:${segs[0].n}`];
  if (clip) out.push(`#EXT-X-PLAYLIST-TYPE:${done ? 'VOD' : 'EVENT'}`);
  out.push('#EXT-X-INDEPENDENT-SEGMENTS', `#EXT-X-MAP:URI="${track.init}"`);
  segs.forEach((s, i) => {
    if (i % 10 === 0) out.push(`#EXT-X-PROGRAM-DATE-TIME:${new Date(mpd.start + s.t * 1000).toISOString()}`);
    out.push(`#EXTINF:${s.d.toFixed(3)},`, s.url);
  });
  if (done) out.push('#EXT-X-ENDLIST');
  return { body: out.join('\n') + '\n', done };
}

/**
 * GET /golf/api/cam/<uid>/<file>.m3u8 → the Response. file is 'video' (master) or v<id>/a<id> (a track).
 * The caller checks the uid is one of Flagcast's cameras first.
 */
export async function camPlaylist(fetcher, uid, file, params) {
  const hdr = (ttl) => ({ 'Content-Type': 'application/vnd.apple.mpegurl', 'Cache-Control': `public, max-age=${ttl}`, 'Access-Control-Allow-Origin': '*' });
  const none = (msg, status = 404) => new Response(JSON.stringify({ error: msg }), { status, headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'max-age=2' } });
  const from = Math.round(+params.get('from') || 0), len = Math.min(180, Math.max(2, +params.get('len') || 30));
  const o = from > 1e12 ? { from, len } : {};
  const r = await fetcher(MPD(uid), { cf: { cacheTtl: 1 } });
  if (r.status !== 200) return none(r.status === 204 || r.status === 404 ? 'This camera isn’t sending right now.' : 'The camera didn’t answer. Try again.', r.status === 204 || r.status === 404 ? 404 : 502);
  const mpd = parseMpd(await r.text(), MPD(uid));
  if (!Number.isFinite(mpd.start) || !mpd.tracks.length) return none('This camera isn’t sending right now.');
  if (file === 'video') {
    const v = mpd.tracks.find((t) => t.kind === 'video');
    if (o.from && !mediaPlaylist(mpd, v, o)) return none('This replay is older than this broadcast. Ask for a clip instead.');
    return new Response(masterPlaylist(mpd, o), { headers: hdr(o.from ? 30 : 2) });
  }
  const track = mpd.tracks.find((t) => (t.kind === 'audio' ? 'a' : 'v') + t.id === file);
  if (!track) return none('That picture size is gone. Reload the camera.');
  const pl = mediaPlaylist(mpd, track, o);
  if (!pl) return none(o.from ? 'This replay is older than this broadcast. Ask for a clip instead.' : 'This camera isn’t sending right now.');
  return new Response(pl.body, { headers: hdr(pl.done ? 86400 : 1) });
}
