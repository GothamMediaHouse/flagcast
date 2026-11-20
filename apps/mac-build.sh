#!/bin/bash
# Mac builds for the Flagcast desktop apps, used by the Build, Install and Publish scripts next to each app.
#   mac-build.sh "<App Name>" release   one universal app (Apple silicon + Intel): .dmg + .zip + latest-mac.yml in dist,
#                                       app and .dmg signed, notarized and stapled
#   mac-build.sh "<App Name>" install   just the .app for this Mac (faster), signed and notarized
# Run it from the app's folder. Needs the "Developer ID Application" certificate in the keychain and
# APPLE_KEYCHAIN_PROFILE (a notarytool keychain profile) set.
# Apple sometimes takes a few minutes to publish a ticket after accepting an app ("Record not found" when
# stapling); this waits and tries again instead of failing the build.
set -e
APP_NAME="$1"; MODE="${2:-release}"
[ -n "$APP_NAME" ] && [ -n "$APPLE_KEYCHAIN_PROFILE" ] || { echo "mac-build.sh: app name and APPLE_KEYCHAIN_PROFILE are needed"; exit 1; }

staple() {   # staple, waiting for Apple's ticket for up to 10 minutes
  for i in $(seq 1 20); do
    xcrun stapler staple "$1" >/dev/null 2>&1 && xcrun stapler validate "$1" >/dev/null 2>&1 && { echo "  ✓ stapled $(basename "$1")"; return 0; }
    [ "$i" = 1 ] && echo "  Waiting for Apple to publish the ticket for $(basename "$1")…"
    sleep 30
  done
  echo "  Apple hasn't published the ticket for $(basename "$1") yet. Run this again in a few minutes."; return 1
}

if [ "$MODE" = install ]; then ARCH=$( [ "$(uname -m)" = arm64 ] && echo --arm64 || echo --x64 ); else ARCH=--universal; fi
LOG=$(mktemp -t flagcast-build)
# 1. the app: built, signed and sent to Apple (electron-builder staples it; if Apple is slow, we do it below)
set +e
npx electron-builder --mac dir $ARCH --publish never 2>&1 | tee "$LOG"
OK=${PIPESTATUS[0]}
set -e
APP=$(ls -dt dist/mac*/"$APP_NAME.app" 2>/dev/null | head -1)
if [ "$OK" != 0 ]; then
  grep -q "Failed to staple" "$LOG" && [ -d "$APP" ] || { echo "The build failed. Scroll up for why."; exit 1; }
  echo "Apple accepted $APP_NAME but its ticket isn't out yet."
  staple "$APP"
fi
rm -f "$LOG"
codesign --verify --deep --strict "$APP"
xcrun stapler validate "$APP" >/dev/null || staple "$APP"
[ "$MODE" = install ] && { echo "Built $APP"; exit 0; }

# 2. the .dmg and .zip (and latest-mac.yml, which updates read) from that same notarized app
npx electron-builder --mac dmg zip --universal --prepackaged "$APP" --publish never
VERSION=$(node -p "require('./package.json').version")
DMG=$(ls dist/*-"$VERSION"-universal.dmg | head -1)
[ -f "$DMG" ] && [ -f dist/latest-mac.yml ] || { echo "The .dmg or latest-mac.yml is missing from dist."; exit 1; }

# 3. the .dmg itself: signed, notarized and stapled, so it opens without warnings
ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')
[ -n "$ID" ] || { echo "No Developer ID Application certificate in the keychain."; exit 1; }
codesign --force --timestamp --sign "$ID" "$DMG"
echo "Sending $(basename "$DMG") to Apple (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$APPLE_KEYCHAIN_PROFILE" --wait | tee /dev/stderr | grep -q "status: Accepted" || { echo "Apple didn't accept $(basename "$DMG"). Scroll up for why."; exit 1; }
staple "$DMG"
# signing and stapling changed the .dmg: refresh its size and checksum in latest-mac.yml, and drop its now
# out-of-date .blockmap (updates download the .zip, which hasn't changed)
python3 - "$DMG" <<'PY'
import sys, hashlib, base64, os, re
d = sys.argv[1]; y = open('dist/latest-mac.yml').read()
h = base64.b64encode(hashlib.sha512(open(d, 'rb').read()).digest()).decode()
y = re.sub(r'(- url: %s\n\s+sha512: )\S+(\n\s+size: )\d+' % re.escape(os.path.basename(d)), lambda m: m.group(1) + h + m.group(2) + str(os.path.getsize(d)), y)
open('dist/latest-mac.yml', 'w').write(y)
PY
rm -f "$DMG.blockmap"
echo "Ready: $DMG"
