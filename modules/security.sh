#!/bin/bash
# =============================================================================
# modules/security.sh — Security Audit System
# =============================================================================
# CONCEPTS TO UNDERSTAND:
#
#   CIS Benchmarks: Industry standard security checks. A checklist of
#   "your server should be configured like this" rules.
#
#   Severity levels:
#     CRITICAL = exploitable right now, fix immediately
#     HIGH     = serious risk, fix this week
#     MEDIUM   = best practice gap, fix this month
#     LOW      = minor improvement, nice to have
#
#   Common checks:
#     grep PermitRootLogin /etc/ssh/sshd_config → should be "no"
#     grep PasswordAuthentication /etc/ssh/sshd_config → should be "no"
#     ss -tlnp → shows all listening ports (look for unexpected ones)
#     find / -perm -4000 → SUID files (can be privilege escalation risk)
# =============================================================================

source "$NOOBTECH_ROOT/lib/logger.sh"
source "$NOOBTECH_ROOT/lib/common.sh"

REPORT_FILE="$NOOBTECH_ROOT/data/security_audit_report.txt"
REMEDIATION_GUIDE="$NOOBTECH_ROOT/docs/SECURITY_GUIDE.md"

cmd_security() {
    local action="${1:-}"
    [ $# -gt 0 ] && shift

    case "$action" in
        scan)   security_scan   "$@" ;;
        report) security_report "$@" ;;
        --help|-h)
            echo "Usage: security scan <server|local> | security report"
            ;;
        *) log_error "SECURITY" "Unknown action: $action. Use: scan, report"; return 1 ;;
    esac
}

# =============================================================================
# security_scan: Run all security checks and generate report
# =============================================================================
security_scan() {
    local target="${1:-local}"
    log_section "Security Audit: $target"

    # Track findings by severity
    local critical=0 high=0 medium=0 low=0 passed=0
    local findings=()

    echo "  ${C_BOLD}Running security checks...${C_RESET}"
    echo ""

    # ── CATEGORY 1: SSH Configuration ───────────────────────────────────────
    echo "  ${C_BOLD}[1/5] SSH Configuration${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check 1: PermitRootLogin
    local root_login
    root_login=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ "$root_login" = "no" ]; then
        _finding "PASS" "LOW" "PermitRootLogin = no" "SSH" && passed=$((passed+1))
    elif [ -z "$root_login" ]; then
        _finding "MEDIUM" "MEDIUM" "PermitRootLogin not explicitly set (default may allow root)" "SSH"
        medium=$((medium+1))
    else
        _finding "CRITICAL" "CRITICAL" "PermitRootLogin = $root_login — root SSH access enabled!" "SSH"
        critical=$((critical+1))
    fi

    # Check 2: PasswordAuthentication
    local pw_auth
    pw_auth=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ "$pw_auth" = "no" ]; then
        _finding "PASS" "LOW" "PasswordAuthentication = no (key-only)" "SSH" && passed=$((passed+1))
    else
        _finding "HIGH" "HIGH" "PasswordAuthentication = yes — brute force risk" "SSH"
        high=$((high+1))
    fi

    # Check 3: SSH Port
    local ssh_port
    ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
    if [ "$ssh_port" = "22" ] || [ -z "$ssh_port" ]; then
        _finding "LOW" "LOW" "SSH on default port 22 — consider changing" "SSH"
        low=$((low+1))
    else
        _finding "PASS" "LOW" "SSH on non-standard port $ssh_port" "SSH" && passed=$((passed+1))
    fi
    echo ""

    # ── CATEGORY 2: User & Privilege Checks ─────────────────────────────────
    echo "  ${C_BOLD}[2/5] Users & Privileges${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check 4: Users with empty passwords
    local empty_pw
    empty_pw=$(awk -F: '($2 == "" || $2 == "!") && NR>1' /etc/shadow 2>/dev/null | wc -l)
    if [ "$empty_pw" -gt 0 ]; then
        _finding "CRITICAL" "CRITICAL" "$empty_pw accounts with empty/locked passwords found" "USERS"
        critical=$((critical+1))
    else
        _finding "PASS" "LOW" "No accounts with empty passwords" "USERS" && passed=$((passed+1))
    fi

    # Check 5: Users with UID 0 (root-level)
    local uid0_users
    uid0_users=$(awk -F: '$3==0{print $1}' /etc/passwd 2>/dev/null | grep -v "^root$" | wc -l)
    if [ "$uid0_users" -gt 0 ]; then
        local uid0_names; uid0_names=$(awk -F: '$3==0{print $1}' /etc/passwd | grep -v "^root$" | tr '\n' ',')
        _finding "CRITICAL" "CRITICAL" "Non-root users with UID 0: $uid0_names" "USERS"
        critical=$((critical+1))
    else
        _finding "PASS" "LOW" "Only root has UID 0" "USERS" && passed=$((passed+1))
    fi

    # Check 6: Sudo users
    local sudo_count
    sudo_count=$(getent group sudo 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' | grep -v "^$" | wc -l)
    if [ "$sudo_count" -gt 5 ]; then
        _finding "MEDIUM" "MEDIUM" "$sudo_count users in sudo group — review if all needed" "USERS"
        medium=$((medium+1))
    else
        _finding "PASS" "LOW" "$sudo_count users in sudo group (acceptable)" "USERS" && passed=$((passed+1))
    fi
    echo ""

    # ── CATEGORY 3: Network & Ports ──────────────────────────────────────────
    echo "  ${C_BOLD}[3/5] Network & Open Ports${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check 7: Check for dangerous open ports
    local dangerous_ports=("23" "21" "25" "111" "512" "513" "514")
    local found_dangerous=0

    for port in "${dangerous_ports[@]}"; do
        if ss -tlnp 2>/dev/null | grep -q ":$port "; then
            _finding "HIGH" "HIGH" "Dangerous port $port is open ($(
                case $port in
                    23) echo "Telnet";;  21) echo "FTP";;
                    25) echo "SMTP";;   111) echo "RPC";;
                    512|513|514) echo "RSH/RLogin";;
                esac
            ))" "NETWORK"
            high=$((high+1))
            found_dangerous=$((found_dangerous+1))
        fi
    done

    if [ "$found_dangerous" -eq 0 ]; then
        _finding "PASS" "LOW" "No dangerous ports open" "NETWORK" && passed=$((passed+1))
    fi

    # Check 8: IPv6 (often forgotten attack surface)
    if [ -f /proc/net/if_inet6 ]; then
        _finding "LOW" "LOW" "IPv6 enabled — ensure firewall covers IPv6 too" "NETWORK"
        low=$((low+1))
    fi
    echo ""

    # ── CATEGORY 4: File System Security ────────────────────────────────────
    echo "  ${C_BOLD}[4/5] File System Security${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check 9: World-writable files
    local world_write
    world_write=$(find /tmp /var/tmp 2>/dev/null -maxdepth 2 -perm -002 -not -type l | wc -l)
    if [ "$world_write" -gt 10 ]; then
        _finding "MEDIUM" "MEDIUM" "$world_write world-writable files in /tmp (review)" "FILES"
        medium=$((medium+1))
    else
        _finding "PASS" "LOW" "World-writable files count acceptable: $world_write" "FILES"
        passed=$((passed+1))
    fi

    # Check 10: Check for hardcoded secrets in configs (grep for common patterns)
    local secret_count=0
    if find "$NOOBTECH_ROOT" -name "*.conf" -o -name "*.sh" 2>/dev/null | \
        xargs grep -l -i "password\s*=\s*[^$]" 2>/dev/null | grep -v ".git" | grep -q "."; then
        secret_count=1
    fi

    if [ "$secret_count" -gt 0 ]; then
        _finding "HIGH" "HIGH" "Possible hardcoded passwords found in config files" "FILES"
        high=$((high+1))
    else
        _finding "PASS" "LOW" "No obvious hardcoded credentials found" "FILES"
        passed=$((passed+1))
    fi
    echo ""

    # ── CATEGORY 5: System Updates ───────────────────────────────────────────
    echo "  ${C_BOLD}[5/5] System Updates & Packages${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check 11: Last update time
    local last_update
    last_update=$(stat -c %Y /var/lib/apt/lists 2>/dev/null || echo "0")
    local now; now=$(date +%s)
    local days_since=$(( (now - last_update) / 86400 ))

    if [ "$days_since" -gt 30 ]; then
        _finding "HIGH" "HIGH" "Package lists not updated in $days_since days — run apt update" "SYSTEM"
        high=$((high+1))
    elif [ "$days_since" -gt 7 ]; then
        _finding "MEDIUM" "MEDIUM" "Package lists $days_since days old — consider updating" "SYSTEM"
        medium=$((medium+1))
    else
        _finding "PASS" "LOW" "Package lists updated $days_since days ago" "SYSTEM"
        passed=$((passed+1))
    fi

    # Check 12: Audit log enabled
    if command -v auditd &>/dev/null || [ -f /var/log/audit/audit.log ]; then
        _finding "PASS" "LOW" "Audit daemon running" "SYSTEM" && passed=$((passed+1))
    else
        _finding "LOW" "LOW" "auditd not installed — consider enabling for compliance" "SYSTEM"
        low=$((low+1))
    fi
    echo ""

    # ── GENERATE REPORT ──────────────────────────────────────────────────────
    local total=$((critical + high + medium + low + passed))
    local issues=$((critical + high + medium + low))

    echo "  ════════════════════════════════════════════"
    echo "  ${C_BOLD}Security Audit Summary${C_RESET}"
    echo "  ════════════════════════════════════════════"
    printf "  %-10s %s\n" "${C_RED}CRITICAL:${C_RESET}" "$critical"
    printf "  %-10s %s\n" "${C_YELLOW}HIGH:${C_RESET}"     "$high"
    printf "  %-10s %s\n" "${C_CYAN}MEDIUM:${C_RESET}"    "$medium"
    printf "  %-10s %s\n" "LOW:"      "$low"
    printf "  %-10s %s\n" "${C_GREEN}PASSED:${C_RESET}"   "$passed"
    echo "  ────────────────────────────────────────────"
    printf "  %-10s %s / %s checks\n" "Total:" "$issues issues" "$total"
    echo ""

    # Generate text report file
    _generate_security_report "$target" "$critical" "$high" "$medium" "$low" "$passed"
    # Generate remediation guide
    _generate_remediation_guide

    log_success "SECURITY" "Audit complete — report saved to data/security_audit_report.txt"
    echo "[$(timestamp)] [SCAN] target=$target critical=$critical high=$high medium=$medium" \
        >> "$LOG_SECURITY"

    [ "$critical" -gt 0 ] && return 1 || return 0
}

# =============================================================================
# security_report: Show the last generated report
# =============================================================================
security_report() {
    if [ ! -f "$REPORT_FILE" ]; then
        log_error "SECURITY" "No report found. Run: security scan first"
        return 1
    fi
    cat "$REPORT_FILE"
}

# =============================================================================
# HELPERS
# =============================================================================

# _finding: Print and record a single security finding
_finding() {
    local severity="$1"
    local display_sev="$2"
    local message="$3"
    local category="$4"

    local color="$C_RESET"
    local icon="○"
    case "$display_sev" in
        CRITICAL) color="$C_RED";    icon="✗" ;;
        HIGH)     color="$C_YELLOW"; icon="!" ;;
        MEDIUM)   color="$C_CYAN";   icon="~" ;;
        LOW)      color="$C_RESET";  icon="•" ;;
        PASS)     color="$C_GREEN";  icon="✓" ;;
    esac

    if [ "$severity" = "PASS" ]; then
        printf "  ${C_GREEN}[✓ PASS]${C_RESET}   %-10s %s\n" "[$category]" "$message"
    else
        printf "  ${color}[%-8s]${C_RESET} %-10s %s\n" "$severity" "[$category]" "$message"
    fi

    # Log to security events log
    echo "[$(timestamp)] [$severity] [$category] $message" >> "$LOG_SECURITY"
}

_generate_security_report() {
    local target="$1" crit="$2" high="$3" med="$4" low="$5" pass="$6"
    {
        echo "=================================================="
        echo " SECURITY AUDIT REPORT"
        echo " Generated: $(timestamp)"
        echo " Target:    $target"
        echo "=================================================="
        echo ""
        echo " FINDINGS SUMMARY:"
        echo "   CRITICAL : $crit  (fix immediately)"
        echo "   HIGH     : $high  (fix this week)"
        echo "   MEDIUM   : $med   (fix this month)"
        echo "   LOW      : $low   (nice to have)"
        echo "   PASSED   : $pass"
        echo ""
        echo " DETAILED FINDINGS:"
        echo "--------------------------------------------------"
        grep -v "^\[.*\] \[SUCCESS\]" "$LOG_SECURITY" 2>/dev/null | tail -30 | \
            sed 's/\[2[0-9]*-[0-9]*-[0-9]* [0-9:]*\] //'
        echo ""
        echo " See docs/SECURITY_GUIDE.md for remediation steps"
        echo "=================================================="
    } > "$REPORT_FILE"
}

_generate_remediation_guide() {
    cat > "$REMEDIATION_GUIDE" << 'EOF'
# Security Remediation Guide

## CRITICAL Findings

### Disable Root SSH Login
```bash
sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### Disable Password Authentication (use SSH keys only)
```bash
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

## HIGH Findings

### Update Package Lists
```bash
sudo apt update && sudo apt upgrade -y
```

### Close Dangerous Ports
```bash
sudo ufw deny 23    # Telnet
sudo ufw deny 21    # FTP
sudo ufw enable
```

## MEDIUM Findings

### Enable NTP Time Sync
```bash
sudo apt install -y ntp
sudo systemctl enable --now ntp
```

### Review Sudo Users
```bash
getent group sudo          # List sudo users
sudo gpasswd -d <user> sudo  # Remove user from sudo
```

## Compliance Checklist
- [ ] SSH key-only authentication
- [ ] Firewall enabled with default deny
- [ ] Root login disabled
- [ ] All packages up to date
- [ ] Audit logging enabled
- [ ] No world-writable sensitive files
- [ ] Regular backup verification
EOF
    log_info "SECURITY" "Remediation guide saved: docs/SECURITY_GUIDE.md"
}
