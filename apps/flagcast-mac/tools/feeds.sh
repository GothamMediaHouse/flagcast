#!/bin/bash
# The update feeds for a built release: tools/feeds.sh Manager   (Admin is retired)
#   appcast.xml     the Sparkle feed the native app reads, the .zip signed with the update key (Keychain, account "flagcast")
#   latest-mac.yml  the feed the older (Electron) app reads, so it updates to the native one
# The first time, macOS asks to let sign_update use the key: click Always Allow.
[ "$1" = "Admin" ] && { echo "Flagcast Admin is retired: Admin lives inside Flagcast Manager now. Release Manager instead."; exit 1; }
set -e
cd "$(dirname "$0")/.."
APP_T="${1:-Manager}"; LOWER=$(echo "$APP_T" | tr '[:upper:]' '[:lower:]')
NAME="Flagcast $APP_T"; SLUG="Flagcast-$APP_T"; OUT="build/release/$APP_T"
APP="build/export-$APP_T/$NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
ZIP="$OUT/$SLUG-$VERSION-universal-mac.zip"; DMG="$OUT/$SLUG-$VERSION-universal.dmg"
[ -f "$ZIP" ] && [ -f "$DMG" ] || { echo "Build it first: tools/release.sh $APP_T"; exit 1; }
echo "== Update feeds"
FEED="https://flagcast.app/updates/$LOWER"
SIG=$(Vendor/sparkle-dist/bin/sign_update --account flagcast "$ZIP")   # sparkle:edSignature="…" length="…"
[ -n "$SIG" ] || { echo "The update wasn’t signed: allow sign_update to use the key when macOS asks, then run tools/feeds.sh $APP_T"; exit 1; }
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
echo "Feeds ready in $OUT"; ls "$OUT"
