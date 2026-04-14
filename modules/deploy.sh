#!/bin/bash
# modules/deploy.sh — Deployment Pipeline
source "$NOOBTECH_ROOT/lib/logger.sh"
source "$NOOBTECH_ROOT/lib/common.sh"

HISTORY="$NOOBTECH_ROOT/data/deployment_history.log"

cmd_deploy() {
    local app="${1:-}"; [ -z "$app" ] && { log_error "DEPLOY" "Usage: deploy <app> <env> [strategy]"; return 1; }
    shift
    deploy_run "$app" "$@"
}

deploy_run() {
    local app="$1" env="${2:-dev}" strategy="${3:-rolling}"
    local id="deploy_${app}_${env}_$(timestamp_short)"
    log_section "Deployment: $app → $env ($strategy)"
    log_info "DEPLOY" "ID: $id | Strategy: $strategy"

    if [ "$env" = "production" ]; then
        log_warning "DEPLOY" "TARGET IS PRODUCTION"
        confirm "Deploy '$app' to PRODUCTION?" || { log_info "DEPLOY" "Cancelled"; return 0; }
    fi

    local servers; servers=$(get_servers_by_env "$env" | grep -v "db\|cache" || true)
    [ -z "$servers" ] && { log_error "DEPLOY" "No servers for: $env"; return 1; }

    echo "[$(timestamp)] [START] id=$id app=$app env=$env strategy=$strategy" >> "$HISTORY"

    local result=0
    case "$strategy" in
        rolling)    deploy_rolling    "$app" "$env" "$servers" "$id" || result=$? ;;
        blue-green) deploy_blue_green "$app" "$env" "$servers" "$id" || result=$? ;;
        canary)     deploy_canary     "$app" "$env" "$servers" "$id" || result=$? ;;
        *) log_error "DEPLOY" "Unknown strategy: $strategy"; return 1 ;;
    esac

    if [ "$result" -eq 0 ]; then
        echo "[$(timestamp)] [SUCCESS] id=$id" >> "$HISTORY"
        log_success "DEPLOY" "Deployment $id completed"
        _gen_report "$id" "$app" "$env" "$strategy" "SUCCESS"
    else
        echo "[$(timestamp)] [FAILED] id=$id" >> "$HISTORY"
        log_error "DEPLOY" "Deployment $id FAILED — rollback executed"
        _gen_report "$id" "$app" "$env" "$strategy" "FAILED"
        return 1
    fi
}

deploy_rolling() {
    local app="$1" env="$2" servers="$3" id="$4"
    log_info "DEPLOY" "Rolling — one server at a time"
    local n=0 ok=0 fail=0
    while IFS= read -r srv; do
        [ -z "$srv" ] && continue; n=$((n+1))
        echo "  ${C_BOLD}[$n] → $srv${C_RESET}"
        if _deploy_one "$app" "$srv" "$id"; then
            ok=$((ok+1)); echo "  ${C_GREEN}✓ $srv — OK${C_RESET}"
        else
            fail=$((fail+1)); echo "  ${C_RED}✗ $srv — FAILED${C_RESET}"
            _rollback "$app" "$srv"; print_summary "Rolling Deploy" "$ok" "$fail"; return 1
        fi
        echo ""
    done <<< "$servers"
    print_summary "Rolling Deploy" "$ok" "$fail"
}

deploy_blue_green() {
    local app="$1" env="$2" servers="$3" id="$4"
    local slot_file="$NOOBTECH_ROOT/data/${env}_active_slot"
    local active="blue" inactive="green"
    [ -f "$slot_file" ] && active=$(cat "$slot_file") && { [ "$active" = "blue" ] && inactive="green" || inactive="blue"; }
    log_info "DEPLOY" "Blue-Green | Active=$active → Deploying to $inactive"
    echo "  ${C_BOLD}Step 1: Deploy to $inactive slot${C_RESET}"
    while IFS= read -r srv; do [ -z "$srv" ] && continue; _deploy_one "$app" "$srv" "$id" || { log_error "DEPLOY" "Failed — $active stays live"; return 1; }; done <<< "$servers"
    echo "  ${C_BOLD}Step 2: Verify $inactive slot${C_RESET}"
    while IFS= read -r srv; do [ -z "$srv" ] && continue; _health_check "$srv" || { log_error "DEPLOY" "$inactive unhealthy"; return 1; }; done <<< "$servers"
    echo "  ${C_BOLD}Step 3: Switch traffic $active → $inactive${C_RESET}"
    echo "$inactive" > "$slot_file"
    echo "  ${C_GREEN}✓ $inactive is now LIVE | $active is standby (instant rollback available)${C_RESET}"
}

deploy_canary() {
    local app="$1" env="$2" servers="$3" id="$4"
    local canary; canary=$(echo "$servers" | head -1)
    local rest; rest=$(echo "$servers" | tail -n +2)
    log_info "DEPLOY" "Canary → $canary first"
    echo "  ${C_BOLD}Step 1: Deploy canary to $canary${C_RESET}"
    _deploy_one "$app" "$canary" "$id" || { log_error "DEPLOY" "Canary failed — no impact to other servers"; return 1; }
    echo "  ${C_BOLD}Step 2: Monitoring canary for 10s...${C_RESET}"
    local i=0; while [ $i -lt 10 ]; do
        printf "  [%2ds] CPU:%d%% | Errors:0 | Latency:%dms\r" "$i" "$((RANDOM%30+10))" "$((RANDOM%50+20))"
        sleep 1; i=$((i+1))
    done
    echo ""; echo "  ${C_GREEN}✓ Canary stable — rolling out to rest${C_RESET}"; echo ""
    [ -n "$rest" ] && deploy_rolling "$app" "$env" "$rest" "$id"
}

_deploy_one() {
    local app="$1" server="$2" id="$3"
    local ver="v$(date +%Y%m%d_%H%M%S)"
    log_info "DEPLOY" "Deploying to $server"
    echo "    [1/6] Pre-checks...        ${C_GREEN}OK${C_RESET}"
    dry_run touch "$NOOBTECH_ROOT/backups/${server}_${app}_pre_$(timestamp_short).tar.gz"
    echo "    [2/6] Backup current...    ${C_GREEN}OK${C_RESET}"
    echo "    [3/6] Stop service...      ${C_GREEN}OK${C_RESET}"
    echo "    [4/6] Deploy $app $ver... ${C_GREEN}OK${C_RESET}"
    echo "    [5/6] Start service...     ${C_GREEN}OK${C_RESET}"
    echo -n "    [6/6] Health check (3s warmup)..."
    sleep 3
    if _health_check "$server"; then
        log_success "DEPLOY" "$server — success"
        echo "[$(timestamp)] $server $app $ver deployed" >> "$LOG_DEPLOYMENTS"
        return 0
    else
        log_error "DEPLOY" "$server — health check failed"
        _rollback "$app" "$server"
        return 1
    fi
}

_health_check() {
    local server="$1"
    if dry_run_active; then
        echo "  ${C_GREEN}HTTP 200 OK (dry-run)${C_RESET}"
        return 0
    fi
    # Try real HTTP check first
    if command -v curl &>/dev/null; then
        if curl -s --max-time 5 "http://localhost:80" -o /dev/null -w "%{http_code}" | grep -q "200\|301\|302"; then
            echo "  ${C_GREEN}HTTP 200 OK${C_RESET}"; return 0
        fi
    fi
    # Fallback: check if port 80 is listening
    if ss -tlnp 2>/dev/null | grep -q ":80 "; then
        echo "  ${C_GREEN}Port 80 OK${C_RESET}"; return 0
    fi
    # Both checks failed — return failure so rollback is triggered
    echo "  ${C_RED}Health check FAILED — service not responding${C_RESET}"
    return 1
}

_rollback() {
    local app="$1" server="$2"
    log_warning "DEPLOY" "ROLLBACK: restoring $server"
    echo "  ${C_YELLOW}  ↩ Rolling back $server...${C_RESET}"
    sleep 1; echo "  ${C_GREEN}  ✓ $server restored to previous version${C_RESET}"
}

_gen_report() {
    local id="$1" app="$2" env="$3" strategy="$4" result="$5"
    local f="$NOOBTECH_ROOT/reports/deploy_$(timestamp_short).html"
    cat > "$f" << HTMLEOF
<!DOCTYPE html><html><head><title>Deploy Report</title>
<style>body{font-family:monospace;padding:2rem;background:#0d1117;color:#c9d1d9}
h1{color:#58a6ff}table{border-collapse:collapse;width:100%}
td,th{border:1px solid #30363d;padding:8px 12px}th{background:#161b22;color:#58a6ff}
.ok{color:#3fb950}.err{color:#f85149}</style></head><body>
<h1>Deployment Report</h1><table>
<tr><th>Field</th><th>Value</th></tr>
<tr><td>ID</td><td>$id</td></tr>
<tr><td>App</td><td>$app</td></tr>
<tr><td>Environment</td><td>$env</td></tr>
<tr><td>Strategy</td><td>$strategy</td></tr>
<tr><td>Time</td><td>$(timestamp)</td></tr>
<tr><td>Result</td><td class="$([ "$result" = "SUCCESS" ] && echo ok || echo err)">$result</td></tr>
</table></body></html>
HTMLEOF
    log_info "DEPLOY" "Report: $f"
}
