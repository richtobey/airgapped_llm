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
  
  # Note: On Apple Silicon, HVF only works for ARM64 guests, not x86_64
  # The generated start_vm.sh script will handle this detection at runtime
  # This is just for informational logging during setup
  if command -v "$QEMU_SYSTEM_BIN" >/dev/null 2>&1; then
    # Check if QEMU supports HVF acceleration
    if "$QEMU_SYSTEM_BIN" -accel help 2>&1 | grep -qi "hvf"; then
      log "QEMU supports HVF acceleration (will be used if compatible with guest architecture)"
    else
      log "WARNING: QEMU may not support HVF acceleration"
      log "  The generated script will detect this at runtime"
    fi
  fi
else
  log "WARNING: Hypervisor.framework not found. VM will use software emulation (very slow)."
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

ISO_NEEDS_DOWNLOAD="true"

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
  
  # Check if checksum file exists and validate
  if [[ -f "$POPOS_ISO.sha256" ]]; then
    log "Found SHA256 checksum file, validating ISO..."
    if command -v shasum >/dev/null 2>&1; then
      if (cd "$(dirname "$POPOS_ISO")" && shasum -a 256 -c "$(basename "$POPOS_ISO.sha256")" >/dev/null 2>&1); then
        log "✓ ISO checksum validation passed - using existing ISO"
        ISO_NEEDS_DOWNLOAD="false"
      else
        log "✗ ISO checksum validation failed - will re-download"
        rm -f "$POPOS_ISO" "$POPOS_ISO.sha256"
        # Clear guest arch so it gets re-detected after download
        unset GUEST_ARCH
        unset CPU_MODEL
      fi
    else
      log "WARNING: shasum not found, cannot validate checksum"
      log "ISO exists but checksum cannot be verified"
      log "Using existing ISO (checksum validation skipped)"
      ISO_NEEDS_DOWNLOAD="false"
    fi
  else
    log "ISO exists but no checksum file found"
    log "Attempting to download checksum file for validation..."
    
    # Try to download checksum file using Python script
    if python3 - <<'PY' "$VM_DIR" "$POPOS_VERSION" "$POPOS_ARCH" "$POPOS_ISO"
import json, sys, urllib.request, urllib.error, hashlib
from pathlib import Path

vm_dir = Path(sys.argv[1])
popos_version = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None
popos_arch = sys.argv[3] if len(sys.argv) > 3 else "amd64"
iso_path = Path(sys.argv[4]) if len(sys.argv) > 4 else None

outdir = vm_dir / "iso"
outdir.mkdir(parents=True, exist_ok=True)

# Determine ISO architecture suffix (same logic as download script)
if popos_arch == "arm64":
    arch_suffix = "arm64"
else:
    arch_suffix = "amd64_nvidia"

def get_iso_from_api(version, channel, arch):
    """Get ISO URL from Pop!_OS API."""
    try:
        api_url = f"https://api.pop-os.org/builds/{version}/{channel}?arch={arch}"
        response = urllib.request.urlopen(api_url, timeout=10)
        data = json.loads(response.read().decode('utf-8'))
        if 'url' in data:
            return data['url']
    except Exception:
        pass
    return None

def find_checksum_url(version, arch_suffix_param):
    """Find checksum URL for given version and architecture. Returns list of URLs to try."""
    # Map arch_suffix to API channel and arch
    if arch_suffix_param == "amd64_nvidia":
        channel = "nvidia"
        arch = "amd64"
    elif arch_suffix_param == "arm64":
        channel = "generic"
        arch = "arm64"
    else:
        channel = "generic"
        arch = "amd64"
    
    urls_to_try = []
    
    if version:
        if version.startswith("http"):
            # Direct URL provided - try .sha256 extension
            urls_to_try.append(version + ".sha256")
        else:
            # Try API first
            iso_url = get_iso_from_api(version, channel, arch)
            if iso_url:
                # Try multiple patterns
                urls_to_try.append(iso_url + ".sha256")
                # Some checksums might be at a different location
                urls_to_try.append(iso_url.replace(".iso", ".sha256"))
            
            # Fallback to old URL patterns
            urls_to_try.append(f"https://iso.pop-os.org/{version}/pop-os_{version}_{arch_suffix_param}.iso.sha256")
            urls_to_try.append(f"https://iso.pop-os.org/{version}/pop-os_{version}_{arch_suffix_param}.sha256")
    else:
        # Auto-detect: Try API with common versions
        for fallback_version in ["24.04", "22.04", "23.04"]:
            iso_url = get_iso_from_api(fallback_version, channel, arch)
            if iso_url:
                urls_to_try.append(iso_url + ".sha256")
                urls_to_try.append(iso_url.replace(".iso", ".sha256"))
        
        # Fallback to old URL patterns
        for fallback_version in ["24.04", "22.04", "23.04"]:
            urls_to_try.append(f"https://iso.pop-os.org/{fallback_version}/pop-os_{fallback_version}_{arch_suffix_param}.iso.sha256")
            urls_to_try.append(f"https://iso.pop-os.org/{fallback_version}/pop-os_{fallback_version}_{arch_suffix_param}.sha256")
    
    return urls_to_try

def compute_local_checksum(iso_path):
    """Compute SHA256 checksum of local ISO file."""
    try:
        sha256_hash = hashlib.sha256()
        with open(iso_path, "rb") as f:
            # Read in chunks to handle large files
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        return sha256_hash.hexdigest()
    except Exception as e:
        return None

# Try to find and download checksum URL
sha256_urls = find_checksum_url(popos_version, arch_suffix)
sha256_file = outdir / "pop-os.iso.sha256"
checksum_downloaded = False

# Try each URL pattern
for sha256_url in sha256_urls:
    try:
        sha256_content = urllib.request.urlopen(sha256_url, timeout=10).read().decode("utf-8").strip()
        # Checksum file might be in format: "hash  filename" or just "hash"
        # Extract just the hash part
        checksum_hash = sha256_content.split()[0] if sha256_content.split() else sha256_content
        sha256_file.write_text(f"{checksum_hash}  pop-os.iso\n", encoding="utf-8")
        print(f"Downloaded SHA256: {sha256_file}")
        checksum_downloaded = True
        break
    except Exception:
        continue

# If download failed, try computing checksum locally
if not checksum_downloaded and iso_path and iso_path.exists():
    print("Could not download checksum file, computing locally from ISO...")
    local_checksum = compute_local_checksum(iso_path)
    if local_checksum:
        sha256_file.write_text(f"{local_checksum}  pop-os.iso\n", encoding="utf-8")
        print(f"Computed SHA256 locally: {sha256_file}")
        print("Note: This checksum was computed locally and cannot verify ISO authenticity")
        checksum_downloaded = True
    else:
        print("Warning: Could not compute local checksum")
        sys.exit(1)
elif not checksum_downloaded:
    print("Warning: Could not download or compute SHA256 checksum")
    print("ISO exists but checksum cannot be obtained")
    sys.exit(1)

if checksum_downloaded:
    sys.exit(0)
else:
    sys.exit(1)
PY
    then
      log "✓ Checksum file downloaded successfully"
      # Now validate the ISO with the downloaded checksum
      if command -v shasum >/dev/null 2>&1; then
        if (cd "$(dirname "$POPOS_ISO")" && shasum -a 256 -c "$(basename "$POPOS_ISO.sha256")" >/dev/null 2>&1); then
          log "✓ ISO checksum validation passed - using existing ISO"
          ISO_NEEDS_DOWNLOAD="false"
        else
          log "✗ ISO checksum validation failed - will re-download"
          rm -f "$POPOS_ISO" "$POPOS_ISO.sha256"
          unset GUEST_ARCH
          unset CPU_MODEL
        fi
      else
        log "WARNING: shasum not found, cannot validate checksum"
        log "Checksum file downloaded but validation skipped"
        ISO_NEEDS_DOWNLOAD="false"
      fi
    else
      log "Could not download checksum file"
      log "Using existing ISO (checksum validation skipped)"
      log "Note: ISO integrity cannot be verified without checksum file"
      ISO_NEEDS_DOWNLOAD="false"
    fi
  fi
fi

if [[ "$ISO_NEEDS_DOWNLOAD" == "true" ]]; then
  # Download Pop!_OS ISO using Python script
  if ! python3 - <<'PY' "$VM_DIR" "$POPOS_VERSION" "$POPOS_ARCH"
import json, sys, urllib.request, urllib.error, re, time
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

# Progress callback function
def format_size(size):
    """Format size in human-readable format."""
    units = ['B', 'KB', 'MB', 'GB']
    size_float = float(size)
    for unit in units:
        if size_float < 1024.0:
            return f"{size_float:.1f} {unit}"
        size_float /= 1024.0
    return f"{size_float:.1f} TB"

def format_time(seconds):
    """Format time in human-readable format."""
    if seconds < 60:
        return f"{int(seconds)}s"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        secs = int(seconds % 60)
        return f"{minutes}m {secs}s"
    else:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        return f"{hours}h {minutes}m"

# Create progress tracker with closure to maintain state
def create_progress_tracker():
    """Create a progress tracker that maintains state between calls."""
    start_time = time.time()
    last_time = start_time
    last_downloaded = 0
    
    def show_progress(block_num, block_size, total_size):
        """Display download progress with time remaining estimate."""
        nonlocal last_time, last_downloaded
        
        current_time = time.time()
        downloaded = block_num * block_size
        elapsed = current_time - start_time
        
        if total_size > 0:
            percent = min(100, (downloaded * 100) / total_size)
            downloaded_str = format_size(downloaded)
            total_str = format_size(total_size)
            remaining = total_size - downloaded
            
            # Calculate current speed (bytes per second)
            # Use recent speed (last few seconds) for more accurate estimate
            time_delta = current_time - last_time
            if time_delta > 0.5:  # Update speed calculation every 0.5 seconds
                downloaded_delta = downloaded - last_downloaded
                current_speed = downloaded_delta / time_delta if time_delta > 0 else 0
                last_time = current_time
                last_downloaded = downloaded
            else:
                # Use average speed if not enough time has passed
                current_speed = downloaded / elapsed if elapsed > 0 else 0
            
            # Calculate time remaining
            if current_speed > 0 and remaining > 0:
                time_remaining = remaining / current_speed
                time_str = format_time(time_remaining)
                speed_str = format_size(current_speed) + "/s"
            else:
                time_str = "calculating..."
                speed_str = "calculating..."
            
            bar_length = 50
            filled = int(bar_length * percent / 100)
            bar = '=' * filled + '-' * (bar_length - filled)
            
            # Progress line with time remaining and speed
            progress_line = f"[{bar}] {percent:.1f}% ({downloaded_str} / {total_str}) @ {speed_str} ETA: {time_str}"
            
            # \033[K clears from cursor to end of line, \r returns to start
            sys.stderr.write(f"\r\033[K{progress_line}")
            sys.stderr.flush()
            
            # Print newline when complete
            if downloaded >= total_size:
                sys.stderr.write("\n")
                sys.stderr.flush()
        else:
            # File size unknown, show downloaded amount and speed
            downloaded_str = format_size(downloaded)
            if elapsed > 0:
                current_speed = downloaded / elapsed
                speed_str = format_size(current_speed) + "/s"
            else:
                speed_str = "calculating..."
            progress_line = f"Downloaded: {downloaded_str} @ {speed_str}..."
            # \033[K clears from cursor to end of line, \r returns to start
            sys.stderr.write(f"\r\033[K{progress_line}")
            sys.stderr.flush()
    
    return show_progress

show_progress = create_progress_tracker()

try:
    # Get file size first for progress tracking
    total_size = 0
    try:
        req = urllib.request.Request(iso_url)
        req.add_header('User-Agent', 'Mozilla/5.0')
        with urllib.request.urlopen(req) as response:
            total_size = int(response.headers.get('Content-Length', 0))
    except Exception:
        pass
    
    # Download with progress callback
    urllib.request.urlretrieve(iso_url, iso_path, reporthook=show_progress)
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
  
  # Verify checksum file was downloaded
  if [[ -f "$POPOS_ISO.sha256" ]]; then
    log "✓ Checksum file downloaded: $POPOS_ISO.sha256"
  else
    log "WARNING: Checksum file not found after download"
    log "  The ISO was downloaded but checksum file is missing"
    log "  This may happen if the checksum URL is not available"
    log "  The ISO will still be used, but integrity cannot be verified"
  fi
  
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

# Auto-detect VM_DIR from script location, with fallback to environment variable
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="\${VM_DIR:-\$(dirname "\$SCRIPT_DIR")}"
VM_DISK="\${VM_DISK:-\$VM_DIR/disk/popos-airgap.qcow2}"
VM_MEMORY="\${VM_MEMORY:-$VM_MEMORY}"
VM_CPUS="\${VM_CPUS:-$VM_CPUS}"
POPOS_ISO="\${POPOS_ISO:-\$VM_DIR/iso/pop-os.iso}"
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

# Check for Hypervisor.framework and HVF support in QEMU
ACCEL_ARG=""
ACCEL_VALUE=""

if [[ -d /System/Library/Frameworks/Hypervisor.framework ]]; then
  # On Apple Silicon, HVF only works for ARM64 guests, not x86_64
  # On Intel Macs, HVF works for x86_64 guests
  if [[ "\$HOST_ARCH" == "arm64" ]] && [[ "\$GUEST_ARCH" == "amd64" ]]; then
    # Apple Silicon running x86_64 guest - HVF not supported
    echo "Note: HVF acceleration not available for x86_64 guests on Apple Silicon"
    echo "  VM will run in emulation mode (slower performance)"
    ACCEL_ARG=""
    ACCEL_VALUE=""
  else
    # Check if QEMU supports HVF acceleration using -accel help
    # Try -accel help first (QEMU 5.1+), handle errors gracefully
    if "\$QEMU_SYSTEM_BIN" -accel help 2>&1 | grep -qi "hvf"; then
      # QEMU supports HVF - use -accel syntax (QEMU 5.1+)
      ACCEL_ARG="-accel"
      ACCEL_VALUE="hvf"
      echo "Using Hypervisor.framework acceleration (HVF)"
    else
      # HVF not available in this QEMU build - run without acceleration
      echo "WARNING: QEMU does not support HVF acceleration. VM will be slow."
      echo "  To enable HVF, reinstall QEMU: brew reinstall qemu"
      echo "  Or install from source with: ./configure --enable-hvf"
      ACCEL_ARG=""
      ACCEL_VALUE=""
    fi
  fi
else
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
    # Remove --install from arguments so it doesn't get passed to QEMU
    shift
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
if [[ -n "\$ACCEL_ARG" ]] && [[ -n "\$ACCEL_VALUE" ]]; then
  if [[ "\$ACCEL_ARG" == "-accel" ]]; then
    # Modern syntax: -accel hvf (two separate arguments)
    QEMU_ARGS=(-accel hvf "\${QEMU_ARGS[@]}")
  else
    # Legacy syntax: -machine type=q35,accel=hvf (single argument)
    QEMU_ARGS=(-machine "\$ACCEL_VALUE" "\${QEMU_ARGS[@]}")
  fi
fi

# Add ISO boot if needed
if [[ "\$BOOT_FROM_ISO" == "true" ]]; then
  QEMU_ARGS+=(-cdrom "\$POPOS_ISO" -boot order=d)
fi

# Add any additional arguments (if any)
if [[ \$# -gt 0 ]]; then
  QEMU_ARGS+=("\${@}")
fi

# Execute QEMU with architecture-specific binary
"\$QEMU_SYSTEM_BIN" "\${QEMU_ARGS[@]}"
START_EOF

# Ensure scripts directory exists
mkdir -p "$VM_DIR/scripts"

# Set executable permissions immediately after creation
chmod +x "$START_SCRIPT" || {
  log "ERROR: Failed to set executable permissions on $START_SCRIPT"
  exit 1
}

# Verify permissions were set
if [[ ! -x "$START_SCRIPT" ]]; then
  log "ERROR: $START_SCRIPT is not executable after chmod"
  ls -l "$START_SCRIPT"
  exit 1
fi

log "✓ Startup script created and made executable: $START_SCRIPT"

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

# Auto-detect VM_DIR from script location, with fallback to environment variable
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
VM_DIR="\${VM_DIR:-\$(dirname "\$SCRIPT_DIR")}"
START_SCRIPT="\${START_SCRIPT:-\$VM_DIR/scripts/start_vm.sh}"

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

# Ensure scripts directory exists
mkdir -p "$VM_DIR/scripts"

# Set executable permissions immediately after creation
chmod +x "$INSTALL_SCRIPT" || {
  log "ERROR: Failed to set executable permissions on $INSTALL_SCRIPT"
  exit 1
}

# Verify permissions were set
if [[ ! -x "$INSTALL_SCRIPT" ]]; then
  log "ERROR: $INSTALL_SCRIPT is not executable after chmod"
  ls -l "$INSTALL_SCRIPT"
  exit 1
fi

log "✓ Installation helper script created and made executable: $INSTALL_SCRIPT"

# Ensure all scripts in scripts directory are executable (safety check)
log "Ensuring all scripts in scripts directory are executable..."
if [[ -d "$VM_DIR/scripts" ]]; then
  # Make all .sh files executable (using -exec for portability)
  find "$VM_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} + || {
    log "WARNING: Some scripts could not be made executable"
  }
  
  # Verify all scripts are executable
  non_executable_count=0
  for script in "$VM_DIR/scripts"/*.sh; do
    if [[ -f "$script" ]] && [[ ! -x "$script" ]]; then
      log "WARNING: Script is not executable: $script"
      ls -l "$script"
      ((non_executable_count++))
    fi
  done
  
  if [[ $non_executable_count -eq 0 ]]; then
    log "✓ Verified all .sh files in scripts directory are executable"
  else
    log "WARNING: $non_executable_count script(s) are not executable"
  fi
else
  log "WARNING: Scripts directory not found: $VM_DIR/scripts"
fi

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
  - If using x86_64 guest, this is expected:
    - HVF acceleration is NOT available for x86_64 guests on Apple Silicon
    - VM runs in emulation mode (slower but functional)
    - This is a QEMU limitation, not a script issue
  - For better performance on Apple Silicon:
    - Use ARM64 Pop!_OS ISO for native performance with HVF acceleration
    - The script will attempt to download ARM64 ISO automatically
    - Check which ISO was downloaded: \`ls -lh iso/pop-os.iso\`
- On Intel Macs:
  - HVF acceleration should work automatically for x86_64 guests
  - If slow, check QEMU supports HVF: \`qemu-system-x86_64 -accel help\`

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
log "═══════════════════════════════════════════════════════════════"
log "NEXT STEPS - Complete Guide for macOS Users"
log "═══════════════════════════════════════════════════════════════"
log ""
log "STEP 1: Install Pop!_OS in the VM"
log "───────────────────────────────────────────────────────────────"
log "Run the installation script to boot the VM and install Pop!_OS:"
log ""
log "    cd $VM_DIR"
log "    ./scripts/install_popos.sh"
log ""
log "What happens:"
log "  • A QEMU window will open showing the Pop!_OS installer"
log "  • Follow the on-screen installation wizard"
log "  • When prompted, choose 'Erase disk and install Pop!_OS'"
log "  • Set up your user account (remember your password!)"
log "  • After installation completes, shut down the VM"
log ""
log "Note: On Apple Silicon Macs, the VM runs in emulation mode"
log "      (slower than native). Installation may take 20-30 minutes."
log ""
log ""
log "STEP 2: Start the VM (after installation)"
log "───────────────────────────────────────────────────────────────"
log "Once Pop!_OS is installed, start the VM normally:"
log ""
log "    cd $VM_DIR"
log "    ./scripts/start_vm.sh"
log ""
log "What happens:"
log "  • QEMU window opens with your Pop!_OS desktop"
log "  • Log in with the account you created during installation"
log "  • The VM has internet access (via NAT networking)"
log ""
log "QEMU Window Controls:"
log "  • Click inside the window to capture mouse/keyboard"
log "  • Press 'Ctrl+Option+G' (or 'Ctrl+Alt+G' on some keyboards)"
log "    to release mouse/keyboard back to macOS"
log "  • Close the window or run 'sudo shutdown now' in VM to stop"
log ""
log ""
log "STEP 3: Transfer Files to the VM"
log "───────────────────────────────────────────────────────────────"
log "To copy your airgap bundle into the VM, you have several options:"
log ""
log "Option A: Using SCP (if VM has SSH enabled)"
log "  • In VM: sudo apt install openssh-server"
log "  • In VM: sudo systemctl start ssh"
log "  • On Mac: scp -r /path/to/airgap_bundle user@vm-ip:/home/user/"
log ""
log "Option B: Using Shared Folder (QEMU virtfs)"
log "  • Requires modifying start_vm.sh to add:"
log "    -virtfs local,path=/path/to/share,mount_tag=share,security_model=mapped"
log "  • In VM: sudo mkdir /mnt/share && sudo mount -t 9p share /mnt/share"
log ""
log "Option C: Using HTTP Server (easiest - recommended)"
log "  • On Mac, find your IP address:"
log "    ifconfig en0 | grep 'inet ' | awk '{print \$2}'"
log "    (or check System Preferences → Network)"
log "  • On Mac: cd /path/to/airgap_bundle && python3 -m http.server 8000"
log "  • In VM browser: http://YOUR_MAC_IP:8000"
log "  • Or in VM terminal: wget -r http://YOUR_MAC_IP:8000"
log ""
log "Option D: USB Drive"
log "  • Format USB as FAT32 or exFAT"
log "  • Copy bundle to USB on Mac"
log "  • Attach USB to VM (QEMU menu: Devices → USB → Select device)"
log "  • In VM: mount /dev/sdb1 /mnt (adjust device as needed)"
log ""
log ""
log "STEP 4: Install Airgap Bundle in VM"
log "───────────────────────────────────────────────────────────────"
log "Once the bundle is in the VM:"
log ""
log "    cd /path/to/airgap_bundle"
log "    sudo ./install_offline.sh"
log ""
log ""
log "TROUBLESHOOTING"
log "───────────────────────────────────────────────────────────────"
log ""
log "QEMU window doesn't open:"
log "  • Check if QEMU is installed: brew list qemu"
log "  • Try running manually: qemu-system-x86_64 --version"
log "  • Check logs: $VM_DIR/logs/"
log ""
log "VM is very slow (Apple Silicon Macs):"
log "  • This is normal - x86_64 emulation is slower than native"
log "  • Consider using a Linux x86_64 machine for better performance"
log "  • Or use native ARM64 Pop!_OS if available (experimental)"
log ""
log "Can't capture mouse/keyboard:"
log "  • Click inside the QEMU window first"
log "  • To release: Ctrl+Option+G (or Ctrl+Alt+G)"
log "  • If stuck, press Ctrl+Option+G multiple times"
log ""
log "VM won't boot:"
log "  • Check disk image exists: ls -lh $VM_DISK"
log "  • Check ISO exists: ls -lh $POPOS_ISO"
log "  • Try reinstalling: ./scripts/install_popos.sh"
log ""
log "Network not working in VM:"
log "  • QEMU uses NAT networking by default"
log "  • VM should have internet access automatically"
log "  • Check: ping google.com in VM"
log ""
log ""
log ""
log "QUICK REFERENCE"
log "───────────────────────────────────────────────────────────────"
log ""
log "Essential Commands:"
log "  Install Pop!_OS:  cd $VM_DIR && ./scripts/install_popos.sh"
log "  Start VM:         cd $VM_DIR && ./scripts/start_vm.sh"
log "  Stop VM:          Shut down from inside VM, or close QEMU window"
log ""
log "Keyboard Shortcuts (QEMU Cocoa display):"
log "  Capture mouse:    Click inside QEMU window"
log "  Release mouse:   Ctrl+Option+G (or Cmd+Option+G)"
log "  QEMU Monitor:     Ctrl+Option+2 (advanced debugging)"
log ""
log "File Locations:"
log "  VM Directory:    $VM_DIR"
log "  VM Disk:          $VM_DISK"
log "  Pop!_OS ISO:      $POPOS_ISO"
log "  Logs:              $VM_DIR/logs/"
log ""
log "For more details, see: $VM_DIR/README.md"
log ""
log "To clean up and start over: ./cleanup_mac_vm.sh"
log ""
log "For more information, see: $VM_DIR/README.md"
log ""
log "To clean up and start over, run: ./cleanup_mac_vm.sh"
log ""

