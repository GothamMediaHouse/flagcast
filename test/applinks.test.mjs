import test from 'node:test';
import assert from 'node:assert/strict';
import { applinks, APPLE_APP } from '../applinks.js';

test('the Apple file sends scorecard links to the player app', async () => {
  const r = applinks(new URL('https://flagcast.app/.well-known/apple-app-site-association'));
  assert.equal(r.headers.get('Content-Type'), 'application/json');
  const j = await r.json(), d = j.applinks.details[0];
  assert.deepEqual(d.appIDs, [APPLE_APP]);
  assert.deepEqual(d.components.map((c) => c['/']), ['/g/*/s/*']);
});

test('the Android file is JSON, and other paths are not taken', async () => {
  const r = applinks(new URL('https://flagcast.app/.well-known/assetlinks.json'));
  assert.ok(Array.isArray(await r.json()));
  assert.equal(applinks(new URL('https://flagcast.app/g/abcdefgh/s/ABC234')), null);
});
