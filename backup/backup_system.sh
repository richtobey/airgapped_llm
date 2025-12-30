#!/bin/bash
# Full disk image backup for physical System76 Pop!_OS system
# Creates complete system backup including partition table and bootloader

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
COMPRESS=true
COMPRESS_TYPE="gzip"  # gzip or xz
VERIFY=false
SKIP_FS_CHECK=false

# Parse arguments
SYSTEM_DISK=""
BACKUP_DEST=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-compress)
            COMPRESS=false
            shift
            ;;
        --compress-type)
            COMPRESS_TYPE="$2"
            shift 2
            ;;
        --verify)
            VERIFY=true
            shift
            ;;
        --skip-fs-check)
            SKIP_FS_CHECK=true
            shift
            ;;
        --help)
            echo "Usage: $0 SYSTEM_DISK BACKUP_DEST [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  SYSTEM_DISK    Block device to backup (e.g., /dev/sda)"
            echo "  BACKUP_DEST    Destination directory for backup"
            echo ""
            echo "Options:"
            echo "  --no-compress       Don't compress backup (faster, larger)"
            echo "  --compress-type TYPE Compression type: gzip or xz (default: gzip)"
            echo "  --verify            Verify backup after creation"
            echo "  --skip-fs-check     Skip filesystem check before backup"
            echo ""
            echo "Example:"
            echo "  $0 /dev/sda /mnt/backup-drive --compress"
            echo ""
            echo "WARNING: This will create a full disk image backup."
            echo "Ensure you have sufficient space on BACKUP_DEST."
            exit 0
            ;;
        *)
            if [[ -z "$SYSTEM_DISK" ]]; then
                SYSTEM_DISK="$1"
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
if [[ -z "$SYSTEM_DISK" ]] || [[ -z "$BACKUP_DEST" ]]; then
    error "Usage: $0 SYSTEM_DISK BACKUP_DEST [OPTIONS]"
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

# Validate compression type
if [[ "$COMPRESS" == "true" ]]; then
    if [[ "$COMPRESS_TYPE" != "gzip" ]] && [[ "$COMPRESS_TYPE" != "xz" ]]; then
        error "Invalid compression type: $COMPRESS_TYPE (use gzip or xz)"
    fi
fi

# Check if system disk exists and is a block device
if [[ ! -b "$SYSTEM_DISK" ]]; then
    error "System disk not found or not a block device: $SYSTEM_DISK"
fi

# Safety check - warn if disk is mounted
if mount | grep -q "^$SYSTEM_DISK"; then
    warn "Disk $SYSTEM_DISK appears to be mounted!"
    warn "For best results, backup should be done from live USB with system unmounted."
    read -p "Continue anyway? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Aborted by user"
        exit 0
    fi
fi

# Check if destination is writable
if [[ ! -d "$BACKUP_DEST" ]]; then
    mkdir -p "$BACKUP_DEST" || error "Cannot create backup destination: $BACKUP_DEST"
fi

if [[ ! -w "$BACKUP_DEST" ]]; then
    error "Backup destination is not writable: $BACKUP_DEST"
fi

# Get disk information
info "Gathering disk information..."
DISK_SIZE=$(blockdev --getsize64 "$SYSTEM_DISK" 2>/dev/null || echo "0")
DISK_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$DISK_SIZE" 2>/dev/null || echo "unknown")

# Get partition information
PARTITION_INFO=$(fdisk -l "$SYSTEM_DISK" 2>/dev/null || echo "")

info "System Disk: $SYSTEM_DISK"
info "Size: $DISK_SIZE_HUMAN"
info "Backup Destination: $BACKUP_DEST"

# Check available space (need at least disk size, more if compressing)
AVAILABLE_SPACE_BYTES=$(df -B1 "$BACKUP_DEST" | tail -1 | awk '{print $4}')
if [[ "$COMPRESS" == "true" ]]; then
    # Compression typically reduces to 30-50% of original
    REQUIRED_SPACE=$((DISK_SIZE / 2))
else
    REQUIRED_SPACE=$DISK_SIZE
fi

if [[ $AVAILABLE_SPACE_BYTES -lt $REQUIRED_SPACE ]]; then
    AVAILABLE_SPACE_HUMAN=$(numfmt --to=iec-i --suffix=B "$AVAILABLE_SPACE_BYTES" 2>/dev/null || echo "unknown")
    warn "Available space: $AVAILABLE_SPACE_HUMAN"
    warn "Required space: $(numfmt --to=iec-i --suffix=B "$REQUIRED_SPACE" 2>/dev/null || echo "unknown")"
    error "Insufficient space on backup destination"
fi

AVAILABLE_SPACE_HUMAN=$(df -h "$BACKUP_DEST" | tail -1 | awk '{print $4}')
info "Available space: $AVAILABLE_SPACE_HUMAN"

# Final confirmation
warn ""
warn "WARNING: This will create a full disk image backup of $SYSTEM_DISK"
warn "This process may take 30-60+ minutes depending on disk size."
warn ""
read -p "Continue with backup? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    info "Aborted by user"
    exit 0
fi

# Create backup directory with timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname 2>/dev/null || echo "system76")
BACKUP_DIR="$BACKUP_DEST/${HOSTNAME}-backup-${TIMESTAMP}"
mkdir -p "$BACKUP_DIR"

info "Backup directory: $BACKUP_DIR"

# Create metadata
info "Creating backup metadata..."
METADATA_FILE="$BACKUP_DIR/backup-metadata.json"
cat > "$METADATA_FILE" <<EOF
{
  "hostname": "$HOSTNAME",
  "backup_date": "$(date -Iseconds)",
  "source_disk": "$SYSTEM_DISK",
  "source_size_bytes": $DISK_SIZE,
  "source_size_human": "$DISK_SIZE_HUMAN",
  "compressed": $COMPRESS,
  "compression_type": "$COMPRESS_TYPE",
  "backup_script_version": "2.0",
  "system_info": "$(uname -a)"
}
EOF

# Backup partition table
info "Backing up partition table..."
PARTITION_TABLE_FILE="$BACKUP_DIR/partition-table.bin"
sfdisk -d "$SYSTEM_DISK" > "$BACKUP_DIR/partition-table.txt" 2>/dev/null || true
dd if="$SYSTEM_DISK" of="$PARTITION_TABLE_FILE" bs=512 count=2048 2>/dev/null || warn "Failed to backup partition table"

# Create backup log
LOG_FILE="$BACKUP_DIR/backup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Perform filesystem check if requested
if [[ "$SKIP_FS_CHECK" != "true" ]]; then
    info "Checking filesystems (this may take a while)..."
    # Try to check filesystems (may fail if mounted, that's OK)
    for part in $(lsblk -n -o NAME "$SYSTEM_DISK" | grep -v "^$(basename "$SYSTEM_DISK")$"); do
        part_path="/dev/$part"
        fstype=$(lsblk -n -o FSTYPE "$part_path" 2>/dev/null || echo "")
        if [[ -n "$fstype" ]] && [[ "$fstype" != "swap" ]] && [[ "$fstype" != "" ]]; then
            if ! mount | grep -q "$part_path"; then
                info "Checking $part_path (filesystem: $fstype)..."
                case "$fstype" in
                    ext*)
                        fsck -n "$part_path" 2>/dev/null || warn "Could not check $part_path"
                        ;;
                    *)
                        warn "Skipping filesystem check for $fstype on $part_path"
                        ;;
                esac
            fi
        fi
    done
fi

# Create disk image backup
BACKUP_FILE="$BACKUP_DIR/system-disk.img"
if [[ "$COMPRESS" == "true" ]]; then
    BACKUP_FILE="${BACKUP_FILE}.${COMPRESS_TYPE}"
    info "Creating compressed disk image backup (this will take a while)..."
    info "Using $COMPRESS_TYPE compression"
    
    # Use pv for progress if available
    if command -v pv >/dev/null 2>&1; then
        info "Showing progress..."
        if [[ "$COMPRESS_TYPE" == "gzip" ]]; then
            if command -v pigz >/dev/null 2>&1; then
                dd if="$SYSTEM_DISK" bs=1M 2>/dev/null | \
                    pv -s "$DISK_SIZE" | \
                    pigz -c > "$BACKUP_FILE"
            else
                dd if="$SYSTEM_DISK" bs=1M 2>/dev/null | \
                    pv -s "$DISK_SIZE" | \
                    gzip -c > "$BACKUP_FILE"
            fi
        else
            dd if="$SYSTEM_DISK" bs=1M 2>/dev/null | \
                pv -s "$DISK_SIZE" | \
                xz -c > "$BACKUP_FILE"
        fi
    else
        # No pv, use dd with status
        if [[ "$COMPRESS_TYPE" == "gzip" ]]; then
            if command -v pigz >/dev/null 2>&1; then
                dd if="$SYSTEM_DISK" bs=1M status=progress 2>&1 | pigz -c > "$BACKUP_FILE"
            else
                dd if="$SYSTEM_DISK" bs=1M status=progress 2>&1 | gzip -c > "$BACKUP_FILE"
            fi
        else
            dd if="$SYSTEM_DISK" bs=1M status=progress 2>&1 | xz -c > "$BACKUP_FILE"
        fi
    fi
else
    info "Creating uncompressed disk image backup (this will take a while)..."
    if command -v pv >/dev/null 2>&1; then
        dd if="$SYSTEM_DISK" bs=1M 2>/dev/null | \
            pv -s "$DISK_SIZE" | \
            dd of="$BACKUP_FILE" bs=1M
    else
        dd if="$SYSTEM_DISK" of="$BACKUP_FILE" bs=1M status=progress
    fi
fi

# Generate checksums
info "Generating checksums..."
CHECKSUM_FILE="$BACKUP_DIR/checksums.sha256"

# Checksum the disk image
sha256sum "$BACKUP_FILE" > "$CHECKSUM_FILE"

# Checksum partition table backup
if [[ -f "$PARTITION_TABLE_FILE" ]]; then
    sha256sum "$PARTITION_TABLE_FILE" >> "$CHECKSUM_FILE"
fi

# Checksum metadata
sha256sum "$METADATA_FILE" >> "$CHECKSUM_FILE"

info "Checksums saved to: $CHECKSUM_FILE"

# Update metadata with backup file info
BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null || echo "0")
BACKUP_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$BACKUP_SIZE" 2>/dev/null || echo "unknown")

# Fix JSON (remove trailing comma)
sed -i 's/,$//' "$METADATA_FILE"
cat >> "$METADATA_FILE" <<EOF
,
  "backup_file": "$(basename "$BACKUP_FILE")",
  "backup_size_bytes": $BACKUP_SIZE,
  "backup_size_human": "$BACKUP_SIZE_HUMAN"
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
info "Backup size: $BACKUP_SIZE_HUMAN"
info ""
info "To restore:"
info "  ./restore_system.sh $BACKUP_DIR $SYSTEM_DISK"
info ""
info "To verify:"
info "  ./verify_backup.sh $BACKUP_DIR"

