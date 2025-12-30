#!/bin/bash
# Create bootable USB with backup and restore tools
# For backing up physical System76 Pop!_OS systems

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="${ISO_DIR:-$HOME/vm-popos/iso}"
USB_DEVICE="${USB_DEVICE:-}"
POPOS_VERSION="${POPOS_VERSION:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    error "This script must be run on macOS"
fi

# Check for required tools
command -v diskutil >/dev/null 2>&1 || error "diskutil not found (macOS required)"
command -v hdiutil >/dev/null 2>&1 || error "hdiutil not found (macOS required)"

# Function to download Pop!_OS ISO
download_popos_iso() {
    local iso_path="$1"
    
    if [[ -f "$iso_path" ]]; then
        info "ISO already exists: $iso_path"
        return 0
    fi
    
    info "Downloading Pop!_OS ISO..."
    
    # Detect architecture
    local arch
    if [[ "$(uname -m)" == "arm64" ]]; then
        arch="amd64"  # Use x86_64 for emulation testing
    else
        arch="amd64"
    fi
    
    # Use NVIDIA variant (same as production)
    local variant="nvidia"
    
    # Get latest version if not specified
    if [[ -z "$POPOS_VERSION" ]]; then
        info "Detecting latest Pop!_OS version..."
        # Try to get latest version from System76
        POPOS_VERSION="22.04"  # Default, user can override
        warn "Using default version: $POPOS_VERSION (set POPOS_VERSION to override)"
    fi
    
    local base_url="https://iso.pop-os.org"
    local iso_name="pop-os_${POPOS_VERSION}_${arch}_${variant}.iso"
    local iso_url="${base_url}/${iso_name}"
    
    info "Downloading: $iso_name"
    info "URL: $iso_url"
    
    mkdir -p "$(dirname "$iso_path")"
    
    # Download with curl
    if ! curl -L -o "$iso_path" "$iso_url"; then
        error "Failed to download ISO"
    fi
    
    info "Download complete: $iso_path"
    info "ISO size: $(du -h "$iso_path" | cut -f1)"
}

# Function to list USB devices
list_usb_devices() {
    info "Available USB devices:"
    diskutil list external physical | grep -E "^/dev/disk" || warn "No external USB devices found"
}

# Function to create bootable USB
create_bootable_usb() {
    local iso_path="$1"
    local device="$2"
    
    if [[ ! -f "$iso_path" ]]; then
        error "ISO not found: $iso_path"
    fi
    
    if [[ ! -b "$device" ]]; then
        error "Invalid device: $device (must be a block device like /dev/disk2)"
    fi
    
    # Safety check - ensure it's an external device
    local device_info
    device_info=$(diskutil info "$device" 2>/dev/null || true)
    if echo "$device_info" | grep -q "Internal"; then
        error "Device $device appears to be internal. Aborting for safety."
    fi
    
    warn "WARNING: This will ERASE all data on $device"
    warn "Device info:"
    diskutil info "$device" | grep -E "(Device Node|Disk Size|Volume Name)" || true
    
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        info "Aborted by user"
        exit 0
    fi
    
    info "Unmounting $device..."
    diskutil unmountDisk "$device" || true
    
    info "Erasing and formatting $device..."
    diskutil eraseDisk FAT32 BACKUP_USB MBRFormat "$device" || error "Failed to format device"
    
    info "Creating bootable USB from ISO..."
    warn "This may take 10-20 minutes..."
    
    # Use dd to write ISO (slow but reliable)
    # Alternative: Use balenaEtcher if available
    if command -v balena-etcher >/dev/null 2>&1 || command -v etcher >/dev/null 2>&1; then
        warn "Consider using balenaEtcher GUI for better progress indication"
        warn "Or continue with dd (this will take a while)..."
        read -p "Continue with dd? (yes/no): " use_dd
        if [[ "$use_dd" == "yes" ]]; then
            info "Writing ISO to USB (this will take 10-20 minutes)..."
            sudo dd if="$iso_path" of="$device" bs=1m status=progress
            sync
        else
            info "Please use balenaEtcher to write the ISO, then run this script again with --skip-iso flag"
            exit 0
        fi
    else
        info "Writing ISO to USB (this will take 10-20 minutes)..."
        sudo dd if="$iso_path" of="$device" bs=1m status=progress
        sync
    fi
    
    info "Bootable USB created successfully!"
}

# Function to copy backup scripts to USB
copy_scripts_to_usb() {
    local mount_point="/Volumes/BACKUP_USB"
    
    # Wait for USB to mount
    local retries=0
    while [[ ! -d "$mount_point" ]] && [[ $retries -lt 10 ]]; do
        sleep 2
        retries=$((retries + 1))
    done
    
    if [[ ! -d "$mount_point" ]]; then
        warn "USB not mounted at $mount_point"
        warn "Please mount it manually and copy scripts:"
        warn "  cp $SCRIPT_DIR/*.sh $mount_point/"
        return 1
    fi
    
    info "Copying backup scripts to USB..."
    cp "$SCRIPT_DIR/backup_system.sh" "$mount_point/" || warn "Failed to copy backup_system.sh"
    cp "$SCRIPT_DIR/restore_system.sh" "$mount_point/" || warn "Failed to copy restore_system.sh"
    cp "$SCRIPT_DIR/verify_backup.sh" "$mount_point/" || warn "Failed to copy verify_backup.sh"
    cp "$SCRIPT_DIR/identify_disks.sh" "$mount_point/" || warn "Failed to copy identify_disks.sh"
    
    chmod +x "$mount_point"/*.sh 2>/dev/null || true
    
    info "Scripts copied to USB"
    info "USB is ready at: $mount_point"
}

# Main execution
main() {
    info "Creating bootable backup USB..."
    
    # Determine ISO path
    local iso_path="${ISO_DIR}/pop-os.iso"
    
    # Download ISO if needed
    if [[ ! -f "$iso_path" ]]; then
        download_popos_iso "$iso_path"
    else
        info "Using existing ISO: $iso_path"
    fi
    
    # List USB devices
    list_usb_devices
    
    # Get USB device
    if [[ -z "$USB_DEVICE" ]]; then
        echo ""
        read -p "Enter USB device (e.g., /dev/disk2): " USB_DEVICE
    fi
    
    if [[ -z "$USB_DEVICE" ]]; then
        error "USB device not specified"
    fi
    
    # Create bootable USB
    create_bootable_usb "$iso_path" "$USB_DEVICE"
    
    # Copy scripts
    copy_scripts_to_usb
    
    info ""
    info "Bootable USB created successfully!"
    info ""
    info "Next steps:"
    info "1. Eject USB: diskutil eject $USB_DEVICE"
    info "2. Insert USB into System76 machine"
    info "3. Boot from USB (hold appropriate key during boot)"
    info "4. Use identify_disks.sh to identify system disk"
    info "5. Use backup_system.sh to backup your physical system"
}

# Parse arguments
SKIP_ISO=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-iso)
            SKIP_ISO=true
            shift
            ;;
        --iso-dir)
            ISO_DIR="$2"
            shift 2
            ;;
        --usb-device)
            USB_DEVICE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-iso          Skip ISO download (use existing)"
            echo "  --iso-dir DIR       ISO directory (default: \$HOME/vm-popos/iso)"
            echo "  --usb-device DEV    USB device (e.g., /dev/disk2)"
            echo "  --help              Show this help"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

main

