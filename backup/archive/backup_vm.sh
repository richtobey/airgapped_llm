#!/bin/bash
# Backup UTM VM disk to external location
# Can be run from bootable USB or directly on Mac

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

# Default options
COMPRESS=false
INCLUDE_CONFIG=false
VERIFY=false
SPLIT=false

# Parse arguments
VM_DISK=""
BACKUP_DEST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --compress)
            COMPRESS=true
            shift
            ;;
        --include-config)
            INCLUDE_CONFIG=true
            shift
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --split)
            SPLIT=true
            shift
            ;;
        --help)
            echo "Usage: $0 VM_DISK BACKUP_DEST [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  VM_DISK       Path to UTM VM disk file (.qcow2)"
            echo "  BACKUP_DEST   Destination directory for backup"
            echo ""
            echo "Options:"
            echo "  --compress         Compress backup with gzip"
            echo "  --include-config   Include UTM VM configuration files"
            echo "  --verify           Verify backup after creation"
            echo "  --split            Split backup into 4GB files (for FAT32)"
            echo ""
            echo "Example:"
            echo "  $0 ~/Library/Containers/com.utmapp.UTM/Data/Documents/PopOS.utm/Images/disk.qcow2 /Volumes/ExternalDrive/backups --compress"
            exit 0
            ;;
        *)
            if [[ -z "$VM_DISK" ]]; then
                VM_DISK="$1"
            elif [[ -z "$BACKUP_DEST" ]]; then
                BACKUP_DEST="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$VM_DISK" ]] || [[ -z "$BACKUP_DEST" ]]; then
    error "Usage: $0 VM_DISK BACKUP_DEST [OPTIONS]"
fi

# Check if VM disk exists
if [[ ! -f "$VM_DISK" ]]; then
    error "VM disk not found: $VM_DISK"
fi

# Check if destination is writable
if [[ ! -d "$BACKUP_DEST" ]]; then
    mkdir -p "$BACKUP_DEST" || error "Cannot create backup destination: $BACKUP_DEST"
fi

if [[ ! -w "$BACKUP_DEST" ]]; then
    error "Backup destination is not writable: $BACKUP_DEST"
fi

# Get VM disk info
VM_DISK_SIZE=$(du -h "$VM_DISK" | cut -f1)
VM_DISK_SIZE_BYTES=$(stat -f%z "$VM_DISK" 2>/dev/null || stat -c%s "$VM_DISK" 2>/dev/null)

info "VM Disk: $VM_DISK"
info "Size: $VM_DISK_SIZE"
info "Backup Destination: $BACKUP_DEST"

# Check available space
AVAILABLE_SPACE=$(df -h "$BACKUP_DEST" | tail -1 | awk '{print $4}')
info "Available space: $AVAILABLE_SPACE"

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
VM_NAME=$(basename "$(dirname "$(dirname "$VM_DISK")")" .utm)
BACKUP_DIR="$BACKUP_DEST/${VM_NAME}-backup-${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

info "Backup directory: $BACKUP_DIR"

# Create metadata
info "Creating backup metadata..."
METADATA_FILE="$BACKUP_DIR/backup-metadata.json"
cat > "$METADATA_FILE" <<EOF
{
  "vm_name": "$VM_NAME",
  "backup_date": "$(date -Iseconds)",
  "source_disk": "$VM_DISK",
  "source_size_bytes": $VM_DISK_SIZE_BYTES,
  "source_size_human": "$VM_DISK_SIZE",
  "compressed": $COMPRESS,
  "split": $SPLIT,
  "host_system": "$(uname -a)",
  "backup_script_version": "1.0"
}
EOF

# Backup UTM config if requested
if [[ "$INCLUDE_CONFIG" == "true" ]]; then
    UTM_DIR=$(dirname "$(dirname "$VM_DISK")")
    if [[ -f "$UTM_DIR/config.plist" ]]; then
        info "Backing up UTM configuration..."
        cp "$UTM_DIR/config.plist" "$BACKUP_DIR/utm-config.plist"
    fi
fi

# Create backup log
LOG_FILE="$BACKUP_DIR/backup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Backup VM disk
BACKUP_FILE="$BACKUP_DIR/vm-disk.qcow2"
if [[ "$COMPRESS" == "true" ]]; then
    BACKUP_FILE="${BACKUP_FILE}.gz"
    info "Creating compressed backup (this may take a while)..."
    if command -v pigz >/dev/null 2>&1; then
        # Use pigz (parallel gzip) if available
        info "Using pigz for faster compression..."
        pigz -c "$VM_DISK" > "$BACKUP_FILE"
    else
        gzip -c "$VM_DISK" > "$BACKUP_FILE"
    fi
else
    info "Creating backup (this may take a while)..."
    if [[ "$SPLIT" == "true" ]]; then
        # Split into 4GB files for FAT32 compatibility
        split -b 4G "$VM_DISK" "$BACKUP_FILE.part"
        info "Backup split into multiple files"
    else
        cp "$VM_DISK" "$BACKUP_FILE"
    fi
fi

# Generate checksums
info "Generating checksums..."
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"

if [[ "$SPLIT" == "true" ]]; then
    # Checksum all parts
    find "$BACKUP_DIR" -name "vm-disk.qcow2.part*" -exec sha256sum {} \; > "$CHECKSUM_FILE"
    sha256sum "$VM_DISK" >> "$CHECKSUM_FILE"
else
    sha256sum "$BACKUP_FILE" > "$CHECKSUM_FILE"
    sha256sum "$VM_DISK" >> "$CHECKSUM_FILE"
fi

info "Checksums saved to: $CHECKSUM_FILE"

# Update metadata with backup file info
BACKUP_SIZE=$(du -h "$BACKUP_FILE"* | tail -1 | cut -f1)
BACKUP_SIZE_BYTES=$(stat -f%z "$BACKUP_FILE"* 2>/dev/null | awk '{sum+=$1} END {print sum}' || stat -c%s "$BACKUP_FILE"* 2>/dev/null | awk '{sum+=$1} END {print sum}')

cat >> "$METADATA_FILE" <<EOF
,
  "backup_file": "$(basename "$BACKUP_FILE")",
  "backup_size_bytes": $BACKUP_SIZE_BYTES,
  "backup_size_human": "$BACKUP_SIZE"
}
EOF

# Verify backup if requested
if [[ "$VERIFY" == "true" ]]; then
    info "Verifying backup..."
    if [[ -f "$SCRIPT_DIR/verify_backup.sh" ]]; then
        "$SCRIPT_DIR/verify_backup.sh" "$BACKUP_DIR"
    else
        warn "verify_backup.sh not found, skipping verification"
    fi
fi

info ""
info "Backup completed successfully!"
info "Backup location: $BACKUP_DIR"
info "Backup size: $BACKUP_SIZE"
info ""
info "To restore:"
info "  ./restore_vm.sh $BACKUP_DIR /path/to/restored-vm.qcow2"
info ""
info "To verify:"
info "  ./verify_backup.sh $BACKUP_DIR"

