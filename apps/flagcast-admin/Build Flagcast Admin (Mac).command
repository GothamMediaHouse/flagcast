#!/bin/bash
# Builds Flagcast Admin for Mac (one app for Apple silicon and Intel, signed and notarized by Apple) and Windows. It's only for Flagcast, not for clubs.
# The finished files land in the dist folder next to this script; "Publish Flagcast Admin.command" puts them online.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
set -e
echo "Installing what the build needs…"
npm install --no-audit --no-fund
echo "Building for Mac (signed + notarized; Apple's check can take a few minutes)…"
# electron-builder finds the "Developer ID Application" certificate in your keychain; notarization
# uses the keychain profile saved by "Set up Apple signing.command" in Showcaller/Releases.
export APPLE_KEYCHAIN_PROFILE="${APPLE_KEYCHAIN_PROFILE:-showcaller-notary}"
bash ../mac-build.sh "Flagcast Admin" release
echo "Building for Windows…"
( unset CSC_LINK CSC_NAME APPLE_KEYCHAIN_PROFILE; CSC_IDENTITY_AUTO_DISCOVERY=false npx electron-builder --win nsis --x64 --publish never ) || echo "Windows build reported a problem: check dist for the .exe"
echo "Done. Opening the dist folder."
open dist
