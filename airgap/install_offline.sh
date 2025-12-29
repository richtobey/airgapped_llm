#!/usr/bin/env bash
set -euo pipefail

# ============
# OS Detection - This script is for Debian/Linux only
# ============
OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  echo "ERROR: This script is designed for Debian/Linux systems only." >&2
  echo "Detected OS: $OS" >&2
  echo "" >&2
  echo "This script uses Debian-specific tools:" >&2
  echo "  - apt-get / dpkg (package management)" >&2
  echo "  - sha256sum (checksum verification)" >&2
  echo "  - .deb package format" >&2
  echo "" >&2
  echo "This script should be run on the target Linux system (e.g., Pop!_OS, Ubuntu, Debian)." >&2
  echo "Use get_bundle.sh on macOS to create the bundle, then transfer it to Linux." >&2
  exit 1
fi

BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/bin}"

log() { echo "[$(date -Is)] $*"; }

sha256_check_file() {
  local file="$1"
  local sha_file="$2"
  (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")")
}

# ============
# 0) Sanity checks
# ============
test -d "$BUNDLE_DIR" || { echo "Bundle dir not found: $BUNDLE_DIR"; exit 1; }

# Re-verify hashes on the airgapped machine (defense-in-depth)
log "Re-verifying downloaded artifacts..."
sha256_check_file "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz.sha256"
sha256_check_file "$BUNDLE_DIR/vscodium/"*_amd64.deb "$BUNDLE_DIR/vscodium/"*_amd64.deb.sha256
sha256_check_file "$BUNDLE_DIR/continue/"Continue.continue-*.vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix.sha256
sha256_check_file "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix.sha256
sha256_check_file "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix.sha256
log "All artifact hashes OK."

# ============
# 1) Install offline APT repo (Lua 5.3 and prereqs)
# ============
REPO_DIR="$BUNDLE_DIR/aptrepo"

# Check if APT repo was built
if [[ ! -f "$REPO_DIR/Packages.gz" ]] && [[ ! -f "$REPO_DIR/Packages" ]]; then
  log "WARNING: APT repo not found or not built."
  log "The bundle was likely created on macOS (which can't build APT repos)."
  log ""
  log "Options:"
  log "  1. Build the APT repo now (requires internet):"
  log "     cd $REPO_DIR"
  log "     sudo apt-get update"
  log "     sudo apt-get -y --download-only install git build-essential python3-dev python3-pip rustup-init"
  log "     # Copy .deb files from /var/cache/apt/archives/ to $REPO_DIR/pool/"
  log "     apt-ftparchive packages pool > Packages && gzip -kf Packages"
  log ""
  log "  2. Skip APT repo setup if packages are already installed"
  log ""
  read -p "Skip APT repo setup? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Please build the APT repo manually and re-run this script."
    exit 1
  fi
  log "Skipping APT repo setup..."
else
  log "Configuring local offline APT repo..."
  # Add a local file:// repo (no network)
  sudo tee /etc/apt/sources.list.d/airgap-local.list >/dev/null <<EOF
deb [trusted=yes] file:$REPO_DIR stable main
EOF

  # Update APT from local repo only
  # Note: If system has other sources configured, they may fail (expected on airgapped system)
  # The local file:// source will work regardless
  log "Updating APT package lists from local repository..."
  sudo apt-get update -y 2>&1 | grep -v "Failed to fetch" || true
  log "Installing development tools and system libraries from offline repo..."
  # Install all packages from the offline repo
  # This includes build tools, Python dev tools, and system libraries for Python packages
  sudo apt-get install -y \
    lua5.3 \
    git \
    git-lfs \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    pkg-config \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    libblas-dev \
    liblapack-dev \
    libopenblas-dev \
    libatlas-base-dev \
    libgfortran5 \
    libgfortran-dev \
    libssl-dev \
    libcrypto++-dev \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    libfreetype6-dev \
    liblcms2-dev \
    libwebp-dev \
    libxml2-dev \
    libxslt1-dev \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    libsqlite3-dev \
    libffi-dev \
    libreadline-dev \
    libncurses5-dev \
    libncursesw5-dev \
    libsndfile1-dev \
    libavcodec-dev \
    libavformat-dev \
    libhdf5-dev \
    libnetcdf-dev \
    vim \
    nano \
    htop \
    tree \
    wget \
    unzip \
    man-db \
    manpages-dev \
    rsync \
    less \
    file \
    || log "WARNING: Some packages may have failed to install. Check manually."
fi

# ============
# 2) Install VSCodium (.deb)
# ============
log "Installing VSCodium..."
sudo dpkg -i "$BUNDLE_DIR"/vscodium/*_amd64.deb || true
# Fix deps from the local repo (no downloads)
sudo apt-get -y -o Acquire::Languages=none --no-download -f install

# ============
# 3) Install Ollama (binary)
# ============
log "Installing Ollama binary..."
TMP_DIR="$(mktemp -d)"
tar -xzf "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" -C "$TMP_DIR"
sudo install -m 0755 "$TMP_DIR/ollama" "$INSTALL_PREFIX/ollama"
rm -rf "$TMP_DIR"

# ============
# 3b) Verify GPU support for Ollama
# ============
log "Verifying GPU support for Ollama..."
GPU_AVAILABLE=false

# Check for NVIDIA drivers
if command -v nvidia-smi >/dev/null 2>&1; then
  log "NVIDIA drivers detected. Checking GPU status..."
  if nvidia-smi >/dev/null 2>&1; then
    log "✓ NVIDIA GPU detected and accessible"
    GPU_AVAILABLE=true
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | while IFS=',' read -r name driver memory; do
      log "  GPU: $name | Driver: $driver | Memory: $memory"
    done
  else
    log "WARNING: nvidia-smi command failed. GPU may not be accessible."
  fi
else
  log "NOTE: nvidia-smi not found. NVIDIA drivers may not be installed."
  log "      Ollama will use CPU mode. For GPU support, install NVIDIA drivers."
fi

# Check for CUDA
if command -v nvcc >/dev/null 2>&1; then
  CUDA_VERSION=$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release \([0-9.]*\).*/\1/')
  if [[ -n "$CUDA_VERSION" ]]; then
    log "✓ CUDA detected: version $CUDA_VERSION"
    GPU_AVAILABLE=true
  else
    log "NOTE: nvcc found but version could not be determined."
  fi
else
  log "NOTE: CUDA compiler (nvcc) not found. CUDA may not be installed."
fi

# Set up GPU environment variable if GPU is available
if [[ "$GPU_AVAILABLE" == "true" ]]; then
  log "GPU support detected. Configuring Ollama for GPU usage..."
  
  # Add to shell profile for persistence
  OLLAMA_GPU_SETUP='export OLLAMA_NUM_GPU=1'
  
  # Check if already in profile
  if ! grep -q "OLLAMA_NUM_GPU" "$HOME/.bashrc" 2>/dev/null && ! grep -q "OLLAMA_NUM_GPU" "$HOME/.zshrc" 2>/dev/null; then
    # Try to detect shell and add to appropriate profile
    if [[ -n "${ZSH_VERSION:-}" ]] || [[ -f "$HOME/.zshrc" ]]; then
      echo "" >> "$HOME/.zshrc"
      echo "# Ollama GPU configuration (added by airgap installer)" >> "$HOME/.zshrc"
      echo "$OLLAMA_GPU_SETUP" >> "$HOME/.zshrc"
      log "✓ Added OLLAMA_NUM_GPU=1 to ~/.zshrc"
    else
      echo "" >> "$HOME/.bashrc"
      echo "# Ollama GPU configuration (added by airgap installer)" >> "$HOME/.bashrc"
      echo "$OLLAMA_GPU_SETUP" >> "$HOME/.bashrc"
      log "✓ Added OLLAMA_NUM_GPU=1 to ~/.bashrc"
    fi
  fi
  
  # Export for current session
  export OLLAMA_NUM_GPU=1
  log "✓ OLLAMA_NUM_GPU=1 set for current session"
else
  log "NOTE: No GPU detected. Ollama will run in CPU mode."
  log "      To enable GPU later, install NVIDIA drivers and CUDA, then:"
  log "      export OLLAMA_NUM_GPU=1"
fi

# Inform about Ollama logs location
log "Ollama logs location: ~/.ollama/logs/server.log"
log "  To monitor logs: tail -f ~/.ollama/logs/server.log"

# ============
# 4) Move model data into ~/.ollama
# ============
log "Restoring Ollama model directory to \$HOME/.ollama ..."
mkdir -p "$HOME/.ollama"
rsync -a "$BUNDLE_DIR/models/.ollama/" "$HOME/.ollama/"

# ============
# 5) Install Continue.dev VSIX into VSCodium
# ============
log "Installing Continue VSIX into VSCodium..."
VSIX_PATH="$(ls -1 "$BUNDLE_DIR"/continue/Continue.continue-*.vsix | head -n1)"
codium --install-extension "$VSIX_PATH" --force

# ============
# 6) Install Python extension into VSCodium
# ============
log "Installing Python extension into VSCodium..."
PYTHON_VSIX="$(ls -1 "$BUNDLE_DIR"/extensions/ms-python.python-*.vsix | head -n1)"
codium --install-extension "$PYTHON_VSIX" --force

# ============
# 7) Install Rust Analyzer extension into VSCodium
# ============
log "Installing Rust Analyzer extension into VSCodium..."
RUST_VSIX="$(ls -1 "$BUNDLE_DIR"/extensions/rust-lang.rust-analyzer-*.vsix | head -n1)"
codium --install-extension "$RUST_VSIX" --force

# ============
# 8) Install Rust toolchain
# ============
RUSTUP_INIT=""
if [[ -f "$BUNDLE_DIR/rust/rustup-init" ]]; then
  RUSTUP_INIT="$BUNDLE_DIR/rust/rustup-init"
elif [[ -f "$BUNDLE_DIR/rust/toolchain/rustup-init" ]]; then
  RUSTUP_INIT="$BUNDLE_DIR/rust/toolchain/rustup-init"
fi

if [[ -n "$RUSTUP_INIT" ]]; then
  log "Installing Rust toolchain..."
  chmod +x "$RUSTUP_INIT"
  
  # Check if rust is already installed
  if command -v rustc >/dev/null 2>&1; then
    log "Rust appears to be already installed. Skipping rustup-init."
  else
    log "Running rustup-init (this will install Rust to ~/.cargo/bin)..."
    # Run rustup-init non-interactively
    "$RUSTUP_INIT" -y --default-toolchain stable --profile default || {
      log "WARNING: rustup-init failed. You may need to run it manually."
    }
    
    # Add cargo to PATH for current session
    if [[ -f "$HOME/.cargo/env" ]]; then
      source "$HOME/.cargo/env"
      log "Rust toolchain installed. Cargo is available at ~/.cargo/bin"
    fi
  fi
else
  log "WARNING: rustup-init not found in bundle. Rust will not be installed."
  log "You can download it manually from https://rustup.rs/ if needed."
fi

# ============
# 8b) Set up Rust crates (if bundled)
# ============
if [[ -d "$BUNDLE_DIR/rust/crates/vendor" ]] && [[ -n "$(ls -A "$BUNDLE_DIR/rust/crates/vendor" 2>/dev/null)" ]]; then
  log "Rust crates found in bundle. Setting up for offline use..."
  
  if command -v cargo >/dev/null 2>&1 || [[ -f "$HOME/.cargo/env" ]]; then
    # Source cargo env if available
    [[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
    
    if command -v cargo >/dev/null 2>&1; then
      log "To use bundled Rust crates in your project:"
      log "  1. Copy Cargo.toml and Cargo.lock from $BUNDLE_DIR/rust/crates/ to your project"
      log "  2. Copy the vendor directory: cp -r $BUNDLE_DIR/rust/crates/vendor <your-project>/"
      log "  3. Add to your Cargo.toml:"
      log "     [source.crates-io]"
      log "     replace-with = \"vendored-sources\""
      log "     [source.vendored-sources]"
      log "     directory = \"vendor\""
      log ""
      log "Or use: cargo build --offline --frozen"
    else
      log "WARNING: cargo not found. Install Rust toolchain first."
    fi
  else
    log "WARNING: Rust not installed. Install Rust toolchain first to use bundled crates."
  fi
else
  log "No Rust crates found in bundle. Skipping Rust crate setup."
fi

# ============
# 9) Install Python packages (if bundled)
# ============
if [[ -d "$BUNDLE_DIR/python" ]] && [[ -n "$(ls -A "$BUNDLE_DIR/python" 2>/dev/null)" ]]; then
  log "Installing Python packages from bundle..."
  
  # Check if pip is available
  if command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1; then
    PIP_CMD="python3 -m pip"
    if command -v pip3 >/dev/null 2>&1; then
      PIP_CMD="pip3"
    fi
    
    # If there's a requirements.txt, install from it (preferred method)
    if [[ -f "$BUNDLE_DIR/python/requirements.txt" ]]; then
      log "Installing from requirements.txt (this may take a while)..."
      $PIP_CMD install --no-index --find-links "$BUNDLE_DIR/python" -r "$BUNDLE_DIR/python/requirements.txt" || {
        log "WARNING: Some packages from requirements.txt failed to install."
        log "This may be normal if some packages are source distributions that need compilation."
      }
    else
      # Fallback: try to install all wheel/tar.gz files
      log "No requirements.txt found. Attempting to install all packages in bundle..."
      log "Note: This may not install dependencies correctly. Use requirements.txt for best results."
      $PIP_CMD install --no-index --find-links "$BUNDLE_DIR/python" \
        $(find "$BUNDLE_DIR/python" -maxdepth 1 \( -name "*.whl" -o -name "*.tar.gz" \) -type f -exec basename {} \; | sed 's/-.*//' | sort -u | head -20) \
        || log "WARNING: Package installation had some failures."
    fi
    
    log "Python packages installation completed."
  else
    log "WARNING: pip3 not found. Python packages cannot be installed."
    log "Install python3-pip from the APT repo first, then re-run this section."
  fi
else
  log "No Python packages found in bundle. Skipping Python package installation."
fi

log "DONE."
log ""
log "Installation Summary:"
log " - VSCodium installed with extensions (Continue, Python, Rust Analyzer)"
log " - Ollama installed (start with: ollama serve)"
log " - Development tools installed (git, build-essential, etc.)"
if [[ -f "$BUNDLE_DIR/rust/rustup-init" ]]; then
  log " - Rust toolchain installed (if rustup-init ran successfully)"
fi
if [[ -d "$BUNDLE_DIR/python" ]] && [[ -n "$(ls -A "$BUNDLE_DIR/python" 2>/dev/null)" ]]; then
  log " - Python packages installed"
fi
log ""
log "Next steps:"
log " 1. Start Ollama: ollama serve"
log " 2. Verify GPU (if available):"
log "    - Check NVIDIA: nvidia-smi"
log "    - Check CUDA: nvcc --version"
log "    - Check Ollama logs: tail -f ~/.ollama/logs/server.log"
log "    - If GPU not detected, set: export OLLAMA_NUM_GPU=1"
log " 3. Verify Rust: rustc --version (if installed)"
log " 4. Verify Python: python3 --version && pip3 --version"
log " 5. Open VSCodium and verify extensions are working"
