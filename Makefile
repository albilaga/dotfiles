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
ghostty:
	mkdir -p $(HOME)/.config/ghostty
	cd $(DOTFILE_PATH)/ghostty && find . -type f | while read file; do \
		mkdir -p $(HOME)/.config/ghostty/$$(dirname $$file); \
		ln -sf $(DOTFILE_PATH)/ghostty/$$file $(HOME)/.config/ghostty/$$file; \
	done

zed:
	mkdir -p $(HOME)/.config/zed
	ln -sf $(DOTFILE_PATH)/zed_config.json $(HOME)/.config/zed/settings.json

all: git zsh ghostty zed
.PHONY: all git zsh ghostty zed
