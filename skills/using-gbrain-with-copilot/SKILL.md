---
name: using-gbrain-with-copilot
version: 1.0.0
description: |
  Wire, verify, and troubleshoot gbrain inside GitHub Copilot CLI: plugin
  install, mcp-config.json, the gbrain custom agent, tool permissions, and
  the brain-first protocol. Use when connecting Copilot CLI to a brain or
  when Copilot cannot see gbrain tools.
triggers:
  - "connect gbrain to copilot"
  - "copilot mcp"
  - "gbrain in copilot"
  - "copilot can't see my brain"
  - "copilot cli setup"
  - "install the gbrain plugin"
  - "copilot plugin"
  - "wire copilot to the brain"
tools:
  - get_brain_identity
  - list_skills
  - search
mutating: false
brain_first: exempt
---

# Using GBrain with GitHub Copilot CLI

Wire GitHub Copilot CLI (the agentic terminal tool, `npm i -g
@github/copilot`) to a gbrain, verify the connection, and fix the common
failure modes. The full reference is `docs/mcp/COPILOT_CLI.md`; this skill is
the operational workflow.

## Contract

This skill guarantees:
- Exactly ONE skills-delivery path is installed (plugin OR manual copy),
  never both — duplicates are flagged and resolved.
- The connection is verified end-to-end (`/mcp` status, `get_brain_identity`,
  a real `search`) before declaring success.
- Existing MCP servers in `mcp-config.json` are never clobbered.
- Every failure mode ends with a paste-ready fix, not a shrug.

## Preflight

1. `gbrain --version` — if it fails, the CLI is not installed. Run
   `scripts/install-copilot.ps1` (Windows) or `scripts/install-copilot.sh`
   (macOS/Linux), or: install Bun, then
   `bun install -g github:jaypetez/gbrain-copilot`.
2. `gbrain doctor --json` — every check should pass. A missing brain means
   `gbrain init --pglite` has not run yet.

## Wiring (pick exactly ONE skills path)

- **Plugin (recommended):** inside `copilot`, run
  `/plugin marketplace add jaypetez/gbrain-copilot`, then
  `/plugin install gbrain@gbrain-copilot`. Ships the MCP server entry,
  all bundled skills, and the `gbrain` custom agent. (Older Copilot CLI
  versions can still use `/plugin install jaypetez/gbrain-copilot`, with a
  deprecation warning and a whole-repo install.)
- **Manual local:** merge
  `{"mcpServers":{"gbrain":{"type":"local","command":"gbrain","args":["serve"],"tools":["*"]}}}`
  into `~/.copilot/mcp-config.json` (honors `$COPILOT_HOME`), or use the
  `/mcp add` interactive form. Optionally copy skill directories to
  `~/.copilot/skills/`.
- **Remote brain:** on the host, `gbrain auth create "copilot"`, then
  `gbrain connect https://host/mcp --token gbrain_xxx --agent copilot
  --install` (merges the http+bearer entry and smoke-tests the token).

Installing the plugin AND copying skills manually produces duplicate skill
names — choose one.

## Verify

1. `/mcp` lists `gbrain` as running.
2. Call `get_brain_identity` — confirms whose brain this is.
3. Call `list_skills` — if it errors, the host has skill publishing off:
   `gbrain config set mcp.publish_skills true`. Core tools (search, query,
   get_page, put_page, think, find_experts) work regardless.
4. Run a real `search` for a topic the user knows is in the brain.

## Permissions

Copilot CLI prompts per tool use. Pre-approve gbrain for a session with
`copilot --allow-tool 'gbrain'`, or persist in
`~/.copilot/permissions-config.json`. Avoid `--allow-all-tools`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `/mcp` shows gbrain failed to start | gbrain CLI not on PATH or brain not initialized — run the installer, check `gbrain --version` + `gbrain doctor` |
| `list_skills` errors | `gbrain config set mcp.publish_skills true` on the host |
| Remote: 401 on every call | token wrong/expired — re-run `gbrain connect ... --agent copilot --install` with a fresh token |
| Slow first response on PGLite | cold WASM start; subsequent calls are fast. Stop `gbrain serve` before large `gbrain sync` runs (single-writer) |
| Duplicate skills listed | plugin + manual copy both installed — remove one (`/plugin uninstall gbrain` or delete from `~/.copilot/skills/`) |

## Anti-Patterns

- **Installing both skills paths.** `/plugin install` AND copying to
  `~/.copilot/skills/` produces duplicate skill names. Pick one.
- **Hand-editing mcp-config.json into invalid JSON.** Use `/mcp add`,
  `gbrain connect --agent copilot --install`, or the installer scripts —
  all three merge safely and refuse to clobber.
- **`--allow-all-tools` to silence permission prompts.** Scope it:
  `copilot --allow-tool 'gbrain'`.
- **Declaring success without a live search.** `/mcp` showing "running"
  proves the process spawned, not that the brain answers — always run a
  real query against known content.
- **Putting the bearer token anywhere except the Authorization header in
  mcp-config.json.** It is a long-lived full-access secret; never echo it
  into chat output or shell history.

## Output Format

After wiring, report to the user:

```
GBrain ↔ Copilot CLI: CONNECTED
  Transport:  local stdio (gbrain serve)   [or: remote http <url>]
  Skills:     via plugin jaypetez/gbrain-copilot   [or: ~/.copilot/skills/ | none]
  Agent:      gbrain (/agent to select)
  Verified:   get_brain_identity ✓ · list_skills ✓ (52) · search ✓
  Next:       ask "search my brain for <topic>"
```

On failure, report the failing step, the symptom row from Troubleshooting
that matches, and the paste-ready fix command.

## After wiring

Adopt the brain-first protocol: search the brain before answering or
writing anything entity-shaped (`skills/conventions/brain-first.md`), fire
the signal detector on inbound messages (`skills/signal-detector/SKILL.md`),
and route tasks via `skills/RESOLVER.md`.
