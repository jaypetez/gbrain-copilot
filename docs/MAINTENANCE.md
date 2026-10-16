# Maintaining this fork

`jaypetez/gbrain-copilot` is a **self-contained fork** of
[`garrytan/gbrain`](https://github.com/garrytan/gbrain) that adds a GitHub
Copilot CLI packaging layer. This doc is the recurring runbook for keeping the
fork healthy, green, shippable, and current with upstream. It assumes you are
maintaining the **source repo** (not a live personal brain).

Upstream lives on branch `master`; this fork lives on `main`. Syncing is a
**reviewed merge with expected conflicts**, never a fast-forward, because the
fork owns an identity layer that must survive every merge.

## Prerequisites

- **Bun** — the whole toolchain runs on Bun (`package.json` floor is
  `>=1.4.0`; CI pins `1.4.3` in `.github/workflows/*`). Keep local Bun at or
  above the CI pin so "green locally" means "green in CI" (`bun upgrade`).
  Install from <https://bun.sh>.
- **git**, **gh** (GitHub CLI), and **Node** (used by a few scripts).

> **Windows note.** `bun run typecheck` and `bun run build` work natively.
> `bun run verify` / `bun run test` may not: some guards need a POSIX shell, and
> `scripts/check-privacy.sh` aborts inside Git Bash's `grep` (exit 134). Run
> individual guards directly with
> `bash scripts/check-*.sh`, run the full suite under **WSL / Git Bash**, or
> just rely on **CI** as the authoritative gate. A few guards also can't pass
> natively on Windows regardless (they run the compiled binary's image/WASM
> decoders, need a built `admin/dist`, or need a configured brain) — CI covers
> these.

---

## One-time setup

Wire up a **fetch-only** upstream remote (push disabled so you can never push to
it by accident):

```bash
git remote add upstream https://github.com/garrytan/gbrain.git
git remote set-url --push upstream DISABLE
git fetch upstream
```

Verify: `git remote -v` should show `upstream ... (fetch)` → `garrytan/gbrain`
and `upstream DISABLE (push)`.

---

## Cadence at a glance

| Cadence | Do this |
|---|---|
| **Monthly** | Sync from upstream + refresh dependencies (below) |
| **On any source change** | Regenerate affected artifacts + `bun run verify` + `bun test` |
| **Quarterly / pre-ship** | Refresh GitHub Actions SHAs |
| **Every release** | Ship with `/ship` |

---

## Monthly: sync from upstream

Treat every sync as a reviewed merge on its own branch.

```bash
git fetch upstream
git checkout main && git pull                 # local main == origin/main
# Review what you're behind on first:
git log --oneline --no-merges main..upstream/master | head -50
git diff --stat main upstream/master | tail -30

git checkout -b sync/upstream-$(date +%Y-%m-%d)
git merge upstream/master                      # conflicts are expected
```

### Conflict resolution rules

**Always keep YOURS on the fork-identity layer** — upstream knows nothing about
Copilot packaging, so its version of these files is always wrong for the fork:

- `src/core/repo-coordinates.ts` — the single source of truth (`GITHUB_REPO`,
  `UPSTREAM_REPO`, `DEFAULT_BRANCH = 'main'`, release/raw URLs)
- `plugin.json`, `.github/plugin/marketplace.json`, `plugins/gbrain/**`
- `scripts/install-copilot.ps1`, `scripts/install-copilot.sh`,
  `scripts/build-copilot-plugin.sh`
- `README.md`, `COPILOT.md`, `INSTALL_FOR_AGENTS.md`
- `.github/workflows/*` — the fork's CI deltas, which every sync must re-apply
  to whatever upstream changed (upstream restructures these constantly):
  - **Runners:** upstream uses Ubicloud labels (`ubicloud-standard-N-ubuntu-2404`);
    the fork has none, so rewrite them to `ubuntu-latest` (jobs would queue forever).
  - **Branch:** `main`, not `master` (triggers, `origin/master` baseline fetches,
    `blob/master` links). Leave `fix-wave-*.yml` and `nightly-watch.yml` on
    `master` — they are upstream-maintainer governance and stay inert here.
  - **No schedules:** every `schedule:`/cron is disabled (Actions budget); `e2e.yml`
    is **dispatch-only** (needs API-key secrets); heavy-tests runs via label/dispatch.
  - **Release gate:** `scripts/release-gate.ts` gates only on the `Test` workflow
    (`GATED`) and the `main` branch (`GATE_BRANCH`); upstream also requires E2E.
    Keep `test/scripts/release-gate.test.ts` in step.

**The version trio** (`VERSION`, `package.json`, `CHANGELOG.md`) — follow the
"Merge-conflict recovery procedure" in `CLAUDE.md`. Keep the fork's version line
(don't blindly adopt upstream's number); keep BOTH sets of CHANGELOG entries.
`/ship` enforces trio consistency at release time.

**Version stamps beyond the trio** — upstream's version table now also includes
`openclaw.plugin.json`, `.codex-plugin/plugin.json`, `.claude-plugin/plugin.json`,
`BOOTSTRAP_FOR_AGENTS.md` (line-1 stamp) and `templates/bootstrap/template-repo/`
(regenerate: `bun run scripts/generate-template-repo.ts --out templates/bootstrap/template-repo`),
in addition to the fork's `plugin.json`, `.github/plugin/marketplace.json` and
`plugins/gbrain/plugin.json`. Bump them all to the new `VERSION`.

**Peeled/restructured files** — when upstream splits a file the fork modified
(e.g. `doctor.ts`, `cli.ts`, `operations.ts`), take upstream's version
(`git checkout --theirs`) and re-apply the fork's small deltas
(`git diff <merge-base> HEAD -- <file>`) onto the new locations rather than
hand-merging conflict hunks. Fork URL repoints must import from
`src/core/repo-coordinates.ts`.

**Everything else** — merge on the merits. Upstream's `src/` fixes and new tests
are the whole point of tracking upstream.

### After resolving

```bash
bun install                                    # refresh bun.lock against merged package.json
# Regenerate committed-but-generated artifacts (see next section)
bun run build:llms
bash scripts/build-copilot-plugin.sh
bun run scripts/generate-plugin-tree.ts --out plugin --variants-out plugin-variants
# Prove it's green + no upstream leakage:
bun run typecheck   > out-tc.txt  2>&1; echo "EXIT=$?"
bun run verify      > out-ver.txt 2>&1; echo "EXIT=$?"
bun test            > out-ut.txt  2>&1; echo "EXIT=$?"
bash scripts/check-fork-hygiene.sh             # catches leaked garrytan/gbrain URLs + manifest/payload drift
```

> **Never pipe test output through `tail`/`head`** — the exit code becomes
> `tail`'s (always 0) and failure detail is truncated. Redirect to a file first,
> then inspect it. (This is a `CLAUDE.md` iron rule.)

Then run the 3-line version-consistency audit from `CLAUDE.md` and ship via
`/ship`.

> **Large or risky upstream diff?** Cherry-pick instead of a full merge:
> `git cherry-pick <sha>` for the specific fixes you want, skipping churn.

---

## Monthly: dependency freshness

There is **no Dependabot or Renovate** here, so this is manual:

```bash
bun outdated                 # list stale deps
bun audit                    # security advisories (if your bun build supports it)
```

Bump deliberately — respect the exact (non-`^`) pins on `@electric-sql/pglite`
and `@modelcontextprotocol/sdk`. Then `bun install` to refresh `bun.lock`, and
re-run `bun run verify` + `bun test`.

---

## On any source change: keep generated artifacts fresh

These are committed but generated; they drift silently and are caught by
CI/guards. Regenerate the ones whose source you touched:

| Artifact | Regenerate with | Guarded by |
|---|---|---|
| `llms.txt`, `llms-full.txt` | `bun run build:llms` | `test/build-llms.test.ts` |
| `plugins/gbrain/**`, `plugins/gbrain/plugin.json` | `bash scripts/build-copilot-plugin.sh` | `scripts/check-fork-hygiene.sh` §3 |
| `docs/eval/METRIC_GLOSSARY.md` | `bun run scripts/generate-metric-glossary.ts` | `scripts/check-eval-glossary-fresh.sh` |
| `bun.lock` | `bun install` | CI cache key |
| `src/admin-embedded.ts` | `bun run build:admin` | `scripts/check-admin-embedded.sh` |

**Rule of thumb:** any `CLAUDE.md` or reference-doc edit → `bun run build:llms`
in the same change, or CI shard 1 fails.

---

## Quarterly / pre-ship: refresh GitHub Actions SHAs

All actions in `.github/workflows/*` are pinned to full commit SHAs with `# vN`
comments. Refresh them using the documented loop in
**`docs/RELEASING.md` → "GitHub Actions SHA maintenance"** (it resolves each
pinned action's current SHA via `gh api` and shows which to bump). This keeps you
on patched action versions without unpinning.

---

## Every release: ship with `/ship`

Never hand-roll a release (`git commit` + `push` + `gh pr create`). `/ship`
handles the 5-file VERSION bump, CHANGELOG, `document-release`, pre-landing
review, and the version-consistency gate. Before it opens the PR, confirm:

- **Conductor branch name == workspace name** (a `CLAUDE.md` iron rule).
- **PR title is version-first**: `vX.Y.Z.W <type>(<scope>): <summary>`.
