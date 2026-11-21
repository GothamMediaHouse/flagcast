// Cloudflare Stream Live for NDI cameras (stream.js), with the Stream API mocked.  node test/stream.test.mjs
import assert from 'node:assert/strict';
import { streamReady, liveInput, inputState, playbackURL, deleteInput, camUid, parseMpd, camPlaylist, WINDOW } from '../stream.js';

let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const env = { CF_ACCOUNT_ID: 'acct123', CF_STREAM_TOKEN: 'tok-test' };

// a pretend Stream API: remembers live inputs, records every call
function mock() {
  const inputs = {}, calls = [];
  let next = 1;
  const fetcher = async (url, init = {}) => {
    calls.push({ url, method: init.method || 'GET', auth: init.headers?.Authorization, body: init.body ? JSON.parse(init.body) : null });
    const m = url.match(/\/accounts\/(\w+)\/stream\/live_inputs(?:\/([^/?]+))?$/);
    const res = (status, body) => ({ ok: status < 300, status, json: async () => body });
    if (!m || m[1] !== 'acct123') return res(404, { success: false, errors: [{ message: 'not found' }] });
    if ((init.method || 'GET') === 'POST') {
      const uid = `uid${next++}`;
      inputs[uid] = { uid, meta: JSON.parse(init.body).meta, recording: JSON.parse(init.body).recording, rtmps: { url: 'rtmps://live.cloudflare.com:443/live/', streamKey: `key-${uid}` }, status: null };
      return res(200, { success: true, result: inputs[uid] });
    }
    const i = inputs[decodeURIComponent(m[2] || '')];
    return i ? res(200, { success: true, result: i }) : res(404, { success: false, errors: [{ message: 'Live input not found' }] });
  };
  return { fetcher, inputs, calls };
}

assert.equal(streamReady({}), false); assert.equal(streamReady({ CF_ACCOUNT_ID: 'a' }), false); assert.equal(streamReady(env), true);
ok('Stream is only on when both secrets are set');

let m = mock();
const a = await liveInput(env, m.fetcher, { name: 'Member-Guest · hole 7' });
assert.equal(a.uid, 'uid1'); assert.equal(a.rtmps.streamKey, 'key-uid1'); assert.equal(a.playback, playbackURL('uid1'));
assert.equal(m.calls[0].method, 'POST'); assert.equal(m.calls[0].auth, 'Bearer tok-test');
assert.equal(m.calls[0].body.recording.mode, 'automatic'); assert.equal(m.calls[0].body.meta.name, 'Member-Guest · hole 7');
ok('a new hole gets a recorded live input (RTMPS address, key, HLS playback)');

const again = await liveInput(env, m.fetcher, { uid: 'uid1', name: 'x' });
assert.equal(again.uid, 'uid1'); assert.equal(Object.keys(m.inputs).length, 1); assert.equal(m.calls.at(-1).method, 'GET');
ok('the same hole reuses its live input');

const gone = await liveInput(env, m.fetcher, { uid: 'deleted-uid', name: 'y' });
assert.equal(gone.uid, 'uid2');
ok('a live input deleted in Cloudflare is made again');

assert.equal(await inputState(env, m.fetcher, 'uid1'), 'unknown');
m.inputs.uid1.status = { current: { state: 'connected' } }; assert.equal(await inputState(env, m.fetcher, 'uid1'), 'connected');
m.inputs.uid1.status = { current: { state: 'disconnected' } }; assert.equal(await inputState(env, m.fetcher, 'uid1'), 'disconnected');
assert.equal(await inputState(env, m.fetcher, 'nope'), 'unknown');
ok('upload health: connected / disconnected / unknown');

// deleting: recordings first, then the input (mock: /videos lists two recordings)
{
  const calls = [];
  const f = async (url, init = {}) => {
    calls.push(`${init.method || 'GET'} ${url.replace(/^.*\/stream/, '')}`);
    const res = (body) => ({ ok: true, status: 200, json: async () => ({ success: true, result: body }) });
    if (url.endsWith('/live_inputs/uidX/videos')) return res([{ uid: 'v1' }, { uid: 'v2' }]);
    return res(null);
  };
  assert.equal(await deleteInput(env, f, 'uidX'), 2);
  assert.deepEqual(calls, ['GET /live_inputs/uidX/videos', 'DELETE /v1', 'DELETE /v2', 'DELETE /live_inputs/uidX']);
}
ok('removing a hole deletes its recordings and its live input');
{
  const f = async (url, init = {}) => url.endsWith('/videos') ? { ok: true, status: 200, json: async () => ({ success: true, result: [{ uid: 'v1' }] }) }
    : { ok: false, status: 501, json: async () => ({ success: false, errors: [{ message: 'Not Implemented: Feature not supported' }] }) };
  await assert.rejects(deleteInput(env, f, 'uidX'), /still finishing .* Try again in a minute/);
}
ok('a recording still being finished: try again in a minute');

await assert.rejects(liveInput({ ...env, CF_ACCOUNT_ID: 'wrong' }, m.fetcher, { name: 'z' }), /not found/);
ok('Stream errors come back as messages');

// ---- Flagcast's own playlists, made from Cloudflare's DASH manifest (the shape a live input really serves)
const U = '0123456789abcdef0123456789abcdef', VID = 'fedcba9876543210fedcba9876543210';
const mpdXml = (count, start = '2026-11-21T17:00:00.000Z') => `<?xml version="1.0" encoding="utf-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="dynamic" availabilityStartTime="${start}" maxSegmentDuration="PT2.023S"><Period id="0" start="PT0.0S">
<AdaptationSet id="1" mimeType="video/mp4"><Representation id="21" bandwidth="2894910" codecs="avc1.64001f" frameRate="30/1" height="720" width="1280">
<SegmentTemplate timescale="30000" startNumber="1" initialization="../../${VID}/video/720/init.mp4?p=abc&amp;s=sig" media="../../${VID}/video/720/seg_$Number$.mp4?p=abc&amp;s=sig">
<SegmentTimeline><S d="60690" /><S d="60000" r="${count - 2}" /></SegmentTimeline></SegmentTemplate></Representation>
<Representation id="22" bandwidth="578982" codecs="avc1.4d401e" frameRate="30/1" height="360" width="640">
<SegmentTemplate timescale="30000" startNumber="1" initialization="../../${VID}/video/360/init.mp4?p=x" media="../../${VID}/video/360/seg_$Number$.mp4?p=x">
<SegmentTimeline><S d="60690" /><S d="60000" r="${count - 2}" /></SegmentTimeline></SegmentTemplate></Representation></AdaptationSet>
<AdaptationSet id="2" mimeType="audio/mp4"><Representation id="25" audioSamplingRate="44100" bandwidth="128000" codecs="mp4a.40.2">
<SegmentTemplate timescale="44100" startNumber="1" initialization="../../${VID}/audio/128/init.mp4?p=y" media="../../${VID}/audio/128/seg_$Number$.mp4?p=y">
<SegmentTimeline><S d="89214" /><S d="88200" r="${count - 2}" /></SegmentTimeline></SegmentTemplate></Representation></AdaptationSet></Period></MPD>`;
const T0 = Date.parse('2026-11-21T17:00:00.000Z');
const cf = (body, status = 200) => async (url) => { assert.equal(url, `https://videodelivery.net/${U}/manifest/video.mpd`); return new Response(status === 200 ? body : null, { status }); };
const lines = async (r) => (await r.text()).trim().split('\n');

assert.equal(playbackURL(U), `https://flagcast.app/golf/api/cam/${U}/video.m3u8`); assert.equal(camUid(playbackURL(U)), U);
assert.equal(camUid(`https://videodelivery.net/${U}/manifest/video.m3u8`), null);
const pm = parseMpd(mpdXml(300), `https://videodelivery.net/${U}/manifest/video.mpd`);
assert.equal(pm.start, T0); assert.equal(pm.tracks.length, 3); assert.equal(pm.tracks[0].segs.length, 300);
assert.equal(pm.tracks[0].segs[1].t, 2.023); assert.equal(pm.tracks[0].segs[0].url, `https://videodelivery.net/${VID}/video/720/seg_1.mp4?p=abc&s=sig`);
assert.equal(pm.tracks[2].kind, 'audio'); assert.ok(Math.abs(pm.tracks[2].segs[299].t - (89214 + 298 * 88200) / 44100) < 1e-9);
ok('the DASH manifest is read: start clock, every segment from the first, exact times');

let L = await lines(await camPlaylist(cf(mpdXml(300)), U, 'video', new URLSearchParams()));
assert.ok(L.includes('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="Camera",DEFAULT=YES,AUTOSELECT=YES,URI="a25.m3u8"'));
assert.equal(L[L.indexOf('v21.m3u8') - 1].includes('RESOLUTION=1280x720'), true); assert.ok(L.indexOf('v21.m3u8') < L.indexOf('v22.m3u8'));
L = await lines(await camPlaylist(cf(mpdXml(300)), U, 'v21', new URLSearchParams()));
const segs = L.filter((l) => l.startsWith('https://')); assert.ok(segs.length >= WINDOW / 2 && segs.length <= WINDOW / 2 + 1);
assert.ok(segs.at(-1).includes('/seg_300.mp4')); assert.ok(!L.includes('#EXT-X-ENDLIST'));
const first = +L.find((l) => l.startsWith('#EXT-X-MEDIA-SEQUENCE:')).split(':')[1];
assert.equal(L.find((l) => l.startsWith('#EXT-X-PROGRAM-DATE-TIME:')), `#EXT-X-PROGRAM-DATE-TIME:${new Date(T0 + (2.023 + (first - 2) * 2) * 1000).toISOString()}`);
ok(`live: the last ${WINDOW} s (Cloudflare lists ~16 s), with the wall clock on it`);

// a replay 3 minutes into the broadcast, 25 s back, 31 s long: segments 78..93, finished
const from = T0 + 155_000;
L = await lines(await camPlaylist(cf(mpdXml(300)), U, 'v21', new URLSearchParams({ from, len: 31 })));
const cs = L.filter((l) => l.startsWith('https://')).map((u) => +u.match(/seg_(\d+)/)[1]);
assert.equal(cs[0], 78); assert.equal(cs.at(-1), 93); assert.ok(L.includes('#EXT-X-PLAYLIST-TYPE:VOD') && L.includes('#EXT-X-ENDLIST'));
L = await lines(await camPlaylist(cf(mpdXml(300)), U, 'video', new URLSearchParams({ from, len: 31 })));
assert.ok(L.includes(`v21.m3u8?from=${from}&len=31`));
// the moment is still arriving: a growing (EVENT) clip without the end mark
L = await lines(await camPlaylist(cf(mpdXml(80)), U, 'a25', new URLSearchParams({ from, len: 31 })));
assert.ok(L.includes('#EXT-X-PLAYLIST-TYPE:EVENT') && !L.includes('#EXT-X-ENDLIST'));
ok('replay clips: any moment of the broadcast, finished or still arriving');

let r = await camPlaylist(cf(mpdXml(300)), U, 'video', new URLSearchParams({ from: T0 - 60_000, len: 31 }));
assert.equal(r.status, 404); assert.match((await r.json()).error, /older than this broadcast/);
r = await camPlaylist(cf('', 204), U, 'video', new URLSearchParams()); assert.equal(r.status, 404); assert.match((await r.json()).error, /isn’t sending/);
r = await camPlaylist(cf(mpdXml(300)), U, 'v99', new URLSearchParams()); assert.equal(r.status, 404);
ok('a moment before this broadcast, a camera that isn’t sending, or a gone track: a clear message');

console.log(`\n${n} passed`);
