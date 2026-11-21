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

/** The HLS address phones and the live page play for a live input. */
export const playbackURL = (uid) => `https://videodelivery.net/${uid}/manifest/video.m3u8`;

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
  for (const v of videos || []) { try { await call(env, fetcher, 'DELETE', `/${encodeURIComponent(v.uid)}`); } catch (e) { if (e.status !== 404) throw e; } }
  try { await call(env, fetcher, 'DELETE', `/live_inputs/${encodeURIComponent(uid)}`); } catch (e) { if (e.status !== 404) throw e; }
  return (videos || []).length;
}
