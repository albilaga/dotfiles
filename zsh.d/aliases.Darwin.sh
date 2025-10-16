################
# LS ALIASES
################

# Use lsd if available, otherwise use default ls with color
if type lsd &> /dev/null; then
  alias ls=lsd
fi

alias l='ls -l'
alias la='ls -a'
alias lla='ls -la'
alias lt='ls --tree'
alias lls='ls -lh --sort=size --reverse'
alias llt='ls -lrt'
