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
