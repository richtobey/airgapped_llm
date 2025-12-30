#!/bin/bash
# Identify disks for backup/restore operations
# Helps prevent mistakes by showing disk information clearly

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

header() {
    echo -e "${BLUE}=== $* ===${NC}"
}

# Check for required tools
command -v lsblk >/dev/null 2>&1 || error "lsblk not found. Install util-linux package."
command -v fdisk >/dev/null 2>&1 || error "fdisk not found. Install fdisk package."

# Function to get disk size in human-readable format
get_disk_size() {
    local disk="$1"
    if command -v blockdev >/dev/null 2>&1; then
        local size_bytes
        size_bytes=$(sudo blockdev --getsize64 "$disk" 2>/dev/null || echo "0")
        if [[ "$size_bytes" -gt 0 ]]; then
            numfmt --to=iec-i --suffix=B "$size_bytes" 2>/dev/null || echo "unknown"
        else
            echo "unknown"
        fi
    else
        lsblk -b -d -n -o SIZE "$disk" 2>/dev/null | numfmt --to=iec-i --suffix=B 2>/dev/null || echo "unknown"
    fi
}

# Function to check if disk is mounted
is_mounted() {
    local disk="$1"
    mount | grep -q "^$disk" || lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -qv "^$"
}

# Function to get mount points
get_mount_points() {
    local disk="$1"
    lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -v "^$" | tr '\n' ' ' || echo "none"
}

# Function to check if disk is system disk (has root partition)
is_system_disk() {
    local disk="$1"
    # Check if any partition is mounted as root
    lsblk -n -o MOUNTPOINT "$disk" 2>/dev/null | grep -q "^/$" && return 0
    # Check partition labels/filesystem labels
    lsblk -n -o LABEL "$disk" 2>/dev/null | grep -qiE "(root|pop|system)" && return 0
    return 1
}

# Main function
main() {
    header "Disk Identification Tool"
    echo ""
    info "This tool helps identify disks for backup and restore operations."
    echo ""
    warn "WARNING: Always double-check disk identifiers before backup/restore!"
    echo ""

    # Get all block devices
    header "Available Block Devices"
    echo ""

    # Use lsblk to list all disks
    local disks
    disks=$(lsblk -d -n -o NAME | grep -E "^(sd|nvme|vd|hd)" || true)

    if [[ -z "$disks" ]]; then
        warn "No suitable disks found"
        exit 1
    fi

    local system_disk=""
    local disk_count=0

    while IFS= read -r disk_name; do
        [[ -z "$disk_name" ]] && continue
        
        disk_count=$((disk_count + 1))
        local disk="/dev/$disk_name"
        
        # Skip if not a block device
        [[ ! -b "$disk" ]] && continue

        echo -e "${BLUE}Disk $disk_count: $disk${NC}"
        
        # Get disk size
        local disk_size
        disk_size=$(get_disk_size "$disk")
        echo "  Size: $disk_size"
        
        # Get disk model/vendor
        if [[ -f "/sys/block/$disk_name/device/model" ]]; then
            local model
            model=$(cat "/sys/block/$disk_name/device/model" 2>/dev/null | tr -d '\n' || echo "unknown")
            echo "  Model: $model"
        fi
        
        # Check if mounted
        if is_mounted "$disk"; then
            local mount_points
            mount_points=$(get_mount_points "$disk")
            echo -e "  ${YELLOW}Status: MOUNTED${NC}"
            echo "  Mount points: $mount_points"
        else
            echo -e "  ${GREEN}Status: Unmounted${NC}"
        fi
        
        # Check if system disk
        if is_system_disk "$disk"; then
            system_disk="$disk"
            echo -e "  ${RED}⚠ SYSTEM DISK (likely contains Pop!_OS)${NC}"
        fi
        
        # Show partitions
        echo "  Partitions:"
        local partitions
        partitions=$(lsblk -n -o NAME,TYPE,SIZE,MOUNTPOINT,FSTYPE "$disk" 2>/dev/null | grep "part" || echo "  (no partitions)")
        echo "$partitions" | sed 's/^/    /'
        
        echo ""
    done <<< "$disks"

    # Summary
    header "Summary"
    echo ""
    if [[ -n "$system_disk" ]]; then
        info "System disk identified: $system_disk"
        echo "  This is likely the disk you want to backup."
    else
        warn "No system disk automatically identified."
        echo "  Look for the disk with root (/) mount point."
    fi
    
    echo ""
    info "To backup the system disk:"
    echo "  ./backup_system.sh $system_disk /mnt/backup-drive"
    echo ""
    info "To identify a specific disk:"
    echo "  lsblk -f $system_disk"
    echo "  sudo fdisk -l $system_disk"
    echo ""
    warn "Always verify the disk identifier before proceeding!"
}

# Run main function
main

