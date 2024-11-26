##############
# BASIC SETUP
##############

typeset -U PATH
autoload colors; colors;

# zsh parameter completion for brew
autoload -Uz compinit
compinit

source <(fzf --zsh)

# Android SDK
export PATH="$HOME/Library/Android/sdk/platform-tools/:$PATH"


alias openzsh="zed ~/.zshrc"
alias reloadzsh="source ~/.zshrc"
alias pingtest="ping 8.8.8.8"
alias updateall="brew update && brew upgrade && brew autoremove && npm update -g && rustup update"
alias cleanup="dotnet nuget locals all -c && brew autoremove && brew cleanup"
alias ll="ls -l"
alias llr="ls -latr"
