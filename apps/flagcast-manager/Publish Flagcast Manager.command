#!/bin/bash
# Puts Flagcast Manager online: a GitHub release manager-v<version> on this repository's GitHub with
#   Mac (native app, apps/flagcast-mac: tools/release.sh Manager):   the universal .dmg, the .zip, appcast.xml, latest-mac.yml
#   Windows (this folder, Electron: npx electron-builder --win):   the Setup .exe, its .blockmap, latest.yml
# flagcast.app/download/manager then hands out the new installers, and installed copies offer the update
# (the native Mac app through appcast.xml, older Mac copies through latest-mac.yml, Windows through latest.yml).
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
APP="manager"; NAME="Flagcast Manager"; SLUG="Flagcast-Manager"
MAC="../flagcast-mac/build/release/Manager"
fail() { echo; echo "Not published: $1"; echo; read -n 1 -s -r -p "Press any key to close."; exit 1; }
[ -f "$MAC/latest-mac.yml" ] || fail "the Mac app isn't built yet (apps/flagcast-mac: tools/release.sh Manager)."
VERSION=$(sed -n 's/^version: //p' "$MAC/latest-mac.yml")
TAG="$APP-v$VERSION"
echo; echo "Publishing $NAME $VERSION…"
[ -n "$REPO" ] || fail "this folder isn't connected to GitHub (it has no git remote called origin)."
command -v gh >/dev/null || fail "the GitHub command line tool isn't installed. In Terminal run:  brew install gh   then  gh auth login"
gh auth status >/dev/null 2>&1 || fail "GitHub isn't signed in on this Mac. In Terminal run:  gh auth login   (choose GitHub.com, then sign in with the browser), then double-click this again."
DMG="$MAC/$SLUG-$VERSION-universal.dmg"; ZIP="$MAC/$SLUG-$VERSION-universal-mac.zip"
EXE="dist/$SLUG-Setup-$VERSION.exe"
for f in "$DMG" "$ZIP" "$MAC/appcast.xml" "$MAC/latest-mac.yml" "$EXE" "$EXE.blockmap" dist/latest.yml; do [ -f "$f" ] || fail "$f is missing. Build it first."; done
grep -q "^version: $VERSION$" dist/latest.yml || fail "the Windows build (dist/latest.yml) is another version. Set package.json to $VERSION and build Windows again."
grep -q "<sparkle:shortVersionString>$VERSION<" "$MAC/appcast.xml" || fail "appcast.xml is from another version. Build the Mac app again."
xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "$(basename "$DMG") isn't notarized by Apple. Build the Mac app again."
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && fail "$TAG is already published. Raise the version, build, then publish."
gh release create "$TAG" "$DMG" "$ZIP" "$MAC/appcast.xml" "$MAC/latest-mac.yml" "$EXE" "$EXE.blockmap" dist/latest.yml --repo "$REPO" --title "$NAME $VERSION" \
  --notes "$NAME $VERSION for Mac (Apple silicon and Intel) and Windows. Download: https://flagcast.app/download/$APP" \
  || fail "GitHub didn't take the release. Scroll up for why."
echo; echo "✓ Published $NAME $VERSION."
echo "  Download page: https://flagcast.app/download/$APP (can take 5 minutes to show the new version)"
echo "  Installed copies will offer the update the next time they open."
echo; read -n 1 -s -r -p "Press any key to close."
