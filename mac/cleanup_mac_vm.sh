#!/usr/bin/env bash
set -euo pipefail

# Cleanup script to remove VM and related files created by setup_mac_vm.sh
# Usage: ./cleanup_mac_vm.sh [--remove-qemu] [--force]

# ============
# Config
# ============
VM_DIR="${VM_DIR:-$HOME/vm-popos}"
REMOVE_QEMU="${REMOVE_QEMU:-false}"
FORCE="${FORCE:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --remove-qemu)
      REMOVE_QEMU="true"
      shift
      ;;
    --force)
      FORCE="true"
      shift
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--remove-qemu] [--force]"
      echo "  --remove-qemu  Also remove QEMU installed via Homebrew"
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
  echo "  - VM directory: $VM_DIR"
  if [[ "$REMOVE_QEMU" == "true" ]]; then
    echo "  - QEMU installation (via Homebrew)"
  fi
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

if [[ -d "$VM_DIR" ]]; then
  log "Found VM directory: $VM_DIR"
  
  # Check if VM is running (look for QEMU processes using the disk)
  VM_DISK="$VM_DIR/disk/popos-airgap.qcow2"
  if [[ -f "$VM_DISK" ]]; then
    # Check for running QEMU processes
    if pgrep -f "qemu.*$(basename "$VM_DISK")" >/dev/null 2>&1; then
      log "WARNING: VM appears to be running!"
      if [[ "$FORCE" != "true" ]]; then
        read -p "VM is running. Stop it first? (yes/no) " -r
        echo
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
          log "Stopping QEMU processes..."
          pkill -f "qemu.*$(basename "$VM_DISK")" || true
          sleep 2
        else
          log "ERROR: Cannot remove VM directory while VM is running."
          log "Please stop the VM first, or use --force to skip this check."
          exit 1
        fi
      else
        log "Force mode: Attempting to stop QEMU processes..."
        pkill -f "qemu.*$(basename "$VM_DISK")" || true
        sleep 2
      fi
    fi
  fi
  
  # Calculate size before removal
  if command -v du >/dev/null 2>&1; then
    SIZE=$(du -sh "$VM_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log "VM directory size: $SIZE"
  fi
  
  # Remove the directory
  rm -rf "$VM_DIR"
  log "✓ Removed VM directory: $VM_DIR"
else
  log "VM directory not found: $VM_DIR (nothing to remove)"
fi

# ============
# 2) Remove QEMU (optional)
# ============
if [[ "$REMOVE_QEMU" == "true" ]]; then
  log "Removing QEMU installation..."
  
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found. Skipping QEMU removal."
  else
    # Check if QEMU is installed
    if brew list qemu >/dev/null 2>&1; then
      log "Found QEMU installation via Homebrew"
      
      if [[ "$FORCE" != "true" ]]; then
        echo ""
        echo "WARNING: This will remove QEMU, which may be used by other VMs or projects."
        read -p "Remove QEMU? (yes/no) " -r
        echo
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
          log "Skipping QEMU removal."
        else
          brew uninstall qemu || {
            log "WARNING: Failed to uninstall QEMU. You may need to remove it manually."
          }
          log "✓ Removed QEMU"
        fi
      else
        brew uninstall qemu || {
          log "WARNING: Failed to uninstall QEMU. You may need to remove it manually."
        }
        log "✓ Removed QEMU"
      fi
    else
      log "QEMU not installed via Homebrew (nothing to remove)"
    fi
  fi
else
  log "Skipping QEMU removal (use --remove-qemu to remove it)"
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
log "  - VM directory: $VM_DIR"
if [[ "$REMOVE_QEMU" == "true" ]]; then
  log "  - QEMU installation"
fi
log ""
log "To recreate the VM, run: ./setup_mac_vm.sh"
log ""

