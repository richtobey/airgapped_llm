#!/usr/bin/env bash
set -euo pipefail

# Automated Pop!_OS installation in QEMU VM
# Usage: install_popos_vm.sh <qemu_binary> <iso_path> <disk_path> <memory> <cpus> <log_dir>

QEMU_BIN="${1:-qemu-system-x86_64}"
ISO_PATH="${2:-}"
DISK_PATH="${3:-}"
VM_MEMORY="${4:-4G}"
VM_CPUS="${5:-2}"
LOG_DIR="${6:-./logs}"

log() { echo "[$(date -Is)] $*"; }

# Validate inputs
if [[ -z "$ISO_PATH" ]] || [[ ! -f "$ISO_PATH" ]]; then
  log "ERROR: Pop!_OS ISO not found: $ISO_PATH"
  exit 1
fi

if [[ -z "$DISK_PATH" ]]; then
  log "ERROR: VM disk path not specified"
  exit 1
fi

mkdir -p "$LOG_DIR"

log "Starting Pop!_OS installation in VM..."
log "  QEMU: $QEMU_BIN"
log "  ISO: $ISO_PATH"
log "  Disk: $DISK_PATH"
log "  Memory: $VM_MEMORY"
log "  CPUs: $VM_CPUS"

# Check for cross-architecture emulation
CROSS_ARCH="${CROSS_ARCH:-false}"
HOST_ARCH="${HOST_ARCH:-$(uname -m)}"

# Determine CPU type and KVM availability
if [[ "$CROSS_ARCH" == "true" ]] || [[ "$HOST_ARCH" == "arm64" ]]; then
  # Cross-architecture emulation (e.g., ARM64 Mac running x86_64 VM)
  CPU_TYPE="qemu64"
  KVM_ARG=""
  log "Using x86_64 emulation on $HOST_ARCH host (CPU: $CPU_TYPE)"
  log "NOTE: Performance will be slower than native/KVM. This is expected on ARM64 Macs."
elif [[ -c /dev/kvm ]]; then
  # Native x86_64 with KVM acceleration
  CPU_TYPE="host"
  KVM_ARG="-enable-kvm"
  log "KVM acceleration enabled (native x86_64)"
else
  # Native x86_64 without KVM (fallback to TCG)
  CPU_TYPE="host"
  KVM_ARG=""
  log "WARNING: /dev/kvm not found. Using TCG emulation (slower)."
fi

# Note: Pop!_OS does not support fully automated installation like Ubuntu autoinstall.
# The installation will require manual interaction through the QEMU window.
# We'll boot the ISO and let the user complete the installation manually.
CLOUD_INIT_ISO=""

# Start QEMU with Pop!_OS ISO
log "Booting Pop!_OS installer..."
log "NOTE: Pop!_OS installation may require manual interaction."
log "      The installer will appear in a QEMU window."
log "      Please complete the installation manually."
log ""
log "Installation steps:"
log "  1. Select 'Install Pop!_OS' from the boot menu"
log "  2. Follow the installation wizard"
log "  3. When prompted, erase disk and install"
log "  4. Create a user account"
log "  5. Complete installation and reboot"
log ""
log "After installation, the VM will reboot into Pop!_OS."
log "Logs are being written to: $LOG_DIR/qemu-install.log"

# Build QEMU command
QEMU_CMD=(
  "$QEMU_BIN"
)

# Add KVM argument if available
if [[ -n "$KVM_ARG" ]]; then
  QEMU_CMD+=($KVM_ARG)
fi

# Add CPU type and other options
QEMU_CMD+=(
  -cpu "$CPU_TYPE"
  -m "$VM_MEMORY"
  -smp "$VM_CPUS"
  -drive "file=$DISK_PATH,format=qcow2,if=virtio"
  -cdrom "$ISO_PATH"
  -boot order=d
  -display gtk
  -vga virtio
  -audiodev pa,id=snd0
  -device virtio-sound-pci,audiodev=snd0
  -usb
  -device usb-tablet
)

# Cloud-init ISO not used for Pop!_OS (manual installation required)

# Add network (user mode)
QEMU_CMD+=(
  -netdev user,id=net0
  -device virtio-net,netdev=net0
)

log "Starting QEMU..."
log "Command: ${QEMU_CMD[*]}"
log ""
log "QEMU window will open. Complete the Pop!_OS installation in the window."
log "Press Ctrl+C in this terminal to stop QEMU (after installation completes)."

# Run QEMU (this will block until VM is shut down)
"${QEMU_CMD[@]}" >"$LOG_DIR/qemu-install.log" 2>&1 &
QEMU_PID=$!

log "QEMU started (PID: $QEMU_PID)"
log "Waiting for installation to complete..."
log "You can monitor progress in the QEMU window."
log ""
log "To stop QEMU after installation: kill $QEMU_PID"

# Wait for QEMU to finish (user will stop it after installation)
wait $QEMU_PID || true

log "QEMU process ended."
log "Pop!_OS installation should be complete."
log "Verify by starting the VM and checking that Pop!_OS boots."

# Cleanup
rm -rf "$CLOUD_INIT_DIR"

log "Installation script completed."

