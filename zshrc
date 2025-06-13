##############
# BASIC SETUP
##############

typeset -U PATH
autoload colors; colors;

#############
## PRIVATE ##
#############
# Include private stuff that's not supposed to show up
# in the dotfiles repo
local private_dir="${HOME}/.zsh.d/private"
if [ -d ${private_dir} ]; then
    for file in ${private_dir}/*.sh; do
    if [ -e ${file} ]; then
        . ${file}
    fi
    done
fi

##########
# HISTORY
##########

HISTFILE=$HOME/.zsh_history
HISTSIZE=50000
SAVEHIST=50000

setopt INC_APPEND_HISTORY     # Immediately append to history file.
setopt EXTENDED_HISTORY       # Record timestamp in history.
setopt HIST_EXPIRE_DUPS_FIRST # Expire duplicate entries first when trimming history.
setopt HIST_IGNORE_DUPS       # Dont record an entry that was just recorded again.
setopt HIST_IGNORE_ALL_DUPS   # Delete old recorded entry if new entry is a duplicate.
setopt HIST_FIND_NO_DUPS      # Do not display a line previously found.
setopt HIST_IGNORE_SPACE      # Dont record an entry starting with a space.
setopt HIST_SAVE_NO_DUPS      # Dont write duplicate entries in the history file.
unsetopt HIST_VERIFY          # Execute commands using history (e.g.: using !$) immediately


#############
# COMPLETION
#############

# Add completions installed through Homebrew packages
# See: https://docs.brew.sh/Shell-Completion
if type brew &>/dev/null; then
  FPATH=/usr/local/share/zsh/site-functions:$FPATH
fi

# Speed up completion init, see: https://gist.github.com/ctechols/ca1035271ad134841284
autoload -Uz compinit
for dump in ~/.zcompdump(N.mh+24); do
  compinit
done
compinit -C

# unsetopt menucomplete
unsetopt flowcontrol
setopt auto_menu
setopt complete_in_word
setopt always_to_end
setopt auto_pushd

# case insensitive auto completion
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

###############
# KEY BINDINGS
###############

# Vim Keybindings
bindkey -v

# This is a "fix" for zsh in Ghostty:
# Ghostty implements the fixterms specification https://www.leonerd.org.uk/hacks/fixterms/
# and under that `Ctrl-[` doesn't send escape but `ESC [91;5u`.
#
# (tmux and Neovim both handle 91;5u correctly, but raw zsh inside Ghostty doesn't)
#
# Thanks to @rockorager for this!
bindkey "^[[91;5u" vi-cmd-mode

# Open line in Vim by pressing 'v' in Command-Mode
autoload -U edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# Push current line to buffer stack, return to PS1
bindkey "^Q" push-input

# Make up/down arrow put the cursor at the end of the line
# instead of using the vi-mode mappings for these keys
bindkey "\eOA" up-line-or-history
bindkey "\eOB" down-line-or-history
bindkey "\eOC" forward-char
bindkey "\eOD" backward-char

# CTRL-R to search through history
bindkey '^R' history-incremental-search-backward
# CTRL-S to search forward in history
bindkey '^S' history-incremental-search-forward
# Accept the presented search result
bindkey '^Y' accept-search

# Use the arrow keys to search forward/backward through the history,
# using the first word of what's typed in as search word
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Use the same keys as bash for history forward/backward: Ctrl+N/Ctrl+P
bindkey '^P' history-search-backward
bindkey '^N' history-search-forward

# Backspace working the way it should
bindkey '^?' backward-delete-char
bindkey '^[[3~' delete-char

# Some emacs keybindings won't hurt nobody
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line

# Where should I put you?
bindkey -s '^F' "tmux-sessionizer\n"

#########
# Aliases
#########

case $OSTYPE in
  linux*)
    local aliasfile="${HOME}/.zsh.d/aliases.Linux.sh"
    [[ -e ${aliasfile} ]] && source ${aliasfile}
  ;;
  darwin*)
    local aliasfile="${HOME}/.zsh.d/aliases.Darwin.sh"
    [[ -e ${aliasfile} ]] && source ${aliasfile}
  ;;
esac

if type lsd &> /dev/null; then
  alias ls=lsd
fi
alias lls='ls -lh --sort=size --reverse'
alias llt='ls -lrt'
alias bear='clear && echo "Clear as a bear!"'

alias history='history 1'
alias hist='history | grep '

# Use rsync with ssh and show progress
alias rsyncssh='rsync -Pr --rsh=ssh'

# Edit/Source vim config
alias ez='vim ~/.zshrc'
alias sz='source ~/.zshrc'

# git
alias gst='git status'
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

alias pingtest="ping 8.8.8.8"
alias updateall="brew update && brew upgrade && brew autoremove && npm update -g && rustup update"
alias cleanup="dotnet nuget locals all -c && brew autoremove && brew cleanup"

##########
# FUNCTIONS
##########

mkdircd() {
  mkdir -p $1 && cd $1
}

render_dot() {
  local out="${1}.png"
  dot "${1}" \
    -Tpng \
    -Nfontname='JetBrains Mono' \
    -Nfontsize=10 \
    -Nfontcolor='#fbf1c7' \
    -Ncolor='#fbf1c7' \
    -Efontname='JetBrains Mono' \
    -Efontcolor='#fbf1c7' \
    -Efontsize=10 \
    -Ecolor='#fbf1c7' \
    -Gbgcolor='#1d2021' > ${out} && \
    kitty +kitten icat --align=left ${out}
}

serve() {
  local port=${1:-8000}
  local ip=$(ipconfig getifaddr en0)
  echo "Serving on ${ip}:${port} ..."
  python -m SimpleHTTPServer ${port}
}

beautiful() {
  while
  do
    i=$((i + 1)) && echo -en "\x1b[3$(($i % 7))mo" && sleep .2
  done
}

spinner() {
  while
  do
    for i in "-" "\\" "|" "/"
    do
      echo -n " $i \r\r"
      sleep .1
    done
  done
}

# Open PR on GitHub
pr() {
  if type gh &> /dev/null; then
    gh pr view -w
  else
    echo "gh is not installed"
  fi
}

# MP4 compression function for GitHub (maximum compression)
compress_mp4_github() {
    if [ $# -eq 0 ]; then
        echo "Usage: compress_mp4_github <input.mp4> [output.mp4]"
        echo "If no output name provided, will use input_compressed.mp4"
        return 1
    fi

    local input="$1"
    local output="${2:-${1%.*}_compressed.mp4}"

    if [ ! -f "$input" ]; then
        echo "Error: Input file '$input' not found"
        return 1
    fi

    echo "Compressing $input to $output (maximum compression for GitHub)..."

    ffmpeg -i "$input" \
        -c:v libx264 \
        -preset veryslow \
        -crf 28 \
        -c:a aac \
        -b:a 64k \
        -ac 1 \
        -ar 22050 \
        -vf "scale=640:-2" \
        -r 15 \
        -movflags +faststart \
        -f mp4 \
        "$output"

    if [ $? -eq 0 ]; then
        local original_size=$(stat -f%z "$input" 2>/dev/null || stat -c%s "$input" 2>/dev/null)
        local compressed_size=$(stat -f%z "$output" 2>/dev/null || stat -c%s "$output" 2>/dev/null)
        local reduction=$((100 - (compressed_size * 100 / original_size)))

        echo "✅ Compression complete!"
        echo "Original size: $(numfmt --to=iec $original_size)B"
        echo "Compressed size: $(numfmt --to=iec $compressed_size)B"
        echo "Size reduction: ${reduction}%"
    else
        echo "❌ Compression failed"
        return 1
    fi
}

# Alternative function with balanced quality/size for when extreme compression isn't needed
compress_mp4_balanced() {
    if [ $# -eq 0 ]; then
        echo "Usage: compress_mp4_balanced <input.mp4> [output.mp4]"
        return 1
    fi

    local input="$1"
    local output="${2:-${1%.*}_balanced.mp4}"

    if [ ! -f "$input" ]; then
        echo "Error: Input file '$input' not found"
        return 1
    fi

    echo "Compressing $input to $output (balanced quality/size)..."

    ffmpeg -i "$input" \
        -c:v libx264 \
        -preset slow \
        -crf 23 \
        -c:a aac \
        -b:a 128k \
        -vf "scale=1280:-2" \
        -r 24 \
        -movflags +faststart \
        -f mp4 \
        "$output"

    if [ $? -eq 0 ]; then
        echo "✅ Balanced compression complete!"
    else
        echo "❌ Compression failed"
        return 1
    fi
}

# Alias for quick access
alias mp4compress='compress_mp4_github'

# PNG compression functions
pngx() {
    local input="$1"
    local basename="${input%.*}"
    pngquant --speed 1 --skip-if-larger "$input" --output "${basename}-output.png"
}

pngxo() {
    pngquant --speed 1 --skip-if-larger --ext .png --force "$1"
}

# Compress all PNG files in current directory with -output.png suffix
pngxa() {
    local png_files=(*.png)

    if [ ${#png_files[@]} -eq 0 ] || [ ! -f "${png_files[0]}" ]; then
        echo "No PNG files found in current directory"
        return 1
    fi

    echo "Found ${#png_files[@]} PNG file(s) to compress..."

    local processed=0
    local skipped=0

    for file in "${png_files[@]}"; do
        # Skip files that already have -output suffix to avoid processing them again
        if [[ "$file" == *"-output.png" ]]; then
            echo "⏭️  Skipping $file (already processed)"
            ((skipped++))
            continue
        fi

        echo "🔄 Processing: $file"
        local basename="${file%.*}"

        if pngquant --speed 1 --skip-if-larger "$file" --output "${basename}-output.png" 2>/dev/null; then
            echo "✅ Compressed: $file → ${basename}-output.png"
            ((processed++))
        else
            echo "⚠️  Skipped: $file (no reduction possible or error)"
            ((skipped++))
        fi
    done

    echo "📊 Summary: $processed compressed, $skipped skipped"
}

# Compress and overwrite all PNG files in current directory
pngxoa() {
    local png_files=(*.png)

    if [ ${#png_files[@]} -eq 0 ] || [ ! -f "${png_files[0]}" ]; then
        echo "No PNG files found in current directory"
        return 1
    fi

    echo "Found ${#png_files[@]} PNG file(s) to compress (will overwrite originals)..."
    echo "⚠️  WARNING: This will overwrite original files!"

    # Ask for confirmation
    echo -n "Continue? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        return 0
    fi

    local processed=0
    local skipped=0

    for file in "${png_files[@]}"; do
        echo "🔄 Processing: $file"

        if pngquant --speed 1 --skip-if-larger --ext .png --force "$file" 2>/dev/null; then
            echo "✅ Compressed: $file (overwritten)"
            ((processed++))
        else
            echo "⚠️  Skipped: $file (no reduction possible or error)"
            ((skipped++))
        fi
    done

    echo "📊 Summary: $processed compressed, $skipped skipped"
}

#########
# PROMPT
#########

setopt prompt_subst

git_prompt_info() {
  local dirstatus=" OK"
  local dirty="%{$fg_bold[red]%} X%{$reset_color%}"

  if [[ ! -z $(git status --porcelain 2> /dev/null | tail -n1) ]]; then
    dirstatus=$dirty
  fi

  ref=$(git symbolic-ref HEAD 2> /dev/null) || \
  ref=$(git rev-parse --short HEAD 2> /dev/null) || return
  echo " %{$fg_bold[green]%}${ref#refs/heads/}$dirstatus%{$reset_color%}"
}

local dir_info_color="%B"

local dir_info_color_file="${HOME}/.zsh.d/dir_info_color"
if [ -r ${dir_info_color_file} ]; then
  source ${dir_info_color_file}
fi

local dir_info="%{$dir_info_color%}%(5~|%-1~/.../%2~|%4~)%{$reset_color%}"
local promptnormal="φ %{$reset_color%}"
local promptjobs="%{$fg_bold[red]%}φ %{$reset_color%}"

PROMPT='${dir_info}$(git_prompt_info) %(1j.$promptjobs.$promptnormal)'

simple_prompt() {
  local prompt_color="%B"
  export PROMPT="%{$prompt_color%}$promptnormal"
}

########
# ENV
########

export COLOR_PROFILE="dark"

case $OSTYPE in
  linux*)
    local envfile="${HOME}/.zsh.d/env.Linux.sh"
    [[ -e ${envfile} ]] && source ${envfile}
  ;;
  darwin*)
    local envfile="${HOME}/.zsh.d/env.Darwin.sh"
    [[ -e ${envfile} ]] && source ${envfile}
  ;;
esac

export LSCOLORS="Gxfxcxdxbxegedabagacad"

# Reduce delay for key combinations in order to change to vi mode faster
# See: http://www.johnhawthorn.com/2012/09/vi-escape-delays/
# Set it to 10ms
export KEYTIMEOUT=1

if type nvim &> /dev/null; then
  alias vim="nvim"
  export EDITOR="nvim"
  export PSQL_EDITOR="nvim -c"set filetype=sql""
  export GIT_EDITOR="nvim"
else
  export EDITOR='vim'
  export PSQL_EDITOR='vim -c"set filetype=sql"'
  export GIT_EDITOR='vim'
fi

# rustup
export PATH="$HOME/.cargo/bin:$PATH"

# homebrew
export PATH="/usr/local/bin:$PATH"
export PATH="/opt/homebrew/opt/gnu-sed/libexec/gnubin:$PATH"

# Android SDK
export PATH="$HOME/Library/Android/sdk/platform-tools/:$PATH"

# Created by `pipx`
export PATH="$PATH:$HOME/.local/bin"

# dotnet tools
export PATH="$PATH:$HOME/.dotnet/tools"

# flutter
export PATH="$PATH:$HOME/flutter/bin"

# fzf
if type fzf &> /dev/null && type rg &> /dev/null; then
  source <(fzf --zsh)
  export FZF_DEFAULT_COMMAND='rg --files --hidden --follow --glob "!.git/*" --glob "!vendor/*"'
  export FZF_CTRL_T_COMMAND='rg --files --hidden --follow --glob "!.git/*" --glob "!vendor/*"'
  export FZF_ALT_C_COMMAND="$FZF_DEFAULT_COMMAND"
fi

#zoxide
if type zoxide &> /dev/null; then
    eval "$(zoxide init zsh --cmd cd)"
fi

# Try out atuin
if type atuin &> /dev/null; then
  eval "$(atuin init zsh)"
fi
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
