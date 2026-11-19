// Par 3 cameras: play live, rewind, and play replays. Used by the live page (phones) and the screens.
// A replay is either a clip link (.mp4, or an .m3u8 recording) or a mark on the hole's live camera: then the
// camera's own recording window (an HLS stream with DVR, ideally with EXT-X-PROGRAM-DATE-TIME) is played back
// from `back` seconds before the mark was made.
const isHls = (u) => /\.m3u8(\?|$)/.test(u || '');

// put a stream or clip into a <video>; returns the hls.js player when one is used
export function attach(video, src, { live = true } = {}) {
  detach(video);
  // Safari plays HLS itself (with the stream's clock and rewind); everywhere else hls.js does, so replays line up
  const safari = /^((?!chrome|android|crios|fxios).)*safari/i.test(navigator.userAgent);
  if (!isHls(src) || safari || !window.Hls || !Hls.isSupported()) { video.src = src; return null; }
  const h = new Hls(live ? { liveSyncDurationCount: 2, backBufferLength: 120 } : {});
  h.loadSource(src); h.attachMedia(video); video._hls = h;
  return h;
}
export function detach(video) {
  if (video._hls) { try { video._hls.destroy(); } catch {} video._hls = null; }
  clearTimeout(video._stop); video._stop = null;
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
