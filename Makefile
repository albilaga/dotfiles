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

pi:
	mkdir -p $(HOME)/.pi/agent/prompts
	ln -sf $(DOTFILE_PATH)/pi/AGENTS.md $(HOME)/.pi/agent/AGENTS.md
	ln -sf $(DOTFILE_PATH)/pi/prompts/pr.md $(HOME)/.pi/agent/prompts/pr.md

all: git zsh config zed pi
.PHONY: all git zsh config zed pi
