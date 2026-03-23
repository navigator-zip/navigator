#!/usr/bin/env bash

# disable shellcheck comments about expansion not happening in single quotes (which we want in this case)
# shellcheck disable=2016
# shellcheck disable=SC1091

# This script will download and install mise (https://mise.jdx.dev) and install the tools from
# .mise.toml. In CI that's all we need to do for success. For developers this will work well for the
# first run but will fully take effect on the next launch or reload of their shell.

MISE_DIR="$HOME/.local/share/mise"

curl https://mise.run | sh

# Add mise activation to the active shell's rc file for next launch/reload.
# Intentionally do not source the rc file here so this script can run in non-interactive shells.
if [[ "$SHELL" == *"zsh"* ]]; then
	MISE_RC_FILE="$HOME/.zshrc"
	MISE_RC_COMMAND='eval "$($HOME/.local/bin/mise activate zsh)"'
elif [[ "$SHELL" == *"bash"* ]]; then
	MISE_RC_FILE="$HOME/.bashrc"
	MISE_RC_COMMAND='eval "$($HOME/.local/bin/mise activate bash)"'
elif [[ "$SHELL" == *"fish"* ]]; then
	MISE_RC_FILE="$HOME/.config/fish/config.fish"
	MISE_RC_COMMAND='$HOME/.local/bin/mise activate fish | source'
fi

if [ -n "${MISE_RC_FILE:-}" ] && [ -n "${MISE_RC_COMMAND:-}" ]; then
	# Keep these rc updates idempotent and newline-safe.
	mkdir -p "$(dirname "$MISE_RC_FILE")"
	touch "$MISE_RC_FILE"
	echo >> "$MISE_RC_FILE"
	if ! grep -Fxq "$MISE_RC_COMMAND" "$MISE_RC_FILE"; then
		echo "$MISE_RC_COMMAND" >> "$MISE_RC_FILE"
	else
		:
	fi
fi

# These are environment variables used by the mise install step and only needed
export MISE_TRUSTED_CONFIG_PATHS
MISE_TRUSTED_CONFIG_PATHS="$(pwd)"

export MISE_YES
MISE_YES=1

export PATH="$HOME/.local/bin:$MISE_DIR/bin:$MISE_DIR/shims:$PATH"

"$HOME/.local/bin/mise" install
