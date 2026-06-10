# Connect GBrain to GitHub Copilot CLI

> New to this? [`COPILOT.md`](../../COPILOT.md) at the repo root is the
> entry point (fastest path, plugin install, troubleshooting). This page is
> the connection reference. Copilot CLI here means the agentic terminal tool
> (`npm i -g @github/copilot`, command `copilot`) — not the old gh extension.

## Option 0: Plugin (one step, ships everything)

Inside `copilot`:

```
/plugin install jaypetez/gbrain-copilot
```

This registers the `gbrain` MCP server (local stdio), all bundled skills,
and the `gbrain` custom agent from one manifest ([`plugin.json`](../../plugin.json)).
Prerequisite: the `gbrain` CLI must be on PATH (`bun install -g
github:jaypetez/gbrain-copilot`, or run `scripts/install-copilot.ps1` /
`scripts/install-copilot.sh`). If `/mcp` shows gbrain failing to start,
that prerequisite is what's missing.

## Option 1: Local stdio (no plugin, zero server)

Merge this into `~/.copilot/mcp-config.json` (or
`$COPILOT_HOME/mcp-config.json` if you override the config dir):

```json
{
  "mcpServers": {
    "gbrain": {
      "type": "local",
      "command": "gbrain",
      "args": ["serve"],
      "tools": ["*"]
    }
  }
}
```

Or use the interactive form: run `copilot`, then `/mcp add` (name `gbrain`,
type local, command `gbrain`, args `serve`). The server is available
immediately — no restart needed. Works with both PGLite and Postgres
engines. The installer scripts (`scripts/install-copilot.ps1|sh`) write
this entry for you, preserving any other servers in the file.

## Option 2: Remote, one command (from a bearer token)

If GBrain runs somewhere as an HTTP server (`gbrain serve --http`, see the
[ngrok-tunnel recipe](../../recipes/ngrok-tunnel.md)) and you have a bearer
token, let `gbrain connect` generate (or apply) the wire-up.

On the host, mint a token and print the paste-ready block:

```bash
gbrain auth create "copilot"
gbrain connect https://YOUR-DOMAIN.ngrok.app/mcp --token gbrain_xxx --agent copilot
```

Already on the machine you want to wire up? Let `connect` write
`mcp-config.json` directly, with a built-in token smoke-test:

```bash
gbrain connect https://YOUR-DOMAIN.ngrok.app --token gbrain_xxx --agent copilot --install
```

(`--install` merges the server entry into `~/.copilot/mcp-config.json` —
honoring `$COPILOT_HOME` — then verifies the token by calling
`get_brain_identity`, so a wrong or expired token fails now, not silently on
the agent's first request. An existing `gbrain` entry is only replaced with
`--force`.)

Pipe-friendly machine output (token redacted unless `--show-token`):

```bash
gbrain connect https://YOUR-DOMAIN.ngrok.app/mcp --token gbrain_xxx --agent copilot --json
```

## Option 3: Remote, manual config

Equivalent to what `gbrain connect --agent copilot` generates:

```json
{
  "mcpServers": {
    "gbrain": {
      "type": "http",
      "url": "https://YOUR-DOMAIN.ngrok.app/mcp",
      "headers": { "Authorization": "Bearer YOUR_TOKEN" },
      "tools": ["*"]
    }
  }
}
```

Replace `YOUR_TOKEN` with a token from `gbrain auth create "copilot"`.

> A `gbrain auth create` token is a long-lived, full-access secret. It lands
> in plaintext in `mcp-config.json` — keep that file private, and prefer a
> scoped/short-lived token where your host supports one.

## Verify

In Copilot CLI, `/mcp` should list `gbrain` as running. Then try:

```
search for [any topic in your brain]
```

You should see results from your GBrain knowledge base.

> **`list_skills` returns nothing?** Skill discovery is gated by
> `mcp.publish_skills` on the host. New brains from `gbrain init` default it
> ON; brains upgraded from an older release stay OFF until you opt in:
> `gbrain config set mcp.publish_skills true`. The core tools (search, query,
> get_page, put_page, think, find_experts) work regardless. Note: `capture`
> is a CLI-only command, not an MCP tool — the agent writes over MCP with
> `put_page`.

## Skills and the custom agent

- **Via the plugin (recommended):** `/plugin install jaypetez/gbrain-copilot`
  ships all `skills/*/SKILL.md` and the `gbrain` agent
  (`.github/agents/gbrain.agent.md`; select it with `/agent`).
- **Manual skills:** copy skill directories into `~/.copilot/skills/`
  (user-wide) or your repo's `.github/skills/` (repo-scoped). The installer
  scripts offer `-CopySkills` / `--copy-skills` for the user-wide path.
- Pick ONE path — plugin + manual copies produce duplicate skill names.

## Permissions

Copilot CLI prompts per tool by default. Pre-approve gbrain's tools for a
session with:

```bash
copilot --allow-tool 'gbrain'
```

or persist it in `~/.copilot/permissions-config.json`. `--allow-all-tools`
exists but approves everything — prefer the scoped form.

## Remove

Delete the `gbrain` entry from `~/.copilot/mcp-config.json` (or use `/mcp`
→ select gbrain → remove). Plugin installs: `/plugin uninstall gbrain`.
