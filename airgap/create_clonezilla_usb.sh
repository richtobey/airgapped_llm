#!/bin/bash
# Create Bootable Clonezilla USB Drive
# Simple script to create a bootable USB with Clonezilla Live
# 
# This script REQUIRES internet connection to download Clonezilla ISO if not provided
#
# Usage:
#   sudo ./create_clonezilla_usb.sh [clonezilla_iso] [usb_device]
#
# Example:
#   sudo ./create_clonezilla_usb.sh clonezilla-live-*.iso /dev/sdb
#   sudo ./create_clonezilla_usb.sh "" /dev/sdb  # Will download ISO automatically

set -euo pipefail

# Debug logging function
DEBUG_LOG="/mnt/t7_mac/airgap/.cursor/debug.log"
debug_log() {
    local location="$1"
    local message="$2"
    local data="$3"
    local hypothesis_id="${4:-}"
    echo "{\"timestamp\":$(date +%s%3N),\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"$hypothesis_id\"}" >> "$DEBUG_LOG"
}

# Function to check internet connectivity
check_internet() {
    # #region agent log
    debug_log "create_clonezilla_usb.sh:check_internet:entry" "Checking internet connection" "{}" "F"
    # #endregion
    
    log_info "Checking internet connection..."
    
    # Try to ping a reliable server
    if ping -c 1 -W 2 8.8.8.8 &>/dev/null || ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:check_internet:success" "Internet connection available" "{}" "F"
        # #endregion
        log_info "Internet connection: OK"
        return 0
    fi
    
    # Try HTTP connection to a reliable site
    if curl -s --max-time 5 --head https://www.google.com &>/dev/null || \
       curl -s --max-time 5 --head https://sourceforge.net &>/dev/null; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:check_internet:success_http" "Internet connection available (HTTP)" "{}" "F"
        # #endregion
        log_info "Internet connection: OK"
        return 0
    fi
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:check_internet:failed" "No internet connection" "{}" "F"
    # #endregion
    log_error "No internet connection detected!"
    log_error "This script requires internet to download Clonezilla ISO if not provided."
    log_info ""
    log_info "Please:"
    log_info "  1. Connect to the internet, OR"
    log_info "  2. Provide an existing Clonezilla ISO file as first argument"
    exit 1
}

# Function to download Clonezilla ISO
download_clonezilla_iso() {
    local output_file="${1:-clonezilla-live-amd64.iso}"
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:entry" "Downloading Clonezilla ISO" "{\"output\":\"$output_file\"}" "G"
    # #endregion
    
    log_info "Downloading Clonezilla Live ISO..."
    log_info "This may take several minutes depending on your connection speed..."
    
    # Use the specific URL from README.md
    local download_url="https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.3.0-33/clonezilla-live-3.3.0-33-amd64.iso/download"
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:trying" "Trying download URL" "{\"url\":\"$download_url\"}" "G"
    # #endregion
    
    log_info "Downloading from: $download_url"
    
    # Use wget to download the ISO file
    if wget --progress=bar:force --trust-server-names \
        --timeout=60 --tries=3 --continue \
        -O "$output_file.tmp" "$download_url" 2>&1 | tee /dev/stderr | grep -E "saving|ERROR|100%"; then
        
        # Check if we got redirected to HTML page
        local file_size=$(stat -f%z "$output_file.tmp" 2>/dev/null || stat -c%s "$output_file.tmp" 2>/dev/null || echo "0")
        local file_type=$(file "$output_file.tmp" 2>/dev/null || echo "")
        
        # #region agent log
        debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:checking" "Checking downloaded file" "{\"size\":$file_size,\"type\":\"$file_type\"}" "G"
        # #endregion
        
        if [[ $file_size -gt 104857600 ]] && [[ ! "$file_type" =~ "HTML" ]]; then
            mv "$output_file.tmp" "$output_file"
            # #region agent log
            debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:success" "Download successful" "{\"file\":\"$output_file\",\"size\":$file_size}" "G"
            # #endregion
            log_info "Download complete: $output_file ($(numfmt --to=iec-i --suffix=B ${file_size} 2>/dev/null || echo "${file_size} bytes"))"
            echo "$output_file"
            return 0
        else
            # #region agent log
            debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:invalid" "Downloaded file invalid" "{\"size\":$file_size,\"type\":\"$file_type\"}" "G"
            # #endregion
            log_warn "Downloaded file appears invalid (size: $file_size bytes, likely HTML redirect)"
            rm -f "$output_file.tmp"
        fi
    else
        # #region agent log
        debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:failed" "Download failed" "{\"url\":\"$download_url\"}" "G"
        # #endregion
        rm -f "$output_file.tmp"
    fi
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:download_clonezilla_iso:failed" "All download attempts failed" "{}" "G"
    # #endregion
    log_error "Failed to download Clonezilla ISO automatically"
    log_error "SourceForge's website may require JavaScript for downloads"
    log_info ""
    log_info "Please download manually:"
    log_info "  wget -O clonezilla-live-amd64.iso \\"
    log_info "    $download_url"
    log_info ""
    log_info "Or visit: https://clonezilla.org/downloads.php"
    log_info ""
    log_info "Then run this script again:"
    log_info "  sudo $0 clonezilla-live-amd64.iso $USB_DEVICE"
    log_info ""
    log_info "Or if you already have the ISO file:"
    log_info "  sudo $0 /path/to/clonezilla-live-*.iso $USB_DEVICE"
    return 1
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# #region agent log
debug_log "create_clonezilla_usb.sh:36" "Script started" "{\"argv\":[\"$@\"],\"euid\":$EUID}" "A"
# #endregion

CLONEZILLA_ISO="${1:-}"
USB_DEVICE="${2:-}"
FOUND_ISO=""  # Global variable for ISO found by function

# #region agent log
debug_log "create_clonezilla_usb.sh:40" "Parameters parsed" "{\"iso\":\"$CLONEZILLA_ISO\",\"usb_device\":\"$USB_DEVICE\"}" "A"
# #endregion

# Check internet connection if ISO not provided
if [[ -z "$CLONEZILLA_ISO" ]]; then
    check_internet
fi

# Function to find Clonezilla ISO
# Returns ISO path via echo, exits with code 1 if not found
find_clonezilla_iso() {
    # #region agent log
    debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:entry" "Finding Clonezilla ISO" "{\"pwd\":\"$(pwd)\"}" "B"
    # #endregion
    
    local iso_files=($(find . -maxdepth 1 -name "clonezilla-live-*.iso" 2>/dev/null))
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:found" "ISO search results" "{\"count\":${#iso_files[@]},\"files\":[$(printf '"%s",' "${iso_files[@]}" | sed 's/,$//')]}" "B"
    # #endregion
    
    # Filter out empty or invalid ISO files
    local valid_iso_files=()
    for iso_file in "${iso_files[@]}"; do
        if [[ -f "$iso_file" ]]; then
            local file_size=$(stat -f%z "$iso_file" 2>/dev/null || stat -c%s "$iso_file" 2>/dev/null || echo "0")
            # #region agent log
            debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:checking" "Checking ISO file" "{\"file\":\"$iso_file\",\"size\":$file_size}" "B"
            # #endregion
            # ISO files should be at least 100MB (104857600 bytes)
            if [[ $file_size -gt 104857600 ]]; then
                valid_iso_files+=("$iso_file")
            else
                log_warn "Skipping invalid/empty ISO file: $iso_file (size: $file_size bytes)"
            fi
        fi
    done
    
    if [[ ${#valid_iso_files[@]} -eq 0 ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:error" "No valid ISO found, will download" "{\"total_found\":${#iso_files[@]}}" "B"
        # #endregion
        FOUND_ISO=""
        log_warn "Clonezilla ISO not found in current directory: $(pwd)"
        if [[ ${#iso_files[@]} -gt 0 ]]; then
            log_warn "Found ${#iso_files[@]} file(s) but they are empty or invalid"
        fi
        log_info ""
        log_info "Downloading Clonezilla ISO automatically..."
        
        # Download ISO
        local downloaded_iso
        if downloaded_iso=$(download_clonezilla_iso "clonezilla-live-amd64.iso"); then
            FOUND_ISO="$downloaded_iso"
            return 0
        else
            return 1
        fi
    elif [[ ${#valid_iso_files[@]} -eq 1 ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:single" "Single valid ISO found" "{\"file\":\"${valid_iso_files[0]}\"}" "B"
        # #endregion
        FOUND_ISO="${valid_iso_files[0]}"
        return 0
    else
        # #region agent log
        debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:multiple" "Multiple valid ISOs found" "{\"count\":${#valid_iso_files[@]}}" "B"
        # #endregion
        log_info "Multiple Clonezilla ISOs found:"
        for i in "${!valid_iso_files[@]}"; do
            echo "  $((i+1)). ${valid_iso_files[$i]}"
        done
        read -p "Select ISO number: " selection
        # #region agent log
        debug_log "create_clonezilla_usb.sh:find_clonezilla_iso:selected" "User selected ISO" "{\"selection\":$selection,\"file\":\"${valid_iso_files[$((selection-1))]}\"}" "B"
        # #endregion
        FOUND_ISO="${valid_iso_files[$((selection-1))]}"
        return 0
    fi
}

# Function to list USB devices
list_usb_devices() {
    # #region agent log
    debug_log "create_clonezilla_usb.sh:list_usb_devices:entry" "Listing USB devices" "{}" "C"
    # #endregion
    
    log_info "Available USB/removable devices:"
    local devices=$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E 'disk|part' | grep -v loop)
    echo "$devices"
    echo ""
    log_info "Look for devices like /dev/sdb, /dev/sdc, etc."
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:list_usb_devices:exit" "USB devices listed" "{\"devices\":\"$devices\"}" "C"
    # #endregion
}

# Function to confirm device
confirm_device() {
    local dev="$1"
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:confirm_device:entry" "Confirming device" "{\"device\":\"$dev\"}" "D"
    # #endregion
    
    log_warn "=========================================="
    log_warn "WARNING: All data on $dev will be destroyed!"
    log_warn "=========================================="
    log_warn "Device information:"
    local device_info=$(fdisk -l "$dev" 2>/dev/null | head -10)
    echo "$device_info"
    echo ""
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:confirm_device:before_confirm" "Before user confirmation" "{\"device\":\"$dev\",\"info\":\"$device_info\"}" "D"
    # #endregion
    
    read -p "Type 'YES' to confirm formatting $dev: " confirm
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:confirm_device:user_input" "User confirmation input" "{\"confirm\":\"$confirm\"}" "D"
    # #endregion
    
    if [[ "$confirm" != "YES" ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:confirm_device:cancelled" "User cancelled" "{}" "D"
        # #endregion
        log_info "Cancelled"
        exit 0
    fi
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:confirm_device:confirmed" "Device confirmed" "{\"device\":\"$dev\"}" "D"
    # #endregion
}

# Function to create bootable USB
create_bootable_usb() {
    local iso_file="$1"
    local usb_dev="$2"
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:entry" "Creating bootable USB" "{\"iso\":\"$iso_file\",\"usb\":\"$usb_dev\"}" "E"
    # #endregion
    
    log_info "Creating bootable Clonezilla USB..."
    log_info "ISO: $iso_file"
    log_info "USB: $usb_dev"
    
    # Verify ISO exists
    if [[ ! -f "$iso_file" ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:create_bootable_usb:iso_missing" "ISO file not found" "{\"iso\":\"$iso_file\"}" "E"
        # #endregion
        log_error "ISO file not found: $iso_file"
        exit 1
    fi
    
    # #region agent log
    local iso_size=$(stat -f%z "$iso_file" 2>/dev/null || stat -c%s "$iso_file" 2>/dev/null || echo "unknown")
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:iso_verified" "ISO verified" "{\"iso\":\"$iso_file\",\"size\":\"$iso_size\"}" "E"
    # #endregion
    
    # Verify USB device exists
    if [[ ! -b "$usb_dev" ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:create_bootable_usb:usb_missing" "USB device not found" "{\"usb\":\"$usb_dev\"}" "E"
        # #endregion
        log_error "USB device not found: $usb_dev"
        exit 1
    fi
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:usb_verified" "USB device verified" "{\"usb\":\"$usb_dev\"}" "E"
    # #endregion
    
    # Unmount any existing partitions
    log_info "Unmounting existing partitions..."
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:before_unmount" "Before unmounting" "{\"usb\":\"$usb_dev\"}" "E"
    # #endregion
    umount "${usb_dev}"* 2>/dev/null || true
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:after_unmount" "After unmounting" "{\"usb\":\"$usb_dev\"}" "E"
    # #endregion
    
    # Write ISO to USB using dd
    log_warn "Writing ISO to USB. This will take several minutes..."
    log_warn "Do not remove USB during this process!"
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:before_dd" "Before dd write" "{\"iso\":\"$iso_file\",\"usb\":\"$usb_dev\"}" "E"
    # #endregion
    
    dd if="$iso_file" of="$usb_dev" bs=4M status=progress oflag=sync
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:after_dd" "After dd write" "{\"iso\":\"$iso_file\",\"usb\":\"$usb_dev\"}" "E"
    # #endregion
    
    # Sync to ensure data is written
    sync
    
    # Verify USB was written correctly
    log_info "Verifying USB creation..."
    sleep 2  # Wait for USB to settle
    
    # Check if USB has partitions (indicates successful write)
    local partition_count=$(fdisk -l "$usb_dev" 2>/dev/null | grep -c "^/dev" || echo "0")
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:create_bootable_usb:complete" "USB creation complete" "{\"usb\":\"$usb_dev\",\"partitions\":$partition_count}" "E"
    # #endregion
    
    if [[ $partition_count -gt 0 ]]; then
        log_info "USB verification: OK (found $partition_count partition(s))"
    else
        log_warn "USB verification: Could not detect partitions (may still work)"
    fi
    
    log_info ""
    log_info "Bootable Clonezilla USB created successfully!"
    log_info "Device: $usb_dev"
    log_info ""
    log_info "Next steps to boot from Clonezilla USB:"
    log_info ""
    log_info "1. IMPORTANT: Keep USB plugged in"
    log_info "2. Power on or restart your computer"
    log_info "3. Immediately press F11 repeatedly during startup"
    log_info "4. In boot menu, look for 'Boot Override' or boot device selection"
    log_info "5. Select the Clonezilla USB (may show as 'UEFI: USB' or similar)"
    log_info "6. Follow Clonezilla prompts to create/restore backups"
    log_info "" 
    log_warn "If USB is NOT recognized in boot menu (F11), try:"
    log_info ""
    log_info "Boot Method:"
    log_info "  - Ensure USB is plugged in BEFORE powering on"
    log_info "  - Press F11 immediately when you see manufacturer logo"
    log_info "  - Look for 'Boot Override' option in the menu"
    log_info ""
    log_info "UEFI Settings (if USB doesn't appear):"
    log_info "  1. Enter BIOS/UEFI setup (F2, F10, DEL, or ESC during boot)"
    log_info "  2. Disable 'Secure Boot' (REQUIRED - Clonezilla doesn't support it)"
    log_info "  3. Enable 'UEFI Boot' mode (disable Legacy/CSM/BIOS mode)"
    log_info "  4. Save and exit, then try F11 boot menu again"
    log_info ""
    log_info "Hardware:"
    log_info "  - Try different USB port (USB 2.0 port often works better)"
    log_info "  - Try different USB drive if available"
    log_info ""
    log_info "Verification:"
    log_info "  - Check USB partition: sudo fdisk -l $usb_dev"
    log_info "  - Verify USB detected: lsblk | grep $(basename $usb_dev)"
}

# Main
main() {
    log_info "=== Clonezilla USB Creator ==="
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:main:entry" "Main function started" "{\"iso_provided\":\"${CLONEZILLA_ISO:-none}\",\"usb_provided\":\"${USB_DEVICE:-none}\"}" "A"
    # #endregion
    
    # Find Clonezilla ISO if not provided
    if [[ -z "$CLONEZILLA_ISO" ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:main:finding_iso" "ISO not provided, searching" "{}" "A"
        # #endregion
        # Call function - uses global FOUND_ISO variable
        if ! find_clonezilla_iso; then
            # #region agent log
            debug_log "create_clonezilla_usb.sh:main:iso_not_found" "ISO not found, exiting" "{\"found\":\"$FOUND_ISO\"}" "A"
            # #endregion
            exit 1
        fi
        if [[ -z "$FOUND_ISO" ]]; then
            # #region agent log
            debug_log "create_clonezilla_usb.sh:main:iso_empty" "ISO variable empty, exiting" "{}" "A"
            # #endregion
            exit 1
        fi
        CLONEZILLA_ISO="$FOUND_ISO"
        # #region agent log
        debug_log "create_clonezilla_usb.sh:main:iso_resolved" "ISO resolved" "{\"iso\":\"$CLONEZILLA_ISO\"}" "A"
        # #endregion
    fi
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:main:iso_resolved" "ISO resolved" "{\"iso\":\"$CLONEZILLA_ISO\"}" "A"
    # #endregion
    
    # Get USB device if not provided
    if [[ -z "$USB_DEVICE" ]]; then
        # #region agent log
        debug_log "create_clonezilla_usb.sh:main:listing_devices" "USB device not provided, listing" "{}" "A"
        # #endregion
        list_usb_devices
        read -p "Enter USB device (e.g., /dev/sdb): " USB_DEVICE
        # #region agent log
        debug_log "create_clonezilla_usb.sh:main:usb_input" "User provided USB device" "{\"usb\":\"$USB_DEVICE\"}" "A"
        # #endregion
    fi
    
    # Confirm
    confirm_device "$USB_DEVICE"
    
    # Create bootable USB
    create_bootable_usb "$CLONEZILLA_ISO" "$USB_DEVICE"
    
    # #region agent log
    debug_log "create_clonezilla_usb.sh:main:complete" "Main function complete" "{}" "A"
    # #endregion
    
    log_info "=== Complete ==="
}

main "$@"
