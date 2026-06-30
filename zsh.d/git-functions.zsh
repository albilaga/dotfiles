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
#                            branch (registers the git town parent); on
#                            main/master it branches off fresh origin/<default>.
#   gwl                      pretty list of worktrees
#   gws                      fzf-switch (cd) between worktrees
#   gwrm                     fzf-remove a worktree (protects main/current/dirty)
#   gwclean                  remove MERGED worktrees, delete branches, prune
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

# Emit one TSV row per worktree: path<TAB>branch<TAB>head<TAB>flags
# (branch shown as "(detached)" when empty; flags include main/current/dirty).
# Drives the pretty list + the fzf picker.
_gw_list_tsv() {
    _gw_parse_worktrees
    local main_top current_top i wtpath branch head flags annotated
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
        printf '%s\t%s\t%s\t%s\n' "$wtpath" "$branch" "${head:0:9}" "${annotated:--}"
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
        #   - no base-ref, on a feature br  -> STACK on the current branch (git
        #                                      town style; based on its LOCAL tip)
        #   - no base-ref, on default/detached -> branch off fresh origin/<default>
        local start_point stack_parent=""
        if [[ -n "$base_ref" ]]; then
            start_point="$(_gw_resolve_start_point "$base_ref" "$remote_url")" \
                || { _gw_error "Base ref '$base_ref' not found locally or on origin."; return 1; }
        elif [[ -n "$current_branch" && "$current_branch" != "$default_branch" \
                && "$current_branch" != "main" && "$current_branch" != "master" ]]; then
            # Stack: base the child on the current branch's LOCAL tip (it may
            # carry unpushed work) and record the git town parent afterwards.
            start_point="$current_branch"
            stack_parent="$current_branch"
        else
            start_point="$(_gw_resolve_start_point "$default_branch" "$remote_url")" \
                || { _gw_error "Base ref '$default_branch' not found locally or on origin."; return 1; }
        fi

        if [[ -n "$stack_parent" ]]; then
            _gw_info "Stacking new branch '$branch' on '$stack_parent' at: $wt_path"
        else
            _gw_info "Creating new branch '$branch' from '$start_point' at: $wt_path"
        fi
        git worktree add -b "$branch" "$wt_path" "$start_point" \
            || { _gw_error "git worktree add failed."; return 1; }
        [[ -n "$stack_parent" ]] && _gw_set_town_parent "$wt_path" "$branch" "$stack_parent"
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
    _gw_list_tsv | while IFS=$'\t' read -r wtpath branch head flags; do
        local marker="  " fcolor="$_GW_NC"
        [[ "$flags" == *current* ]] && marker="${_GW_GREEN}* ${_GW_NC}"
        [[ "$flags" == *main*    ]] && fcolor="$_GW_CYAN"
        [[ "$flags" == *dirty*   ]] && fcolor="$_GW_YELLOW"
        printf "${marker}${_GW_CYAN}%-26s${_GW_NC} %-22s ${_GW_BLUE}%-10s${_GW_NC} ${fcolor}%s${_GW_NC}\n" \
            "$branch" "${wtpath:t}" "$head" "$flags"
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

# --- worktree aliases (gw* namespace) --------------------------------------
alias gwa='git_worktree_add'          # gwa <branch> [base-ref] : add + cd
alias gwl='git_worktree_list'         # pretty list
alias gws='git_worktree_switch'       # fzf cd-switch
alias gwrm='git_worktree_remove'      # fzf remove (safe)
alias gwclean='git_worktree_cleanup'  # remove merged worktrees + prune


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
