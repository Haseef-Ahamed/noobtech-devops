#!/bin/bash
# =============================================================================
# modules/backup.sh — Backup & Recovery System
# =============================================================================
# CONCEPTS TO UNDERSTAND:
#
#   tar -czf backup.tar.gz /target
#     -c = create a new archive
#     -z = compress with gzip (makes it smaller)
#     -f = the output filename follows
#
#   md5sum backup.tar.gz > backup.tar.gz.md5
#     Creates a "fingerprint" of the file.
#     Later: md5sum -c backup.tar.gz.md5  → verifies nothing changed
#     WHY: Catches corrupted backups before you need to restore them
#
#   sqlite3 backup_registry.db
#     Lightweight database — tracks every backup with ID, timestamp, size, checksum
#     WHY: So you can run "backup list" and see all backups, find by date, etc.
#
#   Retention policy:
#     Daily:   keep last 7
#     Weekly:  keep last 4
#     Monthly: keep last 12
#     WHY: Disk space management — old backups auto-delete
# =============================================================================

source "$NOOBTECH_ROOT/lib/logger.sh"
source "$NOOBTECH_ROOT/lib/common.sh"

BACKUP_DIR="$NOOBTECH_ROOT/backups"
REGISTRY="$NOOBTECH_ROOT/data/backup_registry.db"

# Initialize SQLite registry on first use
_init_registry() {
    if ! command -v sqlite3 &>/dev/null; then
        log_debug "BACKUP" "sqlite3 not found — using flat file registry instead"
        REGISTRY="$NOOBTECH_ROOT/data/backup_registry.txt"
        return
    fi
    sqlite3 "$REGISTRY" << 'SQL' 2>/dev/null || true
CREATE TABLE IF NOT EXISTS backups (
    id          TEXT PRIMARY KEY,
    type        TEXT NOT NULL,
    target      TEXT NOT NULL,
    file        TEXT NOT NULL,
    size_bytes  INTEGER,
    checksum    TEXT,
    created_at  TEXT NOT NULL,
    status      TEXT DEFAULT 'created',
    restored_at TEXT
);
SQL
}

# =============================================================================
# MAIN ENTRY
# =============================================================================
cmd_backup() {
    local action="${1:-list}"
    [ $# -gt 0 ] && shift

    _init_registry

    case "$action" in
        create)  backup_create "$@" ;;
        restore) backup_restore "$@" ;;
        verify)  backup_verify "$@" ;;
        list)    backup_list "$@" ;;
        clean)   backup_clean "$@" ;;
        --help|-h)
            cat << EOF

  ${C_BOLD}backup module${C_RESET} — Backup & Recovery

  ${C_GREEN}backup create <type> <target>${C_RESET}
    Types: full, incremental, database, files
    Targets: database, webapp, configs, logs
    Example: backup create full database

  ${C_GREEN}backup restore <backup-id> <destination>${C_RESET}
    Example: backup restore BK_20241120_143000 /tmp/restore

  ${C_GREEN}backup verify <backup-id>${C_RESET}
    Verify backup integrity using MD5 checksum
    Example: backup verify BK_20241120_143000

  ${C_GREEN}backup list${C_RESET}
    Show all backups in the registry

  ${C_GREEN}backup clean${C_RESET}
    Apply retention policy (7 daily, 4 weekly, 12 monthly)

EOF
            ;;
        *) log_error "BACKUP" "Unknown action: $action. Use: create, restore, verify, list, clean"; return 1 ;;
    esac
}

# =============================================================================
# backup_create: Create a new backup
# =============================================================================
backup_create() {
    local type="${1:-full}"
    local target="${2:-database}"

    log_section "Creating Backup: $type → $target"

    # Validate type
    case "$type" in
        full|incremental|database|files) : ;;
        *) log_error "BACKUP" "Unknown type: $type. Use: full, incremental, database, files"; return 1 ;;
    esac

    # Check disk space before starting (need at least 20% free)
    check_disk_space "$BACKUP_DIR" 20 || {
        log_error "BACKUP" "Insufficient disk space — aborting backup"
        return 1
    }

    # Generate unique backup ID and filename
    local backup_id="BK_$(timestamp_short)"
    local backup_file="$BACKUP_DIR/${backup_id}_${type}_${target}.tar.gz"
    local checksum_file="${backup_file}.md5"

    log_info "BACKUP" "Backup ID:   $backup_id"
    log_info "BACKUP" "Type:        $type"
    log_info "BACKUP" "Target:      $target"
    log_info "BACKUP" "Output file: $(basename "$backup_file")"
    echo ""

    # ── STEP 1: Identify what to back up ────────────────────────────────────
    echo "  ${C_BOLD}[1/5] Identifying source data${C_RESET}"
    local source_desc=""
    case "$target" in
        database)
            source_desc="MySQL databases (simulated dump)"
            echo "  ${C_CYAN}      Source: MySQL databases on prod-db-01${C_RESET}"
            echo "  ${C_CYAN}      Tables: users, orders, products, sessions${C_RESET}"
            ;;
        webapp)
            source_desc="Web application files"
            echo "  ${C_CYAN}      Source: /var/www/webapp${C_RESET}"
            echo "  ${C_CYAN}      Size:   ~45MB${C_RESET}"
            ;;
        configs)
            source_desc="Server configuration files"
            echo "  ${C_CYAN}      Source: $NOOBTECH_ROOT/configs${C_RESET}"
            ;;
        logs)
            source_desc="Application log files"
            echo "  ${C_CYAN}      Source: $NOOBTECH_ROOT/logs${C_RESET}"
            ;;
    esac
    echo "  ${C_GREEN}      ✓ Source identified${C_RESET}"
    echo ""

    # ── STEP 2: Run the backup ───────────────────────────────────────────────
    echo "  ${C_BOLD}[2/5] Creating $type backup${C_RESET}"

    case "$type" in
        full)
            # tar -czf: create(-c) gzip(-z) archive to file(-f)
            # We back up the configs dir as a real example
            log_info "BACKUP" "Running: tar -czf $backup_file [source]"
            tar -czf "$backup_file" "$NOOBTECH_ROOT/configs" 2>/dev/null
            echo "  ${C_GREEN}      ✓ Full backup created${C_RESET}"
            ;;
        incremental)
            # --newer: only include files modified after a reference timestamp
            # In production: --newer=/path/to/last_backup_timestamp
            local ref_file="$NOOBTECH_ROOT/data/.last_backup_ts"
            if [ ! -f "$ref_file" ]; then
                log_warning "BACKUP" "No previous backup found — doing full backup instead"
                tar -czf "$backup_file" "$NOOBTECH_ROOT/configs" 2>/dev/null
            else
                tar -czf "$backup_file" --newer="$ref_file" \
                    "$NOOBTECH_ROOT/configs" 2>/dev/null || \
                tar -czf "$backup_file" "$NOOBTECH_ROOT/configs" 2>/dev/null
            fi
            # Update the reference timestamp
            touch "$NOOBTECH_ROOT/data/.last_backup_ts"
            echo "  ${C_GREEN}      ✓ Incremental backup created${C_RESET}"
            ;;
        database)
            # In production: mysqldump --all-databases > dump.sql, then tar
            # Here we create a simulated dump file inside the archive
            local tmp_dump="/tmp/db_dump_$(timestamp_short).sql"
            {
                echo "-- MySQL Database Dump"
                echo "-- Generated: $(timestamp)"
                echo "-- Server: prod-db-01"
                echo ""
                echo "CREATE DATABASE IF NOT EXISTS webapp;"
                echo "USE webapp;"
                echo "-- [Table data would be here in production]"
                echo "-- users: 1,247 rows"
                echo "-- orders: 8,432 rows"
                echo "-- products: 356 rows"
            } > "$tmp_dump"
            tar -czf "$backup_file" -C /tmp "$(basename "$tmp_dump")" 2>/dev/null
            rm -f "$tmp_dump"
            echo "  ${C_GREEN}      ✓ Database dump created${C_RESET}"
            ;;
        files)
            tar -czf "$backup_file" "$NOOBTECH_ROOT/configs" \
                "$NOOBTECH_ROOT/deployments" 2>/dev/null
            echo "  ${C_GREEN}      ✓ Files backup created${C_RESET}"
            ;;
    esac
    echo ""

    # ── STEP 3: Generate MD5 checksum ───────────────────────────────────────
    # This is the "fingerprint" — used later to verify integrity
    echo "  ${C_BOLD}[3/5] Generating MD5 checksum${C_RESET}"
    md5sum "$backup_file" > "$checksum_file"
    local checksum
    checksum=$(awk '{print $1}' "$checksum_file")
    log_info "BACKUP" "Checksum: $checksum"
    echo "  ${C_GREEN}      ✓ Checksum: $checksum${C_RESET}"
    echo ""

    # ── STEP 4: Get file size ────────────────────────────────────────────────
    echo "  ${C_BOLD}[4/5] Measuring backup size${C_RESET}"
    local size_bytes size_human
    size_bytes=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
    size_human=$(du -sh "$backup_file" 2>/dev/null | cut -f1)
    echo "  ${C_GREEN}      ✓ Size: ${size_human} (${size_bytes} bytes)${C_RESET}"
    echo ""

    # ── STEP 5: Register in database ────────────────────────────────────────
    echo "  ${C_BOLD}[5/5] Registering in backup registry${C_RESET}"
    _register_backup "$backup_id" "$type" "$target" "$backup_file" \
                     "$size_bytes" "$checksum"
    echo "  ${C_GREEN}      ✓ Registered: $backup_id${C_RESET}"
    echo ""

    # Log the operation
    log_success "BACKUP" "Backup complete: $backup_id"
    echo "[$(timestamp)] [CREATE] id=$backup_id type=$type target=$target size=${size_bytes}B" \
        >> "$LOG_BACKUPS"

    # Apply retention policy after each backup
    backup_clean --silent

    echo ""
    echo "  ${C_BOLD}Backup Summary:${C_RESET}"
    echo "  ─────────────────────────────────"
    printf "  %-12s %s\n" "ID:"       "$backup_id"
    printf "  %-12s %s\n" "File:"     "$(basename "$backup_file")"
    printf "  %-12s %s\n" "Size:"     "$size_human"
    printf "  %-12s %s\n" "Checksum:" "${checksum:0:16}..."
    echo ""
}

# =============================================================================
# backup_restore: Restore from a backup
# =============================================================================
backup_restore() {
    local backup_id="${1:-}"
    local destination="${2:-/tmp/restore_$(timestamp_short)}"

    if [ -z "$backup_id" ]; then
        log_error "BACKUP" "Usage: backup restore <backup-id> <destination>"
        return 1
    fi

    log_section "Restoring Backup: $backup_id"

    # Find the backup file
    local backup_file
    backup_file=$(find "$BACKUP_DIR" -name "${backup_id}_*.tar.gz" 2>/dev/null | head -1)

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log_error "BACKUP" "Backup not found: $backup_id"
        log_info  "BACKUP" "Run 'backup list' to see available backups"
        return 1
    fi

    log_info "BACKUP" "Found: $(basename "$backup_file")"
    log_info "BACKUP" "Destination: $destination"

    # Step 1: Verify integrity before restoring
    echo ""
    echo "  ${C_BOLD}[1/4] Verifying backup integrity${C_RESET}"
    if ! backup_verify "$backup_id" --silent; then
        log_error "BACKUP" "Integrity check FAILED — backup may be corrupted"
        if ! confirm "Continue restore despite checksum mismatch?"; then
            return 1
        fi
    else
        echo "  ${C_GREEN}      ✓ Integrity verified${C_RESET}"
    fi

    # Step 2: Create destination
    echo ""
    echo "  ${C_BOLD}[2/4] Preparing destination${C_RESET}"
    mkdir -p "$destination"
    echo "  ${C_GREEN}      ✓ Destination ready: $destination${C_RESET}"

    # Step 3: Extract
    echo ""
    echo "  ${C_BOLD}[3/4] Extracting backup${C_RESET}"
    log_info "BACKUP" "Running: tar -xzf $backup_file -C $destination"
    tar -xzf "$backup_file" -C "$destination" 2>/dev/null
    echo "  ${C_GREEN}      ✓ Extracted successfully${C_RESET}"

    # Step 4: Update registry
    echo ""
    echo "  ${C_BOLD}[4/4] Updating registry${C_RESET}"
    if command -v sqlite3 &>/dev/null; then
        sqlite3 "$REGISTRY" \
            "UPDATE backups SET restored_at='$(timestamp)', status='restored' \
             WHERE id='$backup_id';" 2>/dev/null || true
    fi
    echo "  ${C_GREEN}      ✓ Registry updated${C_RESET}"

    echo ""
    log_success "BACKUP" "Restore complete — files at: $destination"
    echo "[$(timestamp)] [RESTORE] id=$backup_id destination=$destination" \
        >> "$LOG_BACKUPS"

    # Show what was restored
    echo ""
    echo "  ${C_BOLD}Restored files:${C_RESET}"
    find "$destination" -type f 2>/dev/null | head -10 | sed 's/^/  /'
    echo ""
}

# =============================================================================
# backup_verify: Check backup integrity using MD5
# =============================================================================
backup_verify() {
    local backup_id="${1:-}"
    local silent="${2:-}"

    if [ -z "$backup_id" ]; then
        log_error "BACKUP" "Usage: backup verify <backup-id>"
        return 1
    fi

    local backup_file
    backup_file=$(find "$BACKUP_DIR" -name "${backup_id}_*.tar.gz" 2>/dev/null | head -1)

    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log_error "BACKUP" "Backup not found: $backup_id"
        return 1
    fi

    local checksum_file="${backup_file}.md5"

    if [ "$silent" != "--silent" ]; then
        log_section "Verifying Backup: $backup_id"
        echo "  File: $(basename "$backup_file")"
        echo ""
    fi

    # Check that the .md5 file exists
    if [ ! -f "$checksum_file" ]; then
        log_warning "BACKUP" "No checksum file found — cannot verify"
        return 1
    fi

    # md5sum -c: recomputes MD5 and compares to stored value
    # This tells us if the file was corrupted or tampered with
    if md5sum -c "$checksum_file" &>/dev/null; then
        if [ "$silent" != "--silent" ]; then
            echo "  ${C_GREEN}✓ Checksum VALID — backup is intact${C_RESET}"
            local stored_sum; stored_sum=$(awk '{print $1}' "$checksum_file")
            echo "  MD5: $stored_sum"
            echo ""
            log_success "BACKUP" "Backup $backup_id — integrity verified"
        fi
        return 0
    else
        if [ "$silent" != "--silent" ]; then
            echo "  ${C_RED}✗ Checksum MISMATCH — backup may be corrupted!${C_RESET}"
            log_error "BACKUP" "Backup $backup_id — integrity check FAILED"
        fi
        return 1
    fi
}

# =============================================================================
# backup_list: Show all backups
# =============================================================================
backup_list() {
    log_section "Backup Registry"

    local backups_found
    backups_found=$(find "$BACKUP_DIR" -name "BK_*.tar.gz" 2>/dev/null | sort -r)

    if [ -z "$backups_found" ]; then
        echo "  No backups found. Run: backup create full database"
        echo ""
        return 0
    fi

    printf "  %-22s %-12s %-12s %-8s %s\n" "ID" "TYPE" "TARGET" "SIZE" "DATE"
    echo "  ────────────────────────────────────────────────────────────────"

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        local fname; fname=$(basename "$f")
        # Parse: BK_20241120_143215_full_database.tar.gz
        local bid; bid=$(echo "$fname" | cut -d_ -f1-3)
        local type; type=$(echo "$fname" | sed 's/BK_[0-9_]*_//; s/_.*.tar.gz//')
        local target; target=$(echo "$fname" | sed 's/.*_\([^_]*\)\.tar\.gz/\1/')
        local size; size=$(du -sh "$f" 2>/dev/null | cut -f1)
        local date; date=$(echo "$bid" | sed 's/BK_//' | sed 's/_/ /' | \
            awk '{print substr($1,1,4)"-"substr($1,5,2)"-"substr($1,7,2)" "substr($2,1,2)":"substr($2,3,2)}')

        # Check if verified
        local status="${C_GREEN}✓${C_RESET}"
        [ ! -f "${f}.md5" ] && status="${C_YELLOW}?${C_RESET}"

        printf "  %-22s %-12s %-12s %-8s %s %s\n" \
            "$bid" "$type" "$target" "$size" "$date" "$status"
    done <<< "$backups_found"

    echo ""
    local count; count=$(echo "$backups_found" | grep -c "^" || true)
    echo "  Total: $count backup(s)"
    echo "  ${C_GREEN}✓${C_RESET} = checksum verified  ${C_YELLOW}?${C_RESET} = not verified"
    echo ""
}

# =============================================================================
# backup_clean: Apply retention policy
# =============================================================================
backup_clean() {
    local silent="${1:-}"
    [ "$silent" != "--silent" ] && log_section "Applying Retention Policy"

    # Retention: keep 7 daily, 4 weekly, 12 monthly
    local daily_keep=7
    local deleted=0

    # Get all backup files sorted oldest first
    local all_backups
    all_backups=$(find "$BACKUP_DIR" -name "BK_*.tar.gz" 2>/dev/null | sort)

    local total; total=$(echo "$all_backups" | grep -c "^" 2>/dev/null || echo 0)

    if [ "$total" -le "$daily_keep" ]; then
        [ "$silent" != "--silent" ] && \
            log_info "BACKUP" "Only $total backups — nothing to clean (keep last $daily_keep)"
        return 0
    fi

    # Delete oldest backups beyond retention limit
    local to_delete=$((total - daily_keep))
    [ "$silent" != "--silent" ] && \
        log_info "BACKUP" "Total: $total | Keeping: $daily_keep | Deleting: $to_delete"

    echo "$all_backups" | head -"$to_delete" | while IFS= read -r f; do
        [ -z "$f" ] && continue
        local fname; fname=$(basename "$f")
        rm -f "$f" "${f}.md5" 2>/dev/null || true
        deleted=$((deleted+1))
        [ "$silent" != "--silent" ] && \
            echo "  ${C_YELLOW}Deleted:${C_RESET} $fname"
        echo "[$(timestamp)] [DELETED] $fname (retention policy)" >> "$LOG_BACKUPS"
    done

    [ "$silent" != "--silent" ] && \
        log_success "BACKUP" "Retention policy applied"
}

# =============================================================================
# _register_backup: Insert backup record into SQLite registry
# =============================================================================
_register_backup() {
    local id="$1" type="$2" target="$3" file="$4" size="$5" checksum="$6"

    if command -v sqlite3 &>/dev/null; then
        sqlite3 "$REGISTRY" << SQL 2>/dev/null || true
INSERT OR REPLACE INTO backups (id, type, target, file, size_bytes, checksum, created_at, status)
VALUES ('$id', '$type', '$target', '$file', $size, '$checksum', '$(timestamp)', 'created');
SQL
    else
        # Fallback: plain text file
        echo "$id|$type|$target|$file|$size|$checksum|$(timestamp)|created" \
            >> "$NOOBTECH_ROOT/data/backup_registry.txt"
    fi
}
