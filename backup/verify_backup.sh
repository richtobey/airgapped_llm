#!/bin/bash
# Verify backup integrity
# Checks checksums and metadata validity

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    return 1
}

info() {
    echo -e "${GREEN}INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}WARN: $*${NC}"
}

# Parse arguments
BACKUP_DIR=""

if [[ $# -eq 0 ]]; then
    error "Usage: $0 BACKUP_DIR"
    exit 1
fi

BACKUP_DIR="$1"

if [[ ! -d "$BACKUP_DIR" ]]; then
    error "Backup directory not found: $BACKUP_DIR"
fi

info "Verifying backup: $BACKUP_DIR"

# Check for required files
METADATA_FILE="$BACKUP_DIR/backup-metadata.json"
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"

if [[ ! -f "$METADATA_FILE" ]]; then
    error "Metadata file not found: $METADATA_FILE"
fi

if [[ ! -f "$CHECKSUM_FILE" ]]; then
    error "Checksum file not found: $CHECKSUM_FILE"
fi

info "Metadata file: OK"
info "Checksum file: OK"

# Verify checksums
info "Verifying checksums..."
if sha256sum -c "$CHECKSUM_FILE" >/dev/null 2>&1; then
    info "Checksums: OK"
else
    error "Checksum verification failed!"
    exit 1
fi

# Check backup file exists (support both VM and physical system backups)
BACKUP_FILE=""
if [[ -f "$BACKUP_DIR/system-disk.img.gz" ]]; then
    BACKUP_FILE="$BACKUP_DIR/system-disk.img.gz"
    BACKUP_TYPE="physical"
elif [[ -f "$BACKUP_DIR/system-disk.img.xz" ]]; then
    BACKUP_FILE="$BACKUP_DIR/system-disk.img.xz"
    BACKUP_TYPE="physical"
elif [[ -f "$BACKUP_DIR/system-disk.img" ]]; then
    BACKUP_FILE="$BACKUP_DIR/system-disk.img"
    BACKUP_TYPE="physical"
elif [[ -f "$BACKUP_DIR/vm-disk.qcow2.gz" ]]; then
    BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2.gz"
    BACKUP_TYPE="vm"
elif [[ -f "$BACKUP_DIR/vm-disk.qcow2" ]]; then
    BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2"
    BACKUP_TYPE="vm"
elif ls "$BACKUP_DIR/vm-disk.qcow2.part"* 1>/dev/null 2>&1; then
    BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2.part*"
    BACKUP_TYPE="vm"
    info "Split backup detected (multiple files)"
else
    error "Backup file not found"
fi

if [[ -f "$BACKUP_FILE" ]] || [[ "$BACKUP_FILE" == *"*"* ]]; then
    info "Backup file(s): OK ($BACKUP_TYPE backup)"
else
    error "Backup file not found: $BACKUP_FILE"
fi

# Check for partition table backup (physical system backups)
if [[ "$BACKUP_TYPE" == "physical" ]]; then
    if [[ -f "$BACKUP_DIR/partition-table.bin" ]] || [[ -f "$BACKUP_DIR/partition-table.txt" ]]; then
        info "Partition table backup: OK"
    else
        warn "Partition table backup not found (may be included in disk image)"
    fi
fi

# Validate metadata JSON
if command -v python3 >/dev/null 2>&1; then
    if python3 -m json.tool "$METADATA_FILE" >/dev/null 2>&1; then
        info "Metadata JSON: Valid"
    else
        error "Metadata JSON: Invalid"
    fi
fi

# Display backup info
info ""
info "Backup Information:"
if command -v jq >/dev/null 2>&1; then
    # Try to get hostname (physical) or vm_name (VM)
    if jq -e '.hostname' "$METADATA_FILE" >/dev/null 2>&1; then
        jq -r '"Hostname: \(.hostname)\nBackup Date: \(.backup_date)\nSource Size: \(.source_size_human)\nBackup Size: \(.backup_size_human)\nCompressed: \(.compressed)\nCompression Type: \(.compression_type // "none")"' "$METADATA_FILE"
    else
        jq -r '"VM Name: \(.vm_name)\nBackup Date: \(.backup_date)\nSource Size: \(.source_size_human)\nBackup Size: \(.backup_size_human)\nCompressed: \(.compressed)"' "$METADATA_FILE"
    fi
else
    # Fallback to grep
    if grep -q '"hostname"' "$METADATA_FILE"; then
        grep -E '"hostname"|"backup_date"|"source_size_human"|"backup_size_human"|"compressed"|"compression_type"' "$METADATA_FILE" | sed 's/.*"\([^"]*\)": "\([^"]*\)".*/\1: \2/' | sed 's/.*"\([^"]*\)": \([^,}]*\).*/\1: \2/'
    else
        grep -E '"vm_name"|"backup_date"|"source_size_human"|"backup_size_human"|"compressed"' "$METADATA_FILE" | sed 's/.*"\([^"]*\)": "\([^"]*\)".*/\1: \2/'
    fi
fi

info ""
info "Backup verification: PASSED"
info "Backup is valid and ready for restore"

