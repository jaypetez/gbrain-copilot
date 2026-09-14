#!/usr/bin/env bash
# Fork sync: bring gbrain-copilot up to date with upstream garrytan/gbrain.
#
# This fork carries a Copilot-CLI overlay on top of upstream gbrain. Upstream
# ships fast, so the fork goes stale quietly — nothing errors, you just stop
# getting new gbrain. This script is the repeatable front half of the sync:
# it wires the remote, reports the gap, and (with --merge) starts the merge on
# a branch. The back half — resolving conflicts and re-running the fork's
# coordinate sweep — is human/agent work, documented in docs/MAINTENANCE.md.
#
# Usage:
#   scripts/sync-upstream.sh                 # report the gap, change nothing
#   scripts/sync-upstream.sh --merge         # also create the branch + merge
#   scripts/sync-upstream.sh --ref v0.50.0.0 # sync to a tag instead of master
#
# Exit codes: 0 up to date or report-only, 1 error, 2 merge left conflicts
# for you to resolve (expected, not a failure).

set -euo pipefail

UPSTREAM_URL="https://github.com/garrytan/gbrain.git"
UPSTREAM_REF="upstream/master"
DO_MERGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --merge) DO_MERGE=1; shift ;;
    --ref) UPSTREAM_REF="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"

# 1. Wire the remote (idempotent). Push is disabled: this fork never pushes
#    upstream, and a stray `git push upstream` would be an unpleasant surprise.
if git remote get-url upstream >/dev/null 2>&1; then
  git remote set-url upstream "$UPSTREAM_URL"
else
  git remote add upstream "$UPSTREAM_URL"
fi
git remote set-url --push upstream DISABLED_no_push_to_upstream

echo "[sync] fetching $UPSTREAM_URL ..."
git fetch upstream --prune --tags

# 2. Report the gap.
BASE=$(git merge-base HEAD "$UPSTREAM_REF")
AHEAD=$(git rev-list --count "$BASE"..HEAD)
BEHIND=$(git rev-list --count "$BASE".."$UPSTREAM_REF")
FORK_POINT=$(git log --format='%s' -1 "$BASE")
UPSTREAM_HEAD=$(git log --format='%s' -1 "$UPSTREAM_REF")

echo
echo "  fork point   : $BASE"
echo "                 $FORK_POINT"
echo "  upstream head: $(git rev-parse --short "$UPSTREAM_REF")"
echo "                 $UPSTREAM_HEAD"
echo "  fork-only commits   : $AHEAD"
echo "  upstream commits due: $BEHIND"

if [ "$BEHIND" -eq 0 ]; then
  echo
  echo "[sync] already up to date with $UPSTREAM_REF."
  exit 0
fi

# 3. The overlap set is what will actually conflict: files both sides touched.
OVERLAP=$(comm -12 \
  <(git diff --name-only "$BASE"..HEAD | sort) \
  <(git diff --name-only "$BASE".."$UPSTREAM_REF" | sort))
echo "  files touched by BOTH sides (conflict candidates): $(printf '%s\n' "$OVERLAP" | grep -c . || true)"

if [ "$DO_MERGE" -eq 0 ]; then
  echo
  printf '%s\n' "$OVERLAP" | sed 's/^/    /'
  echo
  echo "[sync] report only. Re-run with --merge to start the merge,"
  echo "       and read docs/MAINTENANCE.md before resolving."
  exit 0
fi

# 4. Merge on a branch, never on main.
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree is dirty. Commit or stash first." >&2
  exit 1
fi

UPSTREAM_VERSION=$(git show "$UPSTREAM_REF:VERSION" 2>/dev/null | tr -d '[:space:]' || echo unknown)
BRANCH="sync/upstream-${UPSTREAM_VERSION}"
echo
echo "[sync] creating $BRANCH and merging $UPSTREAM_REF ..."
git checkout -b "$BRANCH"

if git merge "$UPSTREAM_REF" --no-edit; then
  echo "[sync] merged cleanly. Still run the post-merge checklist in docs/MAINTENANCE.md."
  exit 0
fi

echo
echo "[sync] conflicts to resolve:"
git diff --name-only --diff-filter=U | sed 's/^/    /'
echo
echo "[sync] next: docs/MAINTENANCE.md — resolution policy, the fork-coordinate"
echo "       sweep, and the post-merge checklist."
exit 2
