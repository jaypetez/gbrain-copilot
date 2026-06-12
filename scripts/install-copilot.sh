#!/usr/bin/env bash
# install-copilot.sh — set up gbrain for GitHub Copilot CLI on macOS/Linux.
#
# Installs Bun if missing, installs gbrain from this fork, runs schema
# migrations, creates a local PGLite brain, and merges the gbrain MCP server
# entry into Copilot CLI's mcp-config.json (preserving existing servers).
#
# Usage (from a clone):  ./scripts/install-copilot.sh [--yes] [--copy-skills] [--skip-init]
# Usage (one-liner):     curl -fsSL https://raw.githubusercontent.com/jaypetez/gbrain-copilot/main/scripts/install-copilot.sh | bash
#
#   --yes          Non-interactive: accept prompts, replace an existing
#                  gbrain MCP entry if present.
#   --copy-skills  Also copy bundled skills to ~/.copilot/skills/ (skip if
#                  you plan to install the plugin via `/plugin marketplace add
#                  jaypetez/gbrain-copilot` + `/plugin install gbrain@gbrain-copilot`,
#                  which ships them — using both duplicates skill names).
#   --skip-init    Skip `gbrain init` (brain already exists).

set -euo pipefail

REPO="github:jaypetez/gbrain-copilot"
YES=0
COPY_SKILLS=0
SKIP_INIT=0
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --copy-skills) COPY_SKILLS=1 ;;
    --skip-init) SKIP_INIT=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\n==> %s\n' "$1"; }

# --- 1. Bun -----------------------------------------------------------------
step "Checking for Bun"
if ! command -v bun >/dev/null 2>&1; then
  step "Installing Bun"
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
  command -v bun >/dev/null 2>&1 || { echo "Bun installed but not on PATH. Open a new shell and re-run." >&2; exit 1; }
  echo "NOTE: add 'export PATH=\"\$HOME/.bun/bin:\$PATH\"' to your shell profile."
fi
echo "Bun $(bun --version)"

# --- 2. gbrain ----------------------------------------------------------------
step "Installing gbrain ($REPO)"
bun install -g "$REPO"
command -v gbrain >/dev/null 2>&1 || export PATH="$HOME/.bun/bin:$PATH"
command -v gbrain >/dev/null 2>&1 || { echo "gbrain not on PATH after install (try: bun pm bin -g)" >&2; exit 1; }
echo "gbrain $(gbrain --version)"

# Bun sometimes skips the postinstall hook on global installs — run the
# migrations explicitly (idempotent; no-op on a fresh install with no brain).
step "Applying schema migrations (idempotent)"
gbrain apply-migrations --yes --non-interactive || echo "WARN: apply-migrations reported an issue; gbrain doctor will diagnose after init." >&2

# --- 3. Brain -------------------------------------------------------------------
if [ "$SKIP_INIT" -eq 0 ]; then
  step "Creating the brain (PGLite, local, no server)"
  echo "NOTE: init may ask about embedding providers and search mode — answer the prompts."
  if [ "$YES" -eq 1 ]; then
    gbrain init --pglite --yes || echo "WARN: gbrain init did not complete cleanly; run gbrain doctor." >&2
  else
    gbrain init --pglite || echo "WARN: gbrain init did not complete cleanly; run gbrain doctor." >&2
  fi
else
  step "Skipping gbrain init (--skip-init)"
fi

# --- 4. Copilot CLI MCP config ---------------------------------------------------
step "Wiring the Copilot CLI MCP config"
COPILOT_DIR="${COPILOT_HOME:-$HOME/.copilot}"
CONFIG="$COPILOT_DIR/mcp-config.json"
mkdir -p "$COPILOT_DIR"

# JSON merge via bun (always present at this point) — preserves existing
# servers, refuses to clobber an existing gbrain entry without --yes, and
# refuses to rewrite unparseable JSON.
FORCE="$YES" CONFIG_PATH="$CONFIG" bun -e '
const { readFileSync, writeFileSync, existsSync } = require("fs");
const path = process.env.CONFIG_PATH;
const force = process.env.FORCE === "1";
let root = {};
if (existsSync(path)) {
  const raw = readFileSync(path, "utf8");
  if (raw.trim() !== "") {
    try { root = JSON.parse(raw); }
    catch { console.error("Existing " + path + " is not valid JSON - fix or remove it, then re-run."); process.exit(1); }
  }
}
root.mcpServers = root.mcpServers ?? {};
if (root.mcpServers.gbrain && !force) {
  console.error("An MCP server named gbrain already exists in " + path + ". Re-run with --yes to replace it.");
  process.exit(0);
}
root.mcpServers.gbrain = { type: "local", command: "gbrain", args: ["serve"], tools: ["*"] };
writeFileSync(path, JSON.stringify(root, null, 2) + "\n");
console.log("Wrote gbrain MCP server entry to " + path);
'

# --- 5. Skills (optional) -----------------------------------------------------------
if [ "$COPY_SKILLS" -eq 1 ]; then
  step "Copying skills to $COPILOT_DIR/skills/"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
  SKILLS_SRC="$SCRIPT_DIR/../skills"
  if [ ! -d "$SKILLS_SRC" ]; then
    echo "WARN: skills/ not found next to this script (one-liner install?). Use /plugin marketplace add jaypetez/gbrain-copilot then /plugin install gbrain@gbrain-copilot inside copilot instead." >&2
  else
    mkdir -p "$COPILOT_DIR/skills"
    for d in "$SKILLS_SRC"/*/; do
      [ -f "$d/SKILL.md" ] || continue
      cp -R "$d" "$COPILOT_DIR/skills/$(basename "$d")"
    done
    echo "Copied skills (do NOT also install the plugin, or skill names will collide)"
  fi
fi

# --- 6. Verify + next steps -----------------------------------------------------------
step "Health check"
gbrain doctor || true

cat <<'EOF'

=============================================================
 gbrain is wired into GitHub Copilot CLI. Next steps:
   1. copilot                      # start Copilot CLI
   2. /mcp                         # confirm gbrain is running
   3. /plugin marketplace add jaypetez/gbrain-copilot
   4. /plugin install gbrain@gbrain-copilot     # skills + gbrain agent
   5. ask: "search my brain for <topic>"
 Docs: COPILOT.md and docs/mcp/COPILOT_CLI.md
=============================================================
EOF
