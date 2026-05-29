# Multi-Account Switcher for Claude Code

> **Fork**: This is a fork of [ming86/cc-account-switcher](https://github.com/ming86/cc-account-switcher).
> Added: live usage stats (session %, weekly %, remaining time, extra usage balance) displayed in `cs l` / `cs s` / `cs st`.

A simple tool to manage and switch between multiple Claude Code accounts on macOS, Linux, and WSL.

## Features

- **Multi-account management**: Add, remove, and list Claude Code accounts
- **Quick switching**: Switch between accounts with simple commands
- **Live usage stats**: See session %, weekly %, time until reset, and extra usage balance for every account at a glance
- **Cross-platform**: Works on macOS, Linux, and WSL
- **Secure storage**: Uses system keychain (macOS) or protected files (Linux/WSL)
- **Settings preservation**: Only switches authentication - your themes, settings, and preferences remain unchanged

## Installation

Clone and run the installer:

```bash
git clone https://github.com/min09357/cc-account-switcher.git
cd cc-account-switcher
./install.sh
source ~/.bashrc
```

The installer:
- Copies `ccswitch.sh` to `~/.claude-account-switch/cs`
- Adds `~/.claude-account-switch` to `$PATH` in `~/.bashrc` (if not already there)
- Migrates existing data from `~/.claude-switch-backup` if present

To update after pulling new changes, run `./install.sh` again.

## Usage

### Basic Commands

```bash
# Add current account to managed accounts
cs a

# List all managed accounts with live usage stats
cs l

# Switch to next account in sequence
cs s

# Switch to specific account by number or email
cs st 2
cs st user2@example.com

# Remove an account
cs r user2@example.com

# Show help
cs h
```

### First Time Setup

1. **Log into Claude Code** with your first account (make sure you're actively logged in)
2. Run `cs a` to add it to managed accounts
3. **Log out** and log into Claude Code with your second account
4. Run `cs a` again
5. Now you can switch between accounts with `cs s`
6. **Important**: After each switch, restart Claude Code to use the new authentication

> **What gets switched:** Only your authentication credentials change. Your themes, settings, preferences, and chat history remain exactly the same.

## Requirements

- Bash 4.4+
- `jq` (JSON processor)

### Installing Dependencies

**macOS:**

```bash
brew install jq
```

**Ubuntu/Debian:**

```bash
sudo apt install jq
```

## How It Works

The switcher stores account authentication data separately:

- **macOS**: Credentials in Keychain, OAuth info in `~/.claude-account-switch/`
- **Linux/WSL**: Both credentials and OAuth info in `~/.claude-account-switch/` with restricted permissions

When switching accounts, it:

1. Backs up the current account's authentication data
2. Restores the target account's authentication data
3. Updates Claude Code's authentication files

## Troubleshooting

### If a switch fails

- Check that you have accounts added: `cs l`
- Verify Claude Code is closed before switching
- Try switching back to your original account

### If you can't add an account

- Make sure you're logged into Claude Code first
- Check that you have `jq` installed
- Verify you have write permissions to your home directory

### If Claude Code doesn't recognize the new account

- Make sure you restarted Claude Code after switching
- Check the current account: `cs l` (look for `(active)` prefix)

## Cleanup/Uninstall

To stop using this tool and remove all data:

1. Note your current active account: `cs l`
2. Remove the data directory: `rm -rf ~/.claude-account-switch`

Your current Claude Code login will remain active.

## Security Notes

- Credentials stored in macOS Keychain or files with 600 permissions
- Authentication files are stored with restricted permissions (600)
- The tool requires Claude Code to be closed during account switches

## License

MIT License - see LICENSE file for details
