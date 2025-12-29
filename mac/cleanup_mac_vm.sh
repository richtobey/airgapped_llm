#!/usr/bin/env bash
set -euo pipefail

# Cleanup script to remove downloaded ISO and related files created by setup_mac_vm.sh
# Usage: ./cleanup_mac_vm.sh [--force]

# ============
# Config
# ============
VM_DIR="${VM_DIR:-$HOME/vm-popos}"
FORCE="${FORCE:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --force)
      FORCE="true"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--force]"
      echo "  --force        Skip confirmation prompts"
      exit 1
      ;;
  esac
done

# Log function compatible with macOS date command
log() { 
  # macOS uses BSD date, which doesn't support -Is format
  # Use a format that works on both macOS and Linux
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS/BSD date
    echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*"
  else
    # Linux/GNU date
    echo "[$(date -Is)] $*"
  fi
}

# ============
# Confirmation
# ============
if [[ "$FORCE" != "true" ]]; then
  echo "This will remove:"
  echo "  - Downloaded Pop!_OS ISO"
  echo "  - VM directory: $VM_DIR"
  if [[ -d "$VM_DIR" ]] && [[ -f "$VM_DIR/iso/pop-os.iso" ]]; then
    echo "  - Note: Valid Pop!_OS ISO will be preserved if checksum verifies"
  fi
  echo ""
  echo "Note: This only removes downloaded files. UTM VMs are stored separately"
  echo "      and will not be affected by this cleanup."
  echo ""
  read -p "Are you sure you want to continue? (yes/no) " -r
  echo
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log "Cleanup cancelled."
    exit 0
  fi
fi

# ============
# 1) Remove VM Directory
# ============
log "Removing VM directory..."

# Initialize preserve flag
PRESERVE_ISO="false"

if [[ -d "$VM_DIR" ]]; then
  log "Found VM directory: $VM_DIR"
  
  # Check if Pop!_OS ISO exists and should be preserved
  POPOS_ISO="$VM_DIR/iso/pop-os.iso"
  POPOS_SHA256="$VM_DIR/iso/pop-os.iso.sha256"
  
  if [[ -f "$POPOS_ISO" ]]; then
    log "Found Pop!_OS ISO: $POPOS_ISO"
    
    if [[ -f "$POPOS_SHA256" ]]; then
      log "Found SHA256 checksum file, validating ISO..."
      if command -v shasum >/dev/null 2>&1; then
        if (cd "$(dirname "$POPOS_ISO")" && shasum -a 256 -c "$(basename "$POPOS_SHA256")" >/dev/null 2>&1); then
          log "✓ ISO checksum validation passed - preserving ISO"
          PRESERVE_ISO="true"
        else
          log "✗ ISO checksum validation failed - will remove ISO"
          log "Note: ISO appears to be corrupted or wrong version"
        fi
      else
        log "WARNING: shasum not found, cannot validate checksum"
        log "Preserving ISO (checksum validation skipped)"
        PRESERVE_ISO="true"
      fi
    else
      log "ISO exists but no checksum file found"
      log "Preserving ISO (checksum validation skipped)"
      log "Note: ISO integrity cannot be verified without checksum file"
      PRESERVE_ISO="true"
    fi
  fi
  
  # Calculate size before removal
  if command -v du >/dev/null 2>&1; then
    SIZE=$(du -sh "$VM_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log "VM directory size: $SIZE"
  fi
  
  # Remove VM components, preserving ISO if valid
  if [[ "$PRESERVE_ISO" == "true" ]]; then
    log "Preserving valid Pop!_OS ISO..."
    
    # Remove subdirectories except iso/
    if [[ -d "$VM_DIR/disk" ]]; then
      rm -rf "$VM_DIR/disk"
      log "✓ Removed disk directory"
    fi
    if [[ -d "$VM_DIR/logs" ]]; then
      rm -rf "$VM_DIR/logs"
      log "✓ Removed logs directory"
    fi
    if [[ -d "$VM_DIR/scripts" ]]; then
      rm -rf "$VM_DIR/scripts"
      log "✓ Removed scripts directory"
    fi
    
    # Remove any other files in VM_DIR root (like README.md)
    find "$VM_DIR" -maxdepth 1 -type f -delete 2>/dev/null || true
    
    log "✓ Cleaned up VM directory (preserved ISO)"
    log "  Preserved: $POPOS_ISO"
    if [[ -f "$POPOS_SHA256" ]]; then
      log "  Preserved: $POPOS_SHA256"
    else
      log "  Note: No checksum file found (ISO preserved anyway)"
    fi
  else
    # Remove the entire directory
    rm -rf "$VM_DIR"
    log "✓ Removed VM directory: $VM_DIR"
  fi
else
  log "VM directory not found: $VM_DIR (nothing to remove)"
fi

# ============
# Summary
# ============
log ""
log "=========================================="
log "Cleanup Complete!"
log "=========================================="
log ""
log "Removed:"
if [[ "$PRESERVE_ISO" == "true" ]]; then
  log "  - Other files in VM directory"
  log "  - Preserved valid Pop!_OS ISO: $VM_DIR/iso/pop-os.iso"
else
  log "  - VM directory: $VM_DIR"
fi
log ""
log "Note: UTM VMs are stored separately and were not affected."
log "      To remove UTM VMs, delete them from within UTM."
log ""
log "To download the ISO again, run: ./setup_mac_vm.sh"
log ""

