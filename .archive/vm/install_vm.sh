#!/usr/bin/env bash
set -euo pipefail

# Install QEMU/KVM VM bundle on airgapped system
# Usage: install_vm.sh [VM_BUNDLE_DIR]

VM_BUNDLE_DIR="${VM_BUNDLE_DIR:-$PWD/vm_bundle}"
VM_INSTALL_DIR="${VM_INSTALL_DIR:-$HOME/.local/share/vm/popos-airgap}"

log() { echo "[$(date -Is)] $*"; }

# ============
# 0) Sanity checks
# ============
test -d "$VM_BUNDLE_DIR" || { echo "VM bundle dir not found: $VM_BUNDLE_DIR"; exit 1; }

# ============
# 1) Check KVM hardware support
# ============
log "Checking for KVM hardware support..."

if ! grep -qE '(vmx|svm)' /proc/cpuinfo; then
  log "WARNING: CPU virtualization support not detected in /proc/cpuinfo"
  log "         Your CPU may not support hardware virtualization."
  log "         The VM will still work but will be slower (software emulation)."
else
  log "✓ CPU virtualization support detected"
fi

if [[ ! -c /dev/kvm ]]; then
  log "WARNING: /dev/kvm not found."
  log "         KVM acceleration will not be available."
  log "         The VM will run slower."
  log ""
  log "To enable KVM:"
  log "  1. Ensure virtualization is enabled in BIOS/UEFI"
  log "  2. Load KVM module: sudo modprobe kvm"
  log "  3. For Intel: sudo modprobe kvm_intel"
  log "  4. For AMD: sudo modprobe kvm_amd"
else
  log "✓ /dev/kvm found"
fi

# ============
# 2) Install QEMU/KVM packages
# ============
log "Checking for QEMU/KVM installation..."

if command -v qemu-system-x86_64 >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1; then
  log "✓ QEMU already installed"
  QEMU_SYSTEM="$(command -v qemu-system-x86_64)"
  QEMU_IMG="$(command -v qemu-img)"
else
  log "QEMU not found. Attempting to install from system packages..."
  
  # Try to install from system repos (if available)
  if command -v apt-get >/dev/null 2>&1; then
    log "Installing QEMU/KVM packages..."
    sudo apt-get update || log "WARNING: apt-get update failed (expected on airgapped system)"
    
    # Check if we have a local APT repo in the bundle
    if [[ -d "$VM_BUNDLE_DIR/airgap_bundle/aptrepo" ]] && [[ -f "$VM_BUNDLE_DIR/airgap_bundle/aptrepo/Packages.gz" ]]; then
      log "Found local APT repo in airgap bundle. Installing QEMU from local repo..."
      
      # Add local repo temporarily
      sudo tee /etc/apt/sources.list.d/airgap-local.list >/dev/null <<EOF
deb [trusted=yes] file:$VM_BUNDLE_DIR/airgap_bundle/aptrepo stable main
EOF
      
      sudo apt-get update 2>&1 | grep -v "Failed to fetch" || true
      
      # Install QEMU packages
      sudo apt-get install -y qemu-system-x86 qemu-utils qemu-kvm || {
        log "WARNING: Could not install QEMU from local repo."
        log "You may need to install QEMU manually or from system repositories."
      }
      
      # Remove temporary repo
      sudo rm -f /etc/apt/sources.list.d/airgap-local.list
    else
      log "No local APT repo found. Attempting system installation..."
      sudo apt-get install -y qemu-system-x86 qemu-utils qemu-kvm || {
        log "ERROR: Could not install QEMU."
        log "Please install QEMU manually:"
        log "  sudo apt-get install qemu-system-x86 qemu-utils qemu-kvm"
        exit 1
      }
    fi
    
    QEMU_SYSTEM="$(command -v qemu-system-x86_64)"
    QEMU_IMG="$(command -v qemu-img)"
  else
    log "ERROR: Could not install QEMU automatically."
    log "Please install QEMU manually for your distribution."
    exit 1
  fi
fi

log "Using QEMU: $QEMU_SYSTEM"
log "Using qemu-img: $QEMU_IMG"

# ============
# 3) Configure user permissions for KVM
# ============
log "Configuring KVM permissions..."

if [[ -c /dev/kvm ]]; then
  # Check if user is in kvm group
  if groups | grep -q kvm; then
    log "✓ User is already in kvm group"
  else
    log "Adding user to kvm group..."
    sudo usermod -aG kvm "$USER" || {
      log "WARNING: Could not add user to kvm group."
      log "You may need to run: sudo usermod -aG kvm $USER"
      log "Then log out and log back in."
    }
    log "NOTE: You may need to log out and log back in for group changes to take effect."
  fi
fi

# ============
# 4) Copy VM disk to installation location
# ============
log "Setting up VM disk..."

VM_DISK="$VM_BUNDLE_DIR/vm/popos-airgap.qcow2"

if [[ ! -f "$VM_DISK" ]]; then
  log "ERROR: VM disk not found: $VM_DISK"
  exit 1
fi

mkdir -p "$VM_INSTALL_DIR"
INSTALLED_DISK="$VM_INSTALL_DIR/popos-airgap.qcow2"

if [[ -f "$INSTALLED_DISK" ]]; then
  log "VM disk already exists at: $INSTALLED_DISK"
  read -p "Overwrite existing VM disk? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$INSTALLED_DISK"
  else
    log "Using existing VM disk."
  fi
fi

if [[ ! -f "$INSTALLED_DISK" ]]; then
  log "Copying VM disk to: $INSTALLED_DISK"
  log "This may take a while (disk image is large)..."
  cp "$VM_DISK" "$INSTALLED_DISK"
  log "VM disk copied."
fi

# ============
# 5) Create VM startup script
# ============
log "Creating VM startup script..."

START_SCRIPT="$VM_INSTALL_DIR/start_vm.sh"

cat >"$START_SCRIPT" <<START_EOF
#!/usr/bin/env bash
set -euo pipefail

# VM startup script for Pop!_OS airgap development environment

VM_DISK="$INSTALLED_DISK"
VM_MEMORY="${VM_MEMORY:-4G}"
VM_CPUS="${VM_CPUS:-2}"

# Check if VM disk exists
if [[ ! -f "\$VM_DISK" ]]; then
  echo "ERROR: VM disk not found: \$VM_DISK"
  exit 1
fi

# Check for QEMU
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: qemu-system-x86_64 not found. Please install QEMU first."
  exit 1
fi

# Detect host architecture
HOST_ARCH="\$(uname -m)"

# Determine CPU type and KVM availability
# Always target x86_64 architecture
if [[ "\$HOST_ARCH" == "arm64" ]] || [[ "\$HOST_ARCH" == "aarch64" ]]; then
  # ARM64 host - use x86_64 emulation
  CPU_TYPE="qemu64"
  KVM_ARG=""
  echo "Detected ARM64 host. Using x86_64 emulation (CPU: \$CPU_TYPE)"
  echo "NOTE: Performance will be slower than native/KVM."
elif [[ -c /dev/kvm ]]; then
  # x86_64 host with KVM
  CPU_TYPE="host"
  KVM_ARG="-enable-kvm"
  echo "Using KVM acceleration (native x86_64)"
else
  # x86_64 host without KVM
  CPU_TYPE="host"
  KVM_ARG=""
  echo "WARNING: /dev/kvm not found. VM will run slower (TCG emulation)."
fi

# Start VM
echo "Starting Pop!_OS VM..."
echo "  Disk: \$VM_DISK"
echo "  Memory: \$VM_MEMORY"
echo "  CPUs: \$VM_CPUS"
echo "  CPU Type: \$CPU_TYPE"
echo "  Target Architecture: x86_64/amd64"
echo ""
echo "QEMU window will open. Use the VM normally."
echo "To stop the VM, shut down Pop!_OS from within the VM."

# Build QEMU command
QEMU_CMD=(
  qemu-system-x86_64
)

# Add KVM if available
if [[ -n "\$KVM_ARG" ]]; then
  QEMU_CMD+=(\$KVM_ARG)
fi

# Add other options
QEMU_CMD+=(
  -cpu "\$CPU_TYPE"
  -m "\$VM_MEMORY"
  -smp "\$VM_CPUS"
  -drive "file=\$VM_DISK,format=qcow2,if=virtio"
  -netdev user,id=net0
  -device virtio-net,netdev=net0
  -display gtk
  -vga virtio
  -audiodev pa,id=snd0
  -device virtio-sound-pci,audiodev=snd0
  -usb
  -device usb-tablet
  "\$@"
)

# Execute QEMU
"\${QEMU_CMD[@]}"
START_EOF

chmod +x "$START_SCRIPT"
log "Startup script created: $START_SCRIPT"

# ============
# 6) Create convenience symlink in bundle
# ============
if [[ -f "$VM_BUNDLE_DIR/scripts/start_vm.sh" ]]; then
  # Update the bundle's start script to point to installed VM
  cat >"$VM_BUNDLE_DIR/scripts/start_vm.sh" <<BUNDLE_START_EOF
#!/usr/bin/env bash
# Convenience script to start the VM
# This calls the installed VM startup script

INSTALLED_SCRIPT="$VM_INSTALL_DIR/start_vm.sh"

if [[ -f "\$INSTALLED_SCRIPT" ]]; then
  exec "\$INSTALLED_SCRIPT" "\$@"
else
  echo "ERROR: VM not installed. Run install_vm.sh first."
  exit 1
fi
BUNDLE_START_EOF
  chmod +x "$VM_BUNDLE_DIR/scripts/start_vm.sh"
fi

# ============
# Summary
# ============
log "DONE. VM installation completed."
log ""
log "Installation Summary:"
log " - VM disk: $INSTALLED_DISK"
log " - Startup script: $START_SCRIPT"
log " - QEMU: $QEMU_SYSTEM"
if [[ -c /dev/kvm ]]; then
  log " - KVM: Enabled"
else
  log " - KVM: Not available (VM will be slower)"
fi
log ""
log "Next steps:"
log "  1. Start the VM: $START_SCRIPT"
log "  2. Or use: $VM_BUNDLE_DIR/scripts/start_vm.sh"
log ""
log "Inside the VM:"
log "  - Pop!_OS is pre-installed"
log "  - Airgap bundle is available at: $VM_BUNDLE_DIR/airgap_bundle/"
log "  - To install airgap bundle in VM:"
log "    cd $VM_BUNDLE_DIR/airgap_bundle"
log "    sudo ./install_offline.sh"
log ""
log "VM Management:"
log "  - Start VM: $START_SCRIPT"
log "  - Stop VM: Shut down Pop!_OS from within the VM"
log "  - VM disk location: $INSTALLED_DISK"

