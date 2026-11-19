#!/bin/bash
# Builds Flagcast Manager for Mac (signed with your Developer ID and notarized by Apple) and for Windows (installer .exe).
# The finished files land in the dist folder next to this script.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
set -e
echo "Installing what the build needs…"
npm install --no-audit --no-fund
echo "Building for Mac (signed + notarized; Apple's check can take a few minutes)…"
# electron-builder finds the "Developer ID Application" certificate in your keychain; notarization
# uses the keychain profile saved by "Set up Apple signing.command" in Showcaller/Releases.
export APPLE_KEYCHAIN_PROFILE="${APPLE_KEYCHAIN_PROFILE:-showcaller-notary}"
npx electron-builder --mac --arm64 --x64 --publish never
echo "Building for Windows…"
( unset CSC_LINK CSC_NAME APPLE_KEYCHAIN_PROFILE; CSC_IDENTITY_AUTO_DISCOVERY=false npx electron-builder --win nsis --x64 --publish never ) || echo "Windows build reported a problem: check dist for the .exe"
echo "Done. Opening the dist folder."
open dist
