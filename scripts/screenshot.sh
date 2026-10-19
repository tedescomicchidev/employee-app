#!/usr/bin/env bash
# Simulator screenshots per seeded scenario -> build/screenshots/<scenario>-<appearance>.png
# Usage: scripts/screenshot.sh [scenario ...]   (default: all scenarios below)
# The app reads `-scenario <name>` from launch arguments (DEBUG builds; see ios/App/StubLaunch.swift).
# Language defaults to German like the mockups; override with SCREENSHOT_LANG=en|fr|it.
# Add scenarios here as features land.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sim=${SIMULATOR_NAME:-iPhone 17}
bundle=ch.example.employee
scenarios=(signin signin-failed signin-offline home-employee home-manager home-publisher
           compose-ok compose-validation review-ok review-success review-error review-offline
           audience-ok feed-ok feed-loading feed-empty feed-error feed-offline detail-ok
           vacation-overview-ok vacation-overview-empty vacation-overview-loading vacation-overview-offline
           vacation-overview-error vacation-my_requests-ok vacation-my_requests-empty vacation-request_detail-ok
           vacation-request_detail-cancel_dialog vacation-manager_inbox-ok vacation-manager_inbox-empty
           vacation-manager_inbox-forbidden vacation-request_decision-ok vacation-request_decision-reject_reason
           vacation-request_decision-invalid_state vacation-request_decision-blocked vacation-team_coverage-ok vacation-team_coverage-empty
           vacation-team_coverage-forbidden vacation-holidays-ok vacation-holidays-canton_missing
           vacation-request-ok vacation-request-validation_overlap vacation-review-ok
           vacation-review-validation_insufficient_balance vacation-review-success)
lang=${SCREENSHOT_LANG:-de}
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
  sleep 2   # let the appearance change settle before launching
  for s in "${scenarios[@]}"; do
    xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$sim" "$bundle" -AppleLanguages "($lang)" -scenario "$s" >/dev/null
    sleep 3
    xcrun simctl io "$sim" screenshot "$out/$s-$appearance.png"
  done
done

# Largest accessibility text size.
xcrun simctl ui "$sim" content_size accessibility-extra-extra-extra-large
for s in "${scenarios[@]}"; do
  xcrun simctl terminate "$sim" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$sim" "$bundle" -AppleLanguages "($lang)" -scenario "$s" >/dev/null
  sleep 3
  xcrun simctl io "$sim" screenshot "$out/$s-largest-text.png"
done
xcrun simctl ui "$sim" content_size large
echo "Screenshots in $out"
