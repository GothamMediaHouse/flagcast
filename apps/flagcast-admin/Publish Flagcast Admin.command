#!/bin/bash
# Puts the Flagcast Admin you built with the Build script online: a GitHub release admin-v<version> on
# this repository's GitHub. flagcast.app/download/admin then hands out the new installers, and copies of
# Flagcast Admin already installed offer the update (Help → Check for Updates…, or by themselves at launch).
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# the GitHub repository this folder comes from (owner/name), the one flagcast.app reads releases from
REPO=$(git remote get-url origin 2>/dev/null | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
APP="admin"; NAME="Flagcast Admin"
VERSION=$(node -p "require('./package.json').version")
TAG="$APP-v$VERSION"
fail() { echo; echo "Not published: $1"; echo; read -n 1 -s -r -p "Press any key to close."; exit 1; }
echo; echo "Publishing $NAME $VERSION…"
[ -n "$REPO" ] || fail "this folder isn't connected to GitHub (it has no git remote called origin)."
command -v gh >/dev/null || fail "the GitHub command line tool isn't installed. In Terminal run:  brew install gh   then  gh auth login"
gh auth status >/dev/null 2>&1 || fail "GitHub isn't signed in on this Mac. In Terminal run:  gh auth login   (choose GitHub.com, then sign in with the browser), then double-click this again."
cd dist || fail "there's no dist folder yet. Double-click the Build script first."
DMG="Flagcast-Admin-$VERSION-universal.dmg"
ZIP="Flagcast-Admin-$VERSION-universal-mac.zip"
EXE="Flagcast-Admin-Setup-$VERSION.exe"
for f in "$DMG" "$ZIP" "$ZIP.blockmap" "$EXE" "$EXE.blockmap" latest-mac.yml latest.yml; do
  [ -f "$f" ] || fail "$f is missing from dist. Double-click the Build script first."
done
grep -q "^version: $VERSION$" latest-mac.yml && grep -q "^version: $VERSION$" latest.yml || fail "latest-mac.yml or latest.yml is from another version. Build again."
xcrun stapler validate "$DMG" >/dev/null 2>&1 || fail "$DMG isn't notarized by Apple. Build again (the Build script notarizes it)."
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && fail "$TAG is already published. Raise the version in package.json, build, then publish."
FILES=("$DMG" "$ZIP" "$ZIP.blockmap" "$EXE" "$EXE.blockmap" latest-mac.yml latest.yml)
[ -f "$DMG.blockmap" ] && FILES+=("$DMG.blockmap")
gh release create "$TAG" "${FILES[@]}" --repo "$REPO" --title "$NAME $VERSION" \
  --notes "$NAME $VERSION for Mac (Apple silicon and Intel) and Windows. Download: https://flagcast.app/download/$APP" \
  || fail "GitHub didn't take the release. Scroll up for why."
echo; echo "✓ Published $NAME $VERSION."
echo "  Download page: https://flagcast.app/download/$APP (can take 5 minutes to show the new version)"
echo "  Installed copies will offer the update the next time they open."
echo; read -n 1 -s -r -p "Press any key to close."
