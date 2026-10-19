#!/usr/bin/env bash
# Every requirement ID in docs/product/requirements.md needs a test that names it (unit, UI, api or
# agent eval), or an entry with a reason in docs/product/traceability-waivers.md. This is a mention
# check: it proves an ID is named in test code, not that the test asserts it. Review the mapping in
# docs/product/test-cases.md for substance. Write each ID out (A11Y-002, A11Y-003); "A11Y-002/003" only
# matches the first. A waiver for an ID
# that has a test is stale and fails too. IDs match as FR-VAC-002, fr_vac_002 or FR-VAC-002.3.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

waivers=docs/product/traceability-waivers.md
dirs=()
for d in api/tests agents/tests evals ios/AppTests ios/AppUITests ios/Packages/Core/Tests ios/Packages/Features/Tests; do
  [ -d "$d" ] && dirs+=("$d")
done

ids=$( { grep -oE '^\*\*FR-[A-Z]+-[0-9]+' docs/product/requirements.md | tr -d '*'
         grep -oE '^\| (NFR|PRIV|EXP|A11Y)-[0-9]+' docs/product/requirements.md | tr -d '| '; } | sort -u)

waived=$(grep -oE '^- [A-Z0-9-]+:' "$waivers" | sed -E 's/^- //; s/:$//' | sort -u || true)

fail=0
for id in $ids; do
  pattern=$(echo "$id" | sed -E 's/-/[-_]/g')
  if grep -rqiE --exclude-dir=.venv --exclude-dir=__pycache__ --exclude-dir=.pytest_cache --exclude-dir=.ruff_cache "${pattern}([^0-9]|$)" "${dirs[@]}"; then
    if echo "$waived" | grep -qx "$id"; then echo "stale waiver (has a test): $id"; fail=1; fi
  elif ! echo "$waived" | grep -qx "$id"; then
    echo "no test and no waiver: $id"; fail=1
  fi
done
for id in $waived; do
  echo "$ids" | grep -qx "$id" || { echo "waiver for unknown id: $id"; fail=1; }
done

[ "$fail" = 0 ] && echo "traceability: every requirement id is named by a test or has a reviewed waiver (mention check)"
exit "$fail"
