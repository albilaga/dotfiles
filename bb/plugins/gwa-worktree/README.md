# GWA Worktree for BB

Adds **GWA worktree** to BB's New Thread environment picker.

The provider runs your interactive Zsh `gwa <branch> [base-ref]` function on the selected machine, then attaches BB to the resulting worktree. Choose an optional **Branch from** value in the composer; leaving it empty preserves `gwa`'s normal stacking behavior.

BB does not own or delete these worktrees. Continue using `gwl`, `gwrm`, `gwclean`, and `gwsync` for lifecycle and stack management.

## Install

```sh
npm install
npm run build
bb plugin install .
```

Then select **GWA worktree** when creating a project thread.

## Requirements

- `/bin/zsh`
- `gwa` available from interactive login Zsh startup files
- Project checkout and worktree on same BB machine
