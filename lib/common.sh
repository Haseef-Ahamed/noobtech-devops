#!/bin/bash
# lib/common.sh — Shared utilities

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/logger.sh"

export NOOBTECH_ROOT="${NOOBTECH_ROOT:-$(dirname "$SCRIPT_DIR")}"
export NOOBTECH_ENV="${NOOBTECH_ENV:-dev}"
export NOOBTECH_DRY_RUN="${NOOBTECH_DRY_RUN:-false}"
export NOOBTECH_VERBOSE="${NOOBTECH_VERBOSE:-false}"

SERVERS_FILE="${NOOBTECH_ROOT}/servers.yaml"

confirm() {
    echo ""; echo "${C_YELLOW}${C_BOLD}  ? $1${C_RESET}"
    echo -n "    Type 'yes' to continue: "; read -r answer
    if [ "$answer" = "yes" ]; then return 0; fi
    return 1
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "SYSTEM" "Required command not found: $cmd"; return 1
    fi
}

check_disk_space() {
    local path="${1:-/}" min_pct="${2:-20}"
    local used; used=$(df "$path" 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}')
    local free=$((100 - used))
    if [ "$free" -lt "$min_pct" ]; then
        log_warning "SYSTEM" "Low disk at $path: ${free}% free"; return 1
    fi
}

dry_run() {
    if [ "${NOOBTECH_DRY_RUN:-false}" = "true" ]; then
        echo "${C_CYAN}  [DRY-RUN]${C_RESET} Would run: $*"; return 0
    fi
    "$@"
}

timestamp()       { date '+%Y-%m-%d %H:%M:%S'; }
timestamp_short() { date '+%Y%m%d_%H%M%S'; }

get_servers_by_env() {
    local env="$1"
    awk -v e="$env" '
        /- hostname:/  { h=$NF }
        /environment:/ { if ($NF == e && h != "") { print h; h="" } }
    ' "$SERVERS_FILE" 2>/dev/null || true
}

get_server_field() {
    local hostname="$1" field="$2"
    awk -v h="$hostname" -v f="$field" '
        /- hostname:/ { found=($NF == h) }
        found && $1 == f":" { print $NF; exit }
    ' "$SERVERS_FILE" 2>/dev/null || true
}

print_summary() {
    local op="$1" passed="$2" failed="$3"
    echo ""; echo "${C_BOLD}  Summary: $op${C_RESET}"
    echo "  ──────────────────────────"
    echo "  Total:  $((passed + failed))"
    echo "  ${C_GREEN}Passed: $passed${C_RESET}"
    if [ "$failed" -gt 0 ]; then echo "  ${C_RED}Failed: $failed${C_RESET}"
    else echo "  Failed: 0"; fi; echo ""
}
