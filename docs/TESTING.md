# Testing Guide

## Manual Test Suite

Run all tests from the project root:

```bash
cd ~/noobtech-devops
```

### Foundation Tests
```bash
./noobtech-devops --help              # Should show full help menu
./noobtech-devops --version           # Should show: noobtech-devops v1.0.0
./noobtech-devops unknownmodule       # Should show: [ERROR] Unknown module
./noobtech-devops server list         # Should show all 9 servers
./noobtech-devops server info prod-web-01  # Should show server details
```

### Config Module Tests
```bash
./noobtech-devops config apply web_server dev-web-01      # Should succeed
./noobtech-devops config apply database dev-db-01         # Should succeed
./noobtech-devops config check dev-web-01                 # Should show OK (just applied)
./noobtech-devops config apply badprofile dev-web-01      # Should show [ERROR]
./noobtech-devops config check nonexistent-server         # Should show [ERROR]

# Drift detection test:
echo "bad_setting = yes" >> data/applied_configs/dev-web-01_web_server.conf
./noobtech-devops config check dev-web-01   # Should show [DRIFT] in red
# Restore:
./noobtech-devops config apply web_server dev-web-01
./noobtech-devops config check dev-web-01   # Should show OK again
```

### Deploy Module Tests
```bash
./noobtech-devops deploy webapp staging rolling     # Should succeed
./noobtech-devops deploy webapp staging blue-green  # Should succeed
./noobtech-devops deploy webapp staging canary      # Should succeed
./noobtech-devops deploy webapp staging badstrategy # Should show [ERROR]
./noobtech-devops deploy webapp dev rolling --dry-run  # Should simulate only
# Check history was logged:
cat data/deployment_history.log   # Should show entries
```

### Backup Module Tests
```bash
./noobtech-devops backup create full database       # Should create BK_*.tar.gz
./noobtech-devops backup create database database   # Should create DB dump
./noobtech-devops backup list                       # Should show backups
# Get the latest ID:
LATEST=$(ls -t backups/BK_*.tar.gz | head -1 | xargs basename | grep -oP 'BK_\d+_\d+')
./noobtech-devops backup verify $LATEST             # Should show: Checksum VALID
./noobtech-devops backup restore $LATEST /tmp/test_restore  # Should extract files
ls /tmp/test_restore                                # Should show files
```

### Monitor Module Tests
```bash
./noobtech-devops monitor dashboard   # Should show ASCII bars + server table
./noobtech-devops monitor status      # Should show all servers HEALTHY
# Check metrics were saved:
ls monitoring/metrics/    # Should have .csv files
```

### Security Module Tests
```bash
./noobtech-devops security scan local    # Should run all 5 categories
./noobtech-devops security report        # Should show saved report
cat data/security_audit_report.txt       # Should have findings
cat docs/SECURITY_GUIDE.md              # Should have fix instructions
```

### Report Module Tests
```bash
./noobtech-devops report generate daily    # Should create HTML file
./noobtech-devops report generate weekly   # Should create HTML file
./noobtech-devops report generate monthly  # Should create HTML file
ls reports/     # Should show .html files
# Open one to verify it renders:
xdg-open reports/daily_report_*.html 2>/dev/null || echo "Open manually in browser"
```

### Global Flags Tests
```bash
./noobtech-devops backup create full database --dry-run    # Should print [DRY-RUN] not create file
NOOBTECH_VERBOSE=true ./noobtech-devops server list        # Should show [DEBUG] lines
./noobtech-devops deploy webapp dev rolling --dry-run      # Should simulate, not deploy
```

## Checking Log Output
```bash
tail -30 logs/operations.log      # Last 30 operations
tail -10 logs/deployments.log     # Last deployment events
tail -10 logs/security_events.log # Last security findings
tail -10 logs/incidents.log       # Last alerts/warnings
```

## Expected Git History (15+ commits)
```bash
git log --oneline   # Should show 15+ commits with feat:/fix:/docs: prefixes
```
