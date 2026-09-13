UNAME := $(shell uname)
# Always point at the main checkout, not the worktree make ran in -
# worktrees are throwaway, symlinks here must survive their removal.
GIT_COMMON_DIR := $(shell git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || pwd)/.git
DOTFILE_PATH := $(patsubst %/.git,%,$(patsubst %/,%,$(dir $(GIT_COMMON_DIR))))
PI_PROFILE = $(or $(PROFILE),$(shell jq -r '.dotfilesProfile // empty' $(HOME)/.pi/agent/settings.json 2>/dev/null),personal)

$(HOME)/.%: %
	ln -sf $(DOTFILE_PATH)/$^ $@

git: $(HOME)/.gitconfig $(HOME)/.githelpers $(HOME)/.gitignore
zsh: $(HOME)/.zshrc
	mkdir -p $(HOME)/.zsh.d
	for file in $(DOTFILE_PATH)/zsh.d/*; do \
		ln -sf $$file $(HOME)/.zsh.d/$$(basename $$file); \
	done
config:
	mkdir -p $(HOME)/.config
	for dir in $(DOTFILE_PATH)/config/*; do \
		if [ -d "$$dir" ]; then \
			app=$$(basename $$dir); \
			mkdir -p $(HOME)/.config/$$app; \
			cd $$dir && find . -type f | while read file; do \
				mkdir -p $(HOME)/.config/$$app/$$(dirname $$file); \
				ln -sf $$dir/$$file $(HOME)/.config/$$app/$$file; \
			done; \
		fi; \
	done

zed:
	mkdir -p $(HOME)/.config/zed
	ln -sf $(DOTFILE_PATH)/zed_config.json $(HOME)/.config/zed/settings.json

herdr:
	herdr plugin list --json | grep -Fq '"plugin_id":"herdr-automatic-rename"' || herdr plugin install qu8n/herdr-automatic-rename --yes
	herdr plugin list --json | grep -Fq '"plugin_id":"persiyanov.reviewr"' || herdr plugin install persiyanov/herdr-reviewr --yes

pi-packages:
	npm install -g --ignore-scripts @earendil-works/pi-coding-agent
	for package in \
		npm:@dietrichgebert/ponytail \
		npm:@pi-archimedes/image-paste \
		npm:pi-subagents \
		npm:pi-mcp-adapter \
		npm:pi-caveman \
		npm:pi-web-access \
		npm:pi-catppuccin \
		npm:pi-commandcode-provider; do \
		pi list | grep -Fq "  $$package" || pi install "$$package"; \
	done
	gh extension list | grep -q '^gh stack[[:space:]]' || gh extension install github/gh-stack
	test -f $(HOME)/.agents/skills/gh-stack/SKILL.md || npx --yes skills add github/gh-stack@gh-stack -g -y
	test -f $(HOME)/.agents/skills/herdr/SKILL.md || npx --yes skills add herdrdev/herdr --skill herdr -g -y
	# Idempotent; installs ~/.pi/agent/extensions/herdr-agent-state.ts (generated
	# by herdr, not tracked in dotfiles - recreated here).
	command -v herdr >/dev/null && herdr integration install pi >/dev/null || true

pi: pi-packages
	mkdir -p $(HOME)/.pi/agent/prompts $(HOME)/.pi/agent/extensions $(HOME)/.pi/agent/skills
	test -f $(DOTFILE_PATH)/pi/profiles/$(PI_PROFILE).json
	jq -s '.[0] * .[1] * {dotfilesProfile: "$(PI_PROFILE)"}' \
		$(DOTFILE_PATH)/pi/settings.json $(DOTFILE_PATH)/pi/profiles/$(PI_PROFILE).json \
		> $(HOME)/.pi/agent/settings.json.tmp
	mv $(HOME)/.pi/agent/settings.json.tmp $(HOME)/.pi/agent/settings.json
	ln -sf $(DOTFILE_PATH)/pi/keybindings.json $(HOME)/.pi/agent/keybindings.json
	ln -sf $(DOTFILE_PATH)/pi/extensions/*.ts $(HOME)/.pi/agent/extensions/
	rm -f $(HOME)/.pi/workflows/model-tiers.json
	ln -sf $(DOTFILE_PATH)/pi/AGENTS.md $(HOME)/.pi/agent/AGENTS.md
	ln -sf $(DOTFILE_PATH)/pi/prompts/*.md $(HOME)/.pi/agent/prompts/
	for dir in $(DOTFILE_PATH)/pi/skills/*; do \
		ln -sfn $$dir $(HOME)/.pi/agent/skills/$$(basename $$dir); \
	done

all: git zsh config zed herdr pi
.PHONY: all git zsh config zed herdr pi pi-packages
