#!/bin/bash
# =============================================================================
# modules/monitor.sh — Monitoring & Health Checks
# =============================================================================
# CONCEPTS TO UNDERSTAND:
#
#   How to read CPU usage in bash:
#     top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d% -f1
#     top -bn1   = run top once (-n1), no interaction (-b=batch mode)
#     grep Cpu   = find the CPU line
#     awk '{print $2}' = grab second column (the user% value)
#
#   How to read memory:
#     free -m   = show memory in megabytes
#     awk 'NR==2{printf "%.0f", $3/$2*100}' = used/total * 100
#
#   How to read disk:
#     df -h /   = disk usage of root filesystem
#     awk 'NR==2{gsub(/%/,"",$5); print $5}' = extract % used number
#
#   Alert thresholds (from assignment):
#     CPU    > 80% for 5min → WARNING
#     Memory > 90%          → CRITICAL
#     Disk   > 85%          → WARNING,  >95% → CRITICAL
#     Service down          → CRITICAL (immediate)
# =============================================================================

source "$NOOBTECH_ROOT/lib/logger.sh"
source "$NOOBTECH_ROOT/lib/common.sh"

METRICS_DIR="$NOOBTECH_ROOT/monitoring/metrics"

cmd_monitor() {
    local action="${1:-dashboard}"
    [ $# -gt 0 ] && shift

    case "$action" in
        start)     monitor_start     "$@" ;;
        status)    monitor_status    "$@" ;;
        dashboard) monitor_dashboard "$@" ;;
        --help|-h)
            echo "Usage: monitor start | monitor status | monitor dashboard"
            ;;
        *) log_error "MONITOR" "Unknown action: $action"; return 1 ;;
    esac
}

# =============================================================================
# monitor_status: Check all servers once and report
# =============================================================================
monitor_status() {
    log_section "Infrastructure Status"

    local servers
    servers=$(awk '/- hostname:/{print $NF}' "$NOOBTECH_ROOT/servers.yaml")

    local healthy=0 warning=0 critical=0

    printf "  %-16s %-10s %-8s %-8s %-8s %s\n" \
        "SERVER" "ENV" "CPU%" "MEM%" "DISK%" "STATUS"
    echo "  ──────────────────────────────────────────────────────────────"

    while IFS= read -r server; do
        [ -z "$server" ] && continue

        local env; env=$(awk -v h="$server" '
            /- hostname:/ { found=($NF==h) }
            found && /environment:/ { print $NF; exit }
        ' "$NOOBTECH_ROOT/servers.yaml")

        # Collect metrics (real on local machine, simulated for remote)
        local cpu mem disk
        cpu=$(_get_cpu_usage)
        mem=$(_get_mem_usage)
        disk=$(_get_disk_usage)

        # Determine status from thresholds
        local status="${C_GREEN}HEALTHY${C_RESET}"
        local severity="ok"

        if [ "$cpu" -gt 80 ] || [ "$mem" -gt 90 ] || [ "$disk" -gt 95 ]; then
            status="${C_RED}CRITICAL${C_RESET}"; severity="critical"
            critical=$((critical+1))
            _write_incident "$server" "CRITICAL" "Threshold exceeded: CPU=${cpu}% MEM=${mem}% DISK=${disk}%"
        elif [ "$cpu" -gt 60 ] || [ "$mem" -gt 75 ] || [ "$disk" -gt 85 ]; then
            status="${C_YELLOW}WARNING${C_RESET}"; severity="warning"
            warning=$((warning+1))
        else
            healthy=$((healthy+1))
        fi

        printf "  %-16s %-10s %-8s %-8s %-8s %b\n" \
            "$server" "${env:-?}" "${cpu}%" "${mem}%" "${disk}%" "$status"

        # Save to CSV for historical tracking
        echo "$(timestamp),$server,$cpu,$mem,$disk,$severity" \
            >> "$METRICS_DIR/${server}.csv"

    done <<< "$servers"

    echo ""
    echo "  ${C_BOLD}Summary:${C_RESET}  ${C_GREEN}Healthy: $healthy${C_RESET}  |  ${C_YELLOW}Warning: $warning${C_RESET}  |  ${C_RED}Critical: $critical${C_RESET}"
    echo ""

    # Service checks
    _check_services

    [ "$critical" -gt 0 ] && return 1 || return 0
}

# =============================================================================
# monitor_dashboard: Real-time ASCII dashboard
# =============================================================================
monitor_dashboard() {
    log_section "Live Infrastructure Dashboard"

    local ts; ts=$(timestamp)
    echo "  Last updated: $ts"
    echo ""

    # ── System metrics (real values from this machine) ──────────────────────
    local cpu mem disk
    cpu=$(_get_cpu_usage)
    mem=$(_get_mem_usage)
    disk=$(_get_disk_usage)

    echo "  ${C_BOLD}── Local System Metrics ─────────────────────────────────${C_RESET}"
    _draw_bar "CPU Usage   " "$cpu"    80 95
    _draw_bar "Memory      " "$mem"    75 90
    _draw_bar "Disk Usage  " "$disk"   85 95
    echo ""

    # ── Simulated server metrics ─────────────────────────────────────────────
    echo "  ${C_BOLD}── Server Fleet (simulated) ─────────────────────────────${C_RESET}"

    local servers=("prod-web-01:production" "prod-web-02:production"
                   "prod-db-01:production"  "stg-web-01:staging"
                   "dev-web-01:development")

    for entry in "${servers[@]}"; do
        local srv="${entry%%:*}"
        local env="${entry##*:}"
        local s_cpu s_mem s_disk
        s_cpu=$((RANDOM % 60 + 10))
        s_mem=$((RANDOM % 50 + 20))
        s_disk=$((RANDOM % 40 + 20))
        local svc_status="${C_GREEN}UP${C_RESET}"

        printf "  %-16s [%-10s]  CPU:%-4s  MEM:%-4s  DISK:%-4s  SVC:%b\n" \
            "$srv" "$env" "${s_cpu}%" "${s_mem}%" "${s_disk}%" "$svc_status"

        echo "$(timestamp),$srv,$s_cpu,$s_mem,$s_disk,ok" \
            >> "$METRICS_DIR/${srv}.csv"
    done
    echo ""

    # ── Service health ────────────────────────────────────────────────────────
    echo "  ${C_BOLD}── Service Health ───────────────────────────────────────${C_RESET}"
    _check_services

    # ── Recent incidents ──────────────────────────────────────────────────────
    echo "  ${C_BOLD}── Recent Incidents ─────────────────────────────────────${C_RESET}"
    if [ -f "$LOG_INCIDENTS" ] && [ -s "$LOG_INCIDENTS" ]; then
        tail -3 "$LOG_INCIDENTS" | sed 's/^/  /'
    else
        echo "  ${C_GREEN}No recent incidents${C_RESET}"
    fi
    echo ""

    log_info "MONITOR" "Dashboard rendered at $(timestamp)"
}

# =============================================================================
# monitor_start: Continuous monitoring daemon
# =============================================================================
monitor_start() {
    local interval="${1:-30}"
    log_section "Starting Monitor Daemon"
    log_info "MONITOR" "Checking every ${interval}s — press Ctrl+C to stop"
    echo ""

    local iteration=0
    while true; do
        iteration=$((iteration+1))
        echo "  ${C_CYAN}[Check #$iteration — $(timestamp)]${C_RESET}"

        # Run status check
        monitor_status 2>/dev/null || {
            log_critical "MONITOR" "Critical issues detected — attempting auto-remediation"
            _auto_remediate
        }

        echo "  Next check in ${interval}s..."
        echo ""
        sleep "$interval"
    done
}

# =============================================================================
# SERVICE CHECKS
# =============================================================================
_check_services() {
    local services=("nginx:80" "mysql:3306" "redis:6379")

    printf "  %-12s %-8s %-10s %s\n" "SERVICE" "PORT" "STATUS" "RESPONSE"
    echo "  ──────────────────────────────────────────"

    for entry in "${services[@]}"; do
        local svc="${entry%%:*}"
        local port="${entry##*:}"

        # Check if port is listening (on this machine)
        local listening="NO"
        if command -v ss &>/dev/null; then
            ss -tlnp 2>/dev/null | grep -q ":$port " && listening="YES"
        elif command -v netstat &>/dev/null; then
            netstat -tlnp 2>/dev/null | grep -q ":$port " && listening="YES"
        fi

        # For demo: simulate service status
        local status_color response
        case "$svc" in
            nginx)  status_color="${C_YELLOW}SIMULATED${C_RESET}"; response="N/A (demo)" ;;
            mysql)  status_color="${C_YELLOW}SIMULATED${C_RESET}"; response="N/A (demo)" ;;
            redis)  status_color="${C_YELLOW}SIMULATED${C_RESET}"; response="N/A (demo)" ;;
        esac

        printf "  %-12s %-8s %-10b %s\n" "$svc" "$port" "$status_color" "$response"
    done
    echo ""
}

# =============================================================================
# AUTO-REMEDIATION: What happens when issues are detected
# =============================================================================
_auto_remediate() {
    log_warning "MONITOR" "Running auto-remediation..."

    # Service restart with exponential backoff
    # Attempt 1: wait 5s, Attempt 2: wait 10s, Attempt 3: wait 20s
    local service="nginx"
    local attempts=3
    local wait_time=5

    for i in $(seq 1 $attempts); do
        log_info "MONITOR" "Restart attempt $i/$attempts for $service (wait: ${wait_time}s)"
        # dry_run systemctl restart $service
        sleep 1  # simulate restart time

        # Check if it came back up (simulated)
        if [ $((RANDOM % 3)) -gt 0 ]; then
            log_success "MONITOR" "$service restarted successfully on attempt $i"
            return 0
        fi

        log_warning "MONITOR" "$service still down — waiting ${wait_time}s before retry"
        sleep "$wait_time"
        wait_time=$((wait_time * 2))  # exponential backoff
    done

    log_critical "MONITOR" "$service failed to restart after $attempts attempts — escalating"
    _write_incident "system" "CRITICAL" "$service failed auto-remediation — manual intervention needed"
}

# =============================================================================
# METRIC COLLECTION HELPERS
# These read REAL values from the machine running the script
# =============================================================================

_get_cpu_usage() {
    # Read actual CPU from /proc/stat
    # Line format: cpu  user nice system idle iowait irq softirq
    local cpu1 cpu2 idle1 idle2 total1 total2
    read -r cpu1 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8; exit}' /proc/stat 2>/dev/null || echo 100)
    read -r idle1 < <(awk '/^cpu /{print $5; exit}' /proc/stat 2>/dev/null || echo 0)
    sleep 0.1
    read -r cpu2 < <(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8; exit}' /proc/stat 2>/dev/null || echo 100)
    read -r idle2 < <(awk '/^cpu /{print $5; exit}' /proc/stat 2>/dev/null || echo 0)

    total1=$cpu1; total2=$cpu2
    local used=$(( (total2 - total1) - (idle2 - idle1) ))
    local total=$(( total2 - total1 ))
    if [ "$total" -eq 0 ]; then echo "0"; return; fi
    echo $(( used * 100 / total ))
}

_get_mem_usage() {
    # free -m: show memory in MB
    # NR==2 = second line (Mem: line)
    # $3/$2*100 = used/total * 100
    free -m 2>/dev/null | awk 'NR==2{printf "%.0f", $3/$2*100}' || echo "0"
}

_get_disk_usage() {
    # df /: disk usage of root filesystem
    # NR==2 = data line, $5 = use%, strip the %
    df / 2>/dev/null | awk 'NR==2{gsub(/%/,"",$5); print $5}' || echo "0"
}

# =============================================================================
# DISPLAY HELPERS
# =============================================================================

# _draw_bar: Draws an ASCII progress bar with color based on thresholds
# Usage: _draw_bar "Label" <value> <warn_threshold> <crit_threshold>
_draw_bar() {
    local label="$1"
    local value="$2"
    local warn="$3"
    local crit="$4"

    # Color based on threshold
    local color="$C_GREEN"
    if [ "$value" -ge "$crit" ]; then color="$C_RED"
    elif [ "$value" -ge "$warn" ]; then color="$C_YELLOW"
    fi

    # Draw bar: 30 chars wide
    local filled=$(( value * 30 / 100 ))
    local empty=$(( 30 - filled ))
    local bar=""
    local i=0
    while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i+1)); done
    while [ $i -lt 30 ]; do bar="${bar}░"; i=$((i+1)); done

    printf "  %-14s [%b%s%b] %3d%%\n" \
        "$label" "$color" "$bar" "$C_RESET" "$value"
}

_write_incident() {
    local server="$1" level="$2" message="$3"
    echo "[$(timestamp)] [$level] [$server] $message" >> "$LOG_INCIDENTS"
}
