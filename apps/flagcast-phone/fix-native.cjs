// After `cap add ios` / `cap add android`: camera permission for scanning the cart card, app name and version.
const fs = require('fs');
const VERSION = require('./package.json').version;

const plist = 'ios/App/App/Info.plist';
if (fs.existsSync(plist)) {
  let t = fs.readFileSync(plist, 'utf8');
  if (!t.includes('NSCameraUsageDescription')) {
    t = t.replace(/<dict>\n/, '<dict>\n\t<key>NSCameraUsageDescription</key>\n\t<string>Flagcast uses the camera to scan the QR code on your cart card.</string>\n');
  }
  t = t.replace(/(<key>CFBundleDisplayName<\/key>\s*<string>)[^<]*/, '$1Flagcast');
  fs.writeFileSync(plist, t);
  const pbx = 'ios/App/App.xcodeproj/project.pbxproj';
  let p = fs.readFileSync(pbx, 'utf8');
  p = p.replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${VERSION};`);
  if (!p.includes('DEVELOPMENT_TEAM')) p = p.replace(/(PRODUCT_BUNDLE_IDENTIFIER = app\.flagcast\.golf;)/g, '$1\n\t\t\t\tDEVELOPMENT_TEAM = C8KXPB4QNA;');
  fs.writeFileSync(pbx, p);
  console.log('iOS: camera permission, name, version', VERSION, 'team C8KXPB4QNA');
}

const man = 'android/app/src/main/AndroidManifest.xml';
if (fs.existsSync(man)) {
  let t = fs.readFileSync(man, 'utf8');
  if (!t.includes('android.permission.CAMERA')) t = t.replace('</manifest>', '    <uses-permission android:name="android.permission.CAMERA" />\n    <uses-feature android:name="android.hardware.camera" android:required="false" />\n</manifest>');
  fs.writeFileSync(man, t);
  const gradle = 'android/app/build.gradle';
  let g = fs.readFileSync(gradle, 'utf8');
  g = g.replace(/versionName "[^"]*"/, `versionName "${VERSION}"`);
  fs.writeFileSync(gradle, g);
  console.log('Android: camera permission, version', VERSION);
}
