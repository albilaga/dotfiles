---
name: git-worktree-stack
description: Operates this dotfiles setup's gwa/gwl/gws/gwrm/gwclean/gwsync Git worktree and stacked-branch workflow. Use when creating, inspecting, syncing, publishing, or cleaning worktrees or stacked PRs, and whenever a task mentions gwsync or gwa.
compatibility: Requires zsh and zsh.d/git-functions.zsh; optional gh-stack, Git Town, gh, fzf.
---

# Git Worktree Stack

Use provided `gw*` commands. Do not replace them with generic worktree or stack commands.

## Run commands

Functions come from interactive zsh config. From another shell or an agent command, run:

```sh
zsh -ic 'gwl'
zsh -ic 'gwsync --no-push'
```

Run from target worktree. Stop on nonzero status; `gwsync` returns nonzero when any branch fails or is skipped.

## Commands

- `gwa <branch> [base-ref]`: create or attach sibling worktree, copy files listed in `.gwa-copy-files`, then enter it. Without base ref, new branch stacks on current feature branch; from default branch it starts at fresh `origin/<default>`.
- `gwl`: list worktrees as branch, parent, path, commit, and flags.
- `gws`: interactively switch worktrees with fzf.
- `gwrm`: interactively remove worktree; protects main/current and prompts before losing dirty work.
- `gwclean`: remove clean merged worktrees and branches, repair lineage, then prune.
- `gwsync`: sync current branch's full chain, parent first.

`gwsync` options:

- `--no-push`: integrate parents locally without pushing. Use before review or PR preparation.
- `--link`: publish multi-branch chain through `gh stack link`; pushes branches and creates missing PRs.
- `--all`: sync every worktree.
- `--dry-run`: show plan only.
- `--rebase` / `--merge`: override backend default strategy.

## Lineage and backends

Immediate parent is shared Git config:

```sh
git config --get "git-town-branch.$(git branch --show-current).parent"
```

This key is canonical shared lineage across worktrees. Existing per-worktree `gh-stack` state may provide a local parent hint; `gwsync` falls back to shared lineage when that state does not contain the branch. `gwl` displays resolved parent. Backend selection is `GIT_WORKTREE_STACK=auto|ghstack|town|plain`; auto prefers `gh-stack` for GitHub, then Git Town, then plain Git.

Never run `gh stack add`, `gh stack sync`, or `gh stack rebase` in this layout. Their state is per-worktree and their checkout cascade fails when sibling branches are checked out elsewhere. Let `gwa` create lineage and let `gwsync` integrate branches. Use `gwsync --link`, not direct `gh stack link`, to publish a chain.

## PR workflow

1. Read current branch's immediate parent from shared lineage. If absent, infer it from ancestry/PR metadata; ask when ambiguous, then record confirmed parent with `git config "git-town-branch.<branch>.parent" "<parent>"`.
2. Run `gwsync --no-push` from top branch before reviewing. Stop on conflicts, skips, or failure.
3. Review each layer with `git diff <immediate-parent>...<branch>` only.
4. Direct branch: push and create PR with that parent as base.
5. Multi-branch stack: run `gwsync --link` from top branch. Verify created PR bases and draft state.

Do not manually force-push. `gwsync` owns required `--force-with-lease` pushes after rebases.
