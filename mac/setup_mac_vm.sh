#!/usr/bin/env bash
set -euo pipefail

# Setup QEMU and Pop OS VM on macOS for testing airgap scripts
# Usage: ./setup_mac_vm.sh

# ============
# Config
# ============
VM_DIR="${VM_DIR:-$HOME/vm-popos}"
VM_DISK_SIZE="${VM_DISK_SIZE:-50G}"
VM_MEMORY="${VM_MEMORY:-4G}"
VM_CPUS="${VM_CPUS:-2}"
POPOS_VERSION="${POPOS_VERSION:-}"
ARCH="amd64"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$VM_DIR"/{iso,disk,logs,scripts}

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
# 1) Check macOS
# ============
log "Checking macOS version..."

if [[ "$(uname)" != "Darwin" ]]; then
  log "ERROR: This script is designed for macOS only."
  log "For Linux, use get_vm_bundle.sh instead."
  exit 1
fi

MACOS_VERSION="$(sw_vers -productVersion)"
log "macOS version: $MACOS_VERSION"

# ============
# 1.5) Detect CPU Architecture
# ============
log "Detecting CPU architecture..."

CPU_TYPE="$(uname -m)"
if [[ "$CPU_TYPE" == "arm64" ]]; then
  ARCH="arm64"
  QEMU_ARCH="x86_64"
  POPOS_ARCH="amd64"
  log "✓ Detected Apple Silicon (ARM64)"
  log "  Will use x86_64 Pop OS ISO in emulation mode for production testing"
  log "  This ensures we test the exact scripts that will run in production"
else
  ARCH="amd64"
  QEMU_ARCH="x86_64"
  POPOS_ARCH="amd64"
  log "✓ Detected Intel Mac (x86_64)"
  log "  Will use x86_64 Pop OS ISO"
fi

log "Architecture configuration:"
log "  CPU Type: $CPU_TYPE"
log "  ARCH: $ARCH"
log "  QEMU Arch: $QEMU_ARCH"
log "  Pop OS Arch: $POPOS_ARCH"

# ============
# 2) Check and install Homebrew
# ============
log "Checking for Homebrew..."

if ! command -v brew >/dev/null 2>&1; then
  log "Homebrew not found. Installing Homebrew..."
  log "This will prompt for your password."
  
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    log "ERROR: Failed to install Homebrew."
    log "Please install Homebrew manually from https://brew.sh"
    exit 1
  }
  
  # Add Homebrew to PATH (for Apple Silicon Macs)
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
else
  log "✓ Homebrew found"
fi

# ============
# 3) Install QEMU
# ============
log "Checking for QEMU installation..."

QEMU_SYSTEM_BIN="qemu-system-$QEMU_ARCH"

if command -v "$QEMU_SYSTEM_BIN" >/dev/null 2>&1 && command -v qemu-img >/dev/null 2>&1; then
  log "✓ QEMU already installed"
  QEMU_SYSTEM="$(command -v "$QEMU_SYSTEM_BIN")"
  QEMU_IMG="$(command -v qemu-img)"
else
  log "Installing QEMU via Homebrew..."
  brew install qemu || {
    log "ERROR: Failed to install QEMU."
    exit 1
  }
  
  # Ensure PATH is updated after Homebrew installation
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  
  # Verify QEMU binaries are now available
  QEMU_SYSTEM="$(command -v "$QEMU_SYSTEM_BIN")"
  QEMU_IMG="$(command -v qemu-img)"
  
  if [[ -z "$QEMU_SYSTEM" ]] || [[ -z "$QEMU_IMG" ]]; then
    log "ERROR: QEMU binaries not found after installation."
    log "Expected binary: $QEMU_SYSTEM_BIN"
    log "Please ensure Homebrew is in your PATH and try again."
    exit 1
  fi
fi

log "Using QEMU: $QEMU_SYSTEM"
log "Using qemu-img: $QEMU_IMG"

# Verify QEMU binaries work
if [[ -z "$QEMU_SYSTEM" ]] || [[ -z "$QEMU_IMG" ]]; then
  log "ERROR: QEMU binaries not found."
  exit 1
fi

# Verify QEMU version
QEMU_VERSION="$($QEMU_SYSTEM --version | head -n1)" || {
  log "ERROR: Failed to get QEMU version. QEMU may not be working correctly."
  exit 1
}
log "QEMU version: $QEMU_VERSION"

# ============
# 4) Check for Hypervisor.framework (macOS virtualization)
# ============
log "Checking for Hypervisor.framework support..."

# macOS uses Hypervisor.framework (HVF) instead of KVM
# This is available on macOS 10.10+ and all modern Macs
if [[ -d /System/Library/Frameworks/Hypervisor.framework ]]; then
  log "✓ Hypervisor.framework found (HVF acceleration available)"
  ACCEL_ARG="-accel hvf"
else
  log "WARNING: Hypervisor.framework not found. VM will use software emulation (very slow)."
  ACCEL_ARG=""
fi

# CPU model selection based on host and guest architecture
# For production testing, we use x86_64 emulation on Apple Silicon
# Default to qemu64 for emulation on ARM64, host passthrough for native x86_64
if [[ "$ARCH" == "arm64" ]]; then
  # On ARM64 host, using x86_64 guest (emulated) for production testing
  CPU_MODEL="qemu64"
  log "Using x86_64 emulation mode (qemu64 CPU model) for production testing"
else
  # On x86_64 host, always use host passthrough
  CPU_MODEL="host"
fi

# ============
# 5) Download Pop!_OS ISO
# ============
log "Fetching Pop!_OS ISO..."

POPOS_ISO="$VM_DIR/iso/pop-os.iso"

if [[ -f "$POPOS_ISO" ]]; then
  log "Pop!_OS ISO already exists: $POPOS_ISO"
  log "Note: Cannot auto-detect ISO architecture from filename."
  
  # For existing ISO, we'll infer guest architecture based on host
  # For production testing, we use x86_64 emulation on Apple Silicon
  if [[ "$ARCH" == "arm64" ]]; then
    # On ARM64 Mac, using x86_64 guest (emulated) for production testing
    GUEST_ARCH="amd64"
    CPU_MODEL="qemu64"
    log "Assuming x86_64 guest ISO (emulation mode) for production testing"
  else
    GUEST_ARCH="amd64"
    CPU_MODEL="host"
    log "Assuming x86_64 guest ISO (native)"
  fi
  
  read -p "Re-download Pop!_OS ISO? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$POPOS_ISO"
    # Clear guest arch so it gets re-detected after download
    unset GUEST_ARCH
    unset CPU_MODEL
  else
    log "Using existing ISO."
  fi
fi

if [[ ! -f "$POPOS_ISO" ]]; then
  # Download Pop!_OS ISO using Python script
  if ! python3 - <<'PY' "$VM_DIR" "$POPOS_VERSION" "$POPOS_ARCH"
import json, sys, urllib.request, urllib.error, re
from pathlib import Path

vm_dir = Path(sys.argv[1])
popos_version = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
popos_arch = sys.argv[3] if len(sys.argv) > 3 else "amd64"
outdir = vm_dir / "iso"
outdir.mkdir(parents=True, exist_ok=True)

# Determine ISO architecture suffix
# For Mac testing, we use amd64_nvidia to match production System76 machines
# Note: Macs don't have NVIDIA GPUs, but we use the NVIDIA variant ISO because:
# 1. It's the exact same ISO that will be deployed to System76 machines
# 2. The NVIDIA drivers won't cause issues - they just won't be active/used
# 3. This ensures we test the same installation process and scripts as production
# 4. We're testing the airgap bundle installation, not GPU functionality
if popos_arch == "arm64":
    arch_suffix = "arm64"
    fallback_arch = "amd64"
else:
    # Use NVIDIA variant for production testing (matches System76 machines)
    # The ISO works fine on Mac - NVIDIA drivers just won't be used
    arch_suffix = "amd64_nvidia"
    fallback_arch = None

def verify_url_exists(url):
    """Check if a URL exists by making a HEAD request."""
    try:
        req = urllib.request.Request(url)
        req.get_method = lambda: 'HEAD'
        req.add_header('User-Agent', 'Mozilla/5.0')
        response = urllib.request.urlopen(req, timeout=10)
        # Check if we got a successful response (200-299)
        if 200 <= response.getcode() < 300:
            return True
        return False
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return False
        # For other HTTP errors, log but don't fail (might be transient)
        print(f"Warning: HTTP {e.code} when checking {url}")
        return False
    except urllib.error.URLError as e:
        print(f"Warning: Network error checking {url}: {e.reason}")
        return False
    except Exception as e:
        print(f"Warning: Error checking {url}: {e}")
        return False

def get_iso_from_api(version, channel, arch):
    """Get ISO URL from Pop!_OS API."""
    try:
        api_url = f"https://api.pop-os.org/builds/{version}/{channel}?arch={arch}"
        print(f"Querying Pop!_OS API: {api_url}")
        response = urllib.request.urlopen(api_url, timeout=10)
        data = json.loads(response.read().decode('utf-8'))
        if 'url' in data:
            iso_url = data['url']
            iso_name = iso_url.split("/")[-1]
            print(f"✓ Found ISO via API: {iso_name}")
            return iso_url, iso_name
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None, None
        print(f"Warning: API returned HTTP {e.code}")
    except Exception as e:
        print(f"Warning: API error: {e}")
    return None, None

def find_iso_url(version, arch_suffix_param):
    """Find ISO URL for given version and architecture."""
    # Map arch_suffix to API channel and arch
    if arch_suffix_param == "amd64_nvidia":
        channel = "nvidia"
        arch = "amd64"
    elif arch_suffix_param == "arm64":
        channel = "generic"  # ARM64 uses generic channel
        arch = "arm64"
    else:
        channel = "generic"
        arch = "amd64"
    
    if version:
        if version.startswith("http"):
            # Direct URL provided
            return version, version.split("/")[-1]
        else:
            # Try API first (most reliable)
            iso_url, iso_name = get_iso_from_api(version, channel, arch)
            if iso_url:
                return iso_url, iso_name
            
            # Fallback to old URL pattern (might work for some versions)
            url = f"https://iso.pop-os.org/{version}/pop-os_{version}_{arch_suffix_param}.iso"
            if verify_url_exists(url):
                return url, f"pop-os_{version}_{arch_suffix_param}.iso"
            # Return API result even if None (will trigger fallback logic)
            return iso_url, iso_name
    else:
        # Auto-detect: Try API with common versions (newest first)
        fallback_versions = ["24.04", "22.04", "23.04"]
        for fallback_version in fallback_versions:
            print(f"Trying version {fallback_version} via API...")
            iso_url, iso_name = get_iso_from_api(fallback_version, channel, arch)
            if iso_url:
                return iso_url, iso_name
        
        # If API fails, try old URL patterns as last resort
        print("API methods failed, trying legacy URL patterns...")
        for fallback_version in fallback_versions:
            url = f"https://iso.pop-os.org/{fallback_version}/pop-os_{fallback_version}_{arch_suffix_param}.iso"
            print(f"Trying legacy URL: {url}")
            if verify_url_exists(url):
                print(f"✓ Found available version: {fallback_version}")
                return url, f"pop-os_{fallback_version}_{arch_suffix_param}.iso"
        
        # If all fallbacks fail, return error with helpful message
        print("ERROR: Could not find any available Pop!_OS ISO.")
        print("Tried versions: " + ", ".join(fallback_versions))
        print("Please specify a version manually:")
        print("  export POPOS_VERSION=22.04")
        print("  or visit https://pop.system76.com/pop/download/ to find the latest version")
        raise SystemExit("No Pop!_OS ISO found. Please specify POPOS_VERSION manually.")

# Try to get ISO for requested architecture
iso_url, iso_name = find_iso_url(popos_version, arch_suffix)

# If ARM64 requested but not found, try x86_64 fallback
if popos_arch == "arm64" and fallback_arch:
    print(f"Attempting to download ARM64 Pop!_OS ISO...")
    iso_path = outdir / "pop-os.iso"
    try:
        # Test if URL exists
        req = urllib.request.Request(iso_url)
        req.get_method = lambda: 'HEAD'
        try:
            urllib.request.urlopen(req)
            print(f"Found ARM64 ISO: {iso_url}")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                print(f"ARM64 ISO not available at {iso_url}")
                print("Falling back to x86_64 ISO (will use emulation)")
                iso_url, iso_name = find_iso_url(popos_version, "amd64_nvidia")
                arch_suffix = "amd64_nvidia"
            else:
                raise
    except Exception as e:
        print(f"Warning: Could not verify ARM64 ISO availability: {e}")
        print("Falling back to x86_64 ISO (will use emulation)")
        iso_url, iso_name = find_iso_url(popos_version, "amd64_nvidia")
        arch_suffix = "amd64_nvidia"

print(f"Pop!_OS ISO URL: {iso_url}")
print(f"ISO filename: {iso_name}")
print(f"Architecture: {arch_suffix}")

# Verify URL exists before attempting download
print(f"Verifying URL exists: {iso_url}")
if not verify_url_exists(iso_url):
    print(f"ERROR: Pop!_OS ISO not found at {iso_url}")
    print("Please check the version or specify manually:")
    print(f"  export POPOS_VERSION=22.04")
    print(f"  or")
    print(f"  export POPOS_VERSION={iso_url}")
    print("")
    print("You can find available versions at: https://pop.system76.com/")
    raise SystemExit(f"Pop!_OS ISO URL not accessible: {iso_url}")

iso_path = outdir / "pop-os.iso"
print(f"URL verified. Downloading Pop!_OS ISO (this may take a while, ~3GB)...")
print(f"URL: {iso_url}")

try:
    urllib.request.urlretrieve(iso_url, iso_path)
    print(f"Downloaded: {iso_path}")
except urllib.error.HTTPError as e:
    if e.code == 404:
        raise SystemExit(f"ERROR: Pop!_OS ISO not found (404): {iso_url}\n"
                         f"Please specify a valid version:\n"
                         f"  export POPOS_VERSION=24.04")
    else:
        raise SystemExit(f"Failed to download Pop!_OS ISO: HTTP {e.code} - {e.reason}")
except Exception as e:
    raise SystemExit(f"Failed to download Pop!_OS ISO: {e}")

# Try to get SHA256 checksum if available
sha256_url = iso_url + ".sha256"
try:
    sha256_content = urllib.request.urlopen(sha256_url).read().decode("utf-8").strip()
    sha256_file = outdir / "pop-os.iso.sha256"
    sha256_file.write_text(sha256_content, encoding="utf-8")
    print(f"Downloaded SHA256: {sha256_file}")
except Exception:
    print("Warning: Could not download SHA256 checksum for Pop!_OS ISO")
PY
  then
    log "ERROR: Pop!_OS ISO download script failed"
    exit 1
  fi
  
  if [[ ! -f "$POPOS_ISO" ]]; then
    log "ERROR: Pop!_OS ISO download failed - file not found after download"
    exit 1
  fi
  
  log "Pop!_OS ISO downloaded: $POPOS_ISO"
  
  # Determine guest architecture
  # Since downloaded ISO is always named "pop-os.iso", we infer from what was requested
  # If ARM64 was requested and available, use ARM64; otherwise use x86_64
  # Note: Python script will have printed architecture info, but we infer here
  if [[ "$POPOS_ARCH" == "arm64" ]]; then
    # Check if ARM64 ISO was likely downloaded (check file size or infer from request)
    # For now, assume ARM64 if that's what was requested (Python script handles fallback)
    # In practice, if ARM64 wasn't available, Python would have fallen back to x86_64
    # and printed a message, but we can't easily detect that here
    # So we'll be conservative: if on ARM64 host, try to detect from ISO characteristics
    # For now, default to requested architecture
    GUEST_ARCH="$POPOS_ARCH"
    log "Using requested architecture: $GUEST_ARCH"
  else
    GUEST_ARCH="amd64"
    log "Using x86_64 guest architecture"
  fi
  
  # Set CPU model based on host and guest architecture
  if [[ "$ARCH" == "arm64" ]] && [[ "$GUEST_ARCH" == "arm64" ]]; then
    CPU_MODEL="host"
    log "Using native ARM64 CPU model (host passthrough)"
  elif [[ "$ARCH" == "arm64" ]] && [[ "$GUEST_ARCH" == "amd64" ]]; then
    CPU_MODEL="qemu64"
    log "Using x86_64 emulation CPU model (qemu64) - performance will be slower"
  else
    CPU_MODEL="host"
    log "Using native x86_64 CPU model (host passthrough)"
  fi
  
  # Verify SHA256 if available
  if [[ -f "$POPOS_ISO.sha256" ]]; then
    log "Verifying Pop!_OS ISO SHA256..."
    if command -v shasum >/dev/null 2>&1; then
      (cd "$(dirname "$POPOS_ISO")" && shasum -a 256 -c "$(basename "$POPOS_ISO.sha256")") || {
        log "WARNING: SHA256 verification failed. Continuing anyway..."
      }
    fi
  fi
fi

# ============
# 6) Create VM disk image
# ============
log "Creating VM disk image (size: $VM_DISK_SIZE)..."
VM_DISK="$VM_DIR/disk/popos-airgap.qcow2"

if [[ -f "$VM_DISK" ]]; then
  log "VM disk image already exists: $VM_DISK"
  read -p "Recreate VM disk? (This will delete existing VM!) (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f "$VM_DISK"
  else
    log "Using existing VM disk."
  fi
fi

if [[ ! -f "$VM_DISK" ]]; then
  if [[ -z "$QEMU_IMG" ]]; then
    log "ERROR: qemu-img not found. Cannot create VM disk."
    exit 1
  fi
  
  "$QEMU_IMG" create -f qcow2 "$VM_DISK" "$VM_DISK_SIZE" || {
    log "ERROR: Failed to create VM disk image"
    exit 1
  }
  log "VM disk image created: $VM_DISK"
  log "Actual size on disk (sparse): $(du -h "$VM_DISK" | cut -f1)"
fi

# ============
# 7) Create VM startup script
# ============
log "Creating VM startup script..."

START_SCRIPT="$VM_DIR/scripts/start_vm.sh"

cat >"$START_SCRIPT" <<START_EOF
#!/usr/bin/env bash
set -euo pipefail

# VM startup script for Pop!_OS on macOS
# Uses QEMU with Hypervisor.framework (HVF) acceleration

# Use absolute paths from parent script, with fallback to relative paths
VM_DIR="\${VM_DIR:-$VM_DIR}"
VM_DISK="\${VM_DISK:-$VM_DIR/disk/popos-airgap.qcow2}"
VM_MEMORY="\${VM_MEMORY:-$VM_MEMORY}"
VM_CPUS="\${VM_CPUS:-$VM_CPUS}"
POPOS_ISO="\${POPOS_ISO:-$VM_DIR/iso/pop-os.iso}"
CPU_MODEL="\${CPU_MODEL:-$CPU_MODEL}"

# Detect host architecture
CPU_TYPE="\$(uname -m)"
if [[ "\$CPU_TYPE" == "arm64" ]]; then
  HOST_ARCH="arm64"
  QEMU_ARCH="aarch64"
else
  HOST_ARCH="amd64"
  QEMU_ARCH="x86_64"
fi

# Determine guest architecture from ISO filename (if ISO exists)
GUEST_ARCH="amd64"  # default
if [[ -f "\$POPOS_ISO" ]]; then
  if echo "\$POPOS_ISO" | grep -q "arm64"; then
    GUEST_ARCH="arm64"
  fi
fi

# Set QEMU binary based on guest architecture
if [[ "\$GUEST_ARCH" == "arm64" ]]; then
  QEMU_SYSTEM_BIN="qemu-system-aarch64"
else
  QEMU_SYSTEM_BIN="qemu-system-x86_64"
fi

# Check if VM disk exists
if [[ ! -f "\$VM_DISK" ]]; then
  echo "ERROR: VM disk not found: \$VM_DISK"
  exit 1
fi

# Check for QEMU
if ! command -v "\$QEMU_SYSTEM_BIN" >/dev/null 2>&1; then
  echo "ERROR: \$QEMU_SYSTEM_BIN not found. Please install QEMU first."
  echo "Run: brew install qemu"
  exit 1
fi

# Check for Hypervisor.framework
if [[ -d /System/Library/Frameworks/Hypervisor.framework ]]; then
  ACCEL_ARG="-accel hvf"
  echo "Using Hypervisor.framework acceleration (HVF)"
else
  ACCEL_ARG=""
  echo "WARNING: Hypervisor.framework not found. VM will be slow."
fi

# Determine CPU model based on host and guest architecture
# Use CPU_MODEL from parent script if set, otherwise auto-detect
CPU_MODEL="\${CPU_MODEL:-}"
if [[ -z "\$CPU_MODEL" ]]; then
  if [[ "\$HOST_ARCH" == "arm64" ]] && [[ "\$GUEST_ARCH" == "arm64" ]]; then
    CPU_MODEL="host"
    echo "Using native ARM64 CPU model (host passthrough)"
  elif [[ "\$HOST_ARCH" == "arm64" ]] && [[ "\$GUEST_ARCH" == "amd64" ]]; then
    CPU_MODEL="qemu64"
    echo "Note: Running x86_64 VM on Apple Silicon (emulation) - performance will be slower"
  else
    CPU_MODEL="host"
    echo "Using native x86_64 CPU model (host passthrough)"
  fi
fi

# Check if this is first boot (need to boot from ISO)
BOOT_FROM_ISO=""
if [[ "\${1:-}" == "--install" ]]; then
  if [[ -f "\$POPOS_ISO" ]]; then
    BOOT_FROM_ISO="true"
    echo "Booting from Pop!_OS ISO for installation..."
    echo "After installation, run this script without --install to boot from disk."
  else
    echo "ERROR: Pop!_OS ISO not found: \$POPOS_ISO"
    exit 1
  fi
fi

# Start VM
echo "Starting Pop!_OS VM..."
echo "  Disk: \$VM_DISK"
echo "  Memory: \$VM_MEMORY"
echo "  CPUs: \$VM_CPUS"
echo ""
echo "QEMU window will open. Use the VM normally."
echo "To stop the VM, shut down Pop!_OS from within the VM."
echo "Or press Ctrl+C in this terminal, then type 'quit' in QEMU monitor (Ctrl+Alt+2)."

# Build QEMU command with proper argument handling
QEMU_ARGS=(
  -cpu "\$CPU_MODEL"
  -m "\$VM_MEMORY"
  -smp "\$VM_CPUS"
  -drive "file=\$VM_DISK,format=qcow2,if=virtio"
  -netdev user,id=net0
  -device virtio-net,netdev=net0
  -display cocoa
  -vga virtio
  -usb
  -device usb-tablet
)

# Add acceleration if available
if [[ -n "\$ACCEL_ARG" ]]; then
  QEMU_ARGS=("\$ACCEL_ARG" "\${QEMU_ARGS[@]}")
fi

# Add ISO boot if needed
if [[ "\$BOOT_FROM_ISO" == "true" ]]; then
  QEMU_ARGS+=(-cdrom "\$POPOS_ISO" -boot order=d)
fi

# Add any additional arguments
QEMU_ARGS+=("\${@}")

# Execute QEMU with architecture-specific binary
"\$QEMU_SYSTEM_BIN" "\${QEMU_ARGS[@]}"
START_EOF

chmod +x "$START_SCRIPT"
log "Startup script created: $START_SCRIPT"

# ============
# 8) Create installation helper script
# ============
log "Creating installation helper script..."

INSTALL_SCRIPT="$VM_DIR/scripts/install_popos.sh"

cat >"$INSTALL_SCRIPT" <<INSTALL_EOF
#!/usr/bin/env bash
set -euo pipefail

# Helper script to install Pop!_OS in the VM
# This will boot from ISO and guide you through installation

VM_DIR="\${VM_DIR:-$VM_DIR}"
START_SCRIPT="\${START_SCRIPT:-$VM_DIR/scripts/start_vm.sh}"

echo "=========================================="
echo "Pop!_OS Installation Guide"
echo "=========================================="
echo ""
echo "This will start the VM with the Pop!_OS installer."
echo "Follow these steps:"
echo ""
echo "1. The VM will boot from the Pop!_OS ISO"
echo "2. Select 'Install Pop!_OS' from the boot menu"
echo "3. Follow the installation wizard:"
echo "   - Choose your language and keyboard layout"
echo "   - Connect to network (optional, for updates)"
echo "   - When prompted, choose 'Erase disk and install'"
echo "   - Create a user account"
echo "   - Complete the installation"
echo "4. After installation, the VM will reboot"
echo "5. After reboot, run the start script without --install:"
echo "   \$START_SCRIPT"
echo ""
echo "Press Enter to start the VM installer..."
read

"\$START_SCRIPT" --install
INSTALL_EOF

chmod +x "$INSTALL_SCRIPT"
log "Installation helper script created: $INSTALL_SCRIPT"

# ============
# 9) Create README
# ============
log "Creating README..."

cat >"$VM_DIR/README.md" <<README_EOF
# Pop OS VM Setup for macOS

This directory contains a QEMU virtual machine with Pop!_OS for testing airgap scripts.

## Quick Start

### First Time Setup (Install Pop!_OS)

1. Run the installation script:
   \`\`\`bash
   ./scripts/install_popos.sh
   \`\`\`

2. Follow the on-screen instructions in the QEMU window to install Pop!_OS.

3. After installation completes and VM reboots, close the VM.

### Starting the VM

After Pop!_OS is installed, start the VM:

\`\`\`bash
./scripts/start_vm.sh
\`\`\`

### Testing Airgap Scripts

1. Copy your airgap bundle to the VM:
   - Use a shared folder (see below)
   - Or use SCP/network transfer
   - Or mount the bundle inside the VM

2. Inside the VM, navigate to the bundle and run:
   \`\`\`bash
   cd /path/to/airgap_bundle
   sudo ./install_offline.sh
   \`\`\`

## VM Configuration

- **Disk Size**: ${VM_DISK_SIZE}
- **Memory**: ${VM_MEMORY}
- **CPUs**: ${VM_CPUS}
- **Disk Image**: \`disk/popos-airgap.qcow2\`
- **Pop!_OS ISO**: \`iso/pop-os.iso\`

## Files

- \`scripts/start_vm.sh\` - Start the VM
- \`scripts/install_popos.sh\` - Install Pop!_OS (first time only)
- \`disk/popos-airgap.qcow2\` - VM disk image
- \`iso/pop-os.iso\` - Pop!_OS installation ISO

## Shared Folders (Optional)

To share files between macOS and the VM, you can:

1. **Use QEMU's 9p virtfs** (requires kernel support in Pop!_OS):
   Add to start script:
   \`\`\`bash
   -virtfs local,path=/path/on/mac,mount_tag=shared,security_model=mapped
   \`\`\`
   
   Then in VM:
   \`\`\`bash
   sudo mkdir -p /mnt/shared
   sudo mount -t 9p -o trans=virtio,version=9p2000.L shared /mnt/shared
   \`\`\`

2. **Use network transfer** (SSH/SCP):
   - Enable SSH in Pop!_OS
   - Use port forwarding: QEMU's user networking forwards port 22
   - Connect from macOS: \`ssh -p 10022 user@localhost\`

3. **Use USB drive**:
   - Pass USB device to VM: \`-device usb-host,hostbus=X,hostaddr=Y\`
   - Or use QEMU's USB redirection

## Architecture Support

This script automatically detects your Mac's architecture and downloads the appropriate Pop!_OS ISO:

- **Apple Silicon (M1/M2/M3)**: 
  - Attempts to download ARM64 Pop!_OS ISO for native performance
  - Falls back to x86_64 ISO if ARM64 not available (uses emulation, slower)
  - Uses \`qemu-system-aarch64\` for ARM64 guests, \`qemu-system-x86_64\` for x86_64 guests
  
- **Intel Mac (x86_64)**: 
  - Downloads x86_64 Pop!_OS ISO
  - Uses \`qemu-system-x86_64\` for native performance

## Performance Notes

- **Apple Silicon with ARM64 guest**: Native performance, fastest option
- **Apple Silicon with x86_64 guest**: Requires emulation, slower but functional
- **Intel Mac**: Native x86_64 performance with HVF acceleration
- **Memory**: Ensure you have enough RAM. VM uses ${VM_MEMORY} + macOS overhead.
- **Disk Space**: VM disk is sparse, but ensure you have ${VM_DISK_SIZE} free space.

## Troubleshooting

### VM Won't Start

- Check QEMU installation: 
  - For x86_64 guest: \`qemu-system-x86_64 --version\`
  - For ARM64 guest: \`qemu-system-aarch64 --version\`
- Reinstall QEMU: \`brew reinstall qemu\`
- Verify correct QEMU binary is being used (check start_vm.sh output)

### VM is Very Slow

- Ensure Hypervisor.framework is available (should be on macOS 10.10+)
- Reduce VM memory: \`VM_MEMORY=2G ./scripts/start_vm.sh\`
- On Apple Silicon: 
  - If using x86_64 guest, this is expected (emulation overhead)
  - Try ARM64 Pop!_OS ISO for native performance: The script will attempt this automatically
  - Check which ISO was downloaded: \`ls -lh iso/pop-os.iso\` (check filename patterns)

### Can't Access Network in VM

- QEMU user networking provides NAT
- VM can access internet, but host can't directly access VM
- Use port forwarding or SSH for access

### Pop!_OS Installation Fails

- Ensure sufficient disk space
- Try increasing VM memory: \`VM_MEMORY=8G ./scripts/start_vm.sh --install\`
- Check QEMU logs in \`logs/\` directory

## Next Steps

After Pop!_OS is installed:

1. Update the system (if network is available)
2. Install QEMU tools in the VM (if needed)
3. Copy your airgap bundle to the VM
4. Test the installation scripts

## Resources

- [QEMU Documentation](https://www.qemu.org/documentation/)
- [Pop!_OS Documentation](https://support.system76.com/)
- [HVF (Hypervisor.framework) Documentation](https://developer.apple.com/documentation/hypervisor)
README_EOF

log "README created: $VM_DIR/README.md"

# ============
# Summary
# ============
log ""
log "=========================================="
log "Setup Complete!"
log "=========================================="
log ""
log "VM Directory: $VM_DIR"
log "Pop!_OS ISO: $POPOS_ISO"
log "VM Disk: $VM_DISK"
log ""
log "Next Steps:"
log "  1. Install Pop!_OS in the VM:"
log "     $INSTALL_SCRIPT"
log ""
log "  2. After installation, start the VM:"
log "     $START_SCRIPT"
log ""
log "  3. Copy your airgap bundle to the VM and test:"
log "     - Use shared folder, network transfer, or USB"
log "     - Inside VM: cd /path/to/airgap_bundle && sudo ./install_offline.sh"
log ""
log "For more information, see: $VM_DIR/README.md"
log ""
log "To clean up and start over, run: ./cleanup_mac_vm.sh"
log ""

