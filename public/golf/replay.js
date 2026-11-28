// Par 3 cameras: play live, rewind, and play replays. Used by the live page (phones) and the screens.
// A replay is either a clip link (.mp4, or an .m3u8 recording) or a mark on the hole's live camera: then the
// camera's own recording window (an HLS stream with DVR, ideally with EXT-X-PROGRAM-DATE-TIME) is played back
// from `back` seconds before the mark was made.
const isHls = (u) => /\.m3u8(\?|$)/.test(u || '');
// Flagcast's NDI cameras (Cloudflare Stream, served by the worker) make a clip of any moment of the broadcast:
// <cam>?from=<ms>&len=<s>. Other cameras are rewound to the moment instead.
const clipCam = (u) => /\/golf\/api\/cam\/[0-9a-f]{32}\/video\.m3u8$/.test(u || '');

// put a stream or clip into a <video>; returns the hls.js player when one is used
export function attach(video, src, { live = true } = {}) {
  detach(video);
  // Safari plays HLS itself (with the stream's clock and rewind); everywhere else hls.js does, so replays line up
  const safari = /^((?!chrome|android|crios|fxios).)*safari/i.test(navigator.userAgent);
  // a live camera that isn't sending yet (a phone that just went live: Cloudflare takes 10–30 seconds to have the
  // first picture) answers 404, and the player gives up for good: keep trying every few seconds until it plays
  // an upright phone sends a tall picture: show all of it (black at the sides) instead of cropping it to fill
  video.onloadedmetadata = () => { video.style.objectFit = video.videoHeight > video.videoWidth ? 'contain' : ''; };
  const again = () => { clearTimeout(video._retry); video._retry = setTimeout(() => { if (video.isConnected) attach(video, src, { live }); }, 4000); };
  if (!isHls(src) || safari || !window.Hls || !Hls.isSupported()) {
    video.src = src;
    if (live) video.onerror = again;
    return null;
  }
  // a big screen (club TVs, a laptop) starts on the sharpest picture and only steps down if it truly can't keep up:
  // with a short live buffer hls.js never measures enough to step up from the small size it guesses at first
  const big = Math.max(screen.width, innerWidth) >= 1000;
  const h = new Hls(live ? { liveSyncDurationCount: 1, liveMaxLatencyDurationCount: 4, maxLiveSyncPlaybackRate: 1.1, backBufferLength: 120,
    abrEwmaDefaultEstimate: big ? 8e6 : 2e6, abrBandWidthUpFactor: 0.9, capLevelToPlayerSize: !big } : {});
  if (live && big) h.on(Hls.Events.MANIFEST_PARSED, (_, d) => { const n = (d && d.levels || h.levels || []).length; if (n) h.startLevel = n - 1; });
  h.loadSource(src); h.attachMedia(video); video._hls = h;
  if (live) h.on(Hls.Events.ERROR, (_, d) => { if (d && d.fatal) again(); });
  return h;
}
export function detach(video) {
  if (video._hls) { try { video._hls.destroy(); } catch {} video._hls = null; }
  clearTimeout(video._stop); video._stop = null;
  clearTimeout(video._retry); video._retry = null; video.onerror = null;
}

const once = (el, ev, ms = 12000) => new Promise((res, rej) => {
  const t = setTimeout(() => { el.removeEventListener(ev, f); rej(new Error('timeout')); }, ms);
  const f = () => { clearTimeout(t); el.removeEventListener(ev, f); res(); };
  el.addEventListener(ev, f);
});

// how far back this camera can rewind, in seconds (0 when it can't)
export function rewindable(video) {
  const s = video.seekable; if (!s || !s.length) return 0;
  const span = s.end(s.length - 1) - s.start(0);
  return Number.isFinite(span) ? Math.max(0, span - 6) : 0;
}
export function liveEdge(video) {
  const s = video.seekable; if (!s || !s.length) return null;
  const e = s.end(s.length - 1); return Number.isFinite(e) ? e - 3 : null;
}
export function goLive(video) { const e = liveEdge(video); if (e != null) video.currentTime = e; video.play().catch(() => {}); }
export function rewind(video, secs) {
  const s = video.seekable; if (!s || !s.length) return false;
  video.currentTime = Math.max(s.start(0) + 1, video.currentTime - secs); video.play().catch(() => {}); return true;
}

// the video time that matches a wall-clock moment, using the stream's program date-time when it has one
function timeFor(video, hls, when) {
  if (hls && hls.levels && hls.levels.length) {
    const lv = hls.levels[Math.max(0, hls.currentLevel)] || hls.levels[0];
    const frags = lv?.details?.fragments || [];
    for (const f of frags) {
      if (f.programDateTime && when >= f.programDateTime && when < f.programDateTime + f.duration * 1000) return f.start + (when - f.programDateTime) / 1000;
    }
    if (frags.length && frags[0].programDateTime) {
      // before the first or after the last fragment
      const first = frags[0], last = frags[frags.length - 1];
      if (when < first.programDateTime) return null;
      return last.start + last.duration + (when - (last.programDateTime + last.duration * 1000)) / 1000;
    }
  }
  if (typeof video.getStartDate === 'function') {
    const d = video.getStartDate(); const t0 = d && d.getTime();
    if (t0 && Number.isFinite(t0)) return (when - t0) / 1000;
  }
  // no clock in the stream: count back from the live edge
  const e = liveEdge(video); return e == null ? null : e + 3 - (Date.now() - when) / 1000;
}

// play one replay in a <video>. Resolves { ok: true } once it's playing, or { ok: false, reason }.
// onEnd runs when a camera replay has played its moment (clip links play to their end).
export async function playReplay(video, r, camUrl, onEnd) {
  try {
    video.muted = true;
    if (r.url) {
      attach(video, r.url, { live: false });
      video.onended = () => onEnd && onEnd();
      await once(video, 'loadeddata'); video.currentTime = 0; await video.play().catch(() => {});
      return { ok: true };
    }
    if (!isHls(camUrl)) return { ok: false, reason: 'This camera can’t be replayed.' };
    if (clipCam(camUrl)) {
      const back = r.back || 25, src = `${camUrl}?from=${Math.round(r.at - back * 1000)}&len=${back + 6}`;
      const chk = await fetch(src, { cache: 'no-store' }).catch(() => null);
      if (!chk || !chk.ok) return { ok: false, reason: (chk && (await chk.json().catch(() => null))?.error) || 'The replay didn’t load. Try again.' };
      attach(video, src, { live: false });
      let ended = false; const end = () => { if (!ended) { ended = true; clearTimeout(video._stop); onEnd && onEnd(); } };
      video.onended = end;
      await once(video, 'loadeddata'); video.currentTime = 0; await video.play().catch(() => {});
      video._stop = setTimeout(end, (back + 8) * 1000); // a clip still being made ends when its last seconds arrive
      return { ok: true };
    }
    const hls = attach(video, camUrl, { live: true });
    await once(video, 'loadedmetadata');
    if (hls) await new Promise((res) => (hls.levels?.[0]?.details ? res() : hls.once(Hls.Events.LEVEL_LOADED, () => res())));
    const from = r.at - (r.back || 25) * 1000;
    const t = timeFor(video, hls, from), s = video.seekable;
    if (t == null || !s.length || t < s.start(0) - 0.5) return { ok: false, reason: 'This replay is older than the camera keeps. Ask for a clip instead.' };
    video.currentTime = Math.min(t, s.end(s.length - 1));
    await video.play().catch(() => {});
    const len = (r.back || 25) + 6;
    video._stop = setTimeout(() => onEnd && onEnd(), len * 1000);
    return { ok: true };
  } catch (e) { return { ok: false, reason: 'The replay didn’t load. Try again.' }; }
}

export const replayTime = (r) => new Date(r.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
