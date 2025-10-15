if which nvim &> /dev/null; then
  alias vim='nvim'
  export EDITOR='nvim'
  export PSQL_EDITOR="nvim -c"set filetype=sql""
  export GIT_EDITOR='nvim'
else
  export EDITOR="vim"
  export PSQL_EDITOR="nvim -c"set filetype=sql""
  export GIT_EDITOR="vim"
fi

if which bat &> /dev/null; then
  alias cat='bat'
fi
