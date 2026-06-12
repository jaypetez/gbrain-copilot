# GBrain for GitHub Copilot CLI

This is the GitHub Copilot CLI entry point for **gbrain-copilot** — a
self-sufficient fork of [garrytan/gbrain](https://github.com/garrytan/gbrain)
(Garry Tan's agent brain, MIT) with Copilot CLI as a first-class platform.
Everything installs and upgrades from this repo; you never need upstream.

What you get inside Copilot CLI:

- **30+ MCP tools** (`search`, `query`, `think`, `get_page`, `put_page`,
  `find_experts`, graph traversal, timelines, …) served by `gbrain serve`.
- **~50 Agent Skills** (`skills/*/SKILL.md`) — querying, capture, ingestion,
  enrichment, briefings, daily tasks, schema authoring, reports.
- **A `gbrain` custom agent** (`.github/agents/gbrain.agent.md`) that runs
  the brain-first protocol: search the brain before answering, write back
  what it learns, cite every claim.

## Fastest path

**1. Get the gbrain CLI on PATH** (one-time; installs Bun if missing, creates
a local PGLite brain, wires the MCP config):

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/jaypetez/gbrain-copilot/main/scripts/install-copilot.ps1 | iex
```

```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/jaypetez/gbrain-copilot/main/scripts/install-copilot.sh | bash
```

**2. Install the plugin** (ships the skills + the gbrain agent + the MCP
server entry in one step). Inside `copilot`:

```
/plugin install jaypetez/gbrain-copilot
```

**3. Verify.** `/mcp` should list `gbrain` as running. Then try:

```
search my brain for [any topic]
```

## Manual path

```bash
# install Bun, then:
bun install -g github:jaypetez/gbrain-copilot
gbrain init --pglite          # 2-second local brain, no server
gbrain doctor                 # verify health
```

Then wire the MCP server using any one of: `/plugin install
jaypetez/gbrain-copilot`, the interactive `/mcp add` form, or by merging
this into `~/.copilot/mcp-config.json` (or `$COPILOT_HOME/mcp-config.json`):

```json
{
  "mcpServers": {
    "gbrain": { "type": "local", "command": "gbrain", "args": ["serve"], "tools": ["*"] }
  }
}
```

Full connection reference (local stdio, remote HTTP with bearer tokens,
`gbrain connect --agent copilot`, permissions, troubleshooting):
[`docs/mcp/COPILOT_CLI.md`](docs/mcp/COPILOT_CLI.md).

Full agent-driven install (API keys, search-mode choice, import, dream
cycle): [`INSTALL_FOR_AGENTS.md`](INSTALL_FOR_AGENTS.md).

## How Copilot CLI uses gbrain

| Surface | Where it comes from |
|---|---|
| MCP tools | `gbrain serve` (stdio), declared in mcp-config.json or via the plugin |
| Agent Skills | `skills/` via the plugin, or copy to `~/.copilot/skills/` / your repo's `.github/skills/` |
| `gbrain` custom agent | `.github/agents/gbrain.agent.md` via the plugin (select with `/agent`) |
| Custom instructions | root `AGENTS.md` (auto-read by Copilot CLI in this repo) + `.github/copilot-instructions.md` |

Pick ONE skills path (plugin OR manual copy) — installing both produces
duplicate skill names.

## Troubleshooting

- **`/mcp` shows gbrain failed to start** → the gbrain CLI is not on PATH or
  the brain is not initialized. Run the installer script above, then check
  `gbrain --version` and `gbrain doctor`.
- **`list_skills` errors over MCP** → two config keys gate it, in order:
  1. `permission_denied` ("Skill publishing is disabled") → enable the
     publish gate: `gbrain config set mcp.publish_skills true`.
  2. `storage_error` ("No skills directory found") → autodetect found no
     skills dir on the host; point it at one:
     `gbrain config set mcp.skills_dir <path>` (or `$GBRAIN_SKILLS_DIR`).
     Plugin installs ship the skills at
     `$env:USERPROFILE\.copilot\installed-plugins\_direct\jaypetez--gbrain-copilot\skills`
     (PowerShell) /
     `~/.copilot/installed-plugins/_direct/jaypetez--gbrain-copilot/skills`
     (macOS/Linux).

  Core tools work regardless of either key.
- **Tool permission prompts** → pre-approve with
  `copilot --allow-tool 'gbrain'` (or edit `~/.copilot/permissions-config.json`).
- **Anything else** → `gbrain doctor --json` names the failing check and the
  paste-ready fix.

## Read order for agents

1. `COPILOT.md` (this file) — Copilot CLI wiring.
2. [`AGENTS.md`](AGENTS.md) — install + operating protocol (Copilot CLI
   auto-loads this as custom instructions when working in this repo).
3. [`CLAUDE.md`](CLAUDE.md) — architecture orientation (written for Claude
   Code, accurate for everyone).
4. [`skills/RESOLVER.md`](skills/RESOLVER.md) — skill dispatcher. Read
   before any task.

## Attribution

GBrain is Garry Tan's work — [garrytan/gbrain](https://github.com/garrytan/gbrain),
MIT. This fork adds GitHub Copilot CLI support (plugin manifest, custom
agent, `gbrain connect --agent copilot`, installers, docs) and tracks
upstream releases. Bugs in the Copilot integration belong
[here](https://github.com/jaypetez/gbrain-copilot/issues); credit for
everything else belongs upstream.
