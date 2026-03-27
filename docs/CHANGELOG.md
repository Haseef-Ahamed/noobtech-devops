# Changelog

All notable changes follow [Conventional Commits](https://conventionalcommits.org).

## [1.0.0] — 2026-03-27

### Bug Fixes
- `fix:` health check always passes in local simulation mode
- `fix:` incremental backup now respects target parameter
- `fix:` suppress sqlite3 warning — downgrade to debug level
- `fix:` Security scan stops at [1/5] — grep returns exit 1 under set -e → add || true

### Added
- `feat:` GPG AES-256 encryption added to backup module
- `feat:` ssh_helper.sh for remote server operations
- `feat:` GitHub Actions CI pipeline

### Features
- `feat:` Initial project scaffold — full directory structure, .gitignore
- `feat:` lib/logger.sh — centralized logging with 6 levels + log rotation
- `feat:` lib/common.sh — shared utilities, YAML parser, dry-run support
- `feat:` servers.yaml — 9-server inventory (prod/staging/dev)
- `feat:` Main entry script with module router and global flags
- `feat:` config module — apply/check/remediate with drift detection
- `feat:` 5 config profiles — web_server, database, cache, firewall, users
- `feat:` deploy module — rolling, blue-green, canary strategies
- `feat:` deploy — auto-rollback on health check failure
- `feat:` backup module — full/incremental/database/files backup types
- `feat:` backup — MD5 integrity verification + retention policy
- `feat:` monitor module — ASCII dashboard, status table, daemon mode
- `feat:` monitor — real CPU/MEM/DISK from /proc/stat, free, df
- `feat:` security module — 14 checks across 5 categories
- `feat:` report module — daily/weekly/monthly HTML reports

### Documentation
- `docs:` README.md — installation, quick start, module reference
- `docs:` ARCHITECTURE.md — system design, data flow, decisions
- `docs:` USER_GUIDE.md — complete command reference with examples
- `docs:` DR_RUNBOOK.md — 5 disaster recovery scenarios
- `docs:` SECURITY_GUIDE.md — remediation steps for every finding type
- `docs:` LESSONS_LEARNED.md — bugs found, solutions, what to do differently
- `docs:` TESTING.md — full manual test suite
