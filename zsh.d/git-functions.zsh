# ============================================================================
# Shared git helpers (module-level)
# ----------------------------------------------------------------------------
# Single source of truth for colored output, gh detection, default-branch
# resolution, and merged-detection. Used by BOTH git_cleanup_branches and the
# git worktree helpers below. Prefixed _gw_ to namespace them.
# ============================================================================

_GW_RED='\033[0;31m'
_GW_GREEN='\033[0;32m'
_GW_YELLOW='\033[1;33m'
_GW_BLUE='\033[0;34m'
_GW_CYAN='\033[0;36m'
_GW_NC='\033[0m'

# Diagnostics go to STDERR so they never pollute command substitutions that
# capture a helper's real (stdout) return value, e.g. default_branch=$(...).
_gw_info()    { echo -e "${_GW_BLUE}[INFO]${_GW_NC} $1" >&2; }
_gw_success() { echo -e "${_GW_GREEN}[SUCCESS]${_GW_NC} $1" >&2; }
_gw_warning() { echo -e "${_GW_YELLOW}[WARNING]${_GW_NC} $1" >&2; }
_gw_error()   { echo -e "${_GW_RED}[ERROR]${_GW_NC} $1" >&2; }

# True if inside a git repo.
_gw_in_repo() { git rev-parse --git-dir >/dev/null 2>&1; }

# gh availability. Default warns (mirrors original check_gh_cli). Pass "quiet"
# to suppress the warning (used by worktree internals that probe gh silently).
_gw_check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        [[ "$1" == "quiet" ]] || _gw_warning "GitHub CLI (gh) not found. Skipping merge checks for GitHub repositories."
        return 1
    fi
    return 0
}

# Extract "owner/repo" from a github remote URL (mirrors original sed pipeline).
_gw_github_repo_path() {
    echo "$1" | sed -E 's|.*github\.com[/:](.*)(\.git)?$|\1|' | sed 's|\.git$||'
}

# Resolve the default branch (main/master). Mirrors original get_default_branch.
_gw_get_default_branch() {
    local remote_url="$1"

    if [[ "$remote_url" == *"github.com"* ]] && _gw_check_gh_cli; then
        local repo_path=$(_gw_github_repo_path "$remote_url")
        gh repo view "$repo_path" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main"
    else
        if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
            echo "main"
        elif git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
            echo "master"
        else
            echo "main"
        fi
    fi
}

# Merged-via-GitHub PR check. Mirrors original is_branch_merged_gh.
_gw_is_merged_gh() {
    local branch="$1"
    local default_branch="$2"
    local remote_url="$3"

    if ! _gw_check_gh_cli; then
        return 1
    fi

    local repo_path=$(_gw_github_repo_path "$remote_url")
    local pr_state=$(gh pr list --repo "$repo_path" --head "$branch" --state merged --json state --jq '.[0].state' 2>/dev/null)

    if [[ "$pr_state" == "MERGED" ]]; then
        return 0
    fi
    return 1
}

# Merged-via-git ancestry check. Mirrors original is_branch_merged_git.
_gw_is_merged_git() {
    local branch="$1"
    local default_branch="$2"

    git fetch origin "$default_branch" >/dev/null 2>&1 || return 1

    local merge_base=$(git merge-base "$branch" "origin/$default_branch" 2>/dev/null || echo "")
    local branch_commit=$(git rev-parse "$branch" 2>/dev/null || echo "")

    if [[ -n "$merge_base" && -n "$branch_commit" && "$merge_base" == "$branch_commit" ]]; then
        return 0
    fi
    return 1
}

# Convenience unifier (gh first for GitHub remotes, then git). Used ONLY by the
# worktree cleanup; git_cleanup_branches keeps its original inline branching so
# its messages stay identical.
_gw_is_branch_merged() {
    local branch="$1"
    local default_branch="$2"
    local remote_url="$3"

    if [[ "$remote_url" == *"github.com"* ]]; then
        _gw_is_merged_gh "$branch" "$default_branch" "$remote_url" && return 0
    fi
    _gw_is_merged_git "$branch" "$default_branch"
}

# ============================================================================
# Branch cleanup
# ----------------------------------------------------------------------------
# Deletes local branches that are merged (via GitHub PR or git ancestry) or no
# longer present on the remote. Delegates merged-detection to the shared _gw_*
# helpers above (behavior identical to the original implementation).
# ============================================================================
git_cleanup_branches() {
    _gw_info "Starting branch cleanup..."

    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi

    local current_branch=$(git branch --show-current)
    _gw_info "Current branch: $current_branch"

    local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ -z "$remote_url" ]]; then
        _gw_warning "No remote 'origin' found."
        remote_url=""
    else
        _gw_info "Remote URL: $remote_url"
    fi

    local default_branch=$(_gw_get_default_branch "$remote_url")
    _gw_info "Default branch: $default_branch"

    _gw_info "Fetching remote information..."
    git fetch --prune >/dev/null 2>&1 || _gw_warning "Failed to fetch remote information"

    local branches_to_check=$(git branch --format='%(refname:short)' | grep -v "^$current_branch$" | grep -v "^$default_branch$" || true)

    if [[ -z "$branches_to_check" ]]; then
        _gw_info "No branches to check for cleanup."
        return 0
    fi

    local deleted_count=0

    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue

        _gw_info "Checking branch: $branch"

        if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
            _gw_info "  Branch exists on remote"

            if [[ "$remote_url" == *"github.com"* ]]; then
                if _gw_is_merged_gh "$branch" "$default_branch" "$remote_url"; then
                    _gw_success "  Branch is merged (via GitHub API) - deleting"
                    git branch -D "$branch"
                    ((deleted_count++))
                elif _gw_is_merged_git "$branch" "$default_branch"; then
                    _gw_success "  Branch is merged (via git) - deleting"
                    git branch -D "$branch"
                    ((deleted_count++))
                else
                    _gw_info "  Branch is not merged - keeping"
                fi
            else
                if _gw_is_merged_git "$branch" "$default_branch"; then
                    _gw_success "  Branch is merged - deleting"
                    git branch -D "$branch"
                    ((deleted_count++))
                else
                    _gw_info "  Branch is not merged - keeping"
                fi
            fi
        else
            _gw_success "  Branch doesn't exist on remote - deleting"
            git branch -D "$branch"
            ((deleted_count++))
        fi
    done <<< "$branches_to_check"

    _gw_success "Branch cleanup completed. Deleted $deleted_count branches."
}

# Create some useful aliases
alias gcb='git_cleanup_branches'
alias git_prune_branches='git_cleanup_branches'

# Optional: Add a shorter alias
alias gclean='git_cleanup_branches'



# Optional: Auto-cleanup function (use with caution)
git_auto_cleanup() {
    echo "⚠️  This will automatically clean up branches. Continue? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        git_cleanup_branches
    else
        echo "Cleanup cancelled."
    fi
}

# ============================================================================
# Git WORKTREE management (gw* namespace)
# ----------------------------------------------------------------------------
# Convention: worktrees are SIBLINGS of the main repo under
#   ${GIT_WORKTREE_DIR:-<repo-parent>/<repo-name>.worktrees}/<sanitized-leaf>
# Branch refs keep their slashes (feature/foo); only the on-disk leaf is
# sanitized (/ -> -) so each worktree is one flat path segment (no nested dirs,
# no collisions). The base dir anchors on the MAIN worktree, so everything is
# correct even when invoked from INSIDE a linked worktree.
#
# Commands:
#   gwa <branch> [base-ref]  add a worktree (new/existing/remote branch) + cd.
#                            A NEW branch with no base-ref STACKS on the current
#                            branch using the detected stacking backend; on
#                            main/master it branches off fresh origin/<default>.
#   gwl                      pretty list of worktrees (with parent branch)
#   gws                      fzf-switch (cd) between worktrees
#   gwrm                     fzf-remove a worktree (protects main/current/dirty)
#   gwclean                  remove MERGED worktrees, delete branches, prune
#   gwsync                   sync a worktree's branch with its parent chain
#
# Stacking backend (_gw_stack_backend): GitHub remote + the gh-stack extension
# -> "ghstack"; else git-town -> "town"; else "plain". Override with
# GIT_WORKTREE_STACK=auto|ghstack|town|plain. It picks how a stacked branch is
# created and how gwsync integrates its parent:
#   town     `git town append` creates the branch; `git town sync`, run inside
#            each worktree bottom-up, integrates it (merge, per git-town's
#            sync-feature-strategy) and pushes.
#   ghstack  plain branch creation + our own rebase cascade, one worktree at a
#            time, then `gwsync --link` publishes the chain via `gh stack link`.
#            `gh stack add|sync|rebase` are NOT usable here: they keep state in
#            the per-worktree $GIT_DIR (so each worktree sees a different stack)
#            and cascade with `git checkout`, which aborts on the first branch
#            that lives in another worktree. `link` needs neither.
#   plain    rebase onto the parent, push per worktree.
# Lineage is always stored in git-town's `git-town-branch.<b>.parent` config key
# -- plain git config, shared by every worktree -- so gwl, gwsync and git-town
# itself all agree on the chain.
# ============================================================================

# --- internals -------------------------------------------------------------

# Absolute path of the MAIN worktree (NOT the current one). The first record of
# `worktree list --porcelain` is always the main worktree.
_gw_main_worktree() {
    git worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print substr($0, 10); exit}'
}

# Sanitize a branch name into a single safe path leaf (slashes/spaces -> dash).
_gw_sanitize_leaf() {
    local leaf="${1//\//-}"
    echo "${leaf// /-}"
}

# Base directory under which worktrees are created.
_gw_base_dir() {
    if [[ -n "$GIT_WORKTREE_DIR" ]]; then
        # ${~...} tilde-expands the value (~/wt -> $HOME/wt); :A then makes it
        # absolute. Without the ~ flag, :A would yield a literal "$PWD/~/wt".
        local d=${~GIT_WORKTREE_DIR}
        echo "${d:A}"
        return 0
    fi
    local main
    main="$(_gw_main_worktree)"
    [[ -z "$main" ]] && return 1
    echo "${main:h}/${main:t}.worktrees"
}

# On-disk path for a branch's worktree.
_gw_path_for_branch() {
    local base leaf
    base="$(_gw_base_dir)" || return 1
    leaf="$(_gw_sanitize_leaf "$1")"
    echo "${base}/${leaf}"
}

# True if the worktree at $1 has uncommitted/untracked changes.
_gw_is_dirty() {
    [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

# Parse `git worktree list --porcelain` into parallel 1-indexed globals:
#   _GW_WT_PATH  _GW_WT_HEAD  _GW_WT_BRANCH  _GW_WT_FLAGS
# branch = short name ("" if detached/bare). flags = comma list of
# detached,bare,locked. Uses process substitution so the arrays persist in the
# current shell (a pipe would lose them to a subshell).
_gw_parse_worktrees() {
    _GW_WT_PATH=(); _GW_WT_HEAD=(); _GW_WT_BRANCH=(); _GW_WT_FLAGS=()
    # NOTE: do NOT name a variable `path` here -- in zsh `path` is tied to $PATH.
    local line wtpath head branch flags
    wtpath=""; head=""; branch=""; flags=""

    _gw_flush() {
        [[ -z "$wtpath" ]] && return
        _GW_WT_PATH+=("$wtpath")
        _GW_WT_HEAD+=("$head")
        _GW_WT_BRANCH+=("$branch")
        _GW_WT_FLAGS+=("$flags")
        wtpath=""; head=""; branch=""; flags=""
    }

    while IFS= read -r line; do
        if [[ -z "$line" ]]; then
            _gw_flush
            continue
        fi
        case "$line" in
            "worktree "*) wtpath="${line#worktree }" ;;
            "HEAD "*)     head="${line#HEAD }" ;;
            "branch "*)   branch="${${line#branch }#refs/heads/}" ;;
            "detached")   flags="${flags:+$flags,}detached" ;;
            "bare")       flags="${flags:+$flags,}bare" ;;
            "locked"*)    flags="${flags:+$flags,}locked" ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null)
    _gw_flush
    unfunction _gw_flush 2>/dev/null
}

# Emit one TSV row per worktree:
#   path<TAB>branch<TAB>head<TAB>flags<TAB>parent
# (branch shown as "(detached)" when empty; flags include main/current/dirty;
# parent comes from the offline lineage hint, "-" when unknown). Drives the
# pretty list + the fzf picker. Keep flags in field 4 -- _gw_fzf_pick matches it.
_gw_list_tsv() {
    _gw_parse_worktrees
    local main_top current_top i wtpath branch head flags annotated parent
    main_top="$(_gw_main_worktree)"
    current_top="$(git rev-parse --show-toplevel 2>/dev/null)"
    for (( i = 1; i <= ${#_GW_WT_PATH[@]}; i++ )); do
        wtpath="${_GW_WT_PATH[$i]}"
        head="${_GW_WT_HEAD[$i]}"
        branch="${_GW_WT_BRANCH[$i]:-(detached)}"
        flags="${_GW_WT_FLAGS[$i]}"
        annotated="$flags"
        [[ "$wtpath" == "$main_top" ]]    && annotated="${annotated:+$annotated,}main"
        [[ "$wtpath" == "$current_top" ]] && annotated="${annotated:+$annotated,}current"
        _gw_is_dirty "$wtpath"            && annotated="${annotated:+$annotated,}dirty"
        parent=""
        [[ -n "${_GW_WT_BRANCH[$i]}" ]] && parent="$(_gw_parent_hint "${_GW_WT_BRANCH[$i]}")"
        printf '%s\t%s\t%s\t%s\t%s\n' "$wtpath" "$branch" "${head:0:9}" "${annotated:--}" "${parent:--}"
    done
}

# fzf picker over worktrees. Echoes the selected PATH (field 1) on stdout.
# Hides the path column from view (--with-nth=2..) but carries it through.
# $1 = header. $2 (optional) = exclude value tested against the FLAGS field
# (e.g. "main") via an awk exact-field match (no grep substring bugs).
_gw_fzf_pick() {
    local header="$1" exclude="$2"
    _gw_list_tsv \
        | awk -F'\t' -v ex="$exclude" '
            ex == "" { print; next }
            {
                n = split($4, f, ",")
                for (i = 1; i <= n; i++) if (f[i] == ex) next
                print
            }' \
        | fzf --header="$header" --delimiter='\t' --with-nth=2.. \
              --preview 'p=$(echo {} | cut -f1); echo "Path: $p"; echo; git -C "$p" log --oneline --decorate -10 2>/dev/null' \
              --preview-window=right,60% \
        | cut -f1
}

# Resolve a ref to a worktree start-point: prefer the up-to-date origin/<ref>
# (fetched with an explicit refspec so it works on narrowed-refspec clones),
# else a local ref. Echoes the start point; returns 1 if the ref exists nowhere.
_gw_resolve_start_point() {
    local ref="$1" remote_url="$2"
    if [[ -n "$remote_url" ]] && git ls-remote --exit-code --heads origin "$ref" >/dev/null 2>&1; then
        git fetch origin "+refs/heads/${ref}:refs/remotes/origin/${ref}" >/dev/null 2>&1
        echo "origin/$ref"
        return 0
    fi
    git rev-parse --verify --quiet "$ref" >/dev/null && { echo "$ref"; return 0; }
    return 1
}

# Register a Git Town parent (stacking) for the freshly-created child branch
# checked out in worktree $1. Uses the official `git town set-parent` when
# git-town is installed; falls back to git-town's lineage config key if that
# errors (e.g. the repo isn't git-town-configured). No-op + hint when git-town
# is absent -- the branch is still physically stacked on the parent either way.
_gw_set_town_parent() {
    local wt="$1" child="$2" parent="$3"
    if ! command -v git-town >/dev/null 2>&1; then
        _gw_warning "git-town not installed; '$child' is stacked on '$parent' but lineage was not registered."
        return 0
    fi
    if git -C "$wt" town set-parent "$parent" --non-interactive >/dev/null 2>&1; then
        _gw_success "git town: '$child' is now a child of '$parent'"
    elif git -C "$wt" config "git-town-branch.${child}.parent" "$parent" >/dev/null 2>&1; then
        _gw_success "git town: set parent of '$child' -> '$parent' (via config)"
    else
        _gw_warning "Could not register git town parent for '$child' (stacked on '$parent' regardless)."
    fi
}

# --- stacking backend detection --------------------------------------------

# True when origin lives on github.com ($1 = optional pre-fetched remote URL).
_gw_remote_is_github() {
    local url="${1-}"
    [[ -z "$url" ]] && url=$(git remote get-url origin 2>/dev/null || echo "")
    [[ "$url" == *github.com* ]]
}

# gh + the github/gh-stack extension. Memoized: `gh extension list` shells out,
# and this is called once per row in the worktree listing.
_gw_has_ghstack() {
    if [[ -z "$_GW_HAS_GHSTACK" ]]; then
        _GW_HAS_GHSTACK=no
        if [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/gh/extensions/gh-stack/gh-stack" ]]; then
            _GW_HAS_GHSTACK=yes
        elif command -v gh >/dev/null 2>&1 && gh extension list 2>/dev/null | grep -q 'gh-stack'; then
            _GW_HAS_GHSTACK=yes
        fi
    fi
    [[ "$_GW_HAS_GHSTACK" == yes ]]
}

_gw_has_town() { command -v git-town >/dev/null 2>&1; }

# Which tool creates stacked branches and drives sync, echoed as one word:
#   ghstack | town | plain
# On GitHub we prefer GitHub's own stacked PRs (gh stack) so the PR chain is
# real on github.com; anywhere else git-town owns lineage. GIT_WORKTREE_STACK
# forces a choice (auto|ghstack|town|plain) and falls back with a warning when
# the requested tool is missing.
_gw_stack_backend() {
    case "${GIT_WORKTREE_STACK:-auto}" in
        ghstack)
            _gw_has_ghstack && { echo ghstack; return 0; }
            _gw_warning "GIT_WORKTREE_STACK=ghstack but 'gh stack' is not installed."
            ;;
        town)
            _gw_has_town && { echo town; return 0; }
            _gw_warning "GIT_WORKTREE_STACK=town but git-town is not installed."
            ;;
        plain)
            echo plain
            return 0
            ;;
    esac
    if _gw_remote_is_github && _gw_has_ghstack; then echo ghstack; return 0; fi
    _gw_has_town && { echo town; return 0; }
    echo plain
}

# --- lineage (who is this branch stacked on?) -------------------------------

# gh-stack stores each stack in $GIT_DIR/gh-stack -- and for a linked worktree
# $GIT_DIR is .git/worktrees/<name>, NOT the shared common dir. A stack created
# by `gh stack` in one worktree is therefore invisible from every other one
# (verified: `gh stack add` run from two sibling worktrees produced two disjoint
# stacks). We only ever READ it, as a hint, and offline -- unlike `gh stack
# view`, which needs the API. Check this worktree's git dir, then the repo's.
_gw_ghstack_state() {
    local -a dirs
    local d top
    top="$(git rev-parse --show-toplevel 2>/dev/null)"
    dirs=( "$(git rev-parse --absolute-git-dir 2>/dev/null)"
           "$(git rev-parse --git-common-dir 2>/dev/null)" )
    for d in "${dirs[@]}"; do
        [[ -z "$d" ]] && continue
        [[ "$d" != /* ]] && d="$top/$d"
        [[ -f "$d/gh-stack" ]] && { echo "$d/gh-stack"; return 0; }
    done
    return 1
}

# Print the whole gh-stack chain containing $1, trunk first, one branch per
# line. Returns 1 when there is no state file, no jq, or $1 is in no stack.
_gw_ghstack_chain() {
    local branch="$1" state
    state="$(_gw_ghstack_state)" || return 1
    if ! command -v jq >/dev/null 2>&1; then
        _gw_warning "jq not installed; cannot read gh-stack lineage (brew install jq)."
        return 1
    fi
    local out
    out="$(jq -r --arg b "$branch" '
        .stacks[]
        | select([.branches[].branch] | index($b))
        | [.trunk.branch] + [.branches[].branch]
        | .[]' "$state" 2>/dev/null)"
    [[ -z "$out" ]] && return 1
    echo "$out"
}

# Cheap, OFFLINE parent lookup used for display: gh-stack's state file first,
# then git-town's lineage config. Deliberately does not resolve the default
# branch (that can hit the GitHub API) so listing worktrees stays instant.
_gw_parent_hint() {
    local branch="$1" prev="" b
    while IFS= read -r b; do
        [[ "$b" == "$branch" ]] && { echo "$prev"; return 0; }
        prev="$b"
    done < <(_gw_ghstack_chain "$branch" 2>/dev/null)
    git config "git-town-branch.${branch}.parent" 2>/dev/null
}

# Ancestry of $1 from the trunk down to $1 itself, one branch per line, trunk
# first. $2 = backend, $3 = default branch. gh-stack's state file wins when it
# knows the branch; otherwise walk git-town's lineage keys, and if nothing is
# recorded assume the branch sits directly on the default branch.
_gw_branch_chain() {
    local branch="$1" backend="$2" default_branch="$3"
    local -a chain full
    local b cur parent depth

    if [[ "$backend" == ghstack ]]; then
        full=( ${(f)"$(_gw_ghstack_chain "$branch")"} )
        if (( ${#full} )); then
            for b in "${full[@]}"; do
                chain+=("$b")
                [[ "$b" == "$branch" ]] && break
            done
            print -l -- "${chain[@]}"
            return 0
        fi
    fi

    cur="$branch"; depth=0
    while [[ -n "$cur" ]] && (( depth++ < 32 )); do
        chain=("$cur" "${chain[@]}")
        [[ "$cur" == "$default_branch" ]] && break
        parent="$(git config "git-town-branch.${cur}.parent" 2>/dev/null)"
        if [[ -z "$parent" ]]; then
            [[ "${chain[1]}" != "$default_branch" ]] && chain=("$default_branch" "${chain[@]}")
            break
        fi
        cur="$parent"
    done
    print -l -- "${chain[@]}"
}

# Parent of $1 ("" when $1 IS the trunk). $2 = backend, $3 = default branch.
_gw_parent_branch() {
    local -a chain
    chain=( ${(f)"$(_gw_branch_chain "$1" "$2" "$3")"} )
    (( ${#chain} >= 2 )) && echo "${chain[-2]}"
}

# --- worktree-safe ref plumbing --------------------------------------------

# Path of the worktree that has $1 checked out ("" / return 1 when none does).
_gw_worktree_of_branch() {
    local target="$1" i
    _gw_parse_worktrees
    for (( i = 1; i <= ${#_GW_WT_BRANCH[@]}; i++ )); do
        if [[ "${_GW_WT_BRANCH[$i]}" == "$target" ]]; then
            echo "${_GW_WT_PATH[$i]}"
            return 0
        fi
    done
    return 1
}

# Fast-forward local <$1> to origin/<$1> from ANY worktree.
# `git fetch origin b:b` refuses outright when b is checked out somewhere ("
# refusing to fetch into branch ... checked out at ..."), so when a worktree
# owns the branch we run a --ff-only merge inside that worktree instead. This is
# the fix for the trap where `git town sync` silently no-ops in a linked
# worktree because its parent branch is stale in the main worktree.
_gw_ff_branch() {
    local branch="$1" owner
    git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1 || return 0
    git fetch origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1

    owner="$(_gw_worktree_of_branch "$branch")"
    if [[ -z "$owner" ]]; then
        if git fetch origin "${branch}:${branch}" >/dev/null 2>&1; then
            _gw_info "  fast-forwarded $branch"
        else
            _gw_warning "  $branch has diverged from origin/$branch (left as-is)"
        fi
        return 0
    fi

    if [[ "$(git -C "$owner" rev-parse HEAD)" == "$(git -C "$owner" rev-parse "origin/$branch" 2>/dev/null)" ]]; then
        return 0
    fi
    if _gw_is_dirty "$owner"; then
        _gw_warning "  $branch is checked out in a dirty worktree ($owner); not fast-forwarding"
        return 0
    fi
    if git -C "$owner" merge --ff-only "origin/$branch" >/dev/null 2>&1; then
        _gw_info "  fast-forwarded $branch (in ${owner:t})"
    else
        _gw_warning "  could not fast-forward $branch (diverged from origin/$branch)"
    fi
}

# --- stacked branch creation ------------------------------------------------

# Record who <$1> is stacked on. git-town's config key is the store for every
# backend: it is plain `git config` (readable with or without git-town), it
# lives in the common config so all worktrees see it, and git-town picks it up
# for free when it is installed.
_gw_set_lineage() {
    local child="$1" parent="$2"
    if git config "git-town-branch.${child}.parent" "$parent" >/dev/null 2>&1; then
        _gw_success "lineage: '$child' is a child of '$parent'"
    else
        _gw_warning "Could not record lineage for '$child' (stacked on '$parent' regardless)."
    fi
}

# Forget branch $1's lineage after it is gone, hoisting its children onto its
# own parent (falling back to $2). Without the re-parent, deleting a merged
# mid-stack branch would leave its children pointing at a ref that no longer
# exists and gwsync would fail trying to rebase onto it.
_gw_drop_lineage() {
    local gone="$1" fallback="$2" grandparent key child
    grandparent="$(git config "git-town-branch.${gone}.parent" 2>/dev/null)"
    [[ -z "$grandparent" ]] && grandparent="$fallback"

    for key in ${(f)"$(git config --name-only --get-regexp '^git-town-branch\..*\.parent$' 2>/dev/null)"}; do
        [[ "$(git config "$key" 2>/dev/null)" == "$gone" ]] || continue
        child="${${key#git-town-branch.}%.parent}"
        git config "$key" "$grandparent" >/dev/null 2>&1 \
            && _gw_info "  re-parented '$child' -> '$grandparent'"
    done
    git config --remove-section "git-town-branch.${gone}" >/dev/null 2>&1
}

# Create $2 as a child of $3 IN THE CURRENT WORKTREE using the stacking tool, so
# the tool records lineage itself, then put this worktree back on the parent.
# The caller then attaches the (now free) child branch to its own worktree.
# $4 = default branch (used to seed missing lineage).
#
# Return 2 = "declined, create it plainly": the caller falls back to
# `git worktree add -b` + _gw_set_lineage. That happens when
#   - the worktree is dirty (the tool would check the new branch out here and
#     drag your uncommitted work onto it), or
#   - the backend is ghstack/plain. gh-stack is deliberately NOT used to create
#     branches: it keeps its stack in the per-worktree $GIT_DIR, so one
#     `gh stack add` per worktree yields a pile of disjoint two-branch stacks
#     instead of one chain. GitHub's side of the stack is published later from
#     the full chain with `gwsync --link` (`gh stack link`), which is what
#     gh-stack itself recommends for externally-managed branches.
_gw_stack_create_branch() {
    local backend="$1" child="$2" parent="$3" default_branch="$4"

    [[ "$backend" == town ]] || return 2

    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        _gw_warning "Uncommitted changes here; skipping $backend stacking to leave them on '$parent'."
        return 2
    fi

    case "$backend" in
        town)
            # `git town append` aborts with "cannot determine parent branch for
            # <parent>" when the PARENT's own lineage is unrecorded and it can't
            # prompt. Seed it from the default branch (branches created by gwa
            # off main already have this; ones you made by hand may not).
            if [[ "$parent" != "$default_branch" && -z "$(git config "git-town-branch.${parent}.parent" 2>/dev/null)" ]]; then
                _gw_info "git town: recording '$parent' as a child of '$default_branch'"
                git config "git-town-branch.${parent}.parent" "$default_branch"
            fi
            _gw_info "git town: appending '$child' on top of '$parent'"
            # --no-sync/--no-push keep this purely local (create branch + record
            # lineage). Syncing and pushing are gwsync's job, and town's own sync
            # cannot touch ancestors that live in other worktrees anyway.
            if ! git town append "$child" --no-sync --no-push --non-interactive >/dev/null 2>&1; then
                _gw_error "git town append failed (is git-town.main-branch configured?)."
                return 1
            fi
            ;;
        *)
            return 2
            ;;
    esac

    if ! git switch --quiet "$parent" 2>/dev/null; then
        _gw_error "Created '$child' but could not switch this worktree back to '$parent'."
        return 1
    fi
    return 0
}

# --- gwa : add a worktree for a new/existing/remote branch, then cd ---------
git_worktree_add() {
    local branch="$1" base_ref="$2"

    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi
    if [[ -z "$branch" ]]; then
        _gw_error "Usage: gwa <branch> [base-ref]"
        return 1
    fi

    local remote_url default_branch wt_path current_branch
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    default_branch=$(_gw_get_default_branch "$remote_url")
    current_branch=$(git branch --show-current 2>/dev/null)

    wt_path="$(_gw_path_for_branch "$branch")" || {
        _gw_error "Could not resolve worktree base dir."
        return 1
    }

    # If this branch is already checked out in a worktree, just cd into it.
    local i
    _gw_parse_worktrees
    for (( i = 1; i <= ${#_GW_WT_BRANCH[@]}; i++ )); do
        if [[ "${_GW_WT_BRANCH[$i]}" == "$branch" ]]; then
            _gw_info "Branch '$branch' already checked out -> switching."
            cd "${_GW_WT_PATH[$i]}" && _gw_success "Now in ${_GW_WT_PATH[$i]}"
            return $?
        fi
    done

    # Collision guard: never clobber an existing path.
    if [[ -e "$wt_path" ]]; then
        _gw_error "Target path already exists: $wt_path"
        return 1
    fi

    mkdir -p "${wt_path:h}" 2>/dev/null

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        _gw_info "Attaching existing local branch '$branch' at: $wt_path"
        git worktree add "$wt_path" "$branch" || { _gw_error "git worktree add failed."; return 1; }
    elif [[ -n "$remote_url" ]] && git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
        _gw_info "Creating worktree tracking origin/$branch at: $wt_path"
        # Explicit destination refspec so refs/remotes/origin/$branch always
        # exists, even on single-branch / narrowed-refspec clones (a plain
        # `git fetch origin $branch` would only update FETCH_HEAD there).
        # Brace ${branch} so zsh treats the ':refs...' as literal text, not a
        # ':r' history modifier on $branch (which would corrupt the refspec).
        git fetch origin "+refs/heads/${branch}:refs/remotes/origin/${branch}" >/dev/null 2>&1
        # No --track: it errors when origin/$branch isn't covered by the
        # configured refspec. Set upstream best-effort afterwards instead.
        git worktree add -b "$branch" "$wt_path" "origin/$branch" || { _gw_error "git worktree add failed."; return 1; }
        git -C "$wt_path" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null 2>&1
    else
        # New branch. Decide the start point:
        #   - explicit base-ref             -> branch off it (prefer origin/<ref>)
        #   - no base-ref, on a feature br  -> STACK on the current branch, via
        #                                      the detected backend (gh stack add
        #                                      / git town append) so the tool owns
        #                                      the lineage; based on its LOCAL tip
        #   - no base-ref, on default/detached -> branch off fresh origin/<default>
        local start_point stack_parent="" backend rc
        if [[ -n "$base_ref" ]]; then
            start_point="$(_gw_resolve_start_point "$base_ref" "$remote_url")" \
                || { _gw_error "Base ref '$base_ref' not found locally or on origin."; return 1; }
        elif [[ -n "$current_branch" && "$current_branch" != "$default_branch" \
                && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
            # Stack: base the child on the current branch's LOCAL tip (it may
            # carry unpushed work) and record lineage afterwards.
            start_point="$current_branch"
            stack_parent="$current_branch"
        else
            start_point="$(_gw_resolve_start_point "$default_branch" "$remote_url")" \
                || { _gw_error "Base ref '$default_branch' not found locally or on origin."; return 1; }
        fi

        backend="$(_gw_stack_backend)"
        rc=2
        if [[ -n "$stack_parent" && "$backend" != plain ]]; then
            # Let the stacking tool create the branch here, then hand this
            # worktree back to the parent; rc=2 means "declined, do it plainly".
            _gw_stack_create_branch "$backend" "$branch" "$stack_parent" "$default_branch"; rc=$?
            (( rc == 1 )) && return 1
        fi

        if (( rc == 0 )); then
            _gw_info "Attaching stacked branch '$branch' at: $wt_path"
            git worktree add "$wt_path" "$branch" \
                || { _gw_error "git worktree add failed."; return 1; }
        else
            if [[ -n "$stack_parent" ]]; then
                _gw_info "Stacking new branch '$branch' on '$stack_parent' at: $wt_path"
            else
                _gw_info "Creating new branch '$branch' from '$start_point' at: $wt_path"
            fi
            git worktree add -b "$branch" "$wt_path" "$start_point" \
                || { _gw_error "git worktree add failed."; return 1; }
            local lineage_parent="$stack_parent"
            # Root of a new stack: record it against the default branch too, so
            # a later append / gwsync knows where this chain terminates.
            [[ -z "$lineage_parent" && -z "$base_ref" ]] && lineage_parent="$default_branch"
            if [[ -n "$lineage_parent" ]]; then
                if _gw_has_town; then
                    _gw_set_town_parent "$wt_path" "$branch" "$lineage_parent"
                else
                    _gw_set_lineage "$branch" "$lineage_parent"
                fi
            fi
        fi
    fi

    if [[ -d "$wt_path" ]]; then
        cd "$wt_path" && _gw_success "Now in worktree: $wt_path  (branch: $branch)"
    else
        _gw_error "Worktree dir missing after add: $wt_path"
        return 1
    fi
}

# --- gwl : pretty list of worktrees ----------------------------------------
git_worktree_list() {
    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi
    _gw_list_tsv | while IFS=$'\t' read -r wtpath branch head flags parent; do
        local marker="  " fcolor="$_GW_NC"
        [[ "$flags" == *current* ]] && marker="${_GW_GREEN}* ${_GW_NC}"
        [[ "$flags" == *main*    ]] && fcolor="$_GW_CYAN"
        [[ "$flags" == *dirty*   ]] && fcolor="$_GW_YELLOW"
        printf "${marker}${_GW_CYAN}%-26s${_GW_NC} %-14s %-22s ${_GW_BLUE}%-10s${_GW_NC} ${fcolor}%s${_GW_NC}\n" \
            "$branch" "-> $parent" "${wtpath:t}" "$head" "$flags"
    done
}

# --- gws : fzf-switch (cd) between worktrees --------------------------------
git_worktree_switch() {
    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi
    if ! command -v fzf &>/dev/null; then
        _gw_warning "fzf not found. Worktrees:"
        git_worktree_list
        return 1
    fi
    local target
    target="$(_gw_fzf_pick 'cd to worktree')"
    [[ -z "$target" ]] && return 0
    if [[ -d "$target" ]]; then
        cd "$target" && _gw_success "Now in $(pwd)"
    else
        _gw_error "Path no longer exists: $target"
        return 1
    fi
}

# --- gwrm : fzf-remove a worktree (protects main / current / dirty) --------
git_worktree_remove() {
    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi
    if ! command -v fzf &>/dev/null; then
        _gw_warning "fzf not found. Worktrees:"
        git_worktree_list
        return 1
    fi

    local main_top current_top wtpath
    main_top="$(_gw_main_worktree)"
    current_top="$(git rev-parse --show-toplevel 2>/dev/null)"

    # Picker excludes the main worktree (never removable) by exact flag match.
    wtpath="$(_gw_fzf_pick 'remove worktree (main hidden)' 'main')"
    [[ -z "$wtpath" ]] && return 0

    # Hard guards (belt-and-suspenders vs the picker filter).
    if [[ "$wtpath" == "$main_top" ]]; then
        _gw_error "Refusing to remove the main worktree."
        return 1
    fi
    if [[ -n "$current_top" && "$wtpath" == "$current_top" ]]; then
        _gw_error "Refusing to remove the worktree you are currently in. cd out first."
        return 1
    fi

    # Recover the branch for optional deletion.
    local branch
    branch="$(git -C "$wtpath" symbolic-ref --quiet --short HEAD 2>/dev/null)"

    local force_flag=""
    if _gw_is_dirty "$wtpath"; then
        _gw_warning "Worktree has uncommitted changes: $wtpath"
        echo -n "Force-remove and LOSE those changes? (y/N) "
        local reply
        read -r reply
        [[ "$reply" =~ ^[Yy]$ ]] || { _gw_info "Aborted."; return 1; }
        force_flag="--force"
    fi

    if git worktree remove $force_flag "$wtpath"; then
        _gw_success "Removed worktree: $wtpath"
        if [[ -n "$branch" ]]; then
            echo -n "Also delete branch '$branch'? (y/N) "
            local del
            read -r del
            if [[ "$del" =~ ^[Yy]$ ]]; then
                git branch -D "$branch" && _gw_success "Deleted branch: $branch"
            fi
        fi
        git worktree prune
    else
        _gw_error "git worktree remove failed: $wtpath"
        return 1
    fi
}

# --- gwclean : remove MERGED worktrees, delete branches, prune -------------
git_worktree_cleanup() {
    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi

    local remote_url default_branch current_top main_top
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    default_branch=$(_gw_get_default_branch "$remote_url")
    current_top="$(git rev-parse --show-toplevel 2>/dev/null)"
    main_top="$(_gw_main_worktree)"

    _gw_info "Default branch: $default_branch"
    _gw_info "Fetching remote information..."
    git fetch --prune >/dev/null 2>&1 || _gw_warning "Failed to fetch remote information"

    # Snapshot into arrays first; we mutate worktrees while iterating.
    _gw_parse_worktrees
    local n=${#_GW_WT_PATH[@]}
    if (( n <= 1 )); then
        _gw_info "No linked worktrees to clean."
        git worktree prune
        return 0
    fi

    local removed=0 i wtpath branch flags
    # Index 1 is always the main worktree (protected); start at 2.
    for (( i = 2; i <= n; i++ )); do
        wtpath="${_GW_WT_PATH[$i]}"
        branch="${_GW_WT_BRANCH[$i]}"
        flags="${_GW_WT_FLAGS[$i]}"

        if [[ "$flags" == *detached* || "$flags" == *bare* || "$flags" == *locked* ]]; then
            _gw_info "Skipping ($flags) worktree: $wtpath"
            continue
        fi
        if [[ "$wtpath" == "$main_top" ]]; then
            continue
        fi
        if [[ -n "$current_top" && "$wtpath" == "$current_top" ]]; then
            _gw_info "Skipping current worktree: $wtpath"
            continue
        fi
        if [[ -z "$branch" ]]; then
            _gw_info "Skipping worktree with no branch: $wtpath"
            continue
        fi
        if [[ "$branch" == "$default_branch" ]]; then
            _gw_info "Skipping default-branch worktree: $wtpath"
            continue
        fi
        if _gw_is_dirty "$wtpath"; then
            _gw_warning "Skipping dirty worktree (uncommitted changes): $wtpath ($branch)"
            continue
        fi

        _gw_info "Checking worktree: $wtpath ($branch)"
        if _gw_is_branch_merged "$branch" "$default_branch" "$remote_url"; then
            _gw_success "  Branch '$branch' is merged - removing worktree"
            if git worktree remove "$wtpath"; then
                # Worktree gone first -> branch is no longer checked out -> safe to delete.
                if git branch -D "$branch" >/dev/null 2>&1; then
                    _gw_success "  Deleted branch '$branch'"
                    _gw_drop_lineage "$branch" "$default_branch"
                else
                    _gw_warning "  Worktree removed; branch '$branch' not deleted."
                fi
                ((removed++))
            else
                _gw_warning "  git worktree remove refused: $wtpath (left intact)"
            fi
        else
            _gw_info "  Branch '$branch' is not merged - keeping"
        fi
    done

    _gw_info "Pruning stale worktree metadata..."
    git worktree prune
    _gw_success "Worktree cleanup completed. Removed $removed worktree(s)."
}

# --- gwsync : sync a worktree's branch with its parent chain ----------------
#
# Why this exists instead of just calling the backend's own sync:
#   * `gh stack sync` / `gh stack rebase` cascade with `git checkout`, so they
#     ABORT the entire stack the moment one branch is checked out in another
#     worktree ("fatal: 'x' is already used by worktree at ..."), which is the
#     normal state here. gwsync does the cascade itself, one branch inside its
#     own worktree; `--link` then publishes the chain with `gh stack link`,
#     the one gh-stack command that needs neither local state nor a checkout.
#   * `git town sync` in a linked worktree silently does NOTHING -- exit 0, no
#     warning -- when its parent is stale and checked out elsewhere. gwsync
#     fast-forwards the ancestors first, then town's sync behaves correctly.
#
# Order is always trunk -> bottom -> top, so each branch integrates a parent
# that is already up to date.
git_worktree_sync() {
    local all=0 dry=0 do_push=1 link=0 strategy=""
    while (( $# )); do
        case "$1" in
            -a|--all)     all=1 ;;
            -n|--dry-run) dry=1 ;;
            --no-push)    do_push=0 ;;
            -l|--link)    link=1 ;;
            --rebase)     strategy=rebase ;;
            --merge)      strategy=merge ;;
            -h|--help)
                cat >&2 <<'EOF'
gwsync [options] - sync worktree branches with their parent, up to main/master

  -a, --all       sync every worktree, not just the current branch's chain
  -n, --dry-run   show what would happen, change nothing
      --no-push   do not push anything
  -l, --link      publish the chain as a GitHub stack (gh stack link);
                  pushes and CREATES PRs for branches that have none
      --rebase    integrate the parent by rebasing (default: ghstack/plain)
      --merge     integrate the parent by merging  (default: town)
EOF
                return 0 ;;
            *) _gw_error "Unknown option: $1 (try gwsync --help)"; return 1 ;;
        esac
        shift
    done

    if ! _gw_in_repo; then
        _gw_error "Not in a git repository!"
        return 1
    fi

    local remote_url default_branch backend
    remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    default_branch=$(_gw_get_default_branch "$remote_url")
    backend="$(_gw_stack_backend)"
    [[ -z "$strategy" ]] && { [[ "$backend" == town ]] && strategy=merge || strategy=rebase; }

    _gw_info "Backend: $backend   Default branch: $default_branch   Strategy: $strategy"

    # git-town hard-errors ("no main branch configured") the moment it runs
    # without a terminal to prompt on, so adopt the branch we just resolved.
    if [[ "$backend" == town && -z "$(git config git-town.main-branch 2>/dev/null)" ]]; then
        (( dry )) || git config git-town.main-branch "$default_branch"
        _gw_info "Set git-town.main-branch=$default_branch for this repo."
    fi

    if (( dry )); then
        _gw_info "(dry run - nothing will be changed)"
    else
        _gw_info "Fetching..."
        git fetch --prune >/dev/null 2>&1 || _gw_warning "git fetch failed"
        _gw_ff_branch "$default_branch"
    fi

    # Which branches are we responsible for?
    local -a targets
    if (( all )); then
        _gw_parse_worktrees
        local i
        for (( i = 1; i <= ${#_GW_WT_BRANCH[@]}; i++ )); do
            [[ -n "${_GW_WT_BRANCH[$i]}" ]] || continue
            [[ "${_GW_WT_BRANCH[$i]}" == "$default_branch" ]] && continue
            targets+=("${_GW_WT_BRANCH[$i]}")
        done
    else
        local cur
        cur="$(git branch --show-current 2>/dev/null)"
        if [[ -z "$cur" ]]; then
            _gw_error "Detached HEAD - nothing to sync."
            return 1
        fi
        if [[ "$cur" == "$default_branch" ]]; then
            _gw_success "On $default_branch - already up to date with origin."
            return 0
        fi
        targets=("$cur")
    fi

    if (( ${#targets} == 0 )); then
        _gw_info "No feature branches to sync."
        return 0
    fi

    # Flatten every target's chain into one bottom-up queue. Chains are emitted
    # trunk-first, so first-seen wins => a parent always precedes its children.
    local -a queue seen
    local t b
    for t in "${targets[@]}"; do
        for b in ${(f)"$(_gw_branch_chain "$t" "$backend" "$default_branch")"}; do
            [[ "$b" == "$default_branch" ]] && continue
            (( ${seen[(Ie)$b]} )) && continue
            seen+=("$b")
            queue+=("$b")
        done
    done

    local failed=0 synced=0 parent wt
    for b in "${queue[@]}"; do
        parent="$(_gw_parent_branch "$b" "$backend" "$default_branch")"
        [[ -z "$parent" ]] && parent="$default_branch"
        wt="$(_gw_worktree_of_branch "$b")"

        echo >&2
        _gw_info "${_GW_CYAN}${b}${_GW_NC} <- ${_GW_CYAN}${parent}${_GW_NC}"

        if [[ -z "$wt" ]]; then
            _gw_info "  no worktree for '$b'; fast-forwarding from origin only"
            (( dry )) || _gw_ff_branch "$b"
            continue
        fi
        if _gw_is_dirty "$wt"; then
            _gw_warning "  uncommitted changes in $wt - skipping '$b'"
            continue
        fi
        if (( dry )); then
            _gw_info "  would $strategy '$parent' into '$b' (in $wt)"
            continue
        fi

        # Pick up the branch's own remote commits before integrating the parent.
        _gw_ff_branch "$b"

        if [[ "$backend" == town ]]; then
            # Ancestors are fresh now, so town's sync actually does its job here
            # (its own strategy, proposal/lineage updates, push).
            local -a town_args=(sync --non-interactive)
            (( do_push )) || town_args+=(--no-push)
            if git -C "$wt" town "${town_args[@]}"; then
                _gw_success "  synced $b"
                (( synced++ ))
            else
                _gw_error "  git town sync failed in $wt"
                _gw_error "  Resolve it there, then 'git -C $wt town continue' and re-run gwsync."
                failed=1
                break
            fi
            continue
        fi

        # ghstack / plain: cascade by hand, inside the branch's own worktree.
        local ok=0
        if [[ "$strategy" == merge ]]; then
            git -C "$wt" merge --no-edit "$parent" && ok=1
        else
            git -C "$wt" rebase "$parent" && ok=1
        fi
        if (( ! ok )); then
            _gw_error "  $strategy of '$parent' into '$b' hit a conflict."
            _gw_error "  Resolve it in: $wt   (then 'git -C $wt $strategy --continue' and re-run gwsync)"
            failed=1
            break
        fi
        _gw_success "  $b is up to date with $parent"
        (( synced++ ))

        # town's own sync already pushed; everyone else pushes per worktree
        # (`gh stack push` needs the local stack state, which is per-worktree
        # and therefore useless here -- see _gw_ghstack_state).
        if (( do_push )) && [[ "$backend" != town ]]; then
            if git -C "$wt" push --force-with-lease >/dev/null 2>&1; then
                _gw_info "  pushed $b"
            else
                _gw_warning "  push failed for $b (no upstream yet? 'git -C $wt push -u origin $b')"
            fi
        fi
    done

    # Publish the chain as a GitHub stack. `gh stack link` is the one gh-stack
    # command that needs no local stack state and checks nothing out, so it is
    # the only one that survives a worktree-per-branch layout -- gh-stack's own
    # docs point to it for branches managed by another tool. It PUSHES and
    # CREATES PRs, so it stays opt-in behind --link.
    if (( link && failed == 0 && dry == 0 )); then
        echo >&2
        if [[ "$backend" != ghstack ]]; then
            _gw_warning "--link needs the ghstack backend (GitHub remote + gh stack); skipping."
        elif (( ${#queue} < 2 )); then
            _gw_warning "--link needs at least two branches in the chain; skipping."
        else
            _gw_info "gh stack link ${queue[*]}"
            gh stack link --base "$default_branch" "${queue[@]}" \
                || _gw_warning "gh stack link failed (is the repo stacked-PR enabled?)."
        fi
    fi

    echo >&2
    if (( failed )); then
        _gw_error "gwsync stopped early. $synced branch(es) synced."
        return 1
    fi
    _gw_success "gwsync completed. $synced branch(es) synced."
}

# --- worktree aliases (gw* namespace) --------------------------------------
alias gwa='git_worktree_add'          # gwa <branch> [base-ref] : add + cd
alias gwl='git_worktree_list'         # pretty list (branch -> parent)
alias gws='git_worktree_switch'       # fzf cd-switch
alias gwrm='git_worktree_remove'      # fzf remove (safe)
alias gwclean='git_worktree_cleanup'  # remove merged worktrees + prune
alias gwsync='git_worktree_sync'      # sync chain with parent/main (-a = all)


alias gst='git status'
alias s='git status'
alias gaa='git add -A'
alias gc='git commit'
alias gcm='git switch main'
alias gd='git diff'
alias gdc='git diff --cached'
# [c]heck [o]ut
alias co='git switch'
alias coc='git switch -c'
# Fuzzy checkout - interactive branch selection
git_fuzzy_checkout() {
  git branch --no-color --sort=-committerdate --format='%(refname:short)' | fzf --header 'git switch' | xargs git switch
}
alias fo='git_fuzzy_checkout'

# Pull request checkout - checkout your own PR
git_pr_checkout() {
  gh pr list --author "@me" | fzf --header 'checkout PR' | awk '{print $(NF-5)}' | xargs git switch
}
alias po='git_pr_checkout'

# Open current PR in browser
git_pr_open() {
  if type gh &> /dev/null; then
    gh pr view -w
  else
    echo "gh is not installed"
  fi
}
alias pr='git_pr_open'

alias up='git push'
alias upf='git push --force'
alias pu='git pull'
alias pur='git pull --rebase'
alias fe='git fetch'
alias re='git rebase'
alias lr='git l -30'
alias cdr='cd $(git rev-parse --show-toplevel)' # cd to git Root
alias hs='git rev-parse --short HEAD'
alias hm='git log --format=%B -n 1 HEAD'
