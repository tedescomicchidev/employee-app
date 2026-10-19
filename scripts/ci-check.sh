#!/usr/bin/env bash
# requirement traceability, ios build+test, api lint+test, agent unit tests. Run from anywhere.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
sim=${SIMULATOR_NAME:-iPhone 17}

echo "== infra =="
cd "$root"
az bicep build --file infra/main.bicep --outfile /dev/null
# NFR-001 / ADR-001: no literal resource location other than switzerlandnorth.
if grep -rnE "location: *'" infra --include=*.bicep | grep -v "switzerlandnorth"; then
  echo "infra: literal location other than switzerlandnorth (ADR-001)"; exit 1
fi
# NFR-014: no keys or secrets in templates.
if grep -rnE "listKeys|listSecrets|adminUserEnabled: *true|disableLocalAuth: *false" infra --include=*.bicep; then
  echo "infra: key-based access found"; exit 1
fi

echo "== traceability =="
"$root/scripts/check-traceability.sh"

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
