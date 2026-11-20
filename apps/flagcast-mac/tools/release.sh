#!/bin/bash
# Builds a native Mac app for release: tools/release.sh Manager   (or Admin)
#   one universal app (Apple silicon + Intel), signed with the Developer ID and notarized by Apple, then in
#   build/release/<App>/:
#     Flagcast-<App>-<version>-universal.dmg          what flagcast.app/download hands out (signed, notarized, stapled)
#     Flagcast-<App>-<version>-universal-mac.zip      what updates download
#     appcast.xml                                     the Sparkle feed the native app reads (signed with the update key)
#     latest-mac.yml                                  the feed the older Electron version reads, so it updates to this one
# Needs: Xcode, the "Developer ID Application" certificate, APPLE_KEYCHAIN_PROFILE (notarytool keychain profile) and the
# Sparkle update key in the keychain ("Set up Mac app updates.command", once).
set -e
cd "$(dirname "$0")/.."
APP_T="${1:-Manager}"; LOWER=$(echo "$APP_T" | tr '[:upper:]' '[:lower:]')
NAME="Flagcast $APP_T"; SLUG="Flagcast-$APP_T"
[ -n "$APPLE_KEYCHAIN_PROFILE" ] || { echo "Set APPLE_KEYCHAIN_PROFILE (the notarytool keychain profile)."; exit 1; }
tools/get-sparkle.sh
[ -x Vendor/sparkle-dist/bin/sign_update ] || { echo "Sparkle's tools are missing: run 'Set up Mac app updates.command' first."; exit 1; }
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_T/Info.plist" >/dev/null 2>&1 || { echo "No update key yet: double-click 'Set up Mac app updates.command' once, then run this again."; exit 1; }
python3 tools/make-project.py >/dev/null
OUT="build/release/$APP_T"; mkdir -p "$OUT"
staple() { for i in $(seq 1 20); do xcrun stapler staple "$1" >/dev/null 2>&1 && xcrun stapler validate "$1" >/dev/null 2>&1 && return 0; [ "$i" = 1 ] && echo "  Waiting for Apple’s ticket for $(basename "$1")…"; sleep 30; done; echo "Apple hasn’t published the ticket yet. Run this again in a few minutes."; return 1; }
notarize() { echo "Sending $(basename "$1") to Apple (a few minutes)…"; xcrun notarytool submit "$1" --keychain-profile "$APPLE_KEYCHAIN_PROFILE" --wait | tee /dev/stderr | grep -q "status: Accepted" || { echo "Apple didn’t accept $(basename "$1"). Scroll up for why."; exit 1; }; }

echo "== Building $NAME (universal)"
ARCHIVE="build/$APP_T.xcarchive"
xcodebuild -project FlagcastMac.xcodeproj -scheme "$APP_T" -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO -quiet archive
cat > build/export-devid.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>developer-id</string><key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>C8KXPB4QNA</string></dict></plist>
EOF
rm -rf "build/export-$APP_T"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/export-devid.plist -exportPath "build/export-$APP_T" -allowProvisioningUpdates -quiet
APP="build/export-$APP_T/$NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
lipo -archs "$APP/Contents/MacOS/$NAME"
codesign --verify --deep --strict "$APP"

echo "== Notarizing the app"
ditto -c -k --keepParent "$APP" "build/$APP_T-notarize.zip"
notarize "build/$APP_T-notarize.zip"; rm -f "build/$APP_T-notarize.zip"
staple "$APP"

ZIP="$OUT/$SLUG-$VERSION-universal-mac.zip"
DMG="$OUT/$SLUG-$VERSION-universal.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "== Making the .dmg"
STAGE="build/dmg-$APP_T"; rm -rf "$STAGE"; mkdir -p "$STAGE"; ditto "$APP" "$STAGE/$NAME.app"; ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"; rm -rf "$STAGE"
ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
codesign --force --timestamp --sign "$ID" "$DMG"
notarize "$DMG"; staple "$DMG"

echo "== Update feeds"
FEED="https://flagcast.app/updates/$LOWER"
SIG=$(Vendor/sparkle-dist/bin/sign_update --account flagcast "$ZIP")   # sparkle:edSignature="…" length="…"
cat > "$OUT/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$NAME</title>
    <item>
      <title>$NAME $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="$FEED/$(basename "$ZIP")" $SIG type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF
# the older (Electron) app reads latest-mac.yml and installs the .zip: the same signed app, so it moves to this one
python3 - "$ZIP" "$DMG" "$VERSION" "$OUT/latest-mac.yml" <<'PY'
import sys, hashlib, base64, os, datetime
z, d, v, out = sys.argv[1:5]
h = lambda p: base64.b64encode(hashlib.sha512(open(p, 'rb').read()).digest()).decode()
open(out, 'w').write(f"""version: {v}
files:
  - url: {os.path.basename(z)}
    sha512: {h(z)}
    size: {os.path.getsize(z)}
  - url: {os.path.basename(d)}
    sha512: {h(d)}
    size: {os.path.getsize(d)}
path: {os.path.basename(z)}
sha512: {h(z)}
releaseDate: '{datetime.datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%S.000Z')}'
""")
PY
echo; echo "Ready: $NAME $VERSION in apps/flagcast-mac/$OUT"; ls -la "$OUT"
