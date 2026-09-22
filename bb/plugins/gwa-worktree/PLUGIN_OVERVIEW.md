Use your existing dotfiles worktree workflow directly from BB's New Thread composer.

Select **GWA worktree**, optionally choose a base branch, and submit the thread. The plugin runs `gwa` through interactive login Zsh on the selected machine and attaches BB to the worktree it creates or finds.

Worktrees remain user-managed. BB never removes them when threads archive or environments retire; use `gwrm` or `gwclean` as usual.

## Requirements

- `gwa` must load from interactive login Zsh configuration.
- Project checkout and worktree must live on the selected BB machine.
