# Disaster Recovery Runbook
# noobtech-devops — Noob Tech Infrastructure

**Purpose:** Step-by-step recovery procedures when things go wrong.  
**Owner:** DevOps Team  
**RTO Target:** 2 hours | **RPO Target:** 24 hours

---

## Emergency Contacts

| Role | Contact | Escalation |
|------|---------|-----------|
| DevOps On-Call | devops@noobtech.com | Primary |
| CTO | cto@noobtech.com | If unresolved > 30 min |

---

## Scenario 1: Failed Deployment (Most Common)

**Symptoms:** Service returning errors after deploy, health check failing.

```bash
# Step 1: Check what deployed last
tail -20 data/deployment_history.log

# Step 2: Roll back immediately
./noobtech-devops deploy webapp production rolling --rollback

# Step 3: Verify service recovered
./noobtech-devops monitor status

# Step 4: Check logs for root cause
tail -50 logs/deployments.log
```

**Expected recovery time:** 5–10 minutes

---

## Scenario 2: Database Corruption / Data Loss

**Symptoms:** Application errors referencing database, missing records.

```bash
# Step 1: Stop writes immediately
# (prevents more corrupt data)
./noobtech-devops config apply database prod-db-01 --dry-run

# Step 2: Find most recent clean backup
./noobtech-devops backup list

# Step 3: Verify backup integrity BEFORE restoring
./noobtech-devops backup verify BK_<ID>

# Step 4: Restore to a temporary location first
./noobtech-devops backup restore BK_<ID> /tmp/db_restore

# Step 5: Inspect the restored data
ls -la /tmp/db_restore/
# Verify tables look correct before proceeding

# Step 6: Restore to production (requires confirmation prompt)
./noobtech-devops backup restore BK_<ID> /var/lib/mysql
```

**Expected recovery time:** 30–60 minutes depending on backup size  
**Data loss:** Up to 24 hours (daily backup frequency)

---

## Scenario 3: Server Completely Down

**Symptoms:** SSH fails, monitor shows server offline.

```bash
# Step 1: Confirm which server is down
./noobtech-devops monitor status

# Step 2: Check if it's a single server or cluster failure
# If only one web server is down, others handle traffic (rolling design)

# Step 3: Attempt restart via cloud console (AWS/manual)
# This tool cannot SSH to a dead server — use cloud provider console

# Step 4: Once server is back, re-apply configuration
./noobtech-devops config remediate <hostname>

# Step 5: Verify it's healthy
./noobtech-devops monitor status
```

**Expected recovery time:** 15–45 minutes

---

## Scenario 4: Configuration Drift Emergency

**Symptoms:** Service behaving differently than expected, security policies not applied.

```bash
# Step 1: See what drifted
./noobtech-devops config check <server>

# Step 2: Review what will change (safe — no changes yet)
./noobtech-devops config remediate <server> --dry-run

# Step 3: Apply fixes (will ask for confirmation)
./noobtech-devops config remediate <server>

# Step 4: Generate audit report
cat data/config_audit_report.txt
```

---

## Scenario 5: Security Breach Suspected

```bash
# Step 1: Run full security audit immediately
./noobtech-devops security scan local > /tmp/emergency_audit.txt

# Step 2: Check for CRITICAL findings
grep "CRITICAL" /tmp/emergency_audit.txt

# Step 3: Review recent operations (who did what)
grep "$(date +%Y-%m-%d)" logs/operations.log

# Step 4: Check for unauthorized config changes
cat logs/config_changes.log

# Step 5: Apply security hardening
./noobtech-devops config apply firewall_rules <server>
./noobtech-devops config apply users <server>

# Step 6: Escalate to CTO if breach confirmed
```

---

## Recovery Time Objectives (RTO) Testing

Run this monthly to verify recovery procedures actually work:

```bash
# Test 1: Verify a backup can actually be restored
./noobtech-devops backup create full database
LATEST=$(ls -t backups/BK_*.tar.gz | head -1 | xargs basename | cut -d_ -f1-3)
./noobtech-devops backup verify $LATEST
./noobtech-devops backup restore $LATEST /tmp/rto_test
echo "RTO Test: $(ls /tmp/rto_test | wc -l) files restored"

# Test 2: Verify monitoring detects issues
./noobtech-devops monitor status

# Test 3: Verify deployment rollback works
./noobtech-devops deploy webapp staging rolling
```

---

## Post-Incident Checklist

After any incident is resolved:

- [ ] Root cause documented in `docs/LESSONS_LEARNED.md`
- [ ] All logs backed up from incident window
- [ ] Monitoring thresholds adjusted if needed
- [ ] Security scan run to confirm no breach
- [ ] Backup verified to be clean (pre-incident)
- [ ] Team notified of resolution
- [ ] Runbook updated with any new steps discovered
