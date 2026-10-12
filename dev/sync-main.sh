#!/bin/sh
# Bring the local main branch up to the remote, fast-forward only.
#
# Why this exists: pull requests here are merged on GitHub and nothing pulls
# afterwards, so local main drifts behind origin/main silently and a worktree
# cut from it looks like a clean checkout. On 2026-10-11 it was 75 commits
# behind and two agents each wasted a full run on a tree that no longer
# existed.
#
# Fast-forward only, so nothing is ever rewritten or discarded. If main has
# local commits the remote does not have, this stops and says so: reconciling
# a diverged main is a decision, not a script.
#
# Usage: sh dev/sync-main.sh [branch] [remote]

set -eu

branch="${1:-main}"
remote="${2:-origin}"

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

before=$(git rev-parse --verify --quiet "refs/heads/$branch" || true)

# --no-write-fetch-head: FETCH_HEAD holds one entry and any fetch replaces it,
# so a script that writes it destroys evidence someone else may be reading.
git fetch --no-write-fetch-head "$remote" "$branch"

far="refs/remotes/$remote/$branch"
target=$(git rev-parse --verify "$far")

if [ -z "$before" ]; then
  echo "no local $branch branch; creating it at $(git rev-parse --short "$target")"
  git branch "$branch" "$target"
  exit 0
fi

if [ "$before" = "$target" ]; then
  echo "$branch already matches $remote/$branch ($(git rev-parse --short "$target"))"
  exit 0
fi

if ! git merge-base --is-ancestor "$before" "$target"; then
  echo "STOP: $branch is not an ancestor of $remote/$branch." >&2
  echo "It has local commits the remote does not. Reconciling that is Amelia's" >&2
  echo "decision, not this script's: nothing has been changed." >&2
  echo "  local:  $(git rev-parse --short "$before")" >&2
  echo "  remote: $(git rev-parse --short "$target")" >&2
  exit 1
fi

# git fetch refuses to write a branch that is checked out somewhere, so find
# the worktree holding it and fast-forward there instead.
holder=$(git worktree list --porcelain | awk -v b="refs/heads/$branch" '
  /^worktree /  { path = substr($0, 10) }
  $0 == "branch " b { print path; exit }
')

if [ -n "$holder" ]; then
  git -C "$holder" merge --ff-only "$far"
  echo "$branch fast-forwarded in $holder"
else
  git branch -f "$branch" "$target"
  echo "$branch fast-forwarded"
fi

echo "  was $(git rev-parse --short "$before")"
echo "  now $(git rev-parse --short "$branch")"
