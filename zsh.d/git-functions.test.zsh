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
