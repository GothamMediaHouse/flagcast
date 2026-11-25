// Go live from an iPhone at the hole: the desk or a pro's PIN gets the hole's live input (SRT + RTMPS) to send to,
// the hole's camera link points at it, and Stop takes it off again. Cloudflare Stream is a stand-in on this computer.
// Run against `npx wrangler dev` started with CF_ACCOUNT_ID=acc, CF_STREAM_TOKEN=tok, CF_STREAM_API=http://127.0.0.1:8793
//   node test/golive.test.mjs [http://127.0.0.1:8787]   (npm test does all of that)
import assert from 'node:assert/strict';
import { createServer } from 'node:http';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const MOCK_PORT = Number(process.argv[3] || 8793);

// the stand-in for Cloudflare Stream's live inputs
const inputs = {}; let made = 0; const live = new Set();
const mock = createServer((req, res) => {
  let body = ''; req.on('data', (c) => { body += c; });
  req.on('end', () => {
    const send = (o, status = 200) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)); };
    if (req.headers.authorization !== 'Bearer tok') return send({ success: false, errors: [{ message: 'bad token' }] }, 403);
    const m = req.url.match(/^\/accounts\/acc\/stream\/live_inputs(?:\/([0-9a-f]{32}))?$/);
    if (!m) return send({ success: false, errors: [{ message: 'not here' }] }, 404);
    if (req.method === 'POST' && !m[1]) {
      const uid = String(++made).padStart(32, '0');
      inputs[uid] = { uid, meta: JSON.parse(body).meta, rtmps: { url: 'rtmps://live.cloudflare.com:443/live/', streamKey: `k${uid}` }, srt: { url: 'srt://live.cloudflare.com:778', streamId: `s${uid}`, passphrase: `p${uid}` } };
      return send({ success: true, result: inputs[uid] });
    }
    if (req.method === 'GET' && m[1]) {
      const i = inputs[m[1]]; if (!i) return send({ success: false, errors: [{ message: 'not found' }] }, 404);
      return send({ success: true, result: { ...i, status: { current: { state: live.has(i.uid) ? 'connected' : 'disconnected' } } } });
    }
    send({ success: false, errors: [{ message: 'no' }] }, 405);
  });
});
await new Promise((r) => mock.listen(MOCK_PORT, '127.0.0.1', r));

const call = async (path, body) => {
  const r = await fetch(BASE + path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { status: r.status, j: await r.json() };
};
const post = async (path, body) => { const { status, j } = await call(path, body); if (status !== 200) throw new Error(`${path} ${status} ${JSON.stringify(j)}`); return j; };
let n = 0; const ok = (name) => console.log(`ok ${++n} - ${name}`);
const state = async (id) => (await fetch(`${BASE}/golf/api/${id}/state`)).json();

try {
  const { id, key } = await post('/golf/api/new', { name: 'Go live test', pass: 'local' });
  const desk = (op, b = {}) => post(`/golf/api/${id}/desk`, { key, op, ...b });
  const cur = await desk('get');
  await desk('save', { setup: { ...cur, displays: [{ id: 'tv1', name: 'Bar' }], pins: [{ name: 'Pat Pro', role: 'pro', pin: '654321' }, { name: 'Marshal', role: 'marshal', pin: '876543' }] } });
  const pro = (op, b = {}) => call(`/golf/api/${id}/pro`, { pin: '654321', op, ...b });

  // a pro goes live on hole 8
  let r = await pro('golive', { hole: 8 });
  assert.equal(r.status, 200, JSON.stringify(r.j));
  const uid = Object.keys(inputs)[0];
  assert.equal(r.j.playback, `https://flagcast.app/golf/api/cam/${uid}/video.m3u8`);
  assert.deepEqual(r.j.srt, { url: 'srt://live.cloudflare.com:778', streamId: `s${uid}`, passphrase: `p${uid}` });
  assert.equal(r.j.rtmps.streamKey, `k${uid}`);
  assert.equal(inputs[uid].meta.name, 'Go live test · hole 8');
  let s = await state(id);
  assert.equal(s.cams[8], r.j.playback); assert.equal(s.golive[8].by, 'Pat Pro'); assert.equal(s.golive[8].had, false);
  ok('a pro goes live on hole 8: SRT and RTMPS to send to, and the hole’s camera link for TVs and phones');

  // the playlist address only works for Flagcast's own cameras: this one is
  const pl = await fetch(`${BASE}/golf/api/cam/${uid}/video.m3u8`);
  assert.notEqual(pl.status, 404, 'the new camera is one of Flagcast’s');
  ok('the camera’s playlist is served (it is in the directory’s cameras)');

  // while it sends, another phone can't take the hole
  live.add(uid);
  r = await call(`/golf/api/${id}/desk`, { key, op: 'golive', hole: 8 });
  assert.equal(r.status, 409); assert.match(r.j.error, /already live from Pat Pro’s phone/);
  r = await call(`/golf/api/${id}/desk`, { key, op: 'golive', hole: 8, take: true });
  assert.equal(r.status, 200); assert.equal(Object.keys(inputs).length, 1, 'the same live input is reused');
  live.delete(uid);
  ok('a hole that is already sending is not taken over unless asked; the live input is reused');

  // on the TVs and phones, then Stop puts them back
  await desk('screen', { display: ['tv1', 'phones'], page: { k: 'cam', hole: 8 } });
  s = await state(id); assert.equal(s.live.force.tv1.k, 'cam'); assert.equal(s.live.phone.hole, 8);
  await desk('golive', { hole: 8, stop: true });
  s = await state(id);
  assert.equal(s.cams[8], undefined); assert.equal(s.golive[8], undefined);
  assert.equal(s.live.force.tv1, undefined); assert.equal(s.live.phone, null);
  ok('Stop takes the camera off hole 8 and sends the TVs and phones back');

  // a hole that already had a camera keeps it after the phone stops
  await desk('golive', { hole: 3 });
  const three = (await state(id)).cams[3];
  await desk('golive', { hole: 3, stop: true });
  await desk('golive', { hole: 3 }); // live input made before: reused
  assert.equal((await state(id)).cams[3], three);
  assert.equal((await state(id)).golive[3].by, 'Desk');
  ok('the desk can go live too');

  // marshals can't; a wrong hole is refused; Stop on a hole that isn't live is fine
  assert.equal((await call(`/golf/api/${id}/pro`, { pin: '876543', op: 'golive', hole: 4 })).status, 403);
  assert.equal((await pro('golive', { hole: 30 })).status, 400);
  assert.equal((await pro('golive', { hole: 0 })).status, 400);
  assert.equal((await pro('golive', { hole: 5, stop: true })).status, 200);
  ok('marshals can’t go live; no hole, no live');

  // the directory only answers the tournament itself
  const direct = await fetch(`${BASE}/golf/api/club/golive`, { method: 'POST', body: JSON.stringify({ id, key, hole: 2 }) });
  assert.notEqual(direct.status, 200);
  ok('nobody can ask the directory for a live input directly (only a tournament can)');
} finally {
  mock.close();
}
