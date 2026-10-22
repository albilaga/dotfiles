#!/bin/zsh
set -eu
source "${0:A:h}/git-functions.zsh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/source/config" "$tmp/worktree"
print token > "$tmp/source/.env"
print settings > "$tmp/source/config/local file"
cat > "$tmp/source/.gwa-copy-files" <<'EOF'
# Local worktree files
.env
config/local file
../outside
missing
EOF

_gw_copy_files "$tmp/source" "$tmp/worktree"
cmp "$tmp/source/.env" "$tmp/worktree/.env"
cmp "$tmp/source/config/local file" "$tmp/worktree/config/local file"
cmp "$tmp/source/.gwa-copy-files" "$tmp/worktree/.gwa-copy-files"
[[ ! -e "$tmp/outside" ]]
print 'gwa copy files: ok'

# Sync must use a freshly rebased local parent, not its old remote history.
git init --bare --initial-branch=main "$tmp/origin.git" >/dev/null
git init --initial-branch=main "$tmp/repo" >/dev/null
git -C "$tmp/repo" config user.name 'Worktree Test'
git -C "$tmp/repo" config user.email 'worktree-test@example.invalid'
print main > "$tmp/repo/main.txt"
git -C "$tmp/repo" add main.txt
git -C "$tmp/repo" commit -m main >/dev/null
git -C "$tmp/repo" remote add origin "$tmp/origin.git"
git -C "$tmp/repo" push -u origin main >/dev/null 2>&1
git -C "$tmp/repo" remote set-head origin main
git -C "$tmp/repo" switch -c parent >/dev/null 2>&1
print parent > "$tmp/repo/parent.txt"
git -C "$tmp/repo" add parent.txt
git -C "$tmp/repo" commit -m parent >/dev/null
git -C "$tmp/repo" push -u origin parent >/dev/null 2>&1
git -C "$tmp/repo" config git-town-branch.parent.parent main
git -C "$tmp/repo" worktree add -b child "$tmp/child" parent >/dev/null 2>&1
git -C "$tmp/repo" config git-town-branch.child.parent parent
print child > "$tmp/child/child.txt"
git -C "$tmp/child" add child.txt
git -C "$tmp/child" commit -m child >/dev/null
git -C "$tmp/repo" switch main >/dev/null 2>&1
print updated > "$tmp/repo/updated.txt"
git -C "$tmp/repo" add updated.txt
git -C "$tmp/repo" commit -m 'update main' >/dev/null
git -C "$tmp/repo" push origin main >/dev/null 2>&1
git -C "$tmp/repo" switch parent >/dev/null 2>&1
if (cd "$tmp/child" && GIT_WORKTREE_STACK=plain git_worktree_sync --no-push); then
    git -C "$tmp/repo" merge-base --is-ancestor main parent
    git -C "$tmp/repo" merge-base --is-ancestor parent child
else
    print -u2 'gwsync rebased parent: failed'
    exit 1
fi
print 'gwsync rebased parent: ok'

# A resolved parent conflict must not be replayed by either child on restart.
git -C "$tmp/repo" worktree add -b grandchild "$tmp/grandchild" child >/dev/null 2>&1
git -C "$tmp/repo" config git-town-branch.grandchild.parent child
print grandchild > "$tmp/grandchild/grandchild.txt"
git -C "$tmp/grandchild" add grandchild.txt
git -C "$tmp/grandchild" commit -m grandchild >/dev/null
git -C "$tmp/repo" switch main >/dev/null 2>&1
print upstream > "$tmp/repo/parent.txt"
git -C "$tmp/repo" add parent.txt
git -C "$tmp/repo" commit -m 'conflicting main change' >/dev/null
git -C "$tmp/repo" push origin main >/dev/null 2>&1
git -C "$tmp/repo" switch parent >/dev/null 2>&1

if (cd "$tmp/grandchild" && GIT_WORKTREE_STACK=plain git_worktree_sync --no-push); then
    print -u2 'expected parent conflict'
    exit 1
fi
child_base=$(git -C "$tmp/repo" rev-parse refs/gwsync/bases/child)
grandchild_base=$(git -C "$tmp/repo" rev-parse refs/gwsync/bases/grandchild)
# Retrying before resolution must not consume saved child boundaries.
if (cd "$tmp/grandchild" && GIT_WORKTREE_STACK=plain git_worktree_sync --no-push); then
    print -u2 'expected paused rebase rejection'
    exit 1
fi
[[ "$(git -C "$tmp/repo" rev-parse refs/gwsync/bases/child)" == "$child_base" ]]
[[ "$(git -C "$tmp/repo" rev-parse refs/gwsync/bases/grandchild)" == "$grandchild_base" ]]
print resolved-parent > "$tmp/repo/parent.txt"
git -C "$tmp/repo" add parent.txt
GIT_EDITOR=true git -C "$tmp/repo" rebase --continue >/dev/null

# New shell proves recovery does not depend on in-memory snapshots.
functions_file="${0:A:h}/git-functions.zsh"
(cd "$tmp/grandchild" && GIT_WORKTREE_STACK=plain zsh -c \
    'source "$1"; git_worktree_sync --no-push' zsh "$functions_file")
git -C "$tmp/repo" merge-base --is-ancestor main parent
git -C "$tmp/repo" merge-base --is-ancestor parent child
git -C "$tmp/repo" merge-base --is-ancestor child grandchild
[[ "$(git -C "$tmp/repo" rev-list --count parent..child)" == 1 ]]
[[ "$(git -C "$tmp/repo" rev-list --count child..grandchild)" == 1 ]]
[[ "$(git -C "$tmp/repo" show grandchild:parent.txt)" == resolved-parent ]]
[[ "$(git -C "$tmp/repo" show grandchild:child.txt)" == child ]]
[[ "$(git -C "$tmp/repo" show grandchild:grandchild.txt)" == grandchild ]]
[[ -z "$(git -C "$tmp/repo" for-each-ref --format='%(refname)' refs/gwsync/bases/)" ]]
print 'gwsync three-layer conflict recovery: ok'

# Continuing a child's own conflict must not replay its newly integrated parent.
print upstream-child > "$tmp/repo/child.txt"
git -C "$tmp/repo" add child.txt
git -C "$tmp/repo" commit -m 'parent adds child file' >/dev/null
if (cd "$tmp/grandchild" && GIT_WORKTREE_STACK=plain git_worktree_sync --no-push); then
    print -u2 'expected child conflict'
    exit 1
fi
print resolved-child > "$tmp/child/child.txt"
git -C "$tmp/child" add child.txt
GIT_EDITOR=true git -C "$tmp/child" rebase --continue >/dev/null
child_tip=$(git -C "$tmp/repo" rev-parse child)
(cd "$tmp/grandchild" && GIT_WORKTREE_STACK=plain zsh -c \
    'source "$1"; git_worktree_sync --no-push' zsh "$functions_file")
[[ "$(git -C "$tmp/repo" rev-parse child)" == "$child_tip" ]]
git -C "$tmp/repo" merge-base --is-ancestor child grandchild
[[ "$(git -C "$tmp/repo" rev-list --count parent..child)" == 1 ]]
[[ "$(git -C "$tmp/repo" rev-list --count child..grandchild)" == 1 ]]
[[ "$(git -C "$tmp/repo" show grandchild:child.txt)" == resolved-child ]]
[[ -z "$(git -C "$tmp/repo" for-each-ref --format='%(refname)' refs/gwsync/bases/)" ]]
print 'gwsync manually continued child: ok'
