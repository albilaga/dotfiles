# Dotfiles

Personal dotfiles for macOS development environment setup. This repository contains shell configurations, application settings, and development tool configurations managed through symbolic links.

## Features

- **Zsh Configuration**: Vi mode, custom prompt with git status, extensive history management
- **Git Integration**: Git Town workflow, GPG signing, custom aliases and functions
- **Modern CLI Tools**: fzf, ripgrep, bat, lsd, zoxide integration
- **Application Configs**: Ghostty terminal, Zed editor, lsd, and more
- **Smart Git Functions**: Intelligent branch cleanup, fuzzy checkout, PR management via gh CLI

## Prerequisites

- macOS (Darwin)
- [Homebrew](https://brew.sh/) package manager

## Installation

### 1. Clone the repository

```bash
git clone <your-repo-url> ~/Documents/personal/dotfiles
cd ~/Documents/personal/dotfiles
```

### 2. Install dependencies

Install all required packages and applications:

```bash
brew bundle
```

This installs:
- Development tools: git, git-lfs, git-town, gh, node, go
- Terminal utilities: neovim, fzf, bat, lsd, ripgrep, zoxide, lazygit
- Applications: Ghostty, Zed, OrbStack, and more
- Fonts: Monaspace font family

### 3. Install dotfiles

Install all configurations:

```bash
make all
```

Or install specific components:

```bash
make git      # Install git configs only
make zsh      # Install zsh configs only
make config   # Install application configs only
make zed      # Install Zed editor settings only
```

### 4. Set up GPG signing (macOS)

The git configuration enables GPG signing for commits and tags by default. To ensure proper GPG functionality on macOS:

1. **Install pinentry-mac** (if not already installed via Brewfile):
   ```bash
   brew install pinentry-mac
   ```

2. **Configure GPG agent**:
   ```bash
   echo "pinentry-program $(which pinentry-mac)" >> ~/.gnupg/gpg-agent.conf
   killall gpg-agent
   ```

3. **Generate or import your GPG key**:

   To generate a new key:
   ```bash
   gpg --full-generate-key
   ```

   To import an existing key:
   ```bash
   gpg --import your-private-key.asc
   ```

4. **Update your GPG key ID in gitconfig**:

   Find your key ID:
   ```bash
   gpg --list-secret-keys --keyid-format=long
   ```

   Then update the `signingkey` in `gitconfig`:
   ```ini
   [user]
       signingkey = YOUR_KEY_ID
   ```

5. **Add your GPG key to GitHub**:
   ```bash
   gpg --armor --export YOUR_KEY_ID
   ```
   Copy the output and add it to [GitHub Settings > SSH and GPG keys](https://github.com/settings/keys)

### 5. Restart your shell

```bash
exec zsh
# or simply open a new terminal window
```

## Post-Installation Configuration

### Personal Information

Update the following files with your personal information:

1. **gitconfig** - Update user name, email, and signingkey:
   ```ini
   [user]
       name = Your Name
       email = your.email@example.com
       signingkey = YOUR_GPG_KEY_ID
   ```

2. **Conditional Git Configs** - Adjust or remove the includeIf directives in `gitconfig`:
   ```ini
   [includeIf "gitdir:~/Documents/personal/"]
       path = ~/Documents/personal/.gitconfig

   [includeIf "gitdir:~/Documents/pans/"]
       path = ~/Documents/pans/.gitconfig
   ```

### Private Configuration

Create a `~/.zsh.d/private/` directory for private/machine-specific configurations:

```bash
mkdir -p ~/.zsh.d/private
```

Any `.sh` files in this directory will be automatically sourced by zsh but won't be tracked in the repository.

## Structure

```
.
├── Makefile                 # Installation automation
├── Brewfile                 # Homebrew dependencies
├── gitconfig                # Git configuration with GPG signing
├── githelpers               # Git log formatting helpers
├── gitignore                # Global gitignore
├── zshrc                    # Main zsh configuration
├── zed_config.json         # Zed editor settings
├── zsh.d/                   # Modular zsh configs
│   ├── aliases.Darwin.sh
│   ├── env.Darwin.sh
│   ├── git-functions.zsh
│   └── video-images-functions.zsh
├── config/                  # Application configs
│   ├── ghostty/
│   └── lsd/
└── opencode/                # Claude Code agent prompts
    └── agent/
```

## Key Features

### Git Functions

- **`gcb` / `gclean`** - Intelligent branch cleanup using GitHub API and git merge detection
- **`fo`** - Fuzzy checkout branches with fzf
- **`po`** - Checkout your own pull requests
- **`pr`** - Open current PR in browser

### Git Aliases

Common shortcuts defined in `gitconfig` and `zsh.d/git-functions.zsh`:

- `gst` / `s` - git status
- `gaa` - git add -A
- `gc` - git commit
- `gcm` - switch to main branch
- `gd` - git diff
- `co` / `coc` - git switch / switch with create
- `up` / `upf` - git push / force push
- `pu` / `pur` - git pull / pull with rebase

### Shell Aliases

- `ez` - Edit zshrc
- `sz` - Source zshrc
- `update` - Update all Homebrew packages
- `cleanup` - Clean package manager caches

### Tools Integration

- **fzf**: Fuzzy finder with ripgrep integration (Ctrl+R for history, Ctrl+T for files)
- **zoxide**: Smart directory jumping (automatically learns your habits)
- **bat**: Syntax-highlighted cat replacement
- **lsd**: Modern ls replacement with icons
- **lazygit**: Terminal UI for git

## Customization

### Adding New Application Configs

1. Create a directory under `config/`:
   ```bash
   mkdir -p config/myapp
   ```

2. Add your config files maintaining the desired structure

3. Run `make config` to symlink to `~/.config/myapp/`

### Modifying Shell Config

After editing `zshrc` or files in `zsh.d/`:

```bash
source ~/.zshrc    # or use: sz
```

Note: Since configurations are symlinked, editing files in either the repository or home directory will affect both locations.

## Git Workflow

This setup assumes a Git Town workflow with:

- **Default branch**: `main`
- **Pull strategy**: rebase
- **Signing**: GPG-signed commits and tags
- **GitHub integration**: PR management via `gh` CLI
- **Branch management**: Automated cleanup of merged branches

## Troubleshooting

### GPG signing fails

If commits fail with GPG errors:

```bash
# Restart GPG agent
killall gpg-agent

# Test GPG signing
echo "test" | gpg --clearsign

# Check GPG agent configuration
cat ~/.gnupg/gpg-agent.conf
```

### Pinentry not showing

Ensure pinentry-mac is configured:

```bash
# Verify pinentry-mac is installed
which pinentry-mac

# Check GPG agent config
grep pinentry ~/.gnupg/gpg-agent.conf

# Restart agent
killall gpg-agent
```

### Zsh completions not working

```bash
# Rebuild completion cache
rm -f ~/.zcompdump*
compinit
```

## License

Personal dotfiles - use at your own discretion.
