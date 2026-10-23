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

# Squashed stacked PRs retain their old PR bases after all parents land on main.
for recovery in stack reflog missing partial; do
(
    git init --initial-branch=main "$tmp/merged-$recovery" >/dev/null
    cd "$tmp/merged-$recovery"
    git config user.name 'Worktree Test'
    git config user.email 'worktree-test@example.invalid'
    print main > main.txt
    git add .
    git commit -m main >/dev/null
    git init --bare --initial-branch=main "$tmp/merged-origin-$recovery.git" >/dev/null
    git remote add origin https://github.com/test/merged.git
    git config "url.$tmp/merged-origin-$recovery.git.insteadOf" https://github.com/test/merged.git
    git push -u origin main >/dev/null 2>&1
    for name in bottom middle top; do
        git switch -c "$name" >/dev/null 2>&1
        print "$name" > "$name.txt"
        git add .
        git commit -m "$name" >/dev/null
    done
    old_top=$(git rev-parse top)
    git worktree add -b leaf "$tmp/leaf-$recovery" top >/dev/null 2>&1
    print leaf > "$tmp/leaf-$recovery/leaf.txt"
    git -C "$tmp/leaf-$recovery" add .
    git -C "$tmp/leaf-$recovery" commit -m leaf >/dev/null
    if [[ "$recovery" == reflog || "$recovery" == missing ]]; then
        print amended-top > top.txt
        git add .
        git commit --amend --no-edit >/dev/null
        git -C "$tmp/leaf-$recovery" rebase --onto top "$old_top" >/dev/null
    fi
    if [[ "$recovery" == partial ]]; then
        git switch middle >/dev/null 2>&1
        git merge --squash top >/dev/null
        git commit -m 'squash top into middle' >/dev/null
        git push origin bottom middle >/dev/null 2>&1
        git switch main >/dev/null 2>&1
    else
        git switch main >/dev/null 2>&1
        git merge --squash top >/dev/null
        git commit -m 'squash stack' >/dev/null
        git push origin main >/dev/null 2>&1
    fi
    cd "$tmp/leaf-$recovery"
    state=$(git rev-parse --git-path gh-stack)
    print '{"stacks":[{"trunk":{"branch":"main"},"branches":[{"branch":"bottom"},{"branch":"middle"},{"branch":"top"},{"branch":"leaf"}]}]}' \
        | jq --arg base "$old_top" '.stacks[0].branches[3].base = $base' > "$state"
    cp "$state" "$tmp/state-before"
    git config git-town-branch.leaf.parent main
    _GW_HAS_GHSTACK=yes
    # Keep all Git traffic local while presenting a GitHub remote to sync.
    git() {
        if [[ "$*" == 'remote get-url origin' ]]; then
            print https://github.com/test/merged.git
        else
            command git "$@"
        fi
    }
    gh() {
        if [[ "$1 $2" == 'repo view' ]]; then
            print main
        elif [[ "$1 $2" == 'pr list' ]]; then
            while (( $# )); do
                if [[ "$1" == --head ]]; then
                    case "$2" in
                        bottom) [[ "$recovery" == partial ]] && print null || print main ;;
                        middle) [[ "$recovery" == partial ]] && print null || print bottom ;;
                        top) print middle ;;
                        cycle) print cycle ;;
                        *) print null ;;
                    esac
                    return 0
                fi
                shift
            done
            return 1
        else
            return 1
        fi
    }
    if [[ "$recovery" == partial ]]; then
        _gw_is_merged_into top middle https://github.com/test/merged.git
    else
        _gw_is_merged_into top main https://github.com/test/merged.git
    fi
    if _gw_is_merged_into leaf main https://github.com/test/merged.git \
        || _gw_is_merged_into cycle main https://github.com/test/merged.git; then
        print -u2 'unmerged or cyclic PR must not count as merged'
        exit 1
    fi
    if [[ "$recovery" == partial ]]; then
        git branch -D top >/dev/null
        new_parent=middle
        expected_chain=$'main\nbottom\nmiddle\nleaf'
    else
        git branch -D bottom middle top >/dev/null
        new_parent=main
        expected_chain=$'main\nleaf'
    fi
    if [[ "$recovery" == missing ]]; then
        git reflog expire --expire=now HEAD
        tip=$(git rev-parse HEAD)
        if GIT_WORKTREE_STACK=ghstack git_worktree_sync --no-push; then
            print -u2 'sync must reject an unknown parent boundary'
            exit 1
        fi
        cmp "$state" "$tmp/state-before"
        [[ "$(git rev-parse HEAD)" == "$tip" ]]
        [[ ! -d "$(git rev-parse --git-path rebase-merge)" ]]
        exit 0
    fi
    GIT_WORKTREE_STACK=ghstack git_worktree_sync --dry-run --no-push || exit 1
    cmp "$state" "$tmp/state-before"
    GIT_WORKTREE_STACK=ghstack git_worktree_sync --no-push || exit 1
    [[ "$(_gw_branch_chain leaf ghstack main)" == "$expected_chain" ]]
    [[ "$(git config git-town-branch.leaf.parent)" == "$new_parent" ]]
    git merge-base --is-ancestor "$new_parent" leaf
    [[ "$(git rev-list --count "$new_parent..leaf")" == 1 ]]
    [[ "$(git show leaf:leaf.txt)" == leaf ]]
    [[ -z "$(git for-each-ref --format='%(refname)' refs/gwsync/bases/leaf)" ]]
    # A second sync must not resurrect the stale stack or replay merged commits.
    tip=$(git rev-parse HEAD)
    GIT_WORKTREE_STACK=ghstack git_worktree_sync --no-push || exit 1
    [[ "$(git rev-parse HEAD)" == "$tip" ]]
)
done
print 'gwsync merged-parent retargeting and boundary recovery: ok'
