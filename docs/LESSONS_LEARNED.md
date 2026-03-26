# Lessons Learned

## Technical Challenges & Solutions

### 1. set -e kills scripts silently on grep with no match
**Problem:** `grep "pattern" file` returns exit code 1 when the pattern is not found. Under `set -e`, this silently kills the entire script with no error message.

**Symptom:** Security scan stopped after [1/5] with no output.

**Fix:** Append `|| true` to any `grep` where "no match" is a valid (non-error) outcome:
```bash
# WRONG — kills script when PermitRootLogin is not set:
root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}')

# CORRECT:
root_login=$(grep "^PermitRootLogin" /etc/ssh/sshd_config | awk '{print $2}') || true
```

**Lesson:** Under `set -e`, only use `&&` shortcircuiting for things that MUST succeed. Use `if/then` or `|| true` for optional checks.

### 2. && shortcircuit returns 1 under set -e
**Problem:** `[ condition ] && { do_something; }` returns exit code 1 when the condition is false. This is standard shell behavior, but under `set -e` it kills the script.

**Symptom:** `log_debug` calls would silently kill the script because `[ false ] && { echo debug; }` returns 1.

**Fix:** Replace `&&` shortcircuits with `if/then`:
```bash
# WRONG:
log_debug() { [ "$VERBOSE" = "true" ] && echo "$1"; }

# CORRECT:
log_debug() { if [ "$VERBOSE" = "true" ]; then echo "$1"; fi; }
```

### 3. case/esac with no matching arm returns 1
**Problem:** A `case "$var" in ... esac` block with no `*)` catch-all returns exit code 1 when nothing matches. Fatal under `set -e`.

**Fix:** Always include `*) : ;;` (colon is bash's no-op command) as a catch-all.

### 4. Sourcing a script re-runs its main() function
**Problem:** `source modules/config.sh` would re-trigger `main "$@"` if the source guard wasn't in place.

**Fix:** Guard main execution with:
```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```
This means: only run `main` if this script is being executed directly, not sourced.

### 5. YAML parsing in bash needs careful awk patterns
**Problem:** Bash has no native YAML parser. Using simple `grep hostname:` matched both `- hostname:` and `ssh_key: ~/.ssh/...hostname/...`.

**Fix:** Use anchored awk patterns that match exact indentation:
```bash
# Finds "- hostname: prod-web-01" (list item)
/- hostname:/  { hostname=$NF }
# Finds "    ip: 10.0.0.1" (indented field — 4 spaces)
/^    ip:/     { ip=$NF }
```

## What I Would Do Differently

1. **Write tests first** — Testing each function in isolation before integrating would have caught the `grep || true` issue much earlier.

2. **Log early and often** — The silent failures under `set -e` were hard to debug without verbose output. Adding `trap 'echo "Error at line $LINENO"' ERR` during development helped enormously.

3. **Separate concerns sooner** — The main script grew too large before I split into modules. Starting with the module structure from day one would be cleaner.

4. **Document the "why" not just the "what"** — Comments explaining *why* a design decision was made (like `|| true` after grep) are more valuable than comments explaining what the code does.
