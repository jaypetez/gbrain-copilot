#!/usr/bin/env bash
# build-copilot-plugin.sh — regenerate the thin Copilot CLI plugin payload.
#
# The marketplace manifest (.github/plugin/marketplace.json) points Copilot
# CLI at metadata.pluginRoot = ./plugins, so `copilot plugin install
# gbrain@gbrain-copilot` installs ONLY plugins/gbrain/ instead of the whole
# repo (Copilot CLI honors no files allowlist and no .copilotignore — the
# pluginRoot subdirectory is the only honored thin-payload mechanism).
#
# Payload contents:
#   plugins/gbrain/skills/      verbatim copy of skills/ (conventions/ +
#                               migrations/ stay — shared deps referenced
#                               by the skills themselves)
#   plugins/gbrain/agents/      copy of .github/agents/gbrain.agent.md
#   plugins/gbrain/plugin.json  root plugin.json with payload-relative
#                               agents/skills paths + version from VERSION
#   plugins/gbrain/README.md    what-this-is pointer back to the repo
#
# Deterministic + idempotent: run twice, `git diff` stays clean. Drift
# between skills/ + the agent file and the committed payload is gated by
# scripts/check-fork-hygiene.sh (run this script to fix).

set -euo pipefail

cd "$(dirname "$0")/.."

rm -rf plugins/gbrain
mkdir -p plugins/gbrain/agents

cp -R skills plugins/gbrain/skills
cp .github/agents/gbrain.agent.md plugins/gbrain/agents/

# plugin.json: derive from the root manifest; only the agents/skills paths
# (payload-relative) and the version (from VERSION) change.
bun -e '
const { readFileSync, writeFileSync } = require("fs");
const manifest = JSON.parse(readFileSync("plugin.json", "utf8"));
manifest.version = readFileSync("VERSION", "utf8").trim();
manifest.agents = "agents";
manifest.skills = "skills";
writeFileSync("plugins/gbrain/plugin.json", JSON.stringify(manifest, null, 2) + "\n");
'

cat > plugins/gbrain/README.md <<'EOF'
# gbrain — Copilot CLI plugin payload

This directory is the **generated** install payload for the GitHub Copilot
CLI plugin (`copilot plugin install gbrain@gbrain-copilot`). The marketplace
manifest at `.github/plugin/marketplace.json` points Copilot CLI here via
`metadata.pluginRoot`, so installs ship only this subtree, not the repo.

Do not edit by hand — regenerate with `scripts/build-copilot-plugin.sh`
from the repo root: <https://github.com/jaypetez/gbrain-copilot>.

Note: `skills/conventions/` and `skills/migrations/` are reference material
shared by the other skills (cross-cutting rules + upgrade walkthroughs),
not broken skills missing a SKILL.md.
EOF

echo "Built plugins/gbrain/ (skills + agent + plugin.json + README)" >&2
