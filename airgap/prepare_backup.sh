#!/bin/bash
# Prepare for Clonezilla Backup
# Simple helper script to prepare system information before backup
#
# Usage:
#   ./prepare_backup.sh [backup_name]
#
# This script gathers system information to help you create a proper backup
# with Clonezilla. It does NOT create the backup - use Clonezilla for that.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

BACKUP_NAME="${1:-backup_$(date +%Y%m%d_%H%M%S)}"

log_info "=== Backup Preparation ==="
log_info "Backup name: $BACKUP_NAME"
echo ""

# Display system information
log_info "System Information:"
echo "  Hostname: $(hostname)"
echo "  OS: $(lsb_release -d | cut -f2)"
echo "  Kernel: $(uname -r)"
echo "  Date: $(date)"
echo ""

# Display disk information
log_info "Disk Information:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE
echo ""

# Display root filesystem
ROOT_DEV=$(df / | tail -1 | awk '{print $1}')
ROOT_SIZE=$(df -h / | tail -1 | awk '{print $2}')
ROOT_USED=$(df -h / | tail -1 | awk '{print $3}')
ROOT_AVAIL=$(df -h / | tail -1 | awk '{print $4}')

log_info "Root Filesystem:"
echo "  Device: $ROOT_DEV"
echo "  Size: $ROOT_SIZE"
echo "  Used: $ROOT_USED"
echo "  Available: $ROOT_AVAIL"
echo ""

# Display partition table
log_info "Partition Table:"
fdisk -l "$(echo $ROOT_DEV | sed 's/[0-9]*$//')" 2>/dev/null | grep -E "^/dev|^Disk" || true
echo ""

# Backup drive requirements
log_info "Backup Drive Requirements:"
echo "  Clonezilla USB: 4-8 GB (for booting only, backups don't go here)"
echo "  Backup Storage Drive: SEPARATE drive needed for storing backups"
echo "  Recommended size: At least 2x your used space (${ROOT_USED})"
echo "  Compressed backup size: ~30-50% of used space per backup"
echo ""

# Recommendations
log_info "Recommendations for Clonezilla Backup:"
echo "  1. Source disk: $(echo $ROOT_DEV | sed 's/[0-9]*$//')"
echo "  2. Backup name: $BACKUP_NAME"
echo "  3. Compression: gzip (recommended)"
echo "  4. Backup location: SEPARATE external USB/HDD (NOT the Clonezilla USB)"
echo "     Minimum free space: ${ROOT_USED} (for one backup)"
echo "     Recommended: 2-3x that for multiple backups"
echo ""

log_info "Next Steps:"
echo "  1. Boot from Clonezilla USB (small USB, 4-8 GB)"
echo "  2. Connect your BACKUP storage drive (separate, larger drive)"
echo "  3. Select: device-image -> savedisk"
echo "  4. Enter backup name: $BACKUP_NAME"
echo "  5. Select source disk: $(echo $ROOT_DEV | sed 's/[0-9]*$//')"
echo "  6. Choose compression: gzip"
echo "  7. Select backup location: Your BACKUP storage drive (not Clonezilla USB)"
echo ""
