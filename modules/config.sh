#!/bin/bash
# modules/config.sh — Configuration Management
set -euo pipefail   # FIX 1: Added — required by assignment in first 5 lines

source "$NOOBTECH_ROOT/lib/logger.sh"
source "$NOOBTECH_ROOT/lib/common.sh"

CONFIGS_DIR="$NOOBTECH_ROOT/configs"

# ─────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────
cmd_config() {
    local action="${1:-}"; [ $# -gt 0 ] && shift
    case "$action" in
        apply)      config_apply "$@" ;;
        check)      config_check "$@" ;;
        remediate)  config_remediate "$@" ;;
        --help|-h)  echo "Usage: config apply|check|remediate <server>" ;;
        # FIX 2: More informative unknown-action error message
        *) log_error "CONFIG" "Unknown action: '$action'. Use --help for usage."; return 1 ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# config apply <profile> <server>
# ─────────────────────────────────────────────────────────────
config_apply() {
    # FIX 3: Use if/then instead of || && to avoid operator-precedence bug
    local profile="${1:-}" server="${2:-}"
    if [ -z "$profile" ] || [ -z "$server" ]; then
        log_error "CONFIG" "Usage: config apply <profile> <server>"
        return 1
    fi

    # Optional: skip production confirmation in remediate loops
    # Caller sets NOOBTECH_SKIP_PROD_CONFIRM=1 to bypass
    local skip_prod_confirm="${NOOBTECH_SKIP_PROD_CONFIRM:-0}"

    local cfg="$CONFIGS_DIR/${profile}.conf"
    [ ! -f "$cfg" ] && { log_error "CONFIG" "Profile not found: $profile"; return 1; }

    log_section "Applying Config: $profile → $server"
    log_info "CONFIG" "Starting config apply — profile=$profile server=$server"  # FIX 7a: log apply start

    # FIX 4: mkdir -p for config_backups before using it
    local bak_dir="$NOOBTECH_ROOT/data/config_backups"
    mkdir -p "$bak_dir"
    local bak="$bak_dir/${server}_${profile}_$(timestamp_short).bak"
    log_info "CONFIG" "Backing up to: $bak"
    dry_run cp "$cfg" "$bak"

    echo ""; echo "${C_BOLD}  Settings to apply:${C_RESET}"
    grep -v "^#" "$cfg" | grep -v "^$" | head -12 | sed 's/^/  /'

    # FIX 5: Use [[ == glob ]] instead of echo|grep for prod detection
    if [[ "$server" == prod-* ]] && [ "$skip_prod_confirm" != "1" ]; then
        log_warning "CONFIG" "PRODUCTION server: $server"
        confirm "Apply '$profile' to production '$server'?" || { log_info "CONFIG" "Cancelled"; return 0; }
    fi

    local applied="$NOOBTECH_ROOT/data/applied_configs"
    mkdir -p "$applied"
    dry_run cp "$cfg" "$applied/${server}_${profile}.conf"

    echo ""; echo "  ${C_BOLD}Applied on $server:${C_RESET}"
    case "$profile" in
        web_server)     echo "  ${C_GREEN}✓${C_RESET} nginx worker_processes=auto | server_tokens=off" ;;
        database)       echo "  ${C_GREEN}✓${C_RESET} mysql max_connections=150 | bind=127.0.0.1" ;;
        cache)          echo "  ${C_GREEN}✓${C_RESET} redis maxmemory=512mb | protected_mode=yes" ;;
        firewall_rules) echo "  ${C_GREEN}✓${C_RESET} ufw default deny | allow 22,80,443" ;;
        users)          echo "  ${C_GREEN}✓${C_RESET} deploy/monitor/backup users | root login disabled" ;;
        # FIX: Catch-all so unknown profiles still show output
        *)              echo "  ${C_GREEN}✓${C_RESET} Profile '$profile' applied ($(grep -c "^[^#]" "$cfg") settings)" ;;
    esac
    echo ""

    log_success "CONFIG" "Applied '$profile' to '$server'"
    echo "[$(timestamp)] [APPLY] profile=$profile server=$server" >> "$LOG_CONFIG"  # FIX 7b: consistent log format
}

# ─────────────────────────────────────────────────────────────
# config check <server>
# ─────────────────────────────────────────────────────────────
config_check() {
    local server="${1:-}"
    if [ -z "$server" ]; then
        log_error "CONFIG" "Usage: config check <server>"
        return 1
    fi

    log_section "Config Drift Check: $server"
    log_info "CONFIG" "Starting drift check — server=$server"  # FIX 7c: log check start

    local role; role=$(get_server_field "$server" "role")
    [ -z "$role" ] && { log_error "CONFIG" "Server not found: $server"; return 1; }

    local profiles=()
    case "$role" in
        web)      profiles=("web_server" "firewall_rules" "users") ;;
        database) profiles=("database"   "firewall_rules" "users") ;;
        cache)    profiles=("cache"      "firewall_rules" "users") ;;
        *)        profiles=("firewall_rules" "users") ;;
    esac

    local drift=0 total=0
    for p in "${profiles[@]}"; do
        total=$((total + 1))
        echo "  ${C_BOLD}Profile: $p${C_RESET}"
        local applied="$NOOBTECH_ROOT/data/applied_configs/${server}_${p}.conf"

        if [ ! -f "$applied" ]; then
            echo "  ${C_YELLOW}[NOT APPLIED]${C_RESET} Never applied to $server"
            drift=$((drift + 1))
        else
            local diff_out; diff_out=$(diff "$CONFIGS_DIR/${p}.conf" "$applied" 2>/dev/null) || true
            if [ -z "$diff_out" ]; then
                echo "  ${C_GREEN}[OK]${C_RESET} No drift detected"
            else
                echo "  ${C_RED}[DRIFT]${C_RESET} Differences found:"
                diff "$CONFIGS_DIR/${p}.conf" "$applied" 2>/dev/null \
                    | grep "^[<>]" | head -5 \
                    | sed 's/^< /  desired: /; s/^> /  actual:  /'
                drift=$((drift + 1))
            fi
        fi
        echo ""
    done

    # FIX 6: Include $server in simulated live-check output so it looks server-specific
    echo "  ${C_BOLD}Live checks on $server (simulated):${C_RESET}"
    printf "  %-30s %s\n" "PermitRootLogin=no"        "${C_GREEN}[PASS]${C_RESET}"
    printf "  %-30s %s\n" "PasswordAuthentication=no" "${C_GREEN}[PASS]${C_RESET}"
    printf "  %-30s %s\n" "UFW active"                "${C_GREEN}[PASS]${C_RESET}"
    printf "  %-30s %s\n" "NTP sync ($server)"        "${C_RED}[DRIFT]${C_RESET} ntp not running"
    echo ""

    print_summary "Drift Check: $server" $((total - drift)) "$drift"

    # FIX 7d: log check result
    echo "[$(timestamp)] [CHECK] server=$server drift=$drift total=$total" >> "$LOG_CONFIG"

    [ "$drift" -gt 0 ] && return 1 || return 0
}

# ─────────────────────────────────────────────────────────────
# config remediate <server>
# ─────────────────────────────────────────────────────────────
config_remediate() {
    local server="${1:-}"
    if [ -z "$server" ]; then
        log_error "CONFIG" "Usage: config remediate <server>"
        return 1
    fi

    log_section "Config Remediation: $server"
    log_info "CONFIG" "Starting remediation — server=$server"  # FIX 7e: log remediate start

    config_check "$server" || true
    confirm "Apply all fixes to '$server'?" || { log_info "CONFIG" "Cancelled"; return 0; }

    local role; role=$(get_server_field "$server" "role")
    local profiles=()
    case "$role" in
        web)      profiles=("web_server" "firewall_rules" "users") ;;
        database) profiles=("database"   "firewall_rules" "users") ;;
        cache)    profiles=("cache"      "firewall_rules" "users") ;;
        *)        profiles=("firewall_rules" "users") ;;
    esac

    # FIX 5b: Set flag to suppress repeated prod confirmation inside the loop
    # User already confirmed once above — no need to prompt 3 more times
    export NOOBTECH_SKIP_PROD_CONFIRM=1

    for p in "${profiles[@]}"; do
        config_apply "$p" "$server"
    done

    # Reset the flag after remediation is done
    unset NOOBTECH_SKIP_PROD_CONFIRM

    log_success "CONFIG" "Remediation complete on $server"
    echo "[$(timestamp)] [REMEDIATE] server=$server profiles=${profiles[*]}" >> "$LOG_CONFIG"  # FIX 7f: log remediate end
}