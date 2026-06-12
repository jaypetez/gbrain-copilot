#!/usr/bin/env bash
# CI guard: fork-specific hygiene for gbrain-copilot.
#
# Three sections, each fail-loud:
#   1. Version sync — VERSION is the single source of truth; the Copilot
#      manifests (plugin.json, plugins/gbrain/plugin.json, and both version
#      fields in .github/plugin/marketplace.json) must match it.
#      (openclaw.plugin.json is the upstream OpenClaw manifest and is
#      intentionally NOT version-synced.)
#   2. Stale upstream URLs — raw-githubusercontent coordinates under the
#      upstream garrytan gbrain repo 404 or serve upstream content in this
#      fork; every shipped doc/script must point at jaypetez/gbrain-copilot.
#      The trailing slash after "gbrain" in STALE_PATTERN keeps the
#      legitimate sibling repo garrytan/gbrain-skillpack-registry out of
#      the match. CHANGELOG.md is excluded (historical record).
#   3. Payload drift — plugins/gbrain/ is generated from skills/ + the
#      gbrain agent by scripts/build-copilot-plugin.sh; a stale payload
#      ships outdated skills to plugin installs.
#
# Sibling to scripts/check-trailing-newline.sh per CLAUDE.md's CI guard
# pattern. Wired into `bun run verify` via run-verify-parallel.sh.
#
# Exit codes: 0 clean, 1 violation found.

set -euo pipefail

cd "$(dirname "$0")/.."

FAILED=0

# ── Section 1: version sync ────────────────────────────────────────────────
VERSION=$(tr -d '[:space:]' < VERSION)

json_get() {
  # $1 = file, $2 = dot path (e.g. metadata.version, plugins.0.version).
  # Prints the value, or nothing if the path is missing.
  JG_FILE="$1" JG_PATH="$2" bun -e '
    const obj = JSON.parse(require("fs").readFileSync(process.env.JG_FILE, "utf8"));
    const v = process.env.JG_PATH.split(".").reduce((o, k) => (o == null ? o : o[k]), obj);
    if (typeof v === "string") process.stdout.write(v);
  '
}

check_version() {
  local file="$1" keypath="$2" got
  [ -f "$file" ] || return 0
  got=$(json_get "$file" "$keypath")
  if [ "$got" != "$VERSION" ]; then
    echo "ERROR: $file .$keypath = '$got' but VERSION = '$VERSION'" >&2
    FAILED=1
  fi
}

check_version "plugin.json" "version"
check_version "plugins/gbrain/plugin.json" "version"
check_version ".github/plugin/marketplace.json" "metadata.version"
check_version ".github/plugin/marketplace.json" "plugins.0.version"

# ── Section 2: stale upstream raw URLs ─────────────────────────────────────
# llms.txt / llms-full.txt are committed generator output — a stale URL
# there means the source doc was fixed without `bun run build:llms`.
STALE_PATTERN='raw\.githubusercontent\.com/garrytan/gbrain/'
URL_FILES=$(
  git ls-files \
    'llms.txt' 'llms-full.txt' 'README.md' 'COPILOT.md' 'INSTALL_FOR_AGENTS.md' \
    'docs/**' 'skills/**' 'scripts/**' 'plugins/**' \
  2>/dev/null | grep -v '^CHANGELOG\.md$' | sort -u
)

while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || continue
  if grep -n "$STALE_PATTERN" "$f" >/dev/null 2>&1; then
    echo "ERROR: stale upstream raw URL in $f:" >&2
    grep -n "$STALE_PATTERN" "$f" | sed 's|^|  |' >&2
    echo "  Fix: point at raw.githubusercontent.com/jaypetez/gbrain-copilot/main/... instead" >&2
    echo "  (llms.txt / llms-full.txt: fix the source doc, then run \`bun run build:llms\`)" >&2
    FAILED=1
  fi
done <<< "$URL_FILES"

# ── Section 3: payload drift ───────────────────────────────────────────────
if [ -d plugins/gbrain ]; then
  if ! diff -r skills plugins/gbrain/skills >/dev/null 2>&1; then
    echo "ERROR: plugins/gbrain/skills is out of sync with skills/." >&2
    echo "  Fix: run scripts/build-copilot-plugin.sh and commit the result." >&2
    diff -rq skills plugins/gbrain/skills 2>&1 | head -10 | sed 's|^|  |' >&2 || true
    FAILED=1
  fi
  if ! cmp -s .github/agents/gbrain.agent.md plugins/gbrain/agents/gbrain.agent.md; then
    echo "ERROR: plugins/gbrain/agents/gbrain.agent.md is out of sync with .github/agents/gbrain.agent.md." >&2
    echo "  Fix: run scripts/build-copilot-plugin.sh and commit the result." >&2
    FAILED=1
  fi
fi

if [ "$FAILED" -eq 1 ]; then
  exit 1
fi

echo "fork-hygiene check: ok (version=$VERSION)"
