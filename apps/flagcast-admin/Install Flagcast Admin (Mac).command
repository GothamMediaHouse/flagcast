#!/bin/bash
# One click: builds Flagcast Admin for this Mac (signed with your Developer ID and checked by Apple), puts it in
# Applications in place of an older copy (the old one goes to the Trash) and opens it.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
APP_NAME="Flagcast Admin"
echo; echo "Installing $APP_NAME. This takes a few minutes (Apple checks the app before it's installed)."
command -v node >/dev/null || { echo "Node.js is needed: https://nodejs.org (install the LTS version, then run this again)"; open "https://nodejs.org/en/download"; exit 1; }
set -e
# Apple's check uses the notarytool keychain profile the build script uses (or APPLE_KEYCHAIN_PROFILE if set)
if [ -z "$APPLE_KEYCHAIN_PROFILE" ]; then
  APPLE_KEYCHAIN_PROFILE=$(grep -o 'APPLE_KEYCHAIN_PROFILE:-[^}]*' "Build Flagcast Admin (Mac).command" | head -1 | cut -d- -f2-)
fi
export APPLE_KEYCHAIN_PROFILE
osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
npm install --no-audit --no-fund
bash ../mac-build.sh "$APP_NAME" install
APP=$(ls -dt dist/mac*/"$APP_NAME.app" | head -1)
[ -d "$APP" ] || { echo "The build didn't make $APP_NAME.app. Scroll up for the error."; exit 1; }
if [ -d "/Applications/$APP_NAME.app" ]; then mv "/Applications/$APP_NAME.app" "$HOME/.Trash/$APP_NAME $(date "+%Y-%m-%d %H.%M.%S").app"; fi
ditto "$APP" "/Applications/$APP_NAME.app"
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
# so the Dock and Finder show the new icon straight away
touch "/Applications/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" 2>/dev/null || true
echo; echo "Installed $APP_NAME $(node -p "require('./package.json').version"). Opening it…"
open "/Applications/$APP_NAME.app"
