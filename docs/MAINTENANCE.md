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
  `>=1.3.10`; CI pins `1.3.13` in `.github/workflows/*`). Keep local Bun at or
  above the CI pin so "green locally" means "green in CI". Install from
  <https://bun.sh>.
- **git**, **gh** (GitHub CLI), and **Node** (used by a few scripts).

> **Windows note.** `bun run typecheck` and `bun run build` work natively, but
> `bun run verify` and `bun run test` do **not** — the guard aliases in
> `package.json` are bare `.sh` paths (e.g. `"check:fork-hygiene":
> "scripts/check-fork-hygiene.sh"`) that bun's Windows shell can't launch
> (`bun: command not found`). Run individual guards directly with
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
scripts/sync-upstream.sh            # how far behind are we? changes nothing
scripts/sync-upstream.sh --merge    # branch + merge; leaves conflicts for you
```

The script wires the `upstream` remote (push disabled), then reports the fork
point, how many commits each side is ahead, and — the number that predicts the
work — **the set of files both sides touched**. Being 2 upstream releases behind
is a 20-minute merge; the v0.42.37.0 → v0.50.0.0 sync was 748 commits, 71
overlapping files, 41 real conflicts, and took a day.

By hand, if you prefer:

```bash
git fetch upstream
git checkout main && git pull                 # local main == origin/main
git log --oneline --no-merges main..upstream/master | head -50
git checkout -b sync/upstream-<upstream-version>
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
- `.github/workflows/*` — this fork intentionally **disabled the heavy-tests
  nightly cron** and made `e2e.yml` **dispatch-only** (Actions-minutes budget).
  Don't let an upstream merge re-enable them.

**The version trio** (`VERSION`, `package.json`, `CHANGELOG.md`) — follow the
"Merge-conflict recovery procedure" in `CLAUDE.md`. Keep the fork's version line
(don't blindly adopt upstream's number); keep BOTH sets of CHANGELOG entries.
`/ship` enforces trio consistency at release time.

**Everything else** — merge on the merits. Upstream's `src/` fixes and new tests
are the whole point of tracking upstream.

Three rules make "on the merits" concrete. They are ranked by how much future
pain they save, and they came out of the v0.50.0.0 sync:

1. **Where upstream independently landed the same fix, take upstream's.** Both
   projects fix the same reported bugs. Upstream's version is usually a superset,
   and taking it stops the file conflicting again on every future sync. That sync
   retired four fork fixes this way: `whoami`'s stdio shape (upstream's returns
   no OS account name), the Windows `serve` watchdog (upstream folded the
   signal-0 probe into `readLiveParentPid` / `probeWatchdogAvailable`),
   `postinstall` (Bun-native), and `jsonb_integrity` (`to_regclass` probe).

2. **Where upstream peeled a function the fork had edited, port the fork's
   behaviour into its new home.** Upstream refactors constantly — `operations.ts`
   → `src/core/ops/*`, `doctor.ts` → `src/commands/doctor/checks/*`, both
   engines → `src/core/{pglite,postgres}-engine/*`. Never resurrect the inline
   copy: you end up with two, and which one wins depends on import order.

3. **Keep genuinely fork-specific behaviour, and say so in a comment.** `gbrain
   doctor`'s 0/1/2 exit contract stays — but implemented on whatever mechanism
   upstream now uses, with a comment naming it as a fork delta so the next person
   doesn't "fix" it back to upstream's 0/1. The same applies to the fresh-brain
   demotions (`retrieval_reflex_health`, `ze_embedding_health`, embedding
   coverage, `pack_upgrade_available`): every upstream merge reintroduces a
   check that warns on a pristine brain and breaks the fresh-brain-exits-0
   contract.

### The coordinate sweep (do not skip)

This is the step that breaks things **silently** if you skip it. Every merge
brings new upstream code with `garrytan/gbrain` baked in. The highest-stakes one:

> `src/core/binary-self-update.ts` verifies a downloaded binary against a GitHub
> build-provenance attestation pinned to a specific repo and branch. Merged
> as-is it pins `garrytan/gbrain@refs/heads/master` — so **every** self-update of
> a fork-built binary fails its integrity check and refuses to install. On users'
> machines, not in CI.

```bash
# Functional coordinates in source — these change runtime behaviour.
grep -rn 'garrytan/gbrain' src/ --include=*.ts \
  | grep -v 'UPSTREAM_REPO\|gbrain-evals\|gbrain-skillpack-registry'

# Shipped docs/skills/scripts — CI-gated for the raw-URL class.
bun run check:fork-hygiene
```

Fix by importing from `src/core/repo-coordinates.ts`, never by editing the
literal. Beyond the files listed above, the recurring offenders are
`check-update.ts` (version probe + release notes), `upgrade.ts` (install
commands), `npm-squat-check.ts` (repo marker), the install hints in
`bootstrap.ts` / `bootstrap/template-repo.ts` / `pglite-embedded-assets.ts` /
`agent-install/state.ts`, and doc links in `harness/registry.ts`,
`creds/errors.ts`, `serve-http.ts`, `schema-version-health.ts`.

Do **not** rewrite `CHANGELOG.md` (historical record, and CI excludes it), the
sibling repos `garrytan/gbrain-evals` and `garrytan/gbrain-skillpack-registry`,
prose crediting upstream, or upstream issue numbers in comments (keep those as
`upstream context: garrytan/gbrain#NNN`).

### Versioning across a sync

Fork releases use the upstream version they contain plus a fork `.MICRO`:
upstream `0.50.0.0` + the first fork release on top → `0.50.0.1`. This keeps the
version honest about which upstream is inside.

> Before the syncs started, the fork drifted into issuing its own `0.42.39.0`
> while upstream separately shipped a *different* `0.42.39.0`. Both survive in
> `CHANGELOG.md`; the fork's entries are tagged `(gbrain-copilot fork)` to
> disambiguate. Don't create more of those.

### After resolving

```bash
bun install                                    # refresh bun.lock against merged package.json
# Regenerate committed-but-generated artifacts (see next section)
bun run build:llms
bash scripts/build-copilot-plugin.sh
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

## Push generic fixes upstream

If a sync ever gets painful enough that you consider carrying a patch series
instead of a merge, do the opposite: send the fork's non-fork-specific
improvements upstream so there is less delta to carry. Anything that is not
Copilot packaging, fork coordinates, or a deliberate fork behaviour is a
candidate.

The v0.50.0.1 sync produced three: Windows path normalization in
`check-orphan-modules.mjs` and `check-skill-refs.mjs` (both compared backslash
paths against `/`-separated literals and silently checked nothing), and
`check-skill-brain-first.sh` parsing doctor's JSON with bun instead of python3.

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
