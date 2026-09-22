#!/usr/bin/env bash
set -euo pipefail

repo=$(mktemp -d "${TMPDIR:-/tmp}/bb-gwa-plugin-test.XXXXXX")
branch="bb-gwa-plugin-test-$$"
worktree=""
cleanup() {
  if [[ -n "$worktree" && -d "$worktree" ]]; then
    git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
  fi
  git -C "$repo" branch -D "$branch" >/dev/null 2>&1 || true
  rm -rf "$repo"
}
trap cleanup EXIT

git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
git -C "$repo" config commit.gpgsign false
printf test > "$repo/file"
git -C "$repo" add file
git -C "$repo" commit -qm init

output=$(cd "$repo" && HERDR_ENV=0 /bin/zsh -lic \
  'gwa "$1" "${2:-}" && print -r -- "__BB_GWA_PATH__=$PWD"' \
  -- "$branch" "" 2>&1)
worktree=$(printf '%s\n' "$output" | awk '/^__BB_GWA_PATH__=/{sub(/^__BB_GWA_PATH__=/, ""); print}' | tail -1)

[[ -n "$worktree" ]]
[[ "$(git -C "$worktree" branch --show-current)" == "$branch" ]]
