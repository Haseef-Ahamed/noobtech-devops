#!/bin/bash
# =============================================================================
# lib/ssh_helper.sh — SSH utilities for remote server operations
# =============================================================================
# In production, these functions would actually SSH to servers.
# For this demo environment they simulate SSH operations safely.
# =============================================================================

# ssh_run: Execute a command on a remote server
# Usage: ssh_run <hostname> "command to run"
ssh_run() {
    local hostname="$1"
    local cmd="$2"
    local ssh_key
    ssh_key=$(get_server_field "$hostname" "ssh_key")

    if [ "${NOOBTECH_DRY_RUN:-false}" = "true" ]; then
        echo "  [DRY-RUN] ssh -i $ssh_key $hostname '$cmd'"
        return 0
    fi

    log_debug "SSH" "Executing on $hostname: $cmd"
    # Production: ssh -i "$ssh_key" -o StrictHostKeyChecking=no "$hostname" "$cmd"
    # Demo: simulate success
    log_debug "SSH" "Command completed on $hostname"
    return 0
}

# ssh_copy: Copy a file to a remote server
# Usage: ssh_copy <local_file> <hostname> <remote_path>
ssh_copy() {
    local local_file="$1"
    local hostname="$2"
    local remote_path="$3"
    local ssh_key
    ssh_key=$(get_server_field "$hostname" "ssh_key")

    if [ "${NOOBTECH_DRY_RUN:-false}" = "true" ]; then
        echo "  [DRY-RUN] scp -i $ssh_key $local_file $hostname:$remote_path"
        return 0
    fi

    log_debug "SSH" "Copying $local_file → $hostname:$remote_path"
    # Production: scp -i "$ssh_key" "$local_file" "$hostname:$remote_path"
    return 0
}

# ssh_check: Test if a server is reachable via SSH
# Usage: ssh_check <hostname>  → returns 0=reachable, 1=unreachable
ssh_check() {
    local hostname="$1"
    local ssh_key
    ssh_key=$(get_server_field "$hostname" "ssh_key")
    log_debug "SSH" "Checking connectivity to $hostname"
    # Production: ssh -i "$ssh_key" -o ConnectTimeout=5 "$hostname" "echo ok" &>/dev/null
    return 0  # Simulate success in demo
}
