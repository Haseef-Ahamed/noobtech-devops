#!/bin/bash
# lib/logger.sh — Centralized logging
# KEY LESSON: Use if/then not && so false conditions don't exit under set -e

LOG_DIR="${NOOBTECH_ROOT:-$(dirname "$(dirname "${BASH_SOURCE[0]}")")}/logs"
LOG_OPERATIONS="$LOG_DIR/operations.log"
LOG_DEPLOYMENTS="$LOG_DIR/deployments.log"
LOG_BACKUPS="$LOG_DIR/backups.log"
LOG_CONFIG="$LOG_DIR/config_changes.log"
LOG_SECURITY="$LOG_DIR/security_events.log"
LOG_INCIDENTS="$LOG_DIR/incidents.log"
LOG_ERRORS="$LOG_DIR/errors.log"

if [ -t 1 ]; then
    C_RED=$(tput setaf 1);    C_GREEN=$(tput setaf 2)
    C_YELLOW=$(tput setaf 3); C_BLUE=$(tput setaf 4)
    C_CYAN=$(tput setaf 6);   C_BOLD=$(tput bold); C_RESET=$(tput sgr0)
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
    C_CYAN=""; C_BOLD=""; C_RESET=""
fi

_log() {
    local level="$1" module="$2" message="$3" logfile="$4"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[$ts] [$level] [$module] $message"
    echo "$line" >> "$logfile"   2>/dev/null || true
    echo "$line" >> "$LOG_OPERATIONS" 2>/dev/null || true
}

log_info()     { _log "INFO"     "$1" "$2" "${3:-$LOG_OPERATIONS}"; echo "${C_BLUE}[INFO]${C_RESET}  ${C_BOLD}[$1]${C_RESET} $2"; }
log_success()  { _log "SUCCESS"  "$1" "$2" "${3:-$LOG_OPERATIONS}"; echo "${C_GREEN}[OK]${C_RESET}    ${C_BOLD}[$1]${C_RESET} $2"; }
log_warning()  { _log "WARNING"  "$1" "$2" "${3:-$LOG_INCIDENTS}";  echo "${C_YELLOW}[WARN]${C_RESET}  ${C_BOLD}[$1]${C_RESET} $2" >&2; }
log_error()    { _log "ERROR"    "$1" "$2" "$LOG_ERRORS";           echo "${C_RED}[ERROR]${C_RESET} ${C_BOLD}[$1]${C_RESET} $2" >&2; }
log_critical() { _log "CRITICAL" "$1" "$2" "$LOG_INCIDENTS"; _log "CRITICAL" "$1" "$2" "$LOG_ERRORS"; echo "${C_RED}${C_BOLD}[CRIT]${C_RESET} ${C_BOLD}[$1]${C_RESET} ${C_RED}$2${C_RESET}" >&2; }

log_debug() {
    if [ "${NOOBTECH_VERBOSE:-false}" = "true" ]; then
        _log "DEBUG" "$1" "$2" "$LOG_OPERATIONS"
        echo "${C_CYAN}[DEBUG]${C_RESET} ${C_BOLD}[$1]${C_RESET} $2"
    fi
}

log_section() {
    local title="$1"
    echo ""; echo "${C_BOLD}${C_BLUE}  ════════════════════════════════════════${C_RESET}"
    echo "${C_BOLD}${C_BLUE}    $title${C_RESET}"
    echo "${C_BOLD}${C_BLUE}  ════════════════════════════════════════${C_RESET}"; echo ""
    _log "INFO" "SYSTEM" "=== $title ===" "$LOG_OPERATIONS"
}

rotate_logs() { find "$LOG_DIR" -name "*.log" -mtime +30 -delete 2>/dev/null || true; }
