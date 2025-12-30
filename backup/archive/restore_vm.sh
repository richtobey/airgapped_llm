#!/bin/bash
# Restore VM from backup
# Can restore to UTM (Mac) or KVM (Linux) format

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}WARN: $*${NC}"
}

# Parse arguments
BACKUP_DIR=""
RESTORE_DEST=""
VERIFY_BACKUP=true
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-verify)
            VERIFY_BACKUP=false
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 BACKUP_DIR RESTORE_DEST [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  BACKUP_DIR    Backup directory (created by backup_vm.sh)"
            echo "  RESTORE_DEST  Destination path for restored VM disk"
            echo ""
            echo "Options:"
            echo "  --no-verify    Skip backup verification before restore"
            echo "  --force        Overwrite existing destination file"
            echo ""
            echo "Example:"
            echo "  $0 /Volumes/ExternalDrive/backups/popos-backup-20240101-120000 ~/restored-vm.qcow2"
            exit 0
            ;;
        *)
            if [[ -z "$BACKUP_DIR" ]]; then
                BACKUP_DIR="$1"
            elif [[ -z "$RESTORE_DEST" ]]; then
                RESTORE_DEST="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$BACKUP_DIR" ]] || [[ -z "$RESTORE_DEST" ]]; then
    error "Usage: $0 BACKUP_DIR RESTORE_DEST [OPTIONS]"
fi

# Check backup directory
if [[ ! -d "$BACKUP_DIR" ]]; then
    error "Backup directory not found: $BACKUP_DIR"
fi

# Check for metadata
METADATA_FILE="$BACKUP_DIR/backup-metadata.json"
if [[ ! -f "$METADATA_FILE" ]]; then
    error "Backup metadata not found. Invalid backup directory?"
fi

# Verify backup if requested
if [[ "$VERIFY_BACKUP" == "true" ]]; then
    info "Verifying backup before restore..."
    if [[ -f "$SCRIPT_DIR/verify_backup.sh" ]]; then
        if ! "$SCRIPT_DIR/verify_backup.sh" "$BACKUP_DIR"; then
            error "Backup verification failed. Use --no-verify to skip (not recommended)"
        fi
    else
        warn "verify_backup.sh not found, skipping verification"
    fi
fi

# Check if destination exists
if [[ -f "$RESTORE_DEST" ]] && [[ "$FORCE" != "true" ]]; then
    error "Destination file exists: $RESTORE_DEST (use --force to overwrite)"
fi

# Create destination directory if needed
RESTORE_DIR=$(dirname "$RESTORE_DEST")
if [[ ! -d "$RESTORE_DIR" ]]; then
    mkdir -p "$RESTORE_DIR" || error "Cannot create destination directory: $RESTORE_DIR"
fi

# Find backup file
BACKUP_FILE=""
if [[ -f "$BACKUP_DIR/vm-disk.qcow2.gz" ]]; then
    BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2.gz"
    COMPRESSED=true
elif [[ -f "$BACKUP_DIR/vm-disk.qcow2" ]]; then
    BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2"
    COMPRESSED=false
elif ls "$BACKUP_DIR/vm-disk.qcow2.part"* 1>/dev/null 2>&1; then
    # Split backup
    BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2.part"
    COMPRESSED=false
    SPLIT=true
else
    error "Backup file not found in: $BACKUP_DIR"
fi

info "Backup directory: $BACKUP_DIR"
info "Restore destination: $RESTORE_DEST"
info "Backup file: $BACKUP_FILE"

# Check available space
AVAILABLE_SPACE=$(df -h "$RESTORE_DIR" | tail -1 | awk '{print $4}')
info "Available space: $AVAILABLE_SPACE"

# Read metadata
VM_NAME=$(grep -o '"vm_name": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4 || echo "unknown")
BACKUP_DATE=$(grep -o '"backup_date": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4 || echo "unknown")
info "VM Name: $VM_NAME"
info "Backup Date: $BACKUP_DATE"

# Restore
info "Starting restore (this may take a while)..."

if [[ "${SPLIT:-false}" == "true" ]]; then
    # Restore from split files
    info "Restoring from split backup files..."
    cat "$BACKUP_DIR/vm-disk.qcow2.part"* > "$RESTORE_DEST"
elif [[ "$COMPRESSED" == "true" ]]; then
    # Restore from compressed backup
    info "Decompressing and restoring..."
    if command -v pigz >/dev/null 2>&1; then
        pigz -dc "$BACKUP_FILE" > "$RESTORE_DEST"
    else
        gunzip -c "$BACKUP_FILE" > "$RESTORE_DEST"
    fi
else
    # Restore from uncompressed backup
    info "Copying backup file..."
    cp "$BACKUP_FILE" "$RESTORE_DEST"
fi

# Verify restored file
RESTORED_SIZE=$(stat -f%z "$RESTORE_DEST" 2>/dev/null || stat -c%s "$RESTORE_DEST" 2>/dev/null)
ORIGINAL_SIZE=$(grep -o '"source_size_bytes": [0-9]*' "$METADATA_FILE" | cut -d' ' -f2 || echo "0")

if [[ "$RESTORED_SIZE" != "$ORIGINAL_SIZE" ]]; then
    warn "Restored file size ($RESTORED_SIZE) differs from original ($ORIGINAL_SIZE)"
    warn "This may be normal if the original disk was sparse"
else
    info "Restored file size matches original"
fi

# Set permissions
chmod 644 "$RESTORE_DEST" 2>/dev/null || true

info ""
info "Restore completed successfully!"
info "Restored VM disk: $RESTORE_DEST"
info "Size: $(du -h "$RESTORE_DEST" | cut -f1)"
info ""
info "Next steps:"
info "  - For UTM: Create new VM and attach this disk"
info "  - For KVM: Use ../kvm/setup_kvm_vm.sh to set up the VM"

