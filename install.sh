#!/usr/bin/env bash

# Installer for cs (Multi-Account Switcher for Claude Code)
# Copies ccswitch.sh to ~/.claude-account-switch/cs and sets up PATH in ~/.bashrc

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.claude-account-switch"
OLD_DIR="$HOME/.claude-switch-backup"
BASHRC="$HOME/.bashrc"

# --- 1. Create install directory with subdirs ---
mkdir -p "$INSTALL_DIR"/{configs,credentials}
chmod 700 "$INSTALL_DIR" "$INSTALL_DIR"/configs "$INSTALL_DIR"/credentials

# --- 2. Copy script as 'cs' ---
cp "$SCRIPT_DIR/ccswitch.sh" "$INSTALL_DIR/cs"
chmod 700 "$INSTALL_DIR/cs"
echo "Installed: $INSTALL_DIR/cs"

# --- 3. Migrate existing backup data (copy, preserve original) ---
if [[ -d "$OLD_DIR" && ! -f "$INSTALL_DIR/sequence.json" ]]; then
    echo "Migrating existing data from $OLD_DIR ..."
    [[ -f "$OLD_DIR/sequence.json" ]] && cp -a "$OLD_DIR/sequence.json" "$INSTALL_DIR/"
    if [[ -d "$OLD_DIR/configs" ]]; then
        cp -a "$OLD_DIR/configs/." "$INSTALL_DIR/configs/" 2>/dev/null || true
    fi
    if [[ -d "$OLD_DIR/credentials" ]]; then
        cp -a "$OLD_DIR/credentials/." "$INSTALL_DIR/credentials/" 2>/dev/null || true
    fi
    echo "Migration done. Original $OLD_DIR left intact; remove it manually if no longer needed."
fi

# --- 4. Ensure PATH contains INSTALL_DIR ---
PATH_EXPORT='export PATH="$HOME/.claude-account-switch:$PATH"'

# Check if INSTALL_DIR is already active in the current shell's PATH
if case ":$PATH:" in *":$INSTALL_DIR:"*) true ;; *) false ;; esac; then
    echo "PATH already includes $INSTALL_DIR."
else
    # Check if the export line already exists in .bashrc (avoid duplicates)
    if [[ -f "$BASHRC" ]] && grep -qF '.claude-account-switch' "$BASHRC"; then
        echo "PATH entry already in $BASHRC (not yet sourced — run: source $BASHRC)"
    else
        echo "$PATH_EXPORT" >> "$BASHRC"
        echo "Added PATH entry to $BASHRC."
        echo "Run: source $BASHRC   (or open a new terminal)"
    fi
fi

echo ""
echo "Done. Try: source $BASHRC && cs h"
