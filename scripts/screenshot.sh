#!/usr/bin/env bash
# Simulator screenshots per seeded scenario -> build/screenshots/<scenario>-<appearance>.png
# Usage: scripts/screenshot.sh [scenario ...]   (default: all scenarios below)
# The app reads `-scenario <name>` from launch arguments. Only `launch` exists in Phase 0;
# add scenarios here as features land.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sim=${SIMULATOR_NAME:-iPhone 17}
bundle=ch.example.employee
scenarios=(launch)
appearances=(light dark)

if [ "$#" -gt 0 ]; then scenarios=("$@"); fi

cd "$root/ios"
xcodegen generate
xcodebuild build -project EmployeeApp.xcodeproj -scheme EmployeeApp \
  -destination "platform=iOS Simulator,name=$sim" \
  -derivedDataPath "$root/build/DerivedData"
app=$(find "$root/build/DerivedData/Build/Products" -name 'EmployeeApp.app' -maxdepth 3 | head -n1)

xcrun simctl boot "$sim" 2>/dev/null || true
xcrun simctl bootstatus "$sim" -b >/dev/null
xcrun simctl install "$sim" "$app"

out="$root/build/screenshots"
mkdir -p "$out"
for appearance in "${appearances[@]}"; do
  xcrun simctl ui "$sim" appearance "$appearance"
  for s in "${scenarios[@]}"; do
    xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$sim" "$bundle" -scenario "$s" >/dev/null
    sleep 2
    xcrun simctl io "$sim" screenshot "$out/$s-$appearance.png"
  done
done

# Largest accessibility text size.
xcrun simctl ui "$sim" content_size accessibility-extra-extra-extra-large
for s in "${scenarios[@]}"; do
  xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$sim" "$bundle" -scenario "$s" >/dev/null
  sleep 2
  xcrun simctl io "$sim" screenshot "$out/$s-largest-text.png"
done
xcrun simctl ui "$sim" content_size large
echo "Screenshots in $out"
