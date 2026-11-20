#!/bin/bash
# Signs the newly built Flagcast Manager and Flagcast Admin updates with this Mac's update key and writes their
# update feeds (appcast.xml and latest-mac.yml). Run it after tools/release.sh. The first time, macOS asks to let
# sign_update use the key "flagcast": click Always Allow.
cd "$(dirname "$0")" || exit 1
for T in Manager Admin; do
  echo; echo "== Flagcast $T"
  tools/feeds.sh "$T" || { echo; echo "Not signed. If macOS asked about the key, click Always Allow and double-click this again."; read -n 1 -s -r -p "Press any key to close."; exit 1; }
done
echo; echo "✓ Both updates are signed. Next: double-click Publish Flagcast Manager.command and Publish Flagcast Admin.command."
echo; read -n 1 -s -r -p "Press any key to close."
