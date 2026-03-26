#!/bin/bash
# =============================================================================
# modules/security.sh — Security Audit System
# =============================================================================
# KEY LESSON FOR THIS FILE:
#   Under set -e, grep returns exit code 1 when NO match is found.
#   This silently kills the script. Fix: always add "|| true" after grep
#   when the "no match" case is valid (not an error).
#
#   grep "something" file    → exit 0 (found), exit 1 (not found), exit 2 (error)
#   grep "something" file || true  → always exit 0 (safe under set -e)
#
# SEVERITY LEVELS:
#   CRITICAL = exploitable right now, fix immediately
#   HIGH     = serious risk, fix this week
#   MEDIUM   = best practice gap, fix this month
#   LOW      = minor improvement, nice to have
# =============================================================================

source "$NOOBTECH_ROOT/lib/logger.sh"
source "$NOOBTECH_ROOT/lib/common.sh"

REPORT_FILE="$NOOBTECH_ROOT/data/security_audit_report.txt"
REMEDIATION_FILE="$NOOBTECH_ROOT/docs/SECURITY_GUIDE.md"

cmd_security() {
    local action="${1:-}"
    [ $# -gt 0 ] && shift
    case "$action" in
        scan)      security_scan "$@" ;;
        report)    security_report ;;
        --help|-h) echo "Usage: security scan <server|local> | security report" ;;
        *) log_error "SECURITY" "Unknown action: $action. Use: scan, report"; return 1 ;;
    esac
}

# =============================================================================
# security_scan: Run all checks and generate report
# =============================================================================
security_scan() {
    local target="${1:-local}"
    log_section "Security Audit: $target"

    local critical=0 high=0 medium=0 low=0 passed=0

    echo "  ${C_BOLD}Running security checks...${C_RESET}"
    echo ""

    # ── [1/5] SSH Configuration ──────────────────────────────────────────────
    echo "  ${C_BOLD}[1/5] SSH Configuration${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # KEY FIX: grep || true — "not found" is valid, not an error
    local root_login
    root_login=$(grep -i "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}') || true

    if [ "$root_login" = "no" ]; then
        _pass "PermitRootLogin = no" "SSH"; passed=$((passed+1))
    elif [ -z "$root_login" ]; then
        _find "MEDIUM" "PermitRootLogin not set — default may allow root login" "SSH"; medium=$((medium+1))
    else
        _find "CRITICAL" "PermitRootLogin = $root_login — root SSH is OPEN!" "SSH"; critical=$((critical+1))
    fi

    local pw_auth
    pw_auth=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}') || true

    if [ "$pw_auth" = "no" ]; then
        _pass "PasswordAuthentication = no (key-only login)" "SSH"; passed=$((passed+1))
    else
        _find "HIGH" "PasswordAuthentication = yes — brute force risk" "SSH"; high=$((high+1))
    fi

    local ssh_port
    ssh_port=$(grep -i "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}') || true

    if [ -z "$ssh_port" ] || [ "$ssh_port" = "22" ]; then
        _find "LOW" "SSH on default port 22 — consider changing to reduce scan noise" "SSH"; low=$((low+1))
    else
        _pass "SSH on non-default port $ssh_port" "SSH"; passed=$((passed+1))
    fi
    echo ""

    # ── [2/5] Users & Privileges ─────────────────────────────────────────────
    echo "  ${C_BOLD}[2/5] Users & Privileges${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check for accounts with empty passwords in /etc/shadow
    local empty_pw=0
    if [ -r /etc/shadow ]; then
        empty_pw=$(awk -F: '($2=="" || $2=="!") && NR>1{count++} END{print count+0}' /etc/shadow 2>/dev/null) || true
    fi
    if [ "${empty_pw:-0}" -gt 0 ]; then
        _find "CRITICAL" "$empty_pw accounts with empty/no passwords" "USERS"; critical=$((critical+1))
    else
        _pass "No accounts with empty passwords" "USERS"; passed=$((passed+1))
    fi

    # Check for non-root users with UID 0 (privilege escalation risk)
    local uid0_count
    uid0_count=$(awk -F: '$3==0 && $1!="root"{count++} END{print count+0}' /etc/passwd 2>/dev/null) || true
    if [ "${uid0_count:-0}" -gt 0 ]; then
        local uid0_names
        uid0_names=$(awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd 2>/dev/null | tr '\n' ' ') || true
        _find "CRITICAL" "Non-root UID 0 users found: $uid0_names" "USERS"; critical=$((critical+1))
    else
        _pass "Only root has UID 0" "USERS"; passed=$((passed+1))
    fi

    # Count sudo group members
    local sudo_count=0
    sudo_count=$(getent group sudo 2>/dev/null | awk -F: '{print $4}' | tr ',' '\n' | grep -c "[a-z]" 2>/dev/null) || true
    if [ "${sudo_count:-0}" -gt 5 ]; then
        _find "MEDIUM" "$sudo_count users in sudo group — review if all are needed" "USERS"; medium=$((medium+1))
    else
        _pass "$sudo_count user(s) in sudo group" "USERS"; passed=$((passed+1))
    fi
    echo ""

    # ── [3/5] Network & Open Ports ───────────────────────────────────────────
    echo "  ${C_BOLD}[3/5] Network & Open Ports${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check for dangerous ports — || true prevents grep exit-1 from stopping script
    local found_dangerous=0
    declare -A port_names=([23]="Telnet" [21]="FTP" [25]="SMTP" [111]="RPC" [512]="RSH")

    for port in 23 21 25 111 512; do
        local port_open
        port_open=$(ss -tlnp 2>/dev/null | grep -c ":${port} " 2>/dev/null) || true
        if [ "${port_open:-0}" -gt 0 ]; then
            _find "HIGH" "Dangerous port ${port} (${port_names[$port]}) is open" "NETWORK"
            high=$((high+1)); found_dangerous=$((found_dangerous+1))
        fi
    done

    if [ "$found_dangerous" -eq 0 ]; then
        _pass "No dangerous ports open (telnet/ftp/rpc blocked)" "NETWORK"; passed=$((passed+1))
    fi

    # Check if UFW firewall is active
    local ufw_status
    ufw_status=$(ufw status 2>/dev/null | head -1) || true
    if echo "$ufw_status" | grep -q "active" 2>/dev/null; then
        _pass "UFW firewall is active" "NETWORK"; passed=$((passed+1))
    else
        _find "HIGH" "UFW firewall is not active — run: sudo ufw enable" "NETWORK"; high=$((high+1))
    fi
    echo ""

    # ── [4/5] File System Security ───────────────────────────────────────────
    echo "  ${C_BOLD}[4/5] File System Security${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # World-writable files in /tmp
    local world_write=0
    world_write=$(find /tmp /var/tmp -maxdepth 2 -perm -002 -not -type l 2>/dev/null | wc -l) || true
    if [ "${world_write:-0}" -gt 20 ]; then
        _find "MEDIUM" "$world_write world-writable files in /tmp" "FILES"; medium=$((medium+1))
    else
        _pass "World-writable file count OK: $world_write" "FILES"; passed=$((passed+1))
    fi

    # Check for hardcoded credentials in project configs
    local secret_hits=0
    secret_hits=$(grep -ril "password\s*=\s*[^$%{]" "$NOOBTECH_ROOT/configs" 2>/dev/null | wc -l) || true
    if [ "${secret_hits:-0}" -gt 0 ]; then
        _find "HIGH" "Possible hardcoded passwords in $secret_hits config file(s)" "FILES"; high=$((high+1))
    else
        _pass "No hardcoded credentials found in configs/" "FILES"; passed=$((passed+1))
    fi

    # Check SSH key permissions (should be 600, not readable by others)
    local bad_ssh_perms=0
    bad_ssh_perms=$(find ~/.ssh -name "*.pem" -o -name "id_*" 2>/dev/null | \
        xargs ls -la 2>/dev/null | awk '$1 ~ /[g-o][r-w]/' | wc -l) || true
    if [ "${bad_ssh_perms:-0}" -gt 0 ]; then
        _find "HIGH" "$bad_ssh_perms SSH key(s) with insecure permissions (need chmod 600)" "FILES"
        high=$((high+1))
    else
        _pass "SSH key permissions are secure" "FILES"; passed=$((passed+1))
    fi
    echo ""

    # ── [5/5] System Updates & Compliance ────────────────────────────────────
    echo "  ${C_BOLD}[5/5] System Updates & Compliance${C_RESET}"
    echo "  ─────────────────────────────────────────"

    # Check how old the package lists are
    local last_update days_since=999
    last_update=$(stat -c %Y /var/lib/apt/lists 2>/dev/null) || true
    if [ -n "$last_update" ]; then
        local now; now=$(date +%s)
        days_since=$(( (now - last_update) / 86400 ))
    fi

    if [ "$days_since" -gt 30 ]; then
        _find "HIGH" "Packages not updated in $days_since days — run: sudo apt update" "SYSTEM"; high=$((high+1))
    elif [ "$days_since" -gt 7 ]; then
        _find "MEDIUM" "Package lists $days_since days old — consider updating soon" "SYSTEM"; medium=$((medium+1))
    else
        _pass "Package lists updated $days_since day(s) ago" "SYSTEM"; passed=$((passed+1))
    fi

    # Check if audit daemon is installed
    if command -v auditctl &>/dev/null || [ -f /var/log/audit/audit.log ]; then
        _pass "Audit daemon (auditd) is installed" "SYSTEM"; passed=$((passed+1))
    else
        _find "LOW" "auditd not installed — run: sudo apt install auditd" "SYSTEM"; low=$((low+1))
    fi

    # Check fail2ban (intrusion prevention)
    if command -v fail2ban-client &>/dev/null; then
        _pass "fail2ban is installed (brute force protection)" "SYSTEM"; passed=$((passed+1))
    else
        _find "MEDIUM" "fail2ban not installed — run: sudo apt install fail2ban" "SYSTEM"; medium=$((medium+1))
    fi
    echo ""

    # ── SUMMARY ──────────────────────────────────────────────────────────────
    local total=$((critical + high + medium + low + passed))

    echo "  ${C_BOLD}════════════════════════════════════════════${C_RESET}"
    echo "  ${C_BOLD}Security Audit Summary — $target${C_RESET}"
    echo "  ${C_BOLD}════════════════════════════════════════════${C_RESET}"
    printf "  ${C_RED}%-12s${C_RESET} %d\n"    "CRITICAL:"  "$critical"
    printf "  ${C_YELLOW}%-12s${C_RESET} %d\n" "HIGH:"      "$high"
    printf "  ${C_CYAN}%-12s${C_RESET} %d\n"   "MEDIUM:"    "$medium"
    printf "  %-12s %d\n"                       "LOW:"       "$low"
    printf "  ${C_GREEN}%-12s${C_RESET} %d\n"  "PASSED:"    "$passed"
    echo "  ────────────────────────────────────────────"
    printf "  %-12s %d issues / %d checks\n"   "Total:"     "$((critical+high+medium+low))" "$total"
    echo ""

    # Write the report files
    _write_report "$target" "$critical" "$high" "$medium" "$low" "$passed"
    _write_remediation_guide
    log_success "SECURITY" "Report saved: data/security_audit_report.txt"
    log_success "SECURITY" "Remediation guide: docs/SECURITY_GUIDE.md"

    echo "[$(timestamp)] [SCAN] target=$target critical=$critical high=$high medium=$medium low=$low" \
        >> "$LOG_SECURITY"

    # Return non-zero if critical issues found (useful in CI pipelines)
    if [ "$critical" -gt 0 ]; then return 1; fi
    return 0
}

security_report() {
    if [ ! -f "$REPORT_FILE" ]; then
        log_error "SECURITY" "No report found. Run: security scan local"
        return 1
    fi
    cat "$REPORT_FILE"
}

# =============================================================================
# DISPLAY HELPERS
# =============================================================================
_pass() {
    local msg="$1" cat="$2"
    printf "  ${C_GREEN}[✓ PASS  ]${C_RESET} [%-8s] %s\n" "$cat" "$msg"
    echo "[$(timestamp)] [PASS] [$cat] $msg" >> "$LOG_SECURITY"
}

_find() {
    local sev="$1" msg="$2" cat="$3"
    local color="$C_RESET"
    case "$sev" in
        CRITICAL) color="$C_RED"    ;;
        HIGH)     color="$C_YELLOW" ;;
        MEDIUM)   color="$C_CYAN"   ;;
        LOW)      color="$C_RESET"  ;;
    esac
    printf "  ${color}[%-8s]${C_RESET} [%-8s] %s\n" "$sev" "$cat" "$msg"
    echo "[$(timestamp)] [$sev] [$cat] $msg" >> "$LOG_SECURITY"
}

# =============================================================================
# REPORT GENERATORS
# =============================================================================
_write_report() {
    local target="$1" crit="$2" high="$3" med="$4" low="$5" pass="$6"
    {
        echo "======================================================"
        echo "  SECURITY AUDIT REPORT"
        echo "  Generated : $(timestamp)"
        echo "  Target    : $target"
        echo "======================================================"
        echo ""
        echo "  FINDINGS SUMMARY:"
        printf "  %-12s %s\n" "CRITICAL:"  "$crit  ← fix immediately"
        printf "  %-12s %s\n" "HIGH:"      "$high  ← fix this week"
        printf "  %-12s %s\n" "MEDIUM:"    "$med   ← fix this month"
        printf "  %-12s %s\n" "LOW:"       "$low   ← nice to have"
        printf "  %-12s %s\n" "PASSED:"    "$pass"
        echo ""
        echo "  DETAILED FINDINGS (from security_events.log):"
        echo "------------------------------------------------------"
        grep -v "\[PASS\]\|\[SUCCESS\]" "$LOG_SECURITY" 2>/dev/null | tail -30 | \
            sed 's/\[20[0-9-]* [0-9:]*\] //' || echo "  (no findings)"
        echo ""
        echo "  See docs/SECURITY_GUIDE.md for fix instructions."
        echo "======================================================"
    } > "$REPORT_FILE"
}

_write_remediation_guide() {
    cat > "$REMEDIATION_FILE" << 'EOF'
# Security Remediation Guide
# Generated by noobtech-devops security scan

## CRITICAL Priority — Fix Immediately

### Disable Root SSH Login
```bash
sudo sed -i 's/#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
# Verify:
grep PermitRootLogin /etc/ssh/sshd_config
```

### Remove Non-Root Users with UID 0
```bash
# Find them:
awk -F: '$3==0 && $1!="root"{print $1}' /etc/passwd
# Remove sudo (safer than deleting):
sudo gpasswd -d <username> sudo
```

## HIGH Priority — Fix This Week

### Enable Key-Only SSH (Disable Password Auth)
```bash
sudo sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd
```

### Enable UFW Firewall
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
sudo ufw status
```

### Update All Packages
```bash
sudo apt update && sudo apt upgrade -y
sudo apt autoremove -y
```

### Install fail2ban (Brute Force Protection)
```bash
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban
sudo fail2ban-client status
```

## MEDIUM Priority — Fix This Month

### Install auditd (Compliance Logging)
```bash
sudo apt install -y auditd
sudo systemctl enable --now auditd
# View audit log:
sudo ausearch -m LOGIN --start today
```

### Change SSH Default Port
```bash
sudo sed -i 's/#*Port 22/Port 2222/' /etc/ssh/sshd_config
sudo systemctl restart sshd
# Update firewall:
sudo ufw allow 2222/tcp
sudo ufw delete allow 22/tcp
```

### Review Sudo Users
```bash
getent group sudo          # List all sudo users
sudo gpasswd -d <user> sudo  # Remove unnecessary users
```

## LOW Priority — Nice to Have

### Disable IPv6 if Unused
```bash
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### Install Rootkit Detection
```bash
sudo apt install -y rkhunter
sudo rkhunter --check --sk
```

## Compliance Checklist (CIS Benchmark Subset)
- [ ] SSH root login disabled
- [ ] Password authentication disabled (key-only)
- [ ] UFW firewall active with default deny
- [ ] All packages up to date (< 7 days)
- [ ] auditd installed and running
- [ ] fail2ban installed and running
- [ ] No accounts with empty passwords
- [ ] No non-root users with UID 0
- [ ] SSH keys have 600 permissions
- [ ] No dangerous ports open (23/21/25/111)
EOF
    log_info "SECURITY" "Remediation guide written: docs/SECURITY_GUIDE.md"
}
