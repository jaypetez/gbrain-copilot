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
