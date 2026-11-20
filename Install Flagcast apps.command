#!/bin/bash
# One click for every Flagcast app on this Mac and your phones:
#   1. Flagcast Manager and Flagcast Admin for this Mac (signed, checked by Apple, put in Applications)
#   2. Flagcast, Manager and Admin on every iPhone and iPad paired with this Mac that's unlocked nearby
#      (same Wi-Fi or a cable). Phone installs are test installs: they last about a week.
cd "$(dirname "$0")" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
ok=(); skipped=()

echo "== Mac apps"
for app in manager admin; do
  f=$(ls apps/flagcast-$app/Install*\(Mac\).command 2>/dev/null | head -1)
  if bash "$f" < /dev/null; then ok+=("$(basename "$f" .command | sed 's/Install //; s/ (Mac)//') on this Mac"); else skipped+=("$(basename "$f") failed: scroll up for why"); fi
done

echo; echo "== iPhone and iPad apps"
if ! command -v xcodebuild >/dev/null; then
  skipped+=("iPhone/iPad apps: Xcode isn't installed")
else
  # phones and iPads paired with this Mac and reachable now
  json=$(mktemp); xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1
  devices=$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for x in d.get("result",{}).get("devices",[]):
    hw=x.get("hardwareProperties",{}); cp=x.get("connectionProperties",{})
    if hw.get("reality")=="physical" and hw.get("platform") in ("iOS","iPadOS") and cp.get("pairingState")=="paired" and cp.get("tunnelState")!="unavailable":
        print(x["identifier"]+"\t"+x.get("deviceProperties",{}).get("name","iPhone"))
' "$json" 2>/dev/null); rm -f "$json"
  if [ -z "$devices" ]; then
    skipped+=("iPhone/iPad apps: no paired iPhone or iPad nearby (unlock it on the same Wi-Fi and run this again)")
  else
    B="$PWD/build/install-ios"; mkdir -p "$B"
    build() { xcodebuild -project "$1" -scheme "$2" -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$B" -allowProvisioningUpdates build > "$B/$2.log" 2>&1; }
    echo "Building Flagcast, Manager and Admin for iPhone and iPad…"
    build apps/flagcast-ios/Flagcast.xcodeproj Flagcast && build apps/flagcast-staff-ios/FlagcastStaff.xcodeproj Manager && build apps/flagcast-staff-ios/FlagcastStaff.xcodeproj Admin \
      || { skipped+=("iPhone/iPad apps: the build stopped (logs in build/install-ios)"); devices=""; }
    while IFS=$'\t' read -r id name; do
      [ -n "$id" ] || continue
      for a in "Flagcast" "Flagcast Manager" "Flagcast Admin"; do
        if xcrun devicectl device install app --device "$id" "$B/Build/Products/Release-iphoneos/$a.app" >/dev/null 2>&1; then ok+=("$a on $name")
        else skipped+=("$a on $name: couldn't install (unlock it and keep it near this Mac)"); fi
      done
    done <<< "$devices"
  fi
fi

echo; echo "== Done"
for x in "${ok[@]}"; do echo "  ✓ $x"; done
for x in "${skipped[@]}"; do echo "  – $x"; done
