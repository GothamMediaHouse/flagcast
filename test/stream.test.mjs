// Cloudflare Stream Live for NDI cameras (stream.js), with the Stream API mocked.  node test/stream.test.mjs
import assert from 'node:assert/strict';
import { streamReady, liveInput, inputState, playbackURL, deleteInput } from '../stream.js';

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

await assert.rejects(liveInput({ ...env, CF_ACCOUNT_ID: 'wrong' }, m.fetcher, { name: 'z' }), /not found/);
ok('Stream errors come back as messages');

console.log(`\n${n} passed`);
