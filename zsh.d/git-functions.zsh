# Branch cleanup function
git-cleanup-branches() {
    # Colors for output
    local RED='\033[0;31m'
    local GREEN='\033[0;32m'
    local YELLOW='\033[1;33m'
    local BLUE='\033[0;34m'
    local NC='\033[0m' # No Color

    # Function to print colored output
    print_info() {
        echo -e "${BLUE}[INFO]${NC} $1"
    }

    print_success() {
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    }

    print_warning() {
        echo -e "${YELLOW}[WARNING]${NC} $1"
    }

    print_error() {
        echo -e "${RED}[ERROR]${NC} $1"
    }

    # Function to check if gh CLI is available
    check_gh_cli() {
        if ! command -v gh &> /dev/null; then
            print_warning "GitHub CLI (gh) not found. Skipping merge checks for GitHub repositories."
            return 1
        fi
        return 0
    }

    # Function to get the default branch (main or master)
    get_default_branch() {
        local remote_url="$1"

        # Try to get default branch from remote
        if [[ "$remote_url" == *"github.com"* ]] && check_gh_cli; then
            # Use gh CLI to get default branch
            local repo_path=$(echo "$remote_url" | sed -E 's|.*github\.com[/:](.*)(\.git)?$|\1|' | sed 's|\.git$||')
            gh repo view "$repo_path" --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "main"
        else
            # Fallback: check if main or master exists on remote
            if git ls-remote --exit-code --heads origin main >/dev/null 2>&1; then
                echo "main"
            elif git ls-remote --exit-code --heads origin master >/dev/null 2>&1; then
                echo "master"
            else
                echo "main" # Default fallback
            fi
        fi
    }

    # Function to check if branch is merged using gh CLI
    is_branch_merged_gh() {
        local branch="$1"
        local default_branch="$2"
        local remote_url="$3"

        if ! check_gh_cli; then
            return 1
        fi

        # Extract repository path from URL
        local repo_path=$(echo "$remote_url" | sed -E 's|.*github\.com[/:](.*)(\.git)?$|\1|' | sed 's|\.git$||')

        # Check if there's a PR for this branch and if it's merged
        local pr_state=$(gh pr list --repo "$repo_path" --head "$branch" --state merged --json state --jq '.[0].state' 2>/dev/null)

        if [[ "$pr_state" == "MERGED" ]]; then
            return 0
        fi

        return 1
    }

    # Function to check if branch is merged using git
    is_branch_merged_git() {
        local branch="$1"
        local default_branch="$2"

        # Fetch latest changes
        git fetch origin "$default_branch" >/dev/null 2>&1 || return 1

        # Check if branch is merged into default branch
        local merge_base=$(git merge-base "$branch" "origin/$default_branch" 2>/dev/null || echo "")
        local branch_commit=$(git rev-parse "$branch" 2>/dev/null || echo "")

        if [[ -n "$merge_base" && -n "$branch_commit" && "$merge_base" == "$branch_commit" ]]; then
            return 0
        fi

        return 1
    }

    # Main logic
    print_info "Starting branch cleanup..."

    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        print_error "Not in a git repository!"
        return 1
    fi

    # Get current branch to avoid deleting it
    local current_branch=$(git branch --show-current)
    print_info "Current branch: $current_branch"

    # Get remote URL
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ -z "$remote_url" ]]; then
        print_warning "No remote 'origin' found."
        remote_url=""
    else
        print_info "Remote URL: $remote_url"
    fi

    # Get default branch
    local default_branch=$(get_default_branch "$remote_url")
    print_info "Default branch: $default_branch"

    # Fetch latest remote information
    print_info "Fetching remote information..."
    git fetch --prune >/dev/null 2>&1 || print_warning "Failed to fetch remote information"

    # Get all local branches except current branch
    local branches_to_check=$(git branch --format='%(refname:short)' | grep -v "^$current_branch$" | grep -v "^$default_branch$" || true)

    if [[ -z "$branches_to_check" ]]; then
        print_info "No branches to check for cleanup."
        return 0
    fi

    local deleted_count=0

    # Check each branch
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue

        print_info "Checking branch: $branch"

        # Check if branch exists on remote
        if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
            print_info "  Branch exists on remote"

            # If it's a GitHub repository, check if branch is merged
            if [[ "$remote_url" == *"github.com"* ]]; then
                if is_branch_merged_gh "$branch" "$default_branch" "$remote_url"; then
                    print_success "  Branch is merged (via GitHub API) - deleting"
                    git branch -D "$branch"
                    ((deleted_count++))
                elif is_branch_merged_git "$branch" "$default_branch"; then
                    print_success "  Branch is merged (via git) - deleting"
                    git branch -D "$branch"
                    ((deleted_count++))
                else
                    print_info "  Branch is not merged - keeping"
                fi
            else
                # For non-GitHub repos, only check via git
                if is_branch_merged_git "$branch" "$default_branch"; then
                    print_success "  Branch is merged - deleting"
                    git branch -D "$branch"
                    ((deleted_count++))
                else
                    print_info "  Branch is not merged - keeping"
                fi
            fi
        else
            print_success "  Branch doesn't exist on remote - deleting"
            git branch -D "$branch"
            ((deleted_count++))
        fi
    done <<< "$branches_to_check"

    print_success "Branch cleanup completed. Deleted $deleted_count branches."
}

# Create some useful aliases
alias gcb='git-cleanup-branches'
alias git-prune-branches='git-cleanup-branches'

# Optional: Add a shorter alias
alias gclean='git-cleanup-branches'



# Optional: Auto-cleanup function (use with caution)
git-auto-cleanup() {
    echo "⚠️  This will automatically clean up branches. Continue? (y/N)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        git-cleanup-branches
    else
        echo "Cleanup cancelled."
    fi
}


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
# [f]uzzy check[o]ut
fo() {
  git branch --no-color --sort=-committerdate --format='%(refname:short)' | fzf --header 'git switch' | xargs git switch
}
# [p]ull request check[o]ut
po() {
  gh pr list --author "@me" | fzf --header 'checkout PR' | awk '{print $(NF-5)}' | xargs git switch
}
# Open PR on GitHub
pr() {
  if type gh &> /dev/null; then
    gh pr view -w
  else
    echo "gh is not installed"
  fi
}

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
