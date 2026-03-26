# Architecture — noobtech-devops

## System Design

```
User
 │
 ▼
noobtech-devops (main entry script)
 │   Parses: module, action, global flags
 │   Routes to correct module via case/esac
 │
 ├── lib/logger.sh      ← Loaded first by every module
 │     All output goes here before reaching terminal or log files
 │     Log levels: DEBUG → INFO → SUCCESS → WARNING → ERROR → CRITICAL
 │
 ├── lib/common.sh      ← Loaded second by every module
 │     Shared functions: confirm(), dry_run(), check_disk_space()
 │     YAML parser: get_servers_by_env(), get_server_field()
 │
 ├── modules/config.sh  ← config apply|check|remediate
 ├── modules/deploy.sh  ← deploy <app> <env> [strategy]
 ├── modules/backup.sh  ← backup create|restore|verify|list
 ├── modules/monitor.sh ← monitor dashboard|status|start
 ├── modules/security.sh← security scan|report
 └── modules/report.sh  ← report generate daily|weekly|monthly
```

## Key Design Decisions

### 1. Single entry point
One script (`noobtech-devops`) routes everything. No matter which feature you use, the command structure is always `./noobtech-devops <module> <action>`. This makes it easy for any engineer to discover and use.

### 2. Shared library pattern
Every module sources `lib/logger.sh` and `lib/common.sh` first. This means:
- Logging format is identical across all modules
- All operations go to `logs/operations.log` automatically
- Functions like `confirm()` and `dry_run()` work the same everywhere

### 3. set -euo pipefail
All scripts run with `set -euo pipefail` which means:
- `-e`: exit immediately on any error (prevents silent failures)
- `-u`: treat unset variables as errors (catches typos like `$PATHH`)
- `-o pipefail`: catch errors in piped commands (`cmd1 | cmd2`)

This required careful handling: any command that can return non-zero for valid reasons (grep with no match, diff finding differences) must have `|| true` appended.

### 4. Desired vs Actual State (Config Management)
The config module is built around the infrastructure-as-code concept:
```
configs/*.conf    = DESIRED state (what the server should be)
Applied on server = ACTUAL state (what the server currently is)
Drift             = Any difference between desired and actual
```
This is the same concept used by Ansible, Puppet, and Chef.

### 5. Deployment Safety Chain
Every deployment follows this sequence with no skippable steps:
```
Pre-check (disk, connectivity)
    → Backup current version
    → Stop service
    → Deploy new code
    → Start service
    → Health check (HTTP 200)
    → If fail: automatic rollback
```
The health check acts as an automatic gate — bad deployments never stay deployed.

### 6. Centralized Audit Trail
Every operation writes to `logs/operations.log` regardless of which module ran it. This creates a complete audit trail you can search with `grep` or `awk`.

## Data Flow

```
User command
    │
    ▼
noobtech-devops parses $1=module $2=action $3..=args
    │
    ▼
lib/logger.sh + lib/common.sh loaded
    │
    ▼
modules/<name>.sh loaded + cmd_<name>() called
    │
    ├── Reads:  servers.yaml, configs/*.conf
    ├── Writes: logs/*.log, data/*.log, reports/*.html
    └── Output: terminal (colored) + log file (plain text)
```

## Log File Structure

| File | What goes here |
|------|----------------|
| `logs/operations.log` | Every single operation — the master audit trail |
| `logs/deployments.log` | Deployment start/end events |
| `logs/backups.log` | Backup create/restore/delete events |
| `logs/config_changes.log` | Every config applied or changed |
| `logs/security_events.log` | All security scan findings |
| `logs/incidents.log` | WARNING and CRITICAL alerts |
| `logs/errors.log` | All ERROR and CRITICAL messages |

## Alert Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| CPU usage | > 80% | > 95% |
| Memory usage | > 75% | > 90% |
| Disk usage | > 85% | > 95% |
| Service down | — | Immediate |
| Response time | > 2s | > 5s |

## Deployment Strategies

| Strategy | How it works | Best for |
|----------|-------------|---------|
| Rolling | One server at a time | Most deployments |
| Blue-Green | Deploy to idle env, switch traffic | Zero-risk releases |
| Canary | 1 server first, monitor, then rest | Risky changes |
