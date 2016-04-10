#!/bin/bash

# Run as Root
if [ "$(whoami)" != "root" ]; then
	sudo "$0" "$@"
	exit 0
fi

# Supress most-recent login
hushlogins=(
	"$HOME/.hushlogin"
	"/var/root/.hushlogin"
	)
for hushlogin in "${hushlogins[@]}"; do
	touch "$hushlogin"
done

# Enable case-insensitive tab completion
inputrcs=(
	"$HOME/.inputrc"
	"/var/root/.inputrc"
	)
for inputrc in "${inputrcs[@]}"; do
	echo 'set completion-ignore-case on' > "$inputrc"
done

# Customize PS1 and PATH
profiles=(
	"$HOME/.bash_profile"
	"/var/root/.profile"
	)
for profile in "${profiles[@]}"; do
	echo 'export PS1="\\$ "' > "$profile"
	echo 'export PATH' >> "$profile"
	echo 'export PATH="/usr/local/bin:$PATH"' >> "$profile"
done