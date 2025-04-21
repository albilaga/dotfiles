UNAME := $(shell uname)
DOTFILE_PATH := $(shell pwd)

$(HOME)/.%: %
	ln -sf $(DOTFILE_PATH)/$^ $@

git: $(HOME)/.gitconfig $(HOME)/.githelpers $(HOME)/.gitignore
zsh: $(HOME)/.zshrc $(HOME)/.zsh.d

$(HOME)/.config/ghostty/config:
	mkdir -p $(HOME)/.config/ghostty
	ln -sf $(DOTFILE_PATH)/ghostty_config $(HOME)/.config/ghostty/config

ghostty: $(HOME)/.config/ghostty/config

GHOSTTY_THEMES := $(HOME)/.config/ghostty/themes

ghostty-themes:
	mkdir -p $(GHOSTTY_THEMES)
	ln -sf $(DOTFILE_PATH)/ghostty-themes/* $(GHOSTTY_THEMES)/


all: git zsh ghostty ghostty-themes
.PHONY: all
