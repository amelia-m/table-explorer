#!/bin/sh
# Create a worktree from an up-to-date main, in one step.
#
# Why this exists: the failure this guards against happens at worktree
# creation, not later. `git worktree add -b x _scratch/wt-x main` silently
# uses whatever main points at, and local main here is routinely tens of
# commits behind origin/main because pull requests are merged on GitHub.
# Syncing first is one line; finding out afterwards cost two agent runs.
#
# Usage: sh dev/new-worktree.sh <new-branch> [path] [base]
#   sh dev/new-worktree.sh feat/thing
#   sh dev/new-worktree.sh feat/thing _scratch/wt-thing
#   sh dev/new-worktree.sh fix/thing _scratch/wt-thing dev/public-fixtures

set -eu

if [ $# -lt 1 ]; then
  echo "usage: sh dev/new-worktree.sh <new-branch> [path] [base]" >&2
  exit 2
fi

new_branch="$1"
base="${3:-main}"

# Default path: _scratch/wt-<last segment of the branch name>.
if [ $# -ge 2 ] && [ -n "$2" ]; then
  path="$2"
else
  leaf=$(printf '%s' "$new_branch" | sed 's|.*/||')
  path="_scratch/wt-$leaf"
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if [ -e "$path" ]; then
  echo "STOP: $path already exists; nothing has been changed." >&2
  exit 1
fi

if git rev-parse --verify --quiet "refs/heads/$new_branch" >/dev/null; then
  echo "STOP: branch $new_branch already exists; nothing has been changed." >&2
  exit 1
fi

# Only main is synced automatically. Another base is the caller's to choose,
# and silently moving someone else's branch would be the opposite of the fix.
if [ "$base" = "main" ]; then
  sh dev/sync-main.sh
else
  echo "base $base is not main; not syncing it"
fi

git worktree add -b "$new_branch" "$path" "$base"

echo
echo "worktree $path on $new_branch, cut from $base at $(git rev-parse --short "$base")"
echo "quote that sha in any brief you write about this worktree."
