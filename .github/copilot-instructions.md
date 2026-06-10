# Copilot instructions for gbrain-copilot

This repo is GBrain — a Bun/TypeScript knowledge brain (CLI + MCP server) —
forked from garrytan/gbrain with first-class GitHub Copilot CLI support.

- **Using GBrain from Copilot CLI?** Read `COPILOT.md` (entry point) and
  `docs/mcp/COPILOT_CLI.md` (connection reference).
- **Working on the codebase?** Read `AGENTS.md` (install + operating
  protocol), then `CLAUDE.md` (architecture, invariants, reference map).
  Read a file's entry in `docs/architecture/KEY_FILES.md` before editing it.
- **Skills routing:** `skills/RESOLVER.md` dispatches tasks to the ~50
  bundled skills (`skills/*/SKILL.md`, YAML-frontmatter triggers).
- **Runtime is Bun-only** (`engines.bun >= 1.3.10`). Build/test with `bun`,
  never node/npm: `bun run typecheck`, `bun test`, `bun run check:resolver`.
- **Trust boundary:** CLI callers are trusted (`remote=false`); MCP/HTTP
  callers are not (`remote=true`). Consult `src/core/operations.ts` before
  touching any operation contract.
- **Privacy:** never commit real names of people, companies, or funds into
  public artifacts — use placeholders (`alice-example`, `acme-example`).
