#!/usr/bin/env bash
# Read-only environment check. Prints tool versions, az/azd login state and MCP servers.
# Never prints tokens or secrets.
set -uo pipefail

fail=0
ok()   { printf 'OK    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }

check_tool() { # name, version command...
  local name=$1; shift
  if command -v "$name" >/dev/null 2>&1; then
    ok "$name: $("$@" 2>&1 | head -n1)"
  else
    bad "$name not found"
  fi
}

check_tool xcodebuild xcodebuild -version
check_tool xcodegen xcodegen --version
check_tool swift swift --version
check_tool uv uv --version
check_tool python3 python3 --version
check_tool git git --version
check_tool gh gh --version
check_tool az az version --query '"azure-cli"' -o tsv
check_tool azd azd version

if command -v az >/dev/null 2>&1; then
  if az account show --query name -o tsv >/dev/null 2>&1; then ok "az logged in"; else warn "az not logged in (human: az login)"; fi
fi
if command -v azd >/dev/null 2>&1; then
  if azd auth login --check-status >/dev/null 2>&1; then ok "azd logged in"; else warn "azd not logged in (human: azd auth login)"; fi
fi
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then ok "gh logged in"; else warn "gh not logged in"; fi
fi

if command -v claude >/dev/null 2>&1; then
  mcp=$(claude mcp list 2>&1) || true
  if printf '%s' "$mcp" | grep -qi 'microsoft-learn'; then
    ok "MCP server microsoft-learn configured"
  else
    warn "MCP server microsoft-learn not found in 'claude mcp list'"
  fi
else
  warn "claude CLI not found; cannot list MCP servers"
fi

exit "$fail"
