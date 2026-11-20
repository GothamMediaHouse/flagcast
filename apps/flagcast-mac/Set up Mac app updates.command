#!/bin/bash
# Once, on the Mac that publishes Flagcast Manager and Flagcast Admin: makes the key that signs their updates.
# The private key stays in this Mac's keychain (Sparkle's generate_keys, account "flagcast"); the public half goes
# into both apps (SUPublicEDKey) so they only install updates signed with it. Keep a copy of the key somewhere
# safe (the script offers to export it): without it, a new Mac can't publish updates the installed apps accept.
cd "$(dirname "$0")" || exit 1
set -e
tools/get-sparkle.sh
if [ ! -x Vendor/sparkle-dist/bin/generate_keys ]; then
  echo "Getting Sparkle’s tools…"
  mkdir -p Vendor && curl -fsSL -o Vendor/sparkle-tools.tar.xz "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz"
  echo "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27  Vendor/sparkle-tools.tar.xz" | shasum -a 256 -c - >/dev/null
  mkdir -p Vendor/sparkle-dist && tar -xf Vendor/sparkle-tools.tar.xz -C Vendor/sparkle-dist && rm Vendor/sparkle-tools.tar.xz
fi
echo; echo "Making the update key (or using the one already in the keychain)…"
Vendor/sparkle-dist/bin/generate_keys --account flagcast >/dev/null
KEY=$(Vendor/sparkle-dist/bin/generate_keys --account flagcast -p)
[ -n "$KEY" ] || { echo "The key wasn’t made. Scroll up for why."; exit 1; }
for T in Manager Admin; do
  /usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" "$T/Info.plist" >/dev/null 2>&1 || true
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $KEY" "$T/Info.plist"
done
echo; echo "✓ Done. Both apps now only install updates signed with this Mac’s key."
echo
read -r -p "Save a backup of the key to your Desktop (keep it somewhere safe, not in Git)? [y/N] " a
if [ "$a" = y ] || [ "$a" = Y ]; then Vendor/sparkle-dist/bin/generate_keys --account flagcast -x "$HOME/Desktop/flagcast-update-key.txt" && echo "Saved to your Desktop: flagcast-update-key.txt"; fi
echo; read -n 1 -s -r -p "Press any key to close."
