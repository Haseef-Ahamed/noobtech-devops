# noobtech-devops

> Production-ready infrastructure automation platform for Noob Tech

A unified command-line tool that automates the six core tasks of a DevOps engineer: configuration management, deployment, backup, monitoring, security auditing, and reporting.

## Why this exists

Noob Tech had five manual pain points before this tool:
- Deployments took 2–3 hours and required direct SSH access to production
- No automated backups — a near data-loss incident triggered this project
- Outages were discovered by customers, not engineers
- No version control for server configurations
- Security audits were never done

This tool solves all five in a single command interface.

## Installation

```bash
git clone https://github.com/noobtech/noobtech-devops-platform.git
cd noobtech-devops-platform
chmod +x noobtech-devops
./noobtech-devops --help
```

**Requirements:** bash 4.0+, git, tar, md5sum, awk, ss (iproute2)  
**Optional:** sqlite3 (backup registry), gpg (backup encryption)

## Quick Start

```bash
# See all servers
./noobtech-devops server list

# Check a server's config drift
./noobtech-devops config check dev-web-01

# Deploy to staging
./noobtech-devops deploy webapp staging rolling

# Create a backup
./noobtech-devops backup create full database

# Live monitoring dashboard
./noobtech-devops monitor dashboard

# Security audit
./noobtech-devops security scan local

# Generate daily report
./noobtech-devops report generate daily
```

## Module Reference

| Module | Actions | Description |
|--------|---------|-------------|
| `server` | `list`, `info` | View infrastructure inventory |
| `config` | `apply`, `check`, `remediate` | Configuration management & drift detection |
| `deploy` | `<app> <env> [strategy]` | Rolling, Blue-Green, or Canary deployments |
| `backup` | `create`, `restore`, `verify`, `list` | Backup & recovery operations |
| `monitor` | `dashboard`, `status`, `start` | Health monitoring & alerting |
| `security` | `scan`, `report` | Security auditing & compliance |
| `report` | `generate <type>` | HTML reports: daily, weekly, monthly |

## Global Flags

```bash
--env=<dev|staging|production>   # Target environment
--verbose                         # Show debug output
--dry-run                         # Simulate without making changes
--help                            # Show help for any module
```

## Project Structure

```
noobtech-devops/
├── noobtech-devops      # Main entry script — start here
├── lib/
│   ├── logger.sh        # Centralized logging (all modules use this)
│   └── common.sh        # Shared utilities, YAML parser helpers
├── modules/
│   ├── config.sh        # Configuration management
│   ├── deploy.sh        # Deployment pipeline
│   ├── backup.sh        # Backup & recovery
│   ├── monitor.sh       # Health monitoring
│   ├── security.sh      # Security auditing
│   └── report.sh        # Report generation
├── configs/             # Server configuration profiles
├── servers.yaml         # Infrastructure inventory (source of truth)
├── deployments/         # Deployment manifests per app/environment
├── logs/                # All operation logs (auto-rotated 30 days)
├── data/                # Registries, metrics, audit reports
├── backups/             # Backup archives + checksums
├── monitoring/metrics/  # Historical CSV metrics per server
└── docs/                # Full documentation
```

## Environment Variables

```bash
NOOBTECH_ENV=production      # Default environment
NOOBTECH_VERBOSE=true        # Enable debug output
NOOBTECH_DRY_RUN=true        # Safe simulation mode
NOOBTECH_ROOT=/custom/path   # Override project root
```

## License

MIT — Noob Tech Internal Tool
