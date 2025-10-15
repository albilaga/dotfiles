################
# LS ALIASES
################

# Use lsd if available, otherwise use default ls with color
if type lsd &> /dev/null; then
  alias ls=lsd
fi
alias lls='ls -lh --sort=size --reverse'
alias llt='ls -lrt'
