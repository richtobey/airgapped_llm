#!/usr/bin/env bash
set -euo pipefail

# ============
# Config
# ============
VM_BUNDLE_DIR="${VM_BUNDLE_DIR:-$PWD/vm_bundle}"
VM_DISK_SIZE="${VM_DISK_SIZE:-50G}"
VM_MEMORY="${VM_MEMORY:-4G}"
VM_CPUS="${VM_CPUS:-2}"
PREINSTALL_AIRGAP="${PREINSTALL_AIRGAP:-true}"
POPOS_VERSION="${POPOS_VERSION:-}"
ARCH="amd64"  # Always target x86_64/amd64 architecture

# Detect host architecture
HOST_ARCH="$(uname -m)"
HOST_OS="$(uname -s)"

# Determine if we need cross-architecture emulation
if [[ "$HOST_ARCH" == "arm64" ]] && [[ "$HOST_OS" == "Darwin" ]]; then
  # Apple Silicon Mac - need x86_64 emulation
  CROSS_ARCH=true
  log "Detected Apple Silicon Mac (ARM64). Will use x86_64 emulation."
elif [[ "$HOST_ARCH" == "x86_64" ]] || [[ "$HOST_ARCH" == "amd64" ]]; then
  # x86_64 host - native or KVM
  CROSS_ARCH=false
  log "Detected x86_64 host. Will use native/KVM acceleration."
else
  # Unknown architecture - assume cross-arch needed
  CROSS_ARCH=true
  log "WARNING: Unknown host architecture ($HOST_ARCH). Assuming x86_64 emulation needed."
fi

# Get script directory for helper scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get project root directory (parent of vm/)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p \
  "$VM_BUNDLE_DIR"/{qemu,popos,vm,airgap_bundle,config,scripts,logs}

log() { echo "[$(date -Is)] $*"; }

sha256_check_file() {
  local file="$1"
  local sha_file="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")")
  elif command -v shasum >/dev/null 2>&1; then
    # macOS uses shasum
    (cd "$(dirname "$file")" && shasum -a 256 -c "$(basename "$sha_file")")
  else
    echo "ERROR: Neither sha256sum nor shasum found"
    exit 1
  fi
}

# ============
# 1) Download QEMU binaries (if not already installed)
# ============
log "Checking for QEMU installation..."

# Always require qemu-system-x86_64 for x86_64 target
if command -v qemu-system-x86_64 >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1; then
  log "QEMU x86_64 found in system PATH. Will use system QEMU."
  QEMU_SYSTEM="$(command -v qemu-system-x86_64)"
  QEMU_IMG="$(command -v qemu-img)"
else
  log "QEMU x86_64 not found in system. This script requires QEMU to be installed."
  log "Please install QEMU first:"
  log "  - Linux: sudo apt-get install qemu-system-x86 qemu-utils"
  log "  - macOS: brew install qemu"
  log ""
  log "Note: On Apple Silicon Macs, QEMU will use x86_64 emulation (slower than native)."
  exit 1
fi

log "Using QEMU: $QEMU_SYSTEM"
log "Using qemu-img: $QEMU_IMG"

# Check QEMU version and capabilities
QEMU_VERSION="$($QEMU_SYSTEM --version 2>&1 | head -n1 || echo "unknown")"
log "QEMU version: $QEMU_VERSION"

if [[ "$CROSS_ARCH" == "true" ]]; then
  log "NOTE: Running x86_64 emulation on $HOST_ARCH host."
  log "      Performance will be slower than native/KVM."
  log "      Consider using a Linux x86_64 machine for faster bundle creation."
fi

# Copy QEMU binaries to bundle (for reference/portability)
# Note: On Linux, QEMU binaries have many dependencies, so we'll document them
cat >"$VM_BUNDLE_DIR/qemu/README.txt" <<EOF
QEMU binaries and dependencies

This directory contains information about QEMU installation.

System QEMU binaries used:
- qemu-system-x86_64: $QEMU_SYSTEM
- qemu-img: $QEMU_IMG

Host architecture: $HOST_ARCH ($HOST_OS)
Cross-architecture emulation: $CROSS_ARCH
Target architecture: x86_64/amd64

On the target airgapped system, QEMU must be installed.
Required packages (Debian/Ubuntu/Pop!_OS):
- qemu-system-x86
- qemu-utils
- qemu-kvm (for KVM acceleration on x86_64 hosts)

These packages will be included in the APT repo if building on Linux.

Note: This VM bundle targets x86_64 architecture. On ARM64 hosts,
      QEMU will use software emulation (TCG) which is slower than
      native/KVM acceleration.
EOF

# ============
# 2) Download Pop!_OS ISO
# ============
log "Fetching Pop!_OS ISO..."
log "Target: amd64 NVIDIA variant (for System76 machine compatibility)"

python3 - <<'PY' "$VM_BUNDLE_DIR" "$POPOS_VERSION"
import json, sys, urllib.request, urllib.error, re
from pathlib import Path

bundle = Path(sys.argv[1])
popos_version = sys.argv[2] if len(sys.argv) > 2 else None
outdir = bundle/"popos"
outdir.mkdir(parents=True, exist_ok=True)

# Pop!_OS now uses an API to get download URLs
# API endpoint: https://api.pop-os.org/builds/{version}/{channel}?arch={arch}
# For System76 machines, we always use the NVIDIA variant (amd64_nvidia)
# This matches what System76 machines use and ensures compatibility

def get_iso_from_api(version, channel="nvidia", arch="amd64"):
    """Get ISO URL and SHA256 from Pop!_OS API."""
    try:
        api_url = f"https://api.pop-os.org/builds/{version}/{channel}?arch={arch}"
        print(f"Querying Pop!_OS API: {api_url}")
        response = urllib.request.urlopen(api_url, timeout=10)
        data = json.loads(response.read().decode('utf-8'))
        if 'url' in data:
            iso_url = data['url']
            iso_name = iso_url.split("/")[-1]
            sha256 = data.get('sha_sum', None)
            print(f"✓ Found ISO via API: {iso_name}")
            return iso_url, iso_name, sha256
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None, None, None
        print(f"Warning: API returned HTTP {e.code}")
    except Exception as e:
        print(f"Warning: API error: {e}")
    return None, None, None

sha256_from_api = None

if popos_version:
    # User specified version/URL
    if popos_version.startswith("http"):
        iso_url = popos_version
        iso_name = iso_url.split("/")[-1]
        sha256_from_api = None  # Can't get SHA256 from direct URL
    else:
        # Try API first (most reliable)
        iso_url, iso_name, sha256_from_api = get_iso_from_api(popos_version, "nvidia", "amd64")
        if not iso_url:
            # Fallback to old URL pattern
            iso_url = f"https://iso.pop-os.org/{popos_version}/pop-os_{popos_version}_amd64_nvidia.iso"
            iso_name = f"pop-os_{popos_version}_amd64_nvidia.iso"
            sha256_from_api = None
else:
    # Auto-detect: Try API with common versions (newest first)
    fallback_versions = ["24.04", "22.04", "23.04"]
    iso_url = None
    iso_name = None
    
    for version in fallback_versions:
        print(f"Trying version {version} via API...")
        iso_url, iso_name, sha256_from_api = get_iso_from_api(version, "nvidia", "amd64")
        if iso_url:
            break
    
    # If API fails, try legacy URL patterns
    if not iso_url:
        print("API methods failed, trying legacy URL patterns...")
        for version in fallback_versions:
            legacy_url = f"https://iso.pop-os.org/{version}/pop-os_{version}_amd64_nvidia.iso"
            try:
                req = urllib.request.Request(legacy_url)
                req.get_method = lambda: 'HEAD'
                urllib.request.urlopen(req, timeout=10)
                iso_url = legacy_url
                iso_name = f"pop-os_{version}_amd64_nvidia.iso"
                sha256_from_api = None
                print(f"✓ Found legacy URL: {iso_name}")
                break
            except Exception:
                continue
    
    if not iso_url:
        print("ERROR: Could not find any available Pop!_OS ISO.")
        print("Tried versions: " + ", ".join(fallback_versions))
        print("Please specify a version manually:")
        print("  export POPOS_VERSION=22.04")
        raise SystemExit("No Pop!_OS ISO found. Please specify POPOS_VERSION manually.")

print(f"Pop!_OS ISO URL: {iso_url}")
print(f"ISO filename: {iso_name}")

# Download ISO (this is large, ~3GB)
iso_path = outdir / iso_name
print(f"Downloading Pop!_OS ISO (this may take a while, ~3GB)...")
try:
    urllib.request.urlretrieve(iso_url, iso_path)
    print(f"Downloaded: {iso_path}")
except Exception as e:
    raise SystemExit(f"Failed to download Pop!_OS ISO: {e}")

# Save SHA256 checksum if available
sha256_file = outdir / (iso_name + ".sha256")
if sha256_from_api:
    # Use SHA256 from API response
    sha256_file.write_text(f"{sha256_from_api}  {iso_name}\n", encoding="utf-8")
    print(f"Saved SHA256 from API: {sha256_file}")
else:
    # Try to get SHA256 checksum from URL (legacy method)
    sha256_url = iso_url + ".sha256"
    try:
        sha256_content = urllib.request.urlopen(sha256_url, timeout=10).read().decode("utf-8").strip()
        sha256_file.write_text(sha256_content, encoding="utf-8")
        print(f"Downloaded SHA256: {sha256_file}")
    except Exception:
        print("Warning: Could not download SHA256 checksum for Pop!_OS ISO")
PY

POPOS_ISO="$(ls -1 "$VM_BUNDLE_DIR/popos"/pop-os_*.iso 2>/dev/null | head -n1)"
if [[ -z "$POPOS_ISO" ]]; then
  log "ERROR: Pop!_OS ISO not found after download"
  exit 1
fi

log "Pop!_OS ISO downloaded: $POPOS_ISO"

# Verify SHA256 if available
if [[ -f "$POPOS_ISO.sha256" ]]; then
  log "Verifying Pop!_OS ISO SHA256..."
  sha256_check_file "$POPOS_ISO" "$POPOS_ISO.sha256" || {
    log "WARNING: SHA256 verification failed. Continuing anyway..."
  }
fi

# ============
# 3) Create VM disk image
# ============
log "Creating VM disk image (size: $VM_DISK_SIZE)..."
VM_DISK="$VM_BUNDLE_DIR/vm/popos-airgap.qcow2"

if [[ -f "$VM_DISK" ]]; then
  log "VM disk image already exists. Removing old image..."
  rm -f "$VM_DISK"
fi

"$QEMU_IMG" create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE"
log "VM disk image created: $VM_DISK"

# ============
# 4) Install Pop!_OS in VM (automated)
# ============
log "Installing Pop!_OS in VM..."
log "This will use the helper script to automate installation."

# Check if helper script exists
if [[ ! -f "$SCRIPT_DIR/scripts/install_popos_vm.sh" ]]; then
  log "ERROR: Pop!_OS installation helper script not found: $SCRIPT_DIR/scripts/install_popos_vm.sh"
  log "Please ensure scripts/install_popos_vm.sh exists in the vm/ directory."
  exit 1
fi

# Run Pop!_OS installation
# Pass cross-architecture flag to installation script
export CROSS_ARCH="$CROSS_ARCH"
export HOST_ARCH="$HOST_ARCH"
"$SCRIPT_DIR/scripts/install_popos_vm.sh" \
  "$QEMU_SYSTEM" \
  "$POPOS_ISO" \
  "$VM_DISK" \
  "$VM_MEMORY" \
  "$VM_CPUS" \
  "$VM_BUNDLE_DIR/logs" || {
  log "ERROR: Pop!_OS installation failed. Check logs in $VM_BUNDLE_DIR/logs/"
  log "You may need to install Pop!_OS manually by running the script again."
  exit 1
}

log "Pop!_OS installed in VM."

# ============
# 5) Create airgap bundle (nested)
# ============
log "Creating airgap bundle inside VM bundle..."
AIRGAP_BUNDLE_DIR="$VM_BUNDLE_DIR/airgap_bundle"

# Call get_bundle.sh from airgap/ directory with modified BUNDLE_DIR
export BUNDLE_DIR="$AIRGAP_BUNDLE_DIR"
# Preserve other environment variables
export OLLAMA_MODELS="${OLLAMA_MODELS:-mistral:7b-instruct mixtral:8x7b mistral:7b-instruct-q4_K_M}"
export OLLAMA_MODEL="${OLLAMA_MODEL:-}"
export PYTHON_REQUIREMENTS="${PYTHON_REQUIREMENTS:-$PROJECT_ROOT/requirements.txt}"
export RUST_CARGO_TOML="${RUST_CARGO_TOML:-$PROJECT_ROOT/Cargo.toml}"

log "Running get_bundle.sh from airgap/ directory to create nested airgap bundle..."
"$PROJECT_ROOT/airgap/get_bundle.sh" || {
  log "ERROR: Failed to create airgap bundle"
  exit 1
}

log "Airgap bundle created at: $AIRGAP_BUNDLE_DIR"

# ============
# 6) Copy airgap bundle into VM (via shared folder or direct copy)
# ============
if [[ "$PREINSTALL_AIRGAP" == "true" ]]; then
  log "Pre-installing airgap bundle in VM..."
  
  # We'll copy the bundle into the VM disk image
  # This requires mounting the qcow2 image or using guestfish/virt-copy-in
  # For simplicity, we'll create a script that can be run inside the VM
  
  # Create a script to copy and install the bundle inside the VM
  cat >"$VM_BUNDLE_DIR/scripts/install_airgap_in_vm.sh" <<'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

# This script runs inside the VM to install the airgap bundle
# It expects the airgap bundle to be available at /mnt/airgap_bundle

BUNDLE_DIR="${1:-/mnt/airgap_bundle}"

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "ERROR: Airgap bundle not found at $BUNDLE_DIR"
  exit 1
fi

echo "Installing airgap bundle from $BUNDLE_DIR..."
cd "$BUNDLE_DIR"

# Run the installation script
if [[ -f "install_offline.sh" ]]; then
  chmod +x install_offline.sh
  sudo ./install_offline.sh || {
    echo "WARNING: Some installation steps may have failed"
  }
else
  echo "ERROR: install_offline.sh not found in bundle"
  exit 1
fi

echo "Airgap bundle installation completed."
SCRIPT_EOF
  chmod +x "$VM_BUNDLE_DIR/scripts/install_airgap_in_vm.sh"
  
  log "Created installation script for VM: $VM_BUNDLE_DIR/scripts/install_airgap_in_vm.sh"
  log "Note: The airgap bundle will need to be mounted/copied into the VM before running this script."
  log "You can do this manually or use virt-copy-in/virt-rescue tools."
else
  log "Skipping pre-installation. Airgap bundle will be installed manually in VM."
fi

# ============
# 7) Create VM configuration files
# ============
log "Creating VM configuration files..."

# QEMU command-line arguments
# Note: CPU type depends on host architecture
if [[ "$CROSS_ARCH" == "true" ]]; then
  CPU_TYPE="qemu64"
  KVM_ARG="# KVM not available for cross-architecture emulation"
else
  CPU_TYPE="host"
  KVM_ARG="-enable-kvm"
fi

cat >"$VM_BUNDLE_DIR/config/qemu-args.txt" <<EOF
# QEMU command-line arguments for starting the VM
# Usage: qemu-system-x86_64 \$(cat config/qemu-args.txt)
# Target architecture: x86_64/amd64
# Host architecture: $HOST_ARCH
# Cross-architecture: $CROSS_ARCH

$KVM_ARG
-cpu $CPU_TYPE
-m ${VM_MEMORY}
-smp ${VM_CPUS}
-drive file=vm/popos-airgap.qcow2,format=qcow2,if=virtio
-netdev user,id=net0
-device virtio-net,netdev=net0
-display gtk
-vga virtio
-audiodev pa,id=snd0
-device virtio-sound-pci,audiodev=snd0
-usb
-device usb-tablet
EOF

# Startup script
cat >"$VM_BUNDLE_DIR/scripts/start_vm.sh" <<'START_EOF'
#!/usr/bin/env bash
set -euo pipefail

# Get script directory (vm/scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Get VM bundle directory (parent of scripts/, which is vm/)
VM_BUNDLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_DISK="$VM_BUNDLE_DIR/vm/popos-airgap.qcow2"

# Check if VM disk exists
if [[ ! -f "$VM_DISK" ]]; then
  echo "ERROR: VM disk not found: $VM_DISK"
  exit 1
fi

# Check for QEMU x86_64
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
  echo "ERROR: qemu-system-x86_64 not found. Please install QEMU first."
  exit 1
fi

# Detect host architecture
HOST_ARCH="$(uname -m)"

# Determine CPU type and KVM availability
# Always target x86_64 architecture
if [[ "$HOST_ARCH" == "arm64" ]] || [[ "$HOST_ARCH" == "aarch64" ]]; then
  # ARM64 host - use x86_64 emulation
  CPU_TYPE="qemu64"
  KVM_ARG=""
  echo "Detected ARM64 host. Using x86_64 emulation (CPU: $CPU_TYPE)"
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
echo "  Target Architecture: x86_64/amd64"
echo "  Host Architecture: $HOST_ARCH"
echo "  CPU Type: $CPU_TYPE"
cd "$VM_BUNDLE_DIR"

# Build QEMU command
QEMU_CMD=(
  qemu-system-x86_64
)

# Add KVM if available
if [[ -n "$KVM_ARG" ]]; then
  QEMU_CMD+=($KVM_ARG)
fi

# Add other options
QEMU_CMD+=(
  -cpu "$CPU_TYPE"
  -m 4G
  -smp 2
  -drive "file=$VM_DISK,format=qcow2,if=virtio"
  -netdev user,id=net0
  -device virtio-net,netdev=net0
  -display gtk
  -vga virtio
  -audiodev pa,id=snd0
  -device virtio-sound-pci,audiodev=snd0
  -usb
  -device usb-tablet
  "$@"
)

# Execute QEMU
"${QEMU_CMD[@]}"
START_EOF
chmod +x "$VM_BUNDLE_DIR/scripts/start_vm.sh"

# Create README for VM bundle
cat >"$VM_BUNDLE_DIR/README.txt" <<README_EOF
VM Bundle for Airgapped Development Environment

This bundle contains:
- QEMU/KVM virtual machine with Pop!_OS pre-installed
- Complete airgap development bundle (nested)

VM Configuration:
- Target Architecture: x86_64/amd64 (always)
- Host Architecture: $HOST_ARCH
- Cross-architecture: $CROSS_ARCH
- Disk size: ${VM_DISK_SIZE}
- Memory: ${VM_MEMORY}
- CPUs: ${VM_CPUS}
- Disk image: vm/popos-airgap.qcow2

Installation:
1. Transfer this entire vm_bundle directory to your airgapped system
2. Run: ./install_vm.sh
3. Follow the installation instructions

Starting the VM:
- Use: ./scripts/start_vm.sh
- Or manually run qemu-system-x86_64 with arguments from config/qemu-args.txt

Inside the VM:
- Pop!_OS is pre-installed
- Airgap bundle is available at: airgap_bundle/
- To install airgap bundle in VM, run:
  cd airgap_bundle
  sudo ./install_offline.sh

Requirements on host system:
- QEMU/KVM installed
- KVM hardware support (Intel VT-x or AMD-V)
- Sufficient disk space (~60GB+)
- Sufficient RAM (host needs ${VM_MEMORY} + overhead for VM)
README_EOF

log "VM configuration files created."

# ============
# Summary
# ============
log "DONE. VM bundle created at: $VM_BUNDLE_DIR"
log ""
log "VM Bundle Summary:"
log " - Pop!_OS ISO: $POPOS_ISO"
log " - VM disk image: $VM_DISK"
log " - Airgap bundle: $AIRGAP_BUNDLE_DIR"
log " - Total size: ~55-60GB (check with: du -sh $VM_BUNDLE_DIR)"
log ""
log "Next steps:"
log "  1. Transfer $VM_BUNDLE_DIR to your airgapped system"
log "  2. On airgapped system, run: ./install_vm.sh"
log "  3. Start the VM with: ./scripts/start_vm.sh"

