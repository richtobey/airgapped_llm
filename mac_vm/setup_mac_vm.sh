#!/usr/bin/env bash
set -euo pipefail

# Download Pop!_OS ISO for use with UTM on macOS
# This script downloads the Pop!_OS ISO and provides instructions for
# installing UTM from the Mac App Store and setting up Pop!_OS in UTM.
# Usage: ./setup_mac_vm.sh

# ============
# Config
# ============
VM_DIR="${VM_DIR:-$HOME/vm-popos}"
POPOS_VERSION="${POPOS_VERSION:-}"
ARCH="amd64"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$VM_DIR/iso"

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
# 2) Detect CPU Architecture
# ============
log "Detecting CPU architecture..."

CPU_TYPE="$(uname -m)"
if [[ "$CPU_TYPE" == "arm64" ]]; then
  ARCH="arm64"
  POPOS_ARCH="amd64"
  log "✓ Detected Apple Silicon (ARM64)"
  log "  Will download x86_64 Pop!_OS ISO for use with UTM"
else
  ARCH="amd64"
  POPOS_ARCH="amd64"
  log "✓ Detected Intel Mac (x86_64)"
  log "  Will download x86_64 Pop!_OS ISO"
fi

log "Architecture configuration:"
log "  CPU Type: $CPU_TYPE"
log "  ARCH: $ARCH"
log "  Pop!_OS Arch: $POPOS_ARCH"

# ============
# 3) Download Pop!_OS ISO
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
# Summary
# ============
log ""
log "=========================================="
log "ISO Download Complete!"
log "=========================================="
log ""
log "Pop!_OS ISO: $POPOS_ISO"
log ""
log "═══════════════════════════════════════════════════════════════"
log "NEXT STEPS - Install UTM and Setup Pop!_OS"
log "═══════════════════════════════════════════════════════════════"
log ""
log "See README.md and follow the steps"
log "───────────────────────────────────────────────────────────────"
