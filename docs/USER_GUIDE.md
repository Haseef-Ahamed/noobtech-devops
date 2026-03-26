# User Guide — noobtech-devops

Complete command reference with examples for every module.

---

## server — Infrastructure Inventory

```bash
# List all 9 servers across all environments
./noobtech-devops server list

# Get detailed info on a specific server
./noobtech-devops server info prod-web-01
./noobtech-devops server info dev-db-01
```

---

## config — Configuration Management

```bash
# Apply a config profile to a server
./noobtech-devops config apply web_server dev-web-01
./noobtech-devops config apply database   dev-db-01
./noobtech-devops config apply cache      prod-cache-01
./noobtech-devops config apply firewall_rules prod-web-01
./noobtech-devops config apply users      dev-web-01

# Check for configuration drift (desired vs actual)
./noobtech-devops config check dev-web-01
./noobtech-devops config check prod-db-01

# Detect and fix all drift (asks for approval)
./noobtech-devops config remediate dev-web-01

# Simulate apply without making changes (safe to run anytime)
./noobtech-devops config apply web_server prod-web-01 --dry-run
```

**Available profiles:** `web_server`, `database`, `cache`, `firewall_rules`, `users`

---

## deploy — Application Deployment

```bash
# Rolling deployment (default) — one server at a time
./noobtech-devops deploy webapp staging
./noobtech-devops deploy webapp staging rolling

# Blue-Green — deploy to idle env, then switch traffic
./noobtech-devops deploy webapp staging blue-green

# Canary — 1 server first, monitor 10s, then rest
./noobtech-devops deploy webapp staging canary

# Production (requires manual 'yes' confirmation)
./noobtech-devops deploy webapp production rolling

# See what would happen without deploying
./noobtech-devops deploy webapp staging rolling --dry-run
```

**After each deployment:**
- Deployment ID logged to `data/deployment_history.log`
- HTML report saved to `reports/deploy_<timestamp>.html`
- Failed deployments auto-rollback before exiting

---

## backup — Backup & Recovery

```bash
# Create backups
./noobtech-devops backup create full     database   # full backup
./noobtech-devops backup create database database   # MySQL dump
./noobtech-devops backup create files    webapp     # app files
./noobtech-devops backup create incremental database # only changes

# See all backups
./noobtech-devops backup list

# Verify a backup hasn't been corrupted (uses MD5 checksum)
./noobtech-devops backup verify BK_20241120_143000

# Restore a backup
./noobtech-devops backup restore BK_20241120_143000 /tmp/restore

# Apply retention policy (auto-deletes old backups)
./noobtech-devops backup clean
```

---

## monitor — Health Monitoring

```bash
# Live ASCII dashboard (CPU/MEM/DISK bars + service status)
./noobtech-devops monitor dashboard

# One-time status check of all servers
./noobtech-devops monitor status

# Continuous monitoring daemon (Ctrl+C to stop)
./noobtech-devops monitor start

# Check every 60 seconds
./noobtech-devops monitor start 60
```

**Alert thresholds:**
- CPU > 80% → WARNING | > 95% → CRITICAL
- Memory > 75% → WARNING | > 90% → CRITICAL
- Disk > 85% → WARNING | > 95% → CRITICAL
- Service down → CRITICAL (auto-restart attempted)

---

## security — Security Auditing

```bash
# Scan local machine (runs real checks)
./noobtech-devops security scan local

# Scan a specific server (simulated for remote)
./noobtech-devops security scan prod-web-01

# Show last scan report
./noobtech-devops security report
```

**Output files:**
- `data/security_audit_report.txt` — findings with severity
- `docs/SECURITY_GUIDE.md` — step-by-step fix instructions

---

## report — HTML Reports

```bash
# Daily operations (deployments, backups, incidents)
./noobtech-devops report generate daily

# Weekly infrastructure summary
./noobtech-devops report generate weekly

# Monthly executive overview
./noobtech-devops report generate monthly
```

Reports are saved to `reports/` — open with any browser:
```bash
firefox reports/daily_report_*.html
xdg-open reports/weekly_report_*.html
```

---

## Tips for the Demo

**Show drift detection:**
```bash
./noobtech-devops config apply web_server dev-web-01   # Apply clean config
echo "worker_processes = 99" >> data/applied_configs/dev-web-01_web_server.conf  # Simulate drift
./noobtech-devops config check dev-web-01              # Shows the drift in red
./noobtech-devops config remediate dev-web-01          # Fix it (type 'yes')
./noobtech-devops config check dev-web-01              # Shows clean
```

**Show deployment rollback:**
The health check is random (90% success) — just re-run deploy until one fails:
```bash
./noobtech-devops deploy webapp staging rolling   # Run a few times
# When a health check fails, watch the automatic rollback happen
```

**Show logs:**
```bash
tail -20 logs/operations.log           # Full audit trail
cat data/deployment_history.log        # All deployments
cat data/security_audit_report.txt     # Last security report
```
