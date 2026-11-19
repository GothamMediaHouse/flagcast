#!/bin/bash
# Builds Flagcast Admin for Mac (signed with your Developer ID and notarized by Apple). It's only for Flagcast, not for clubs.
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
echo "Done. Opening the dist folder."
open dist
