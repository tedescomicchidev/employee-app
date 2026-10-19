#!/usr/bin/env bash
# Every requirement ID in docs/product/requirements.md needs a test that names it (unit, UI, api or
# agent eval), or an entry with a reason in docs/product/traceability-waivers.md. A waiver for an ID
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
  if grep -rqiE "${pattern}([^0-9]|$)" "${dirs[@]}"; then
    if echo "$waived" | grep -qx "$id"; then echo "stale waiver (has a test): $id"; fail=1; fi
  elif ! echo "$waived" | grep -qx "$id"; then
    echo "no test and no waiver: $id"; fail=1
  fi
done
for id in $waived; do
  echo "$ids" | grep -qx "$id" || { echo "waiver for unknown id: $id"; fail=1; }
done

[ "$fail" = 0 ] && echo "traceability: every requirement id has a test or a reviewed waiver"
exit "$fail"
