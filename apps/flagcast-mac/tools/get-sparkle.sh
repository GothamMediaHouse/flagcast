#!/bin/bash
# Fetches Sparkle (the Mac apps' one-click updates) into Vendor/, checked against its published checksum.
# Sparkle's own release for Swift Package Manager: https://github.com/sparkle-project/Sparkle/releases
set -e
cd "$(dirname "$0")/.."
VERSION=2.10.1
SHA=4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a
[ -d Vendor/Sparkle.xcframework ] && [ -f Vendor/.sparkle-$VERSION ] && exit 0
mkdir -p Vendor && cd Vendor
curl -fsSL -o sparkle.zip "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"
echo "$SHA  sparkle.zip" | shasum -a 256 -c - >/dev/null || { echo "Sparkle download didn't match its checksum"; rm -f sparkle.zip; exit 1; }
rm -rf Sparkle.xcframework && unzip -q sparkle.zip -d sparkle-tmp && mv sparkle-tmp/Sparkle.xcframework . && rm -rf sparkle-tmp sparkle.zip
touch .sparkle-$VERSION
echo "Sparkle $VERSION ready"
