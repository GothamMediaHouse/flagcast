// Links that open the Flagcast player app when it's on the phone: a cart's scorecard link (/g/<id>/s/<code>), from the
// invite email or the QR code on the cart card. Without the app the same link opens the web player, as before.
//   iPhone: Universal Links. /.well-known/apple-app-site-association names the app (team C8KXPB4QNA, app.flagcast.golf)
//           and the paths it takes; the app has applinks:flagcast.app in its entitlements.
//   Android: App Links. /.well-known/assetlinks.json names the app and its signing certificate(s); the app's manifest
//           has an autoVerify intent filter for the same paths.
// No Worker-only imports: test/applinks.test.mjs runs it in Node.

export const APPLE_APP = 'C8KXPB4QNA.app.flagcast.golf';
export const ANDROID_APP = 'app.flagcast.golf';
// SHA-256 fingerprints of the Android app's signing certificates (the release key, and Google Play's app signing key
// if Play signs it). Public values, not secrets. The app isn't on Google Play yet: add the release and Play keys when it is.
export const ANDROID_CERTS = [
  '19:1A:5C:DC:26:A2:B9:A3:3C:20:0C:1A:A7:52:52:2B:C5:C2:5E:1C:81:29:82:8C:E4:BB:F4:EA:94:06:8B:9E', // debug builds from Matt's Mac
];

const json = (o) => new Response(JSON.stringify(o), { headers: { 'Content-Type': 'application/json', 'Cache-Control': 'public, max-age=3600' } });

export function applinks(url) {
  if (url.pathname === '/.well-known/apple-app-site-association' || url.pathname === '/apple-app-site-association') {
    return json({ applinks: { details: [{ appIDs: [APPLE_APP], components: [{ '/': '/g/*/s/*', comment: 'a cart’s scorecard' }] }] } });
  }
  if (url.pathname === '/.well-known/assetlinks.json') {
    return json(ANDROID_CERTS.length ? [{ relation: ['delegate_permission/common.handle_all_urls'],
      target: { namespace: 'android_app', package_name: ANDROID_APP, sha256_cert_fingerprints: ANDROID_CERTS } }] : []);
  }
  return null;
}
