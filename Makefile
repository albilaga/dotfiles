UNAME := $(shell uname)
DOTFILE_PATH := $(shell pwd)

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
	command -v pi >/dev/null || npm install -g --ignore-scripts @earendil-works/pi-coding-agent
	for package in \
		npm:@dietrichgebert/ponytail \
		npm:@quintinshaw/pi-dynamic-workflows \
		npm:pi-mcp-adapter \
		npm:pi-caveman \
		npm:pi-web-access \
		npm:pi-catppuccin; do \
		pi list | grep -Fq "  $$package" || pi install "$$package"; \
	done
	gh extension list | grep -q '^gh stack[[:space:]]' || gh extension install github/gh-stack
	test -f $(HOME)/.agents/skills/gh-stack/SKILL.md || npx --yes skills add github/gh-stack@gh-stack -g -y
	test -f $(HOME)/.agents/skills/herdr/SKILL.md || npx --yes skills add herdrdev/herdr --skill herdr -g -y
	# Idempotent; installs ~/.pi/agent/extensions/herdr-agent-state.ts (generated
	# by herdr, not tracked in dotfiles - recreated here).
	command -v herdr >/dev/null && herdr integration install pi >/dev/null || true

pi: pi-packages
	mkdir -p $(HOME)/.pi/agent/prompts
	cp $(DOTFILE_PATH)/pi/settings.json $(HOME)/.pi/agent/settings.json
	mkdir -p $(HOME)/.pi/workflows
	cp $(DOTFILE_PATH)/pi/workflows-model-tiers.json $(HOME)/.pi/workflows/model-tiers.json
	ln -sf $(DOTFILE_PATH)/pi/AGENTS.md $(HOME)/.pi/agent/AGENTS.md
	ln -sf $(DOTFILE_PATH)/pi/prompts/pr.md $(HOME)/.pi/agent/prompts/pr.md

all: git zsh config zed herdr pi
.PHONY: all git zsh config zed herdr pi pi-packages
