#!/usr/bin/env bash

# Multi-Account Switcher for Claude Code
# Simple tool to manage and switch between multiple Claude Code accounts

set -euo pipefail

# Configuration
readonly BACKUP_DIR="$HOME/.claude-account-switch"
readonly SEQUENCE_FILE="$BACKUP_DIR/sequence.json"

# Container detection
is_running_in_container() {
    # Check for Docker environment file
    if [[ -f /.dockerenv ]]; then
        return 0
    fi
    
    # Check cgroup for container indicators
    if [[ -f /proc/1/cgroup ]] && grep -q 'docker\|lxc\|containerd\|kubepods' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    
    # Check mount info for container filesystems
    if [[ -f /proc/self/mountinfo ]] && grep -q 'docker\|overlay' /proc/self/mountinfo 2>/dev/null; then
        return 0
    fi
    
    # Check for common container environment variables
    if [[ -n "${CONTAINER:-}" ]] || [[ -n "${container:-}" ]]; then
        return 0
    fi
    
    return 1
}

# Platform detection
detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) 
            if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        *) echo "unknown" ;;
    esac
}

# Get Claude configuration file path with fallback
get_claude_config_path() {
    local primary_config="$HOME/.claude/.claude.json"
    local fallback_config="$HOME/.claude.json"
    
    # Check primary location first
    if [[ -f "$primary_config" ]]; then
        # Verify it has valid oauthAccount structure
        if jq -e '.oauthAccount' "$primary_config" >/dev/null 2>&1; then
            echo "$primary_config"
            return
        fi
    fi
    
    # Fallback to standard location
    echo "$fallback_config"
}

# Basic validation that JSON is valid
validate_json() {
    local file="$1"
    if ! jq . "$file" >/dev/null 2>&1; then
        echo "Error: Invalid JSON in $file"
        return 1
    fi
}

# Email validation function
validate_email() {
    local email="$1"
    # Use robust regex for email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Account identifier resolution function
resolve_account_identifier() {
    local identifier="$1"
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        echo "$identifier"  # It's a number
    else
        # Look up account number by email
        local account_num
        account_num=$(jq -r --arg email "$identifier" '.accounts | to_entries[] | select(.value.email == $email) | .key' "$SEQUENCE_FILE" 2>/dev/null)
        if [[ -n "$account_num" && "$account_num" != "null" ]]; then
            echo "$account_num"
        else
            echo ""
        fi
    fi
}

# Safe JSON write with validation
write_json() {
    local file="$1"
    local content="$2"
    local temp_file
    temp_file=$(mktemp "${file}.XXXXXX")
    
    echo "$content" > "$temp_file"
    if ! jq . "$temp_file" >/dev/null 2>&1; then
        rm -f "$temp_file"
        echo "Error: Generated invalid JSON"
        return 1
    fi
    
    mv "$temp_file" "$file"
    chmod 600 "$file"
}

# Check Bash version (4.4+ required)
check_bash_version() {
    local version
    version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    if ! awk -v ver="$version" 'BEGIN { exit (ver >= 4.4 ? 0 : 1) }'; then
        echo "Error: Bash 4.4+ required (found $version)"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    for cmd in jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: Required command '$cmd' not found"
            echo "Install with: apt install $cmd (Linux) or brew install $cmd (macOS)"
            exit 1
        fi
    done
}

# Setup backup directories
setup_directories() {
    mkdir -p "$BACKUP_DIR"/{configs,credentials}
    chmod 700 "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"/{configs,credentials}
}

# Claude Code process detection (Node.js app)
is_claude_running() {
    ps -eo pid,comm,args | awk '$2 == "claude" || $3 == "claude" {exit 0} END {exit 1}'
}

# Wait for Claude Code to close (no timeout - user controlled)
wait_for_claude_close() {
    if ! is_claude_running; then
        return 0
    fi
    
    echo "Claude Code is running. Please close it first."
    echo "Waiting for Claude Code to close..."
    
    while is_claude_running; do
        sleep 1
    done
    
    echo "Claude Code closed. Continuing..."
}

# Get current account info from .claude.json
get_current_account() {
    if [[ ! -f "$(get_claude_config_path)" ]]; then
        echo "none"
        return
    fi
    
    if ! validate_json "$(get_claude_config_path)"; then
        echo "none"
        return
    fi
    
    local email
    email=$(jq -r '.oauthAccount.emailAddress // empty' "$(get_claude_config_path)" 2>/dev/null)
    echo "${email:-none}"
}

# Read credentials based on platform
read_credentials() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || echo ""
            ;;
        linux|wsl)
            if [[ -f "$HOME/.claude/.credentials.json" ]]; then
                cat "$HOME/.claude/.credentials.json"
            else
                echo ""
            fi
            ;;
    esac
}

# Write credentials based on platform
write_credentials() {
    local credentials="$1"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security add-generic-password -U -s "Claude Code-credentials" -a "$USER" -w "$credentials" 2>/dev/null
            ;;
        linux|wsl)
            mkdir -p "$HOME/.claude"
            printf '%s' "$credentials" > "$HOME/.claude/.credentials.json"
            chmod 600 "$HOME/.claude/.credentials.json"
            ;;
    esac
}

# Read account credentials from backup
read_account_credentials() {
    local account_num="$1"
    local email="$2"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security find-generic-password -s "Claude Code-Account-${account_num}-${email}" -w 2>/dev/null || echo ""
            ;;
        linux|wsl)
            local cred_file="$BACKUP_DIR/credentials/.claude-credentials-${account_num}-${email}.json"
            if [[ -f "$cred_file" ]]; then
                cat "$cred_file"
            else
                echo ""
            fi
            ;;
    esac
}

# Write account credentials to backup
write_account_credentials() {
    local account_num="$1"
    local email="$2"
    local credentials="$3"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security add-generic-password -U -s "Claude Code-Account-${account_num}-${email}" -a "$USER" -w "$credentials" 2>/dev/null
            ;;
        linux|wsl)
            local cred_file="$BACKUP_DIR/credentials/.claude-credentials-${account_num}-${email}.json"
            printf '%s' "$credentials" > "$cred_file"
            chmod 600 "$cred_file"
            ;;
    esac
}

# Read account config from backup
read_account_config() {
    local account_num="$1"
    local email="$2"
    local config_file="$BACKUP_DIR/configs/.claude-config-${account_num}-${email}.json"
    
    if [[ -f "$config_file" ]]; then
        cat "$config_file"
    else
        echo ""
    fi
}

# Write account config to backup
write_account_config() {
    local account_num="$1"
    local email="$2"
    local config="$3"
    local config_file="$BACKUP_DIR/configs/.claude-config-${account_num}-${email}.json"

    echo "$config" > "$config_file"
    chmod 600 "$config_file"
}

# Delete an account's credential and config backups (platform-aware)
delete_account_backups() {
    local account_num="$1"
    local email="$2"
    local platform
    platform=$(detect_platform)

    case "$platform" in
        macos)
            security delete-generic-password -s "Claude Code-Account-${account_num}-${email}" 2>/dev/null || true
            ;;
        linux|wsl)
            rm -f "$BACKUP_DIR/credentials/.claude-credentials-${account_num}-${email}.json"
            ;;
    esac
    rm -f "$BACKUP_DIR/configs/.claude-config-${account_num}-${email}.json"
}

# Initialize sequence.json if it doesn't exist
init_sequence_file() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        local init_content='{
  "activeAccountNumber": null,
  "lastUpdated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "sequence": [],
  "accounts": {}
}'
        write_json "$SEQUENCE_FILE" "$init_content"
    fi
}

# Get next account number.
# cmd_remove_account compact-renumbers accounts to 1..N, so keys are always
# contiguous and max+1 is exactly the next free slot.
get_next_account_number() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "1"
        return
    fi

    local max_num
    max_num=$(jq -r '.accounts | keys | map(tonumber) | max // 0' "$SEQUENCE_FILE")
    echo $((max_num + 1))
}

# Check if account exists by email
account_exists() {
    local email="$1"
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        return 1
    fi
    
    jq -e --arg email "$email" '.accounts[] | select(.email == $email)' "$SEQUENCE_FILE" >/dev/null 2>&1
}

# Add account
cmd_add_account() {
    setup_directories
    init_sequence_file
    
    local current_email
    current_email=$(get_current_account)
    
    if [[ "$current_email" == "none" ]]; then
        echo "Error: No active Claude account found. Please log in first."
        exit 1
    fi
    
    if account_exists "$current_email"; then
        echo "Account $current_email is already managed."
        exit 0
    fi
    
    local account_num
    account_num=$(get_next_account_number)
    
    # Backup current credentials and config
    local current_creds current_config
    current_creds=$(read_credentials)
    current_config=$(cat "$(get_claude_config_path)")
    
    if [[ -z "$current_creds" ]]; then
        echo "Error: No credentials found for current account"
        exit 1
    fi
    
    # Get account UUID
    local account_uuid
    account_uuid=$(jq -r '.oauthAccount.accountUuid' "$(get_claude_config_path)")
    
    # Store backups
    write_account_credentials "$account_num" "$current_email" "$current_creds"
    write_account_config "$account_num" "$current_email" "$current_config"
    
    # Update sequence.json
    local updated_sequence
    updated_sequence=$(jq --arg num "$account_num" --arg email "$current_email" --arg uuid "$account_uuid" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .accounts[$num] = {
            email: $email,
            uuid: $uuid,
            added: $now
        } |
        .sequence += [$num | tonumber] |
        .activeAccountNumber = ($num | tonumber) |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo "Added Account $account_num: $current_email"
}

# Remove account
cmd_remove_account() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: cs r <account_number|email>"
        exit 1
    fi
    
    local identifier="$1"
    local account_num
    
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "Error: No accounts are managed yet"
        exit 1
    fi
    
    # Handle email vs numeric identifier
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        account_num="$identifier"
    else
        # Validate email format
        if ! validate_email "$identifier"; then
            echo "Error: Invalid email format: $identifier"
            exit 1
        fi
        
        # Resolve email to account number
        account_num=$(resolve_account_identifier "$identifier")
        if [[ -z "$account_num" ]]; then
            echo "Error: No account found with email: $identifier"
            exit 1
        fi
    fi
    
    local account_info
    account_info=$(jq -r --arg num "$account_num" '.accounts[$num] // empty' "$SEQUENCE_FILE")
    
    if [[ -z "$account_info" ]]; then
        echo "Error: Account-$account_num does not exist"
        exit 1
    fi
    
    local email
    email=$(echo "$account_info" | jq -r '.email')
    
    local active_account
    active_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    
    if [[ "$active_account" == "$account_num" ]]; then
        echo "Warning: Account-$account_num ($email) is currently active"
    fi
    
    echo -n "Are you sure you want to permanently remove Account-$account_num ($email)? [y/N] "
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Remove the target account's backups
    delete_account_backups "$account_num" "$email"

    # Compact-renumber the surviving accounts so numbers stay contiguous 1..N.
    # Account numbers are baked into backup storage (filenames / keychain service
    # names), so relocating a number means moving its backing data too.

    # Survivor old numbers in their current sequence (rotation) order.
    local old_order_json
    old_order_json=$(jq -c --arg num "$account_num" \
        '[ .sequence[] | select(. != ($num | tonumber)) ]' "$SEQUENCE_FILE")

    # Assign new numbers by sequence position (i-th survivor -> i), collecting
    # only the accounts whose number actually changes.
    local -a survivors
    mapfile -t survivors < <(printf '%s' "$old_order_json" | jq -r '.[]')

    local -a moves_old moves_new moves_email
    local new=0 old em
    for old in "${survivors[@]}"; do
        new=$((new + 1))
        if [[ "$old" != "$new" ]]; then
            em=$(jq -r --arg n "$old" '.accounts[$n].email' "$SEQUENCE_FILE")
            moves_old+=("$old")
            moves_new+=("$new")
            moves_email+=("$em")
        fi
    done

    # New numbers are always <= old numbers (we only ever shift down). Executing
    # the moves in ascending old-number order guarantees a destination slot is
    # already vacated before we write to it, so no live backup is overwritten.
    # sequence order is not necessarily ascending, so sort the move list here;
    # the new-number assignment above is unaffected (it used sequence order).
    local -a move_order
    mapfile -t move_order < <(
        local i
        for i in "${!moves_old[@]}"; do
            printf '%s\t%s\n' "${moves_old[$i]}" "$i"
        done | sort -n | cut -f2
    )

    local idx creds config
    for idx in "${move_order[@]}"; do
        old="${moves_old[$idx]}"
        new="${moves_new[$idx]}"
        em="${moves_email[$idx]}"

        # read -> write(new) -> delete(old): a crash mid-move leaves both copies
        # (recoverable) rather than a gap.
        creds=$(read_account_credentials "$old" "$em")
        config=$(read_account_config "$old" "$em")
        if [[ -z "$creds" || -z "$config" ]]; then
            echo "Error: Missing backup data for Account-$old; aborting renumber"
            exit 1
        fi
        write_account_credentials "$new" "$em" "$creds"
        write_account_config "$new" "$em" "$config"
        delete_account_backups "$old" "$em"
    done

    # Rewrite sequence.json metadata in a single pass: remap .accounts keys,
    # .sequence values, and .activeAccountNumber to the new numbering. A removed
    # or now-nonexistent active account collapses to null.
    local updated_sequence
    updated_sequence=$(jq \
        --argjson oldOrder "$old_order_json" \
        --arg active "$active_account" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .accounts as $accountsIn
        | ($oldOrder | to_entries | map({key: (.value | tostring), value: (.key + 1)}) | from_entries) as $remap
        | .accounts = (reduce ($remap | to_entries[]) as $e ({}; .[($e.value | tostring)] = $accountsIn[$e.key]))
        | .sequence = ($oldOrder | map($remap[(. | tostring)]))
        | .activeAccountNumber = (if $active == "null" or ($active | length) == 0 then null else ($remap[$active] // null) end)
        | .lastUpdated = $now
    ' "$SEQUENCE_FILE")

    write_json "$SEQUENCE_FILE" "$updated_sequence"

    echo "Account-$account_num ($email) has been removed"
    if [[ ${#moves_old[@]} -gt 0 ]]; then
        echo "Renumbered remaining accounts to 1..${#survivors[@]}"
    fi
}

# First-run setup workflow
first_run_setup() {
    local current_email
    current_email=$(get_current_account)
    
    if [[ "$current_email" == "none" ]]; then
        echo "No active Claude account found. Please log in first."
        return 1
    fi
    
    echo -n "No managed accounts found. Add current account ($current_email) to managed list? [Y/n] "
    read -r response
    
    if [[ "$response" == "n" || "$response" == "N" ]]; then
        echo "Setup cancelled. You can run 'cs a' later."
        return 1
    fi
    
    cmd_add_account
    return 0
}

# List accounts with live usage data (parallel fetch per account)
cmd_list() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "No accounts are managed yet."
        first_run_setup
        exit 0
    fi

    # Get current active account from .claude.json
    local current_email
    current_email=$(get_current_account)

    # Find which account number corresponds to the current email
    local active_account_num=""
    if [[ "$current_email" != "none" ]]; then
        active_account_num=$(jq -r --arg email "$current_email" \
            '.accounts | to_entries[] | select(.value.email == $email) | .key' \
            "$SEQUENCE_FILE" 2>/dev/null)
    fi

    # Read sequence and emails into arrays
    local -a seq_nums seq_emails
    while IFS= read -r n; do seq_nums+=("$n"); done < <(jq -r '.sequence[]' "$SEQUENCE_FILE")
    for n in "${seq_nums[@]}"; do
        seq_emails+=("$(jq -r --arg n "$n" '.accounts[$n].email' "$SEQUENCE_FILE")")
    done

    # Calculate max email length for usage column alignment
    local maxlen=0
    for email in "${seq_emails[@]}"; do
        if (( ${#email} > maxlen )); then maxlen=${#email}; fi
    done

    # Fetch usage for all accounts in parallel
    local tmpdir
    tmpdir=$(mktemp -d)
    for i in "${!seq_nums[@]}"; do
        local num="${seq_nums[$i]}" email="${seq_emails[$i]}"
        fetch_account_usage_str "$num" "$email" "$active_account_num" > "$tmpdir/$i" &
    done
    wait

    # Print results in sequence order
    echo "Accounts:"
    for i in "${!seq_nums[@]}"; do
        local num="${seq_nums[$i]}" email="${seq_emails[$i]}"
        local usage_str prefix
        usage_str=$(cat "$tmpdir/$i")
        if [[ "$num" == "$active_account_num" ]]; then
            prefix="(active) "
        else
            prefix="         "
        fi
        printf '%s%s: %-*s  %s\n' "$prefix" "$num" "$maxlen" "$email" "$usage_str"
    done

    rm -rf "$tmpdir"
}

# Switch to next account
cmd_switch() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "Error: No accounts are managed yet"
        exit 1
    fi
    
    local current_email
    current_email=$(get_current_account)
    
    if [[ "$current_email" == "none" ]]; then
        echo "Error: No active Claude account found"
        exit 1
    fi
    
    # Check if current account is managed
    if ! account_exists "$current_email"; then
        echo "Notice: Active account '$current_email' was not managed."
        cmd_add_account
        local account_num
        account_num=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
        echo "It has been automatically added as Account-$account_num."
        echo "Please run 'cs s' again to switch to the next account."
        exit 0
    fi
    
    # wait_for_claude_close
    
    local active_account sequence
    active_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    sequence=($(jq -r '.sequence[]' "$SEQUENCE_FILE"))
    
    # Find next account in sequence
    local next_account current_index=0
    for i in "${!sequence[@]}"; do
        if [[ "${sequence[i]}" == "$active_account" ]]; then
            current_index=$i
            break
        fi
    done
    
    next_account="${sequence[$(((current_index + 1) % ${#sequence[@]}))]}"
    
    perform_switch "$next_account"
}

# Switch to specific account
cmd_switch_to() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: cs st <account_number|email>"
        exit 1
    fi
    
    local identifier="$1"
    local target_account
    
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "Error: No accounts are managed yet"
        exit 1
    fi
    
    # Handle email vs numeric identifier
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        target_account="$identifier"
    else
        # Validate email format
        if ! validate_email "$identifier"; then
            echo "Error: Invalid email format: $identifier"
            exit 1
        fi
        
        # Resolve email to account number
        target_account=$(resolve_account_identifier "$identifier")
        if [[ -z "$target_account" ]]; then
            echo "Error: No account found with email: $identifier"
            exit 1
        fi
    fi
    
    local account_info
    account_info=$(jq -r --arg num "$target_account" '.accounts[$num] // empty' "$SEQUENCE_FILE")
    
    if [[ -z "$account_info" ]]; then
        echo "Error: Account-$target_account does not exist"
        exit 1
    fi
    
    # wait_for_claude_close
    perform_switch "$target_account"
}

# Perform the actual account switch
perform_switch() {
    local target_account="$1"
    
    # Get current and target account info
    local current_account target_email current_email
    current_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    target_email=$(jq -r --arg num "$target_account" '.accounts[$num].email' "$SEQUENCE_FILE")
    current_email=$(get_current_account)
    
    # Step 1: Backup current account
    local current_creds current_config
    current_creds=$(read_credentials)
    current_config=$(cat "$(get_claude_config_path)")
    
    write_account_credentials "$current_account" "$current_email" "$current_creds"
    write_account_config "$current_account" "$current_email" "$current_config"
    
    # Step 2: Retrieve target account
    local target_creds target_config
    target_creds=$(read_account_credentials "$target_account" "$target_email")
    target_config=$(read_account_config "$target_account" "$target_email")
    
    if [[ -z "$target_creds" || -z "$target_config" ]]; then
        echo "Error: Missing backup data for Account-$target_account"
        exit 1
    fi
    
    # Step 3: Activate target account
    write_credentials "$target_creds"
    
    # Extract oauthAccount from backup and validate
    local oauth_section
    oauth_section=$(echo "$target_config" | jq '.oauthAccount' 2>/dev/null)
    if [[ -z "$oauth_section" || "$oauth_section" == "null" ]]; then
        echo "Error: Invalid oauthAccount in backup"
        exit 1
    fi
    
    # Merge with current config and validate
    local merged_config
    merged_config=$(jq --argjson oauth "$oauth_section" '.oauthAccount = $oauth' "$(get_claude_config_path)" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to merge config"
        exit 1
    fi
    
    # Use existing safe write_json function
    write_json "$(get_claude_config_path)" "$merged_config"
    
    # Step 4: Update state
    local updated_sequence
    updated_sequence=$(jq --arg num "$target_account" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .activeAccountNumber = ($num | tonumber) |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo "Switched to Account-$target_account ($target_email)"
    # Display updated account list
    cmd_list
    
}

# Convert ISO8601 date to epoch seconds (handles fractional seconds and timezone)
iso_to_epoch() {
    local iso_date="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        date -j -f "%Y-%m-%dT%H:%M:%S" "${iso_date%%.*}" "+%s" 2>/dev/null || echo "0"
    else
        date -d "$iso_date" "+%s" 2>/dev/null || echo "0"
    fi
}

# Fetch raw usage JSON for a given access token
fetch_usage_api() {
    local token="$1"
    curl -s --max-time 8 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "User-Agent: claude-code/2.0.32" 2>/dev/null || true
}

# Build usage display string for one account; always exits 0 (falls back to "?" on any error)
fetch_account_usage_str() {
    local num="$1"
    local email="$2"
    local active_num="$3"
    local fallback="(?, ?), (?, ?), (? / ?)"

    # Read credentials via platform abstraction
    local creds
    if [[ "$num" == "$active_num" ]]; then
        creds=$(read_credentials)
    else
        creds=$(read_account_credentials "$num" "$email")
    fi

    local token
    token=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    if [[ -z "$token" ]]; then echo "$fallback"; return 0; fi

    local resp
    resp=$(fetch_usage_api "$token")
    if [[ -z "$resp" ]]; then echo "$fallback"; return 0; fi

    # Validate response has expected fields
    local s_pct
    s_pct=$(echo "$resp" | jq -r '.five_hour.utilization // empty' 2>/dev/null)
    if [[ -z "$s_pct" ]]; then echo "$fallback"; return 0; fi

    # Extract and round percentages
    local w_pct s_reset w_reset used_c limit_c
    s_pct=$(echo "$resp"  | jq -r '(.five_hour.utilization // 0) | round' 2>/dev/null)
    w_pct=$(echo "$resp"  | jq -r '(.seven_day.utilization  // 0) | round' 2>/dev/null)
    s_reset=$(echo "$resp" | jq -r '.five_hour.resets_at // ""' 2>/dev/null)
    w_reset=$(echo "$resp" | jq -r '.seven_day.resets_at  // ""' 2>/dev/null)
    # extra_usage: null fields become 0 via // 0; API returns cents as float, floor to int
    used_c=$(echo  "$resp" | jq -r '(.extra_usage.used_credits  // 0) | floor' 2>/dev/null)
    limit_c=$(echo "$resp" | jq -r '(.extra_usage.monthly_limit // 0) | floor' 2>/dev/null)

    # Calculate remaining seconds for session and weekly resets
    local now ssec wsec
    now=$(date +%s)
    ssec=$(( $(iso_to_epoch "$s_reset") - now ))
    wsec=$(( $(iso_to_epoch "$w_reset") - now ))
    if (( ssec < 0 )); then ssec=0; fi
    if (( wsec < 0 )); then wsec=0; fi

    printf '(%d%%, %d%%), (%dh %dm, %dd %dh %dm), (%d.%02d$ / %d.%02d$)' \
        "$s_pct" "$w_pct" \
        $(( ssec/3600 )) $(( (ssec%3600)/60 )) \
        $(( wsec/86400 )) $(( (wsec%86400)/3600 )) $(( (wsec%3600)/60 )) \
        $(( used_c/100 )) $(( used_c%100 )) \
        $(( limit_c/100 )) $(( limit_c%100 ))
}

# Show usage
show_usage() {
    echo "Multi-Account Switcher for Claude Code"
    echo "Usage: cs [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  a               Add current account to managed accounts"
    echo "  r <num|email>   Remove account by number or email"
    echo "  l               List all managed accounts"
    echo "  s               Rotate to next account in sequence"
    echo "  st <num|email>  Switch to specific account number or email"
    echo "  h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  cs a"
    echo "  cs l"
    echo "  cs s"
    echo "  cs st 2"
    echo "  cs st user@example.com"
    echo "  cs r user@example.com"
}

# Main script logic
main() {
    # Basic checks - allow root execution in containers
    if [[ $EUID -eq 0 ]] && ! is_running_in_container; then
        echo "Error: Do not run this script as root (unless running in a container)"
        exit 1
    fi
    
    check_bash_version
    check_dependencies
    
    case "${1:-}" in
        a)
            cmd_add_account
            ;;
        r)
            shift
            cmd_remove_account "$@"
            ;;
        l)
            cmd_list
            ;;
        s)
            cmd_switch
            ;;
        st)
            shift
            cmd_switch_to "$@"
            ;;
        h)
            show_usage
            ;;
        "")
            show_usage
            ;;
        *)
            echo "Error: Unknown command '$1'"
            show_usage
            exit 1
            ;;
    esac
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi