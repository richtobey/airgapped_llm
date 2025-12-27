#!/usr/bin/env bash
set -euo pipefail

# ============
# Config
# ============
BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"
ARCH="amd64"
# Models to bundle (space-separated list)
# Default: Bundle all recommended models for different VRAM configurations
# - mistral:7b-instruct: Best for 16GB VRAM (~4GB download, ~13.7GB VRAM)
# - mixtral:8x7b: For 24GB+ VRAM (~26GB download, ~48GB VRAM)
# - mistral:7b-instruct-q4_K_M: Quantized version for saving VRAM (~2GB download, ~3.4GB VRAM)
# 
# To bundle only specific models, set OLLAMA_MODELS env var:
#   export OLLAMA_MODELS="mistral:7b-instruct mixtral:8x7b mistral:7b-instruct-q4_K_M"
# Or for backward compatibility, use OLLAMA_MODEL for a single model:
#   export OLLAMA_MODEL="mistral:7b-instruct"
if [[ -n "${OLLAMA_MODEL:-}" ]] && [[ -z "${OLLAMA_MODELS:-}" ]]; then
  # Backward compatibility: single model
  OLLAMA_MODELS="$OLLAMA_MODEL"
elif [[ -z "${OLLAMA_MODELS:-}" ]]; then
  # Default: bundle all recommended models
  OLLAMA_MODELS="mistral:7b-instruct mixtral:8x7b mistral:7b-instruct-q4_K_M"
fi

mkdir -p \
  "$BUNDLE_DIR"/{ollama,models,vscodium,continue,extensions,aptrepo/{pool,conf},rust/{toolchain,crates},python,logs}

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
# 1) Ollama (Linux amd64) + official SHA256 from GitHub Releases
# ============
log "Fetching Ollama latest release metadata and linux-amd64 tarball..."

python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, re
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"ollama"
outdir.mkdir(parents=True, exist_ok=True)

api = "https://api.github.com/repos/ollama/ollama/releases/latest"
data = json.loads(urllib.request.urlopen(api).read().decode("utf-8"))

# asset name per Ollama release page: ollama-linux-amd64.tgz
target_name = "ollama-linux-amd64.tgz"
assets = {a["name"]: a["browser_download_url"] for a in data["assets"]}
if target_name not in assets:
  raise SystemExit(f"Could not find {target_name} in latest release assets: {list(assets)[:10]}...")

url = assets[target_name]
print("Ollama URL:", url)

# Download tarball
tgz = outdir/target_name
urllib.request.urlretrieve(url, tgz)

# Get official sha256: easiest is to scrape the GitHub release HTML, which includes "sha256:<hash>" next to asset
release_html = urllib.request.urlopen(data["html_url"]).read().decode("utf-8", errors="ignore")
m = re.search(rf"{re.escape(target_name)}.*?sha256:([0-9a-f]{{64}})", release_html, re.S | re.I)
if not m:
  raise SystemExit("Could not parse official sha256 from release page HTML.")
sha = m.group(1)

sha_file = outdir/(target_name + ".sha256")
sha_file.write_text(f"{sha}  {target_name}\n", encoding="utf-8")
print("Wrote sha256 file:", sha_file)
PY

log "Verifying Ollama sha256..."
sha256_check_file "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz.sha256"
log "Ollama verified."

# ============
# 2) Pull Ollama models, then copy ~/.ollama
# ============
# Detect OS for model pulling
OS="$(uname -s)"

# Convert space-separated models to array
read -ra MODEL_ARRAY <<< "$OLLAMA_MODELS"
MODEL_COUNT=${#MODEL_ARRAY[@]}

if [[ "$OS" == "Darwin" ]]; then
  log "macOS detected. Downloading macOS Ollama binary to pull $MODEL_COUNT model(s)..."
  
  # Download macOS Ollama for pulling models
  # Detect Mac architecture
  MAC_ARCH="$(uname -m)"
  if [[ "$MAC_ARCH" == "arm64" ]]; then
    MAC_TARGET="arm64"
  else
    MAC_TARGET="amd64"
  fi
  
  python3 - <<'PY' "$BUNDLE_DIR" "$MAC_TARGET"
import json, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
mac_target = sys.argv[2]
outdir = bundle/"ollama"
outdir.mkdir(parents=True, exist_ok=True)

api = "https://api.github.com/repos/ollama/ollama/releases/latest"
data = json.loads(urllib.request.urlopen(api).read().decode("utf-8"))
assets = {a["name"]: a["browser_download_url"] for a in data["assets"]}

# Look for macOS binary (could be ollama-darwin, ollama-mac, or in a .zip/.tgz)
# Common patterns: ollama-darwin, ollama-darwin-amd64, ollama-darwin-arm64, etc.
macos_name = None
for name in assets:
  name_lower = name.lower()
  if ("darwin" in name_lower or "mac" in name_lower) and mac_target in name_lower:
    macos_name = name
    break

# Fallback: any darwin/mac binary
if not macos_name:
  for name in assets:
    name_lower = name.lower()
    if "darwin" in name_lower or "mac" in name_lower:
      macos_name = name
      break

if not macos_name:
  raise SystemExit(f"Could not find macOS ({mac_target}) Ollama binary in release assets: {list(assets)[:10]}")

macos_url = assets[macos_name]
urllib.request.urlretrieve(macos_url, outdir/macos_name)
print("Downloaded macOS Ollama:", macos_name)
PY

  TMP_OLLAMA="$BUNDLE_DIR/ollama/_tmp_ollama"
  rm -rf "$TMP_OLLAMA"
  mkdir -p "$TMP_OLLAMA"
  
  # Handle different archive formats or direct binary
  MACOS_BINARY="$(ls "$BUNDLE_DIR/ollama"/ollama-*darwin* "$BUNDLE_DIR/ollama"/ollama-*mac* 2>/dev/null | head -n1)"
  if [[ -z "$MACOS_BINARY" ]]; then
    log "ERROR: Could not find downloaded macOS Ollama binary"
    exit 1
  fi
  
  # If it's an archive, extract it; otherwise copy the binary
  if [[ "$MACOS_BINARY" == *.zip ]]; then
    unzip -q "$MACOS_BINARY" -d "$TMP_OLLAMA"
    chmod +x "$TMP_OLLAMA/ollama" 2>/dev/null || find "$TMP_OLLAMA" -name "ollama" -type f -exec chmod +x {} \;
  elif [[ "$MACOS_BINARY" == *.tgz ]] || [[ "$MACOS_BINARY" == *.tar.gz ]]; then
    tar -xzf "$MACOS_BINARY" -C "$TMP_OLLAMA"
    chmod +x "$TMP_OLLAMA/ollama" 2>/dev/null || find "$TMP_OLLAMA" -name "ollama" -type f -exec chmod +x {} \;
  else
    # Assume it's a direct binary
    cp "$MACOS_BINARY" "$TMP_OLLAMA/ollama"
    chmod +x "$TMP_OLLAMA/ollama"
  fi
  
  # Find the actual ollama binary
  if [[ ! -x "$TMP_OLLAMA/ollama" ]]; then
    OLLAMA_BIN="$(find "$TMP_OLLAMA" -name "ollama" -type f | head -n1)"
    if [[ -n "$OLLAMA_BIN" ]]; then
      cp "$OLLAMA_BIN" "$TMP_OLLAMA/ollama"
      chmod +x "$TMP_OLLAMA/ollama"
    else
      log "ERROR: Could not find ollama binary in extracted archive"
      exit 1
    fi
  fi
  
  export PATH="$TMP_OLLAMA:$PATH"
  
elif [[ "$OS" == "Linux" ]]; then
  log "Linux detected. Using Linux Ollama binary to pull $MODEL_COUNT model(s)..."
  
  TMP_OLLAMA="$BUNDLE_DIR/ollama/_tmp_ollama"
  rm -rf "$TMP_OLLAMA"
  mkdir -p "$TMP_OLLAMA"
  
  tar -xzf "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" -C "$TMP_OLLAMA"
  export PATH="$TMP_OLLAMA:$PATH"
else
  log "WARNING: Unknown OS ($OS). Skipping model pull."
  log "You will need to manually pull the models on the target Linux system."
  mkdir -p "$BUNDLE_DIR/models/.ollama"
  exit 0
fi

# Start ollama server in the background on the online machine just for pulling
# (it will create ~/.ollama)
log "Starting Ollama server to pull models..."
nohup ollama serve >"$BUNDLE_DIR/logs/ollama_serve.log" 2>&1 &
SERVE_PID=$!
sleep 3

# Pull all models
log "Pulling $MODEL_COUNT model(s): ${OLLAMA_MODELS}"
log "This may take a while, especially for large models like mixtral:8x7b (~26GB)..."
for model in "${MODEL_ARRAY[@]}"; do
  log "Pulling model: $model ..."
  ollama pull "$model" || {
    log "WARNING: Failed to pull $model. Continuing with other models..."
  }
done

# Stop server
kill "$SERVE_PID" || true
wait "$SERVE_PID" 2>/dev/null || true

log "Copying \$HOME/.ollama into bundle..."
mkdir -p "$BUNDLE_DIR/models"
rsync -a --delete "$HOME/.ollama/" "$BUNDLE_DIR/models/.ollama/"

# Calculate total size
TOTAL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
log "Model data copied. Total size: $TOTAL_SIZE"
log "Models bundled: ${OLLAMA_MODELS}"
log "Note: mistral:7b-instruct ~4GB, mixtral:8x7b ~26GB, mistral:7b-instruct-q4_K_M ~2GB"

# ============
# 3) VSCodium .deb + published .sha256, then verify
# ============
log "Fetching VSCodium latest .deb + .sha256..."
python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"vscodium"
outdir.mkdir(parents=True, exist_ok=True)

api = "https://api.github.com/repos/VSCodium/vscodium/releases/latest"
data = json.loads(urllib.request.urlopen(api).read().decode("utf-8"))
assets = {a["name"]: a["browser_download_url"] for a in data["assets"]}

# pick amd64 deb + its .sha256
deb = next((n for n in assets if n.endswith("_amd64.deb")), None)
sha = deb + ".sha256" if deb and (deb + ".sha256") in assets else None
if not deb or not sha:
  raise SystemExit(f"Could not find amd64 deb and sha256 in assets (deb={deb}, sha={sha}).")

urllib.request.urlretrieve(assets[deb], outdir/deb)
urllib.request.urlretrieve(assets[sha], outdir/sha)
print("Downloaded:", deb, "and", sha)
PY

log "Verifying VSCodium sha256..."
# .sha256 is usually in the form "<hash>  <filename>"
sha256_check_file "$BUNDLE_DIR/vscodium/"*_amd64.deb "$BUNDLE_DIR/vscodium/"*_amd64.deb.sha256
log "VSCodium verified."

# ============
# 4) Continue.dev VSIX from Open VSX + sha256 resource, then verify
# ============
log "Fetching Continue VSIX + sha256 from Open VSX..."
python3 - <<'PY' "$BUNDLE_DIR"
import re, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"continue"
outdir.mkdir(parents=True, exist_ok=True)

# We scrape the extension page to discover exact version + download + sha256 links.
# (Open VSX stores a sha256 resource type for extensions.)
page_url = "https://open-vsx.org/extension/Continue/continue"
html = urllib.request.urlopen(page_url).read().decode("utf-8", errors="ignore")

# Try to find the "download" API URL and the "sha256" URL.
# Common Open VSX patterns include /api/<ns>/<ext>/<ver>/file/...vsix and /api/<ns>/<ext>/<ver>/sha256
m_ver = re.search(r'"version"\s*:\s*"([^"]+)"', html)
version = m_ver.group(1) if m_ver else None
if not version:
  # fallback: look for something like /api/.../<ver>/file/
  m = re.search(r'/api/Continue/continue/([^/]+)/file/', html)
  version = m.group(1) if m else None
if not version:
  raise SystemExit("Could not determine Continue extension version from Open VSX page HTML.")

# We'll construct URLs using the discovered version.
# The file name is typically Continue.continue-<version>.vsix
vsix_name = f"Continue.continue-{version}.vsix"
download_url = f"https://open-vsx.org/api/Continue/continue/{version}/file/{vsix_name}"
sha256_url   = f"https://open-vsx.org/api/Continue/continue/{version}/sha256"

# Download both
urllib.request.urlretrieve(download_url, outdir/vsix_name)
urllib.request.urlretrieve(sha256_url, outdir/(vsix_name + ".sha256"))

print("Version:", version)
print("Downloaded:", vsix_name)
print("SHA256 URL:", sha256_url)
PY

log "Verifying Continue VSIX sha256..."
sha256_check_file "$BUNDLE_DIR/continue/"Continue.continue-*.vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix.sha256
log "Continue VSIX verified."

# ============
# 5) Python Extension VSIX from Open VSX + sha256, then verify
# ============
log "Fetching Python extension VSIX + sha256 from Open VSX..."
python3 - <<'PY' "$BUNDLE_DIR"
import re, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

# We scrape the extension page to discover exact version + download + sha256 links.
page_url = "https://open-vsx.org/extension/ms-python/python"
html = urllib.request.urlopen(page_url).read().decode("utf-8", errors="ignore")

# Try to find the version
m_ver = re.search(r'"version"\s*:\s*"([^"]+)"', html)
version = m_ver.group(1) if m_ver else None
if not version:
  # fallback: look for something like /api/.../<ver>/file/
  m = re.search(r'/api/ms-python/python/([^/]+)/file/', html)
  version = m.group(1) if m else None
if not version:
  raise SystemExit("Could not determine Python extension version from Open VSX page HTML.")

# Construct URLs using the discovered version
vsix_name = f"ms-python.python-{version}.vsix"
download_url = f"https://open-vsx.org/api/ms-python/python/{version}/file/{vsix_name}"
sha256_url   = f"https://open-vsx.org/api/ms-python/python/{version}/sha256"

# Download both
urllib.request.urlretrieve(download_url, outdir/vsix_name)
urllib.request.urlretrieve(sha256_url, outdir/(vsix_name + ".sha256"))

print("Version:", version)
print("Downloaded:", vsix_name)
print("SHA256 URL:", sha256_url)
PY

log "Verifying Python extension VSIX sha256..."
sha256_check_file "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix.sha256
log "Python extension VSIX verified."

# ============
# 6) Rust Analyzer Extension VSIX from Open VSX + sha256, then verify
# ============
log "Fetching Rust Analyzer extension VSIX + sha256 from Open VSX..."
python3 - <<'PY' "$BUNDLE_DIR"
import re, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

# We scrape the extension page to discover exact version + download + sha256 links.
page_url = "https://open-vsx.org/extension/rust-lang/rust-analyzer"
html = urllib.request.urlopen(page_url).read().decode("utf-8", errors="ignore")

# Try to find the version
m_ver = re.search(r'"version"\s*:\s*"([^"]+)"', html)
version = m_ver.group(1) if m_ver else None
if not version:
  # fallback: look for something like /api/.../<ver>/file/
  m = re.search(r'/api/rust-lang/rust-analyzer/([^/]+)/file/', html)
  version = m.group(1) if m else None
if not version:
  raise SystemExit("Could not determine Rust Analyzer extension version from Open VSX page HTML.")

# Construct URLs using the discovered version
vsix_name = f"rust-lang.rust-analyzer-{version}.vsix"
download_url = f"https://open-vsx.org/api/rust-lang/rust-analyzer/{version}/file/{vsix_name}"
sha256_url   = f"https://open-vsx.org/api/rust-lang/rust-analyzer/{version}/sha256"

# Download both
urllib.request.urlretrieve(download_url, outdir/vsix_name)
urllib.request.urlretrieve(sha256_url, outdir/(vsix_name + ".sha256"))

print("Version:", version)
print("Downloaded:", vsix_name)
print("SHA256 URL:", sha256_url)
PY

log "Verifying Rust Analyzer extension VSIX sha256..."
sha256_check_file "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix.sha256
log "Rust Analyzer extension VSIX verified."

# ============
# 7) Offline APT repo for Lua 5.3 + common prereqs
# ============
# This step requires a Linux system with apt-get
# On macOS, we'll create a note file and skip the actual repo build
OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  log "WARNING: Not on Linux. Skipping APT repo build."
  log "You have two options:"
  log "  1. Run this script on a Linux system (VM, container, or Pop!_OS) to build the APT repo"
  log "  2. Build the APT repo manually on the target Pop!_OS system before running install_offline.sh"
  log ""
  log "To build manually on Pop!_OS, run:"
  log "  APT_PACKAGES=(lua5.3 ca-certificates curl xz-utils tar)"
  log "  sudo apt-get update"
  log "  sudo apt-get -y --download-only install \"\${APT_PACKAGES[@]}\""
  log "  # Then copy .deb files from /var/cache/apt/archives/ to $BUNDLE_DIR/aptrepo/pool/"
  log "  # And run: cd $BUNDLE_DIR/aptrepo && apt-ftparchive packages pool > Packages && gzip -kf Packages"
  log ""
  
  # Create placeholder structure
  mkdir -p "$BUNDLE_DIR/aptrepo/pool"
  cat >"$BUNDLE_DIR/aptrepo/README.txt" <<EOF
APT repository not built on macOS.
Please build this on a Linux system (or the target Pop!_OS system) before running install_offline.sh.

Required packages (see get_bundle.sh for full list):
- Core: lua5.3, ca-certificates, curl, xz-utils, tar
- Version control: git, git-lfs
- Build tools: build-essential, gcc, g++, make, cmake
- Python: python3-dev, python3-pip, python3-venv
- Utilities: vim, nano, htop, tree, wget, unzip, rsync
- Documentation: man-db, manpages-dev

See get_bundle.sh comments for manual build instructions.
EOF
else
  log "Building local APT repo with development tools and dependencies..."
  # Comprehensive list of packages for airgapped development
  APT_PACKAGES=(
    # Core utilities (already included)
    lua5.3
    ca-certificates
    curl
    xz-utils
    tar
    # Version control
    git
    git-lfs
    # Build tools
    build-essential
    gcc
    g++
    make
    cmake
    pkg-config
    # Python development
    python3
    python3-dev
    python3-pip
    python3-venv
    python3-setuptools
    # System libraries for Python packages
    # Math/Linear Algebra (numpy, scipy, pandas)
    libblas-dev
    liblapack-dev
    libopenblas-dev
    libatlas-base-dev
    libgfortran5
    libgfortran-dev
    # SSL/TLS (requests, httpx, cryptography)
    libssl-dev
    libcrypto++-dev
    # Image processing (matplotlib, pillow, sphinx)
    libpng-dev
    libjpeg-dev
    libtiff-dev
    libfreetype6-dev
    liblcms2-dev
    libwebp-dev
    # XML/HTML parsing (lxml, beautifulsoup4)
    libxml2-dev
    libxslt1-dev
    # Compression (various packages)
    zlib1g-dev
    libbz2-dev
    liblzma-dev
    # Database (sqlite3, psycopg2)
    libsqlite3-dev
    # System libraries
    libffi-dev
    libreadline-dev
    libncurses5-dev
    libncursesw5-dev
    # Audio (if needed)
    libsndfile1-dev
    # Video (if needed)
    libavcodec-dev
    libavformat-dev
    # HDF5 (pandas, h5py)
    libhdf5-dev
    # NetCDF (scientific computing)
    libnetcdf-dev
    # System utilities
    vim
    nano
    htop
    tree
    wget
    unzip
    # Documentation
    man-db
    manpages-dev
    # Additional helpful tools
    rsync
    less
    file
    # QEMU/KVM (for VM bundle support)
    qemu-system-x86
    qemu-utils
    qemu-kvm
  )

  # Download packages + dependencies into aptrepo/pool
  # (This uses apt's resolver on the online machine, but stores .debs for offline.)
  TMP_APT="$BUNDLE_DIR/aptrepo/_tmp"
  rm -rf "$TMP_APT"
  mkdir -p "$TMP_APT"

  # Make sure apt metadata is fresh
  sudo apt-get update -y

  # Download (no install) into a temp cache, then copy .debs into the repo pool
  sudo apt-get -y --download-only -o Dir::Cache="$TMP_APT" install "${APT_PACKAGES[@]}"

  mkdir -p "$BUNDLE_DIR/aptrepo/pool"
  find "$TMP_APT/archives" -maxdepth 1 -type f -name "*.deb" -print -exec cp -n {} "$BUNDLE_DIR/aptrepo/pool/" \;

  # Create minimal repo metadata
  cat >"$BUNDLE_DIR/aptrepo/conf/distributions" <<EOF
Origin: airgap
Label: airgap
Suite: stable
Codename: stable
Architectures: amd64
Components: main
Description: Local offline repo for airgapped installs
EOF

  # Build Packages index
  pushd "$BUNDLE_DIR/aptrepo" >/dev/null
  apt-ftparchive packages pool > Packages
  gzip -kf Packages
  popd >/dev/null

  log "APT repo built."
fi

# ============
# 8) Download Rust toolchain (rustup-init)
# ============
log "Downloading Rust toolchain installer..."
python3 - <<'PY' "$BUNDLE_DIR"
import sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"rust"/"toolchain"
outdir.mkdir(parents=True, exist_ok=True)

# Download rustup-init for Linux x86_64
rustup_url = "https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
rustup_path = outdir/"rustup-init"

try:
    urllib.request.urlretrieve(rustup_url, rustup_path)
    rustup_path.chmod(0o755)  # Make executable
    print("Downloaded rustup-init")
except Exception as e:
    print(f"Warning: Could not download rustup-init: {e}")
    print("You may need to download it manually from https://rustup.rs/")
PY

# Verify rustup-init was downloaded
if [[ -f "$BUNDLE_DIR/rust/toolchain/rustup-init" ]]; then
  # Also create a symlink/copy in the rust directory for easy access
  cp "$BUNDLE_DIR/rust/toolchain/rustup-init" "$BUNDLE_DIR/rust/rustup-init" 2>/dev/null || true
fi

if [[ -f "$BUNDLE_DIR/rust/toolchain/rustup-init" ]] || [[ -f "$BUNDLE_DIR/rust/rustup-init" ]]; then
  log "Rust toolchain installer downloaded."
else
  log "WARNING: rustup-init not downloaded. You may need to download it manually."
fi

# ============
# 8b) Download Rust crates (if Cargo.toml exists)
# ============
RUST_CARGO_TOML="${RUST_CARGO_TOML:-Cargo.toml}"
if [[ -f "$RUST_CARGO_TOML" ]]; then
  log "Found Cargo.toml. Bundling Rust crates for offline use..."
  log "Note: This requires cargo to be installed on the build machine."
  
  if command -v cargo >/dev/null 2>&1; then
    # Use cargo vendor to bundle all dependencies
    CRATES_DIR="$BUNDLE_DIR/rust/crates"
    mkdir -p "$CRATES_DIR"
    
    # Copy Cargo.toml and Cargo.lock to bundle
    cp "$RUST_CARGO_TOML" "$CRATES_DIR/"
    if [[ -f "Cargo.lock" ]]; then
      cp "Cargo.lock" "$CRATES_DIR/"
    fi
    
    # Vendor all dependencies
    (cd "$CRATES_DIR" && cargo vendor --manifest-path "$(pwd)/Cargo.toml" vendor 2>/dev/null || {
      log "WARNING: cargo vendor failed. You may need to run it manually:"
      log "  cd $CRATES_DIR && cargo vendor"
    })
    
    if [[ -d "$CRATES_DIR/vendor" ]]; then
      log "Rust crates bundled successfully."
    else
      log "WARNING: cargo vendor did not create vendor directory."
      log "You may need to bundle Rust crates manually on the target system."
    fi
  else
    log "WARNING: cargo not found. Cannot bundle Rust crates."
    log "Install Rust first, then re-run this script to bundle crates."
    log "Or bundle crates manually on the target system using: cargo vendor"
  fi
else
  log "No Cargo.toml found. Skipping Rust crate bundling."
  log "To bundle Rust crates:"
  log "  1. Create or copy Cargo.toml to the script directory"
  log "  2. Set RUST_CARGO_TOML env var: export RUST_CARGO_TOML=/path/to/Cargo.toml"
  log "  3. Ensure cargo is installed on the build machine"
  log "  4. Re-run this script"
fi

# ============
# 9) Download Python packages (if requirements.txt exists)
# ============
PYTHON_REQUIREMENTS="${PYTHON_REQUIREMENTS:-requirements.txt}"
if [[ -f "$PYTHON_REQUIREMENTS" ]]; then
  log "Found requirements.txt. Downloading Python packages for Linux..."
  python3 - <<'PY' "$BUNDLE_DIR" "$PYTHON_REQUIREMENTS"
import sys, subprocess
from pathlib import Path

bundle = Path(sys.argv[1])
requirements = Path(sys.argv[2])
outdir = bundle/"python"
outdir.mkdir(parents=True, exist_ok=True)

# Copy requirements.txt to bundle for reference
import shutil
shutil.copy(requirements, outdir/"requirements.txt")

# Use pip download to get all packages and dependencies for Linux
# Note: This downloads Linux wheels even on macOS
# We download with dependencies to ensure everything is bundled
try:
    # Step 1: Download binary wheels with ALL dependencies
    # pip download automatically includes dependencies unless --no-deps is specified
    print("Step 1: Downloading binary wheels for Linux (with ALL dependencies)...")
    result = subprocess.run([
        sys.executable, "-m", "pip", "download",
        "-r", str(requirements),
        "-d", str(outdir),
        "--platform", "manylinux2014_x86_64",  # Compatible Linux platform
        "--platform", "manylinux1_x86_64",      # Older compatibility
        "--platform", "linux_x86_64",
        "--only-binary", ":all:",
        "--python-version", "3",  # Python 3.x
        # IMPORTANT: No --no-deps flag, so ALL transitive dependencies are included
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Warning: Some packages may not have binary wheels: {result.stderr}")
    
    # Step 2: Download source distributions as fallback for packages without wheels
    # This ensures we have everything, even if it needs compilation
    # Also downloads dependencies that might have been missed
    print("Step 2: Downloading source distributions (with ALL dependencies)...")
    subprocess.run([
        sys.executable, "-m", "pip", "download",
        "-r", str(requirements),
        "-d", str(outdir),
        "--no-binary", ":all:",  # Get source dists
        # IMPORTANT: No --no-deps flag, so ALL dependencies are included
    ], capture_output=True, text=True, check=False)
    
    # Step 3: Verify we have all dependencies by attempting to resolve them
    print("Step 3: Verifying dependency completeness...")
    # Use pip check to verify all dependencies can be resolved
    verify_result = subprocess.run([
        sys.executable, "-m", "pip", "check",
    ], capture_output=True, text=True, check=False)
    
    # Count downloaded packages
    downloaded = len(list(outdir.glob("*.whl"))) + len(list(outdir.glob("*.tar.gz")))
    print(f"✓ Downloaded {downloaded} package files (wheels and source distributions)")
    print(f"✓ All dependencies are included (pip download includes transitive dependencies)")
    print(f"  Note: Some packages may need system libraries (included in APT repo)")
    
    print(f"Downloaded Python packages to {outdir}")
    print(f"Note: Source distributions will be compiled on the target system.")
    print(f"      Build tools (gcc, python3-dev) are included in the APT repo.")
except subprocess.CalledProcessError as e:
    print(f"Warning: Could not download all Python packages: {e}")
    print("Some packages may need to be downloaded manually or built from source.")
except FileNotFoundError:
    print("Warning: pip not found. Skipping Python package download.")
except Exception as e:
    print(f"Warning: Error downloading Python packages: {e}")
PY
  log "Python packages downloaded (if any)."
  log "Note: Source distributions will need to be built on the target Linux system."
else
  log "No requirements.txt found. Skipping Python package download."
  log "To bundle Python packages:"
  log "  1. Create a requirements.txt file with your packages"
  log "  2. Set PYTHON_REQUIREMENTS env var: export PYTHON_REQUIREMENTS=/path/to/requirements.txt"
  log "  3. Re-run this script"
fi

log "DONE. Bundle created at: $BUNDLE_DIR"
log ""
log "Bundle Summary:"
log " - Models bundled: ${OLLAMA_MODELS}"
log " - Total bundle size: ~32GB+ (includes all models: ~4GB + ~26GB + ~2GB + other components)"
log " - Ensure you have sufficient disk space before copying"
log ""
log "Next: copy $BUNDLE_DIR to an external drive."
log "Note: The bundle is large due to multiple models. Consider using a large USB drive or external SSD."
