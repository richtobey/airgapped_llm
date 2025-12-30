#!/bin/bash
# Complete migration workflow: Restore backup, convert, and set up KVM VM
# Combines all migration steps into one script

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

# Default configuration
BACKUP_DIR=""
VM_NAME="popos-vm"
VM_DISK="/var/lib/libvirt/images/popos-vm.qcow2"
SKIP_RESTORE=false
SKIP_CONVERT=false
SKIP_SETUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backup-dir|-b)
            BACKUP_DIR="$2"
            shift 2
            ;;
        --vm-name|-n)
            VM_NAME="$2"
            shift 2
            ;;
        --vm-disk|-d)
            VM_DISK="$2"
            shift 2
            ;;
        --skip-restore)
            SKIP_RESTORE=true
            shift
            ;;
        --skip-convert)
            SKIP_CONVERT=true
            shift
            ;;
        --skip-setup)
            SKIP_SETUP=true
            shift
            ;;
        --help)
            echo "Usage: $0 --backup-dir BACKUP_DIR [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  -b, --backup-dir DIR    Backup directory (from backup_vm.sh)"
            echo ""
            echo "Options:"
            echo "  -n, --vm-name NAME      VM name (default: popos-vm)"
            echo "  -d, --vm-disk PATH       VM disk path (default: /var/lib/libvirt/images/popos-vm.qcow2)"
            echo "  --skip-restore          Skip restore step (disk already restored)"
            echo "  --skip-convert          Skip convert step (disk already converted)"
            echo "  --skip-setup            Skip setup step (VM already created)"
            echo ""
            echo "Example:"
            echo "  $0 --backup-dir /path/to/backup/popos-backup-20240101"
            exit 0
            ;;
        *)
            error "Unknown argument: $1"
            ;;
    esac
done

# Validate arguments
if [[ -z "$BACKUP_DIR" ]] && [[ "$SKIP_RESTORE" != "true" ]]; then
    error "Usage: $0 --backup-dir BACKUP_DIR [OPTIONS]"
fi

info "Starting complete migration workflow..."
info "VM Name: $VM_NAME"
info "VM Disk: $VM_DISK"

# Step 1: Restore backup
if [[ "$SKIP_RESTORE" != "true" ]]; then
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
    fi
    
    info ""
    info "=== Step 1: Restore Backup ==="
    
    RESTORE_SCRIPT="$SCRIPT_DIR/../backup/restore_vm.sh"
    if [[ ! -f "$RESTORE_SCRIPT" ]]; then
        error "Restore script not found: $RESTORE_SCRIPT"
    fi
    
    # Create temporary restore location if needed
    TEMP_DISK="${VM_DISK%.*}.restore.qcow2"
    
    if [[ -f "$VM_DISK" ]] && [[ ! -f "$TEMP_DISK" ]]; then
        warn "VM disk already exists: $VM_DISK"
        warn "Using temporary location: $TEMP_DISK"
        VM_DISK="$TEMP_DISK"
    fi
    
    if "$RESTORE_SCRIPT" "$BACKUP_DIR" "$VM_DISK"; then
        info "Restore completed successfully"
    else
        error "Restore failed"
    fi
else
    info "Skipping restore step"
fi

# Step 2: Convert disk
if [[ "$SKIP_CONVERT" != "true" ]]; then
    info ""
    info "=== Step 2: Convert Disk ==="
    
    CONVERT_SCRIPT="$SCRIPT_DIR/convert_utm_to_kvm.sh"
    if [[ ! -f "$CONVERT_SCRIPT" ]]; then
        error "Convert script not found: $CONVERT_SCRIPT"
    fi
    
    CONVERTED_DISK="${VM_DISK%.*}.kvm.qcow2"
    
    if "$CONVERT_SCRIPT" "$VM_DISK" --output "$CONVERTED_DISK" --optimize; then
        info "Conversion completed successfully"
        # Use converted disk for setup
        if [[ "$VM_DISK" == *".restore.qcow2" ]]; then
            # Remove temporary restore file
            rm -f "$VM_DISK"
        fi
        VM_DISK="$CONVERTED_DISK"
    else
        error "Conversion failed"
    fi
else
    info "Skipping convert step"
fi

# Step 3: Set up KVM VM
if [[ "$SKIP_SETUP" != "true" ]]; then
    info ""
    info "=== Step 3: Set Up KVM VM ==="
    
    SETUP_SCRIPT="$SCRIPT_DIR/setup_kvm_vm.sh"
    if [[ ! -f "$SETUP_SCRIPT" ]]; then
        error "Setup script not found: $SETUP_SCRIPT"
    fi
    
    if "$SETUP_SCRIPT" "$VM_NAME" "$VM_DISK"; then
        info "VM setup completed successfully"
    else
        error "VM setup failed"
    fi
else
    info "Skipping setup step"
fi

info ""
info "=== Migration Complete ==="
info ""
info "VM Name: $VM_NAME"
info "VM Disk: $VM_DISK"
info ""
info "Next steps:"
info "  1. Start VM: virsh start $VM_NAME"
info "  2. View console: virt-viewer $VM_NAME"
info "  3. Install SPICE tools (inside VM): sudo apt-get install spice-vdagent"
info "  4. Reboot VM: virsh reboot $VM_NAME"
info "  5. Verify everything works"

