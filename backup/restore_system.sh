#!/bin/bash
# Restore full disk image backup to physical System76 system
# Restores partition table, disk image, and bootloader

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
TARGET_DISK=""
VERIFY_BACKUP=true
FORCE=false
SKIP_BOOTLOADER=false

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
        --skip-bootloader)
            SKIP_BOOTLOADER=true
            shift
            ;;
        --help)
            echo "Usage: $0 BACKUP_DIR TARGET_DISK [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  BACKUP_DIR    Backup directory (created by backup_system.sh)"
            echo "  TARGET_DISK   Target block device to restore to (e.g., /dev/sda)"
            echo ""
            echo "Options:"
            echo "  --no-verify         Skip backup verification before restore"
            echo "  --force             Skip safety confirmations (DANGEROUS)"
            echo "  --skip-bootloader   Don't restore bootloader (advanced)"
            echo ""
            echo "WARNING: This will COMPLETELY ERASE the target disk!"
            echo "All data on TARGET_DISK will be lost!"
            echo ""
            echo "Example:"
            echo "  $0 /mnt/backup/system76-backup-20240101 /dev/sda"
            exit 0
            ;;
        *)
            if [[ -z "$BACKUP_DIR" ]]; then
                BACKUP_DIR="$1"
            elif [[ -z "$TARGET_DISK" ]]; then
                TARGET_DISK="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$BACKUP_DIR" ]] || [[ -z "$TARGET_DISK" ]]; then
    error "Usage: $0 BACKUP_DIR TARGET_DISK [OPTIONS]"
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
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

# Check if target disk exists
if [[ ! -b "$TARGET_DISK" ]]; then
    error "Target disk not found or not a block device: $TARGET_DISK"
fi

# Get target disk size
TARGET_SIZE=$(blockdev --getsize64 "$TARGET_DISK" 2>/dev/null || echo "0")
TARGET_SIZE_HUMAN=$(numfmt --to=iec-i --suffix=B "$TARGET_SIZE" 2>/dev/null || echo "unknown")

# Read metadata
SOURCE_SIZE=$(grep -o '"source_size_bytes": [0-9]*' "$METADATA_FILE" | cut -d' ' -f2 || echo "0")
SOURCE_SIZE_HUMAN=$(grep -o '"source_size_human": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4 || echo "unknown")
HOSTNAME=$(grep -o '"hostname": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4 || echo "unknown")
BACKUP_DATE=$(grep -o '"backup_date": "[^"]*"' "$METADATA_FILE" | cut -d'"' -f4 || echo "unknown")

info "Backup Information:"
info "  Hostname: $HOSTNAME"
info "  Backup Date: $BACKUP_DATE"
info "  Source Disk Size: $SOURCE_SIZE_HUMAN"
info ""
info "Target Disk: $TARGET_DISK"
info "  Target Disk Size: $TARGET_SIZE_HUMAN"

# Check if target is large enough
if [[ $TARGET_SIZE -lt $SOURCE_SIZE ]]; then
    error "Target disk ($TARGET_SIZE_HUMAN) is smaller than source ($SOURCE_SIZE_HUMAN)"
fi

# Find backup file
BACKUP_FILE=""
if [[ -f "$BACKUP_DIR/system-disk.img.gz" ]]; then
    BACKUP_FILE="$BACKUP_DIR/system-disk.img.gz"
    COMPRESSED=true
    COMPRESS_TYPE="gzip"
elif [[ -f "$BACKUP_DIR/system-disk.img.xz" ]]; then
    BACKUP_FILE="$BACKUP_DIR/system-disk.img.xz"
    COMPRESSED=true
    COMPRESS_TYPE="xz"
elif [[ -f "$BACKUP_DIR/system-disk.img" ]]; then
    BACKUP_FILE="$BACKUP_DIR/system-disk.img"
    COMPRESSED=false
else
    error "Backup file not found in: $BACKUP_DIR"
fi

info "Backup file: $BACKUP_FILE"
info "Compressed: $COMPRESSED"

# CRITICAL SAFETY WARNINGS
warn ""
warn "═══════════════════════════════════════════════════════════════"
warn "  WARNING: DESTRUCTIVE OPERATION"
warn "═══════════════════════════════════════════════════════════════"
warn ""
warn "This will COMPLETELY ERASE all data on: $TARGET_DISK"
warn ""
warn "Target disk information:"
warn "  Device: $TARGET_DISK"
warn "  Size: $TARGET_SIZE_HUMAN"
warn ""
warn "All partitions and data on this disk will be PERMANENTLY DELETED!"
warn ""

if [[ "$FORCE" != "true" ]]; then
    # Show what's on the target disk
    info "Current partitions on target disk:"
    fdisk -l "$TARGET_DISK" 2>/dev/null | grep -E "^/dev" || warn "  (no partitions found)"
    echo ""
    
    read -p "Type 'YES' to confirm you want to erase $TARGET_DISK: " confirm
    if [[ "$confirm" != "YES" ]]; then
        info "Aborted by user"
        exit 0
    fi
    
    # Double confirmation
    echo ""
    warn "FINAL CONFIRMATION:"
    warn "You are about to restore backup to $TARGET_DISK"
    warn "This will destroy ALL data on this disk!"
    read -p "Type the full device path ($TARGET_DISK) to confirm: " confirm_path
    if [[ "$confirm_path" != "$TARGET_DISK" ]]; then
        error "Confirmation path mismatch. Aborted."
    fi
fi

# Unmount target disk if mounted
info "Unmounting target disk..."
umount "$TARGET_DISK"* 2>/dev/null || true
for part in $(lsblk -n -o NAME "$TARGET_DISK" | grep -v "^$(basename "$TARGET_DISK")$"); do
    umount "/dev/$part" 2>/dev/null || true
done

# Restore partition table first
PARTITION_TABLE_FILE="$BACKUP_DIR/partition-table.bin"
PARTITION_TABLE_TXT="$BACKUP_DIR/partition-table.txt"

if [[ -f "$PARTITION_TABLE_TXT" ]]; then
    info "Restoring partition table..."
    sfdisk "$TARGET_DISK" < "$PARTITION_TABLE_TXT" || warn "Failed to restore partition table from text file"
    partprobe "$TARGET_DISK" 2>/dev/null || true
    sleep 2
elif [[ -f "$PARTITION_TABLE_FILE" ]]; then
    info "Restoring partition table from binary backup..."
    dd if="$PARTITION_TABLE_FILE" of="$TARGET_DISK" bs=512 count=2048
    partprobe "$TARGET_DISK" 2>/dev/null || true
    sleep 2
else
    warn "No partition table backup found, will restore full disk image"
fi

# Restore disk image
info "Restoring disk image (this will take a while)..."
warn "This may take 30-60+ minutes depending on disk size."

if [[ "$COMPRESSED" == "true" ]]; then
    info "Decompressing and restoring..."
    if command -v pv >/dev/null 2>&1; then
        # Use pv for progress
        if [[ "$COMPRESS_TYPE" == "gzip" ]]; then
            if command -v pigz >/dev/null 2>&1; then
                pigz -dc "$BACKUP_FILE" | pv | dd of="$TARGET_DISK" bs=1M
            else
                gunzip -c "$BACKUP_FILE" | pv | dd of="$TARGET_DISK" bs=1M
            fi
        else
            xz -dc "$BACKUP_FILE" | pv | dd of="$TARGET_DISK" bs=1M
        fi
    else
        # No pv, use dd with status
        if [[ "$COMPRESS_TYPE" == "gzip" ]]; then
            if command -v pigz >/dev/null 2>&1; then
                pigz -dc "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=1M status=progress
            else
                gunzip -c "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=1M status=progress
            fi
        else
            xz -dc "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=1M status=progress
        fi
    fi
else
    info "Restoring uncompressed disk image..."
    if command -v pv >/dev/null 2>&1; then
        pv "$BACKUP_FILE" | dd of="$TARGET_DISK" bs=1M
    else
        dd if="$BACKUP_FILE" of="$TARGET_DISK" bs=1M status=progress
    fi
fi

# Sync to ensure data is written
sync

# Restore bootloader if not skipped
if [[ "$SKIP_BOOTLOADER" != "true" ]]; then
    info "Restoring bootloader..."
    
    # Find root partition
    ROOT_PART=""
    for part in $(lsblk -n -o NAME "$TARGET_DISK" | grep -v "^$(basename "$TARGET_DISK")$"); do
        part_path="/dev/$part"
        fstype=$(lsblk -n -o FSTYPE "$part_path" 2>/dev/null || echo "")
        mountpoint=$(lsblk -n -o MOUNTPOINT "$part_path" 2>/dev/null || echo "")
        
        # Try to identify root partition
        if [[ "$fstype" == "ext4" ]] || [[ "$mountpoint" == "/" ]]; then
            ROOT_PART="$part_path"
            break
        fi
    done
    
    if [[ -z "$ROOT_PART" ]]; then
        # Try first ext4 partition
        ROOT_PART=$(lsblk -n -o NAME,FSTYPE "$TARGET_DISK" | grep "ext4" | head -1 | awk '{print "/dev/"$1}')
    fi
    
    if [[ -n "$ROOT_PART" ]] && [[ -b "$ROOT_PART" ]]; then
        info "Found root partition: $ROOT_PART"
        
        # Mount root partition
        MOUNT_POINT=$(mktemp -d)
        mount "$ROOT_PART" "$MOUNT_POINT" || warn "Could not mount root partition for bootloader restore"
        
        if mountpoint -q "$MOUNT_POINT"; then
            # Check for EFI partition
            EFI_PART=""
            for part in $(lsblk -n -o NAME "$TARGET_DISK" | grep -v "^$(basename "$TARGET_DISK")$"); do
                part_path="/dev/$part"
                fstype=$(lsblk -n -o FSTYPE "$part_path" 2>/dev/null || echo "")
                if [[ "$fstype" == "vfat" ]] || [[ "$fstype" == "efi" ]]; then
                    EFI_PART="$part_path"
                    break
                fi
            done
            
            # Install GRUB
            if command -v grub-install >/dev/null 2>&1; then
                info "Installing GRUB bootloader..."
                
                # Bind mount system directories
                mount --bind /dev "$MOUNT_POINT/dev"
                mount --bind /proc "$MOUNT_POINT/proc"
                mount --bind /sys "$MOUNT_POINT/sys"
                
                if [[ -n "$EFI_PART" ]]; then
                    # EFI boot
                    mkdir -p "$MOUNT_POINT/boot/efi"
                    mount "$EFI_PART" "$MOUNT_POINT/boot/efi" 2>/dev/null || true
                    chroot "$MOUNT_POINT" grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=pop_os || warn "GRUB EFI install failed"
                else
                    # Legacy BIOS boot
                    chroot "$MOUNT_POINT" grub-install "$TARGET_DISK" || warn "GRUB BIOS install failed"
                fi
                
                # Update GRUB config
                chroot "$MOUNT_POINT" update-grub || warn "GRUB config update failed"
                
                # Unmount
                umount "$MOUNT_POINT/boot/efi" 2>/dev/null || true
                umount "$MOUNT_POINT/sys"
                umount "$MOUNT_POINT/proc"
                umount "$MOUNT_POINT/dev"
            else
                warn "grub-install not found, skipping bootloader restore"
            fi
            
            umount "$MOUNT_POINT"
        else
            warn "Could not mount root partition, skipping bootloader restore"
        fi
        rmdir "$MOUNT_POINT" 2>/dev/null || true
    else
        warn "Could not identify root partition, skipping bootloader restore"
    fi
else
    info "Skipping bootloader restore (--skip-bootloader)"
fi

info ""
info "Restore completed successfully!"
info ""
info "Next steps:"
info "  1. Verify the disk: fdisk -l $TARGET_DISK"
info "  2. Reboot the system"
info "  3. If boot fails, boot from live USB and run:"
info "     sudo grub-install $TARGET_DISK"
info "     sudo update-grub"

