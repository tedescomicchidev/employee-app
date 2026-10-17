#!/usr/bin/env bash
# ios build+test, api lint+test, agent unit tests. Run from anywhere.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sim=${SIMULATOR_NAME:-iPhone 17}

echo "== ios =="
cd "$root/ios"
xcodegen generate
xcodebuild test \
  -project EmployeeApp.xcodeproj -scheme EmployeeApp \
  -destination "platform=iOS Simulator,name=$sim" \
  -derivedDataPath "$root/build/DerivedData"

for pkg in Core Features; do
  (cd "$root/ios/Packages/$pkg" && swift test)
done

for dir in api agents; do
  echo "== $dir =="
  cd "$root/$dir"
  uv sync --frozen
  uv run ruff check .
  uv run ruff format --check .
  uv run pytest -q
done

echo "ci-check: all passed"
