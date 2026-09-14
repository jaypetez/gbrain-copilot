# Keeping this fork current with upstream gbrain

`gbrain-copilot` is a fork of [garrytan/gbrain](https://github.com/garrytan/gbrain)
that adds GitHub Copilot CLI support. Upstream ships fast. If nobody syncs, the
fork goes stale *quietly* — nothing errors, you just stop getting new gbrain
while still shipping releases that look current.

This doc is the repeatable procedure. It was written from the v0.42.37.0 →
v0.50.0.0 sync (748 upstream commits, 41 conflicting files) and reflects what
that sync actually taught us.

## TL;DR

```bash
scripts/sync-upstream.sh            # how far behind are we?
scripts/sync-upstream.sh --merge    # branch + merge; leaves conflicts for you
# ... resolve (see "Resolution policy" below) ...
bun run check:fork-hygiene         # stale upstream URLs + version-stamp drift
bun run typecheck && bun test
/ship                               # never hand-roll the release
```

Run the report every few weeks, or any time you are about to cut a release.
Being 2 upstream releases behind is a 20-minute merge. Being 8 behind is a day.

## Why the fork can't just track upstream

Three classes of change make this a real merge and not a fast-forward:

1. **The Copilot overlay** — `--agent copilot`, the marketplace manifest, the
   generated `plugins/gbrain/` payload, `COPILOT.md`, the
   `using-gbrain-with-copilot` skill. Upstream has no equivalent.
2. **Fork coordinates** — this fork installs, self-updates, and verifies release
   binaries from `jaypetez/gbrain-copilot` on `main`, not `garrytan/gbrain` on
   `master`. Every merge drags in new hardcoded upstream URLs.
3. **Fork behaviour deltas** — e.g. `gbrain doctor` exits 0/1/2 here and 0/1
   upstream.

## Resolution policy

Apply these in order. They are ranked by how much future pain they save.

### 1. Prefer upstream's implementation of a fix the fork also made

Both projects fix the same reported bugs. When upstream landed its own version
of something the fork already fixed, **take upstream's** — it is usually a
superset and it stops the file from conflicting again on every future sync.
Real examples from the v0.50.0.0 sync:

| Fork fix | Upstream's version | Outcome |
|---|---|---|
| `whoami` over stdio returned OS identity | `#1061` returns `{transport:'stdio', scopes:[]}` | Took upstream's — no OS username over an MCP pipe |
| win32 `serve` watchdog via a separate signal-0 reader | folded the platform split into `readLiveParentPid` / `probeWatchdogAvailable` | Took upstream's — wider coverage, fewer seams |
| `jsonb_integrity` per-target try/catch | `to_regclass` existence probe + 3 more targets | Took upstream's |
| cross-platform `postinstall` | Bun-native `which()` + `spawnSync` | Took upstream's |

### 2. Port fork behaviour INTO the module upstream peeled it to

Upstream refactors constantly (`operations.ts` → `src/core/ops/*`, `doctor.ts` →
`src/commands/doctor/checks/*`, both engines → `src/core/{pglite,postgres}-engine/*`).
When a conflict is "fork edited a function upstream moved", the answer is
**never** to resurrect the inline copy — take upstream's deletion and re-apply
the fork's behaviour in its new home. Otherwise you end up with two copies and
the dead one silently wins or loses depending on import order.

### 3. Keep genuinely fork-specific behaviour, and say so in a comment

`gbrain doctor`'s 0/1/2 exit contract is a real fork feature. It stays — but
implemented on top of whatever mechanism upstream now uses (`setCliExitVerdict`,
not `process.exit`), with a comment naming it as a fork delta so the next person
doesn't "fix" it back to upstream's 0/1.

### 4. Generated files: regenerate, never hand-merge

- `llms.txt` / `llms-full.txt` → `bun run build:llms`
- `plugins/gbrain/**` → `bash scripts/build-copilot-plugin.sh`
- `templates/bootstrap/template-repo/` → `bun run scripts/generate-template-repo.ts --out templates/bootstrap/template-repo`
- `bun.lock` → `bun install`

Resolve the conflict any way that parses, then regenerate and commit the result.

## The fork-coordinate sweep (do not skip)

**This is the step that breaks things silently if you skip it.** Every merge
brings new upstream code with `garrytan/gbrain` baked in. The highest-stakes one:

> `src/core/binary-self-update.ts` verifies a downloaded binary against a GitHub
> build-provenance attestation pinned to a specific repo and branch. Merged
> as-is, it pins `garrytan/gbrain@refs/heads/master` — so **every** self-update
> of a fork-built binary fails its integrity check and refuses to install.

All of it routes through [`src/core/repo-coordinates.ts`](../src/core/repo-coordinates.ts).
After a merge, sweep for reintroduced upstream coordinates:

```bash
# Functional coordinates in source — these change runtime behaviour.
grep -rn 'garrytan/gbrain' src/ --include=*.ts \
  | grep -v 'UPSTREAM_REPO\|gbrain-evals\|gbrain-skillpack-registry'

# Shipped docs/skills/scripts — CI-gated for the raw-URL class.
bun run check:fork-hygiene
```

Fix by importing from `repo-coordinates.ts` rather than editing the literal.
What must be repointed:

- release/attestation identity (`binary-self-update.ts`)
- version probe + release-notes URL (`check-update.ts`)
- install commands and release links (`upgrade.ts`)
- the npm-squat repo marker (`npm-squat-check.ts`)
- install hints (`bootstrap.ts`, `bootstrap/template-repo.ts`, `pglite-embedded-assets.ts`, `agent-install/state.ts`)
- doc links (`harness/registry.ts`, `creds/errors.ts`, `serve-http.ts`, `schema-version-health.ts`)
- every `raw.githubusercontent.com/...`, `github:...`, and `plugin marketplace add ...`
  in README / COPILOT.md / INSTALL_FOR_AGENTS.md / `docs/` / `skills/` / `scripts/`

What must **not** be repointed:

- `CHANGELOG.md` (historical record — CI excludes it)
- `garrytan/gbrain-evals` and `garrytan/gbrain-skillpack-registry` (real sibling
  repos this fork consumes)
- prose crediting the upstream project
- upstream issue numbers in code comments (keep as `upstream context: garrytan/gbrain#NNN`)

## Versioning across a sync

Fork releases use the upstream version they contain plus a fork `.MICRO`:
upstream `0.50.0.0` + first fork release → **`0.50.0.1`**. This keeps the
version honest about which upstream is inside.

> Before the first sync, the fork had drifted into issuing its own
> `0.42.39.0` while upstream separately shipped a *different* `0.42.39.0`.
> Both entries survive in `CHANGELOG.md`; the fork's are tagged
> `(gbrain-copilot fork)` to disambiguate. Don't create more of those.

After the merge, run the three-line audit from `CLAUDE.md` and stamp the full
version set (`VERSION`, `package.json`, `plugin.json`, both
`.github/plugin/marketplace.json` fields, `plugins/gbrain/plugin.json`,
`openclaw.plugin.json`, `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`,
the `BOOTSTRAP_FOR_AGENTS.md` runbook stamp).

## Post-merge checklist

```bash
bun run typecheck                  # first — surfaces every leftover reference
bun run verify                     # guards incl. check:fork-hygiene
bash scripts/check-bootstrap-tag.sh
bun test > /tmp/units.txt 2>&1; echo "EXIT=$?"   # never pipe to tail; see CLAUDE.md
bun run build:llms                 # any CLAUDE.md / doc edit needs this
bash scripts/build-copilot-plugin.sh
```

Then verify the fork overlay still works end to end:

- `gbrain connect <url> --agent copilot --install` writes `mcp-config.json`
- `copilot plugin install gbrain@gbrain-copilot` installs the thin payload
- `gbrain doctor` on a fresh brain exits 0 (not 1 — the fresh-brain demotions
  are a fork behaviour and merges love to revert them)

Finally: **`/ship`**. Never hand-roll the release.

## When upstream refactors something the fork owns

If a sync ever gets painful enough that you consider carrying a patch series
instead of a merge — don't. The right move is the opposite: push the fork's
generic improvements upstream so there is less delta to carry. Anything in the
fork that isn't Copilot-specific or coordinate-specific is a candidate.
