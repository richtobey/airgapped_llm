#!/usr/bin/env bash
# Use set -eo pipefail but allow controlled failures
# Note: -u (unbound variables) is removed to allow graceful handling of optional variables
set -eo pipefail

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
  echo "Use get_bundle.sh on Pop!_OS (with internet) to create the bundle, then transfer it to this system." >&2
  exit 1
fi

BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/bin}"

# ============
# Logging Setup
# ============
# Debug log path - structured JSON logging for debugging
DEBUG_LOG="${DEBUG_LOG:-$BUNDLE_DIR/logs/install_debug.log}"
# Console log path - captures all console output
CONSOLE_LOG="${CONSOLE_LOG:-$BUNDLE_DIR/logs/install_console.log}"
# Ensure log directories exist
mkdir -p "$(dirname "$DEBUG_LOG")" "$(dirname "$CONSOLE_LOG")" 2>/dev/null || true

# Structured debug logging (JSON format, similar to get_bundle.sh)
debug_log() {
  local location="$1"
  local message="$2"
  local data="${3:-{}}"
  local hypothesis="${4:-INSTALL}"
  local run_id="${5:-run1}"
  local timestamp
  timestamp=$(date +%s)000
  
  local log_entry
  log_entry=$(cat <<EOF
{"id":"log_${timestamp}_${RANDOM}","timestamp":${timestamp},"location":"${location}","message":"${message}","data":${data},"sessionId":"install-session","runId":"${run_id}","hypothesisId":"${hypothesis}"}
EOF
)
  echo "$log_entry" >> "${DEBUG_LOG}" 2>/dev/null || true
}

# Simple log function with timestamp
log() { 
  echo "[$(date -Is)] $*"
}

# Status tracking (similar to get_bundle.sh)
mark_success() {
  eval "STATUS_$1=\"success\""
  debug_log "install_offline.sh:$1:success" "Component installed successfully" "{\"component\":\"$1\",\"status\":\"success\"}" "INSTALL-A" "run1"
}

mark_failed() {
  eval "STATUS_$1=\"failed\""
  debug_log "install_offline.sh:$1:failed" "Component installation failed" "{\"component\":\"$1\",\"status\":\"failed\"}" "INSTALL-B" "run1"
}

mark_skipped() {
  eval "STATUS_$1=\"skipped\""
  debug_log "install_offline.sh:$1:skipped" "Component installation skipped" "{\"component\":\"$1\",\"status\":\"skipped\"}" "INSTALL-C" "run1"
}

get_status() {
  eval "echo \"\$STATUS_$1\""
}

# Initialize status tracking
STATUS_apt_repo=""
STATUS_vscodium=""
STATUS_ollama=""
STATUS_models=""
STATUS_extensions=""
STATUS_rust=""
STATUS_python=""

# Set up console logging - redirect stdout and stderr to both console and log file
if [[ -n "$CONSOLE_LOG" ]]; then
  touch "$CONSOLE_LOG" 2>/dev/null || true
  exec > >(tee -a "$CONSOLE_LOG") 2>&1
  echo "=========================================="
  echo "Installation started: $(date -Is)"
  echo "Console output is being logged to: $CONSOLE_LOG"
  echo "Debug logs (JSON) are being logged to: $DEBUG_LOG"
  echo "=========================================="
  echo ""
fi

# Log script start
debug_log "install_offline.sh:start" "Installation script started" "{\"bundle_dir\":\"$BUNDLE_DIR\",\"install_prefix\":\"$INSTALL_PREFIX\",\"os\":\"$OS\",\"user\":\"$USER\",\"pid\":$$}" "INIT-A" "run1"

sha256_check_file() {
  local file="$1"
  local sha_file="$2"
  (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")")
}

# Verify VSIX file - Open VSX returns just the hash, so we need to format it
sha256_check_vsix() {
  local file="$1"
  local sha_file="$2"
  
  # Read the hash from the file (might be just hash or "hash filename")
  local expected_hash
  if [[ -f "$sha_file" ]]; then
    expected_hash=$(head -n1 "$sha_file" | awk '{print $1}')
  else
    return 1
  fi
  
  # Calculate actual hash
  local actual_hash
  if command -v sha256sum >/dev/null 2>&1; then
    actual_hash=$(sha256sum "$file" | awk '{print $1}')
  else
    log "ERROR: sha256sum not found"
    return 1
  fi
  
  # Compare hashes
  if [[ "$expected_hash" == "$actual_hash" ]]; then
    return 0
  else
    return 1
  fi
}

# ============
# 0) Sanity checks
# ============
test -d "$BUNDLE_DIR" || { echo "Bundle dir not found: $BUNDLE_DIR"; exit 1; }

# Re-verify hashes on the airgapped machine (defense-in-depth)
log "Re-verifying downloaded artifacts..."

# Find Ollama archive (could be .tar.zst or .tgz)
OLLAMA_ARCHIVE=""
OLLAMA_SHA=""
if [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst" ]]; then
  OLLAMA_ARCHIVE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst"
  OLLAMA_SHA="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst.sha256"
elif [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" ]]; then
  OLLAMA_ARCHIVE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz"
  OLLAMA_SHA="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz.sha256"
else
  # Try to find any ollama archive
  OLLAMA_ARCHIVE=$(find "$BUNDLE_DIR/ollama" -maxdepth 1 -name "ollama-linux-amd64*" -type f ! -name "*.sha256" 2>/dev/null | head -n1)
  if [[ -n "$OLLAMA_ARCHIVE" ]]; then
    OLLAMA_SHA="${OLLAMA_ARCHIVE}.sha256"
  fi
fi

if [[ -n "$OLLAMA_ARCHIVE" ]] && [[ -f "$OLLAMA_SHA" ]]; then
  sha256_check_file "$OLLAMA_ARCHIVE" "$OLLAMA_SHA"
else
  log "WARNING: Ollama archive or SHA256 file not found. Skipping verification."
fi

sha256_check_file "$BUNDLE_DIR/vscodium/"*_amd64.deb "$BUNDLE_DIR/vscodium/"*_amd64.deb.sha256
sha256_check_vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix.sha256
sha256_check_vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix.sha256
sha256_check_vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix.sha256
log "All artifact hashes OK."

# ============
# 1) Install offline APT repo (Lua 5.3 and prereqs)
# ============
REPO_DIR="$BUNDLE_DIR/aptrepo"

# Check if APT repo was built
debug_log "install_offline.sh:apt_repo:check" "Checking for APT repository" "{\"repo_dir\":\"$REPO_DIR\",\"packages_gz_exists\":$(test -f "$REPO_DIR/Packages.gz" && echo true || echo false),\"packages_exists\":$(test -f "$REPO_DIR/Packages" && echo true || echo false)}" "APT-A" "run1"

if [[ ! -f "$REPO_DIR/Packages.gz" ]] && [[ ! -f "$REPO_DIR/Packages" ]]; then
  log "ERROR: APT repo not found or not built."
  log "The bundle must be created on Pop!_OS with internet access using get_bundle.sh"
  log "which builds the APT repository automatically."
  log ""
  log "If you have temporary internet access, you can build it now:"
  log "  1. cd $REPO_DIR"
  log "  2. sudo apt-get update"
  log "  3. sudo apt-get -y --download-only install <packages>"
  log "  4. Copy .deb files from /var/cache/apt/archives/ to $REPO_DIR/pool/"
  log "  5. apt-ftparchive packages pool > Packages && gzip -kf Packages"
  log ""
  log "Otherwise, please re-create the bundle on a Pop!_OS system with internet."
  mark_failed "apt_repo"
  debug_log "install_offline.sh:apt_repo:missing" "APT repository not found" "{\"status\":\"failed\",\"repo_dir\":\"$REPO_DIR\"}" "APT-B" "run1"
  exit 1
else
  log "Configuring local offline APT repo..."
  debug_log "install_offline.sh:apt_repo:configure" "Configuring offline APT repository" "{\"repo_dir\":\"$REPO_DIR\"}" "APT-A" "run1"
  
  # Add a local file:// repo (no network)
  if sudo tee /etc/apt/sources.list.d/airgap-local.list >/dev/null <<EOF
deb [trusted=yes] file:$REPO_DIR stable main
EOF
  then
    debug_log "install_offline.sh:apt_repo:sources_configured" "APT sources list configured" "{\"status\":\"success\"}" "APT-A" "run1"
  else
    log "WARNING: Failed to configure APT sources list"
    mark_failed "apt_repo"
    debug_log "install_offline.sh:apt_repo:sources_failed" "Failed to configure APT sources" "{\"status\":\"failed\"}" "APT-B" "run1"
  fi

  # Update APT from local repo only
  # Note: If system has other sources configured, they may fail (expected on airgapped system)
  # The local file:// source will work regardless
  log "Updating APT package lists from local repository..."
  debug_log "install_offline.sh:apt_repo:update_start" "Starting APT update" "{\"repo_dir\":\"$REPO_DIR\"}" "APT-A" "run1"
  
  # Disable network access for apt-get to ensure it only uses local repo
  APT_UPDATE_EXIT=0
  if sudo apt-get update -y -o Acquire::http::Timeout=1 -o Acquire::ftp::Timeout=1 2>&1 | grep -v "Failed to fetch" || true; then
    APT_UPDATE_EXIT=0
  else
    APT_UPDATE_EXIT=$?
  fi
  
  debug_log "install_offline.sh:apt_repo:update_complete" "APT update completed" "{\"exit_code\":$APT_UPDATE_EXIT}" "APT-A" "run1"
  
  if [[ $APT_UPDATE_EXIT -ne 0 ]]; then
    log "WARNING: apt-get update had issues (exit code: $APT_UPDATE_EXIT)"
    log "This may be expected if other sources are configured. Continuing..."
  fi
  
  log "Installing development tools and system libraries from offline repo..."
  debug_log "install_offline.sh:apt_repo:install_start" "Starting package installation" "{\"package_count\":50}" "APT-A" "run1"
  
  # Install all packages from the offline repo
  # This includes build tools, Python dev tools, and system libraries for Python packages
  APT_INSTALL_EXIT=0
  if sudo apt-get install -y \
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
    gfortran \
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
    zstd \
    2>&1; then
    APT_INSTALL_EXIT=0
    mark_success "apt_repo"
    log "✓ APT packages installed successfully"
    debug_log "install_offline.sh:apt_repo:install_success" "APT packages installed successfully" "{\"status\":\"success\",\"exit_code\":0}" "APT-A" "run1"
  else
    APT_INSTALL_EXIT=$?
    log "WARNING: Some packages may have failed to install (exit code: $APT_INSTALL_EXIT). Check manually."
    mark_failed "apt_repo"
    debug_log "install_offline.sh:apt_repo:install_failed" "APT package installation had issues" "{\"status\":\"failed\",\"exit_code\":$APT_INSTALL_EXIT}" "APT-B" "run1"
  fi
fi

# ============
# 2) Install VSCodium (.deb)
# ============
log "Installing VSCodium..."
debug_log "install_offline.sh:vscodium:start" "Starting VSCodium installation" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "VSCODE-A" "run1"

VSCODE_DEB=""
if [[ -f "$BUNDLE_DIR/vscodium/"*_amd64.deb ]]; then
  VSCODE_DEB=$(ls -1 "$BUNDLE_DIR"/vscodium/*_amd64.deb 2>/dev/null | head -n1)
fi

if [[ -z "$VSCODE_DEB" ]] || [[ ! -f "$VSCODE_DEB" ]]; then
  log "ERROR: VSCodium .deb package not found"
  mark_failed "vscodium"
  debug_log "install_offline.sh:vscodium:missing" "VSCodium package not found" "{\"status\":\"failed\",\"bundle_dir\":\"$BUNDLE_DIR\"}" "VSCODE-B" "run1"
else
  if sudo dpkg -i "$VSCODE_DEB" 2>&1; then
    DPKG_EXIT=0
  else
    DPKG_EXIT=$?
  fi
  
  debug_log "install_offline.sh:vscodium:dpkg" "dpkg installation completed" "{\"exit_code\":$DPKG_EXIT}" "VSCODE-A" "run1"
  
  # Fix deps from the local repo (no downloads)
  log "Fixing dependencies from local repo..."
  if sudo apt-get -y -o Acquire::Languages=none --no-download -f install 2>&1; then
    APT_FIX_EXIT=0
    mark_success "vscodium"
    log "✓ VSCodium installed successfully"
    debug_log "install_offline.sh:vscodium:success" "VSCodium installed successfully" "{\"status\":\"success\"}" "VSCODE-A" "run1"
  else
    APT_FIX_EXIT=$?
    if [[ $DPKG_EXIT -eq 0 ]]; then
      mark_success "vscodium"
      log "✓ VSCodium installed (dependency fix had issues but may be OK)"
      debug_log "install_offline.sh:vscodium:partial" "VSCodium installed but dependency fix had issues" "{\"status\":\"partial\",\"dpkg_exit\":$DPKG_EXIT,\"apt_fix_exit\":$APT_FIX_EXIT}" "VSCODE-A" "run1"
    else
      mark_failed "vscodium"
      log "WARNING: VSCodium installation had issues"
      debug_log "install_offline.sh:vscodium:failed" "VSCodium installation failed" "{\"status\":\"failed\",\"dpkg_exit\":$DPKG_EXIT,\"apt_fix_exit\":$APT_FIX_EXIT}" "VSCODE-B" "run1"
    fi
  fi
fi

# ============
# 3) Install Ollama (binary)
# ============
log "Installing Ollama binary..."
debug_log "install_offline.sh:ollama:start" "Starting Ollama installation" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "OLLAMA-A" "run1"

# Find Ollama archive (could be .tar.zst or .tgz)
if [[ -z "$OLLAMA_ARCHIVE" ]]; then
  if [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst" ]]; then
    OLLAMA_ARCHIVE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst"
  elif [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" ]]; then
    OLLAMA_ARCHIVE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz"
  else
    OLLAMA_ARCHIVE=$(find "$BUNDLE_DIR/ollama" -maxdepth 1 -name "ollama-linux-amd64*" -type f ! -name "*.sha256" 2>/dev/null | head -n1)
  fi
fi

if [[ -z "$OLLAMA_ARCHIVE" ]] || [[ ! -f "$OLLAMA_ARCHIVE" ]]; then
  log "ERROR: Ollama archive not found in $BUNDLE_DIR/ollama/"
  log "Expected: ollama-linux-amd64.tar.zst or ollama-linux-amd64.tgz"
  mark_failed "ollama"
  debug_log "install_offline.sh:ollama:missing" "Ollama archive not found" "{\"status\":\"failed\",\"bundle_dir\":\"$BUNDLE_DIR\"}" "OLLAMA-B" "run1"
  exit 1
fi

debug_log "install_offline.sh:ollama:archive_found" "Ollama archive found" "{\"archive\":\"$OLLAMA_ARCHIVE\"}" "OLLAMA-A" "run1"

TMP_DIR="$(mktemp -d)"

# Extract based on file format
if [[ "$OLLAMA_ARCHIVE" == *.tar.zst ]]; then
  log "Extracting .tar.zst archive..."
  # Check for zstd or unzstd
  if command -v unzstd >/dev/null 2>&1; then
    unzstd -c "$OLLAMA_ARCHIVE" | tar -x -C "$TMP_DIR"
  elif command -v zstd >/dev/null 2>&1; then
    zstd -dc "$OLLAMA_ARCHIVE" | tar -x -C "$TMP_DIR"
  else
    log "ERROR: zstd or unzstd not found. Cannot extract .tar.zst file."
    log "Attempting to install zstd from offline APT repo..."
    # Try to install zstd from the offline repo (should be in the bundle)
    if sudo apt-get install -y -o Acquire::Languages=none --no-download zstd 2>/dev/null; then
      log "✓ zstd installed from offline repo"
      # Try extraction again
      if command -v unzstd >/dev/null 2>&1; then
        unzstd -c "$OLLAMA_ARCHIVE" | tar -x -C "$TMP_DIR"
      elif command -v zstd >/dev/null 2>&1; then
        zstd -dc "$OLLAMA_ARCHIVE" | tar -x -C "$TMP_DIR"
      else
        log "ERROR: zstd installation failed or command not found after install"
        rm -rf "$TMP_DIR"
        exit 1
      fi
    else
      log "ERROR: zstd not available in offline repo and cannot be installed."
      log "Install zstd manually: sudo apt-get install -y zstd"
      log "Or re-create bundle with zstd included in APT repo"
      rm -rf "$TMP_DIR"
      exit 1
    fi
  fi
else
  log "Extracting .tgz archive..."
  tar -xzf "$OLLAMA_ARCHIVE" -C "$TMP_DIR"
fi

# Find the ollama binary in the extracted directory
OLLAMA_BIN=""
if [[ -f "$TMP_DIR/ollama" ]]; then
  OLLAMA_BIN="$TMP_DIR/ollama"
elif [[ -f "$TMP_DIR/bin/ollama" ]]; then
  OLLAMA_BIN="$TMP_DIR/bin/ollama"
else
  OLLAMA_BIN=$(find "$TMP_DIR" -name "ollama" -type f -executable 2>/dev/null | head -n1)
fi

if [[ -z "$OLLAMA_BIN" ]] || [[ ! -f "$OLLAMA_BIN" ]]; then
  log "ERROR: Ollama binary not found in extracted archive"
  rm -rf "$TMP_DIR"
  exit 1
fi

if sudo install -m 0755 "$OLLAMA_BIN" "$INSTALL_PREFIX/ollama" 2>&1; then
  mark_success "ollama"
  log "✓ Ollama installed to $INSTALL_PREFIX/ollama"
  debug_log "install_offline.sh:ollama:success" "Ollama installed successfully" "{\"status\":\"success\",\"install_path\":\"$INSTALL_PREFIX/ollama\"}" "OLLAMA-A" "run1"
else
  mark_failed "ollama"
  log "ERROR: Failed to install Ollama binary"
  debug_log "install_offline.sh:ollama:install_failed" "Failed to install Ollama binary" "{\"status\":\"failed\"}" "OLLAMA-B" "run1"
fi
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
debug_log "install_offline.sh:models:start" "Starting model restoration" "{\"source\":\"$BUNDLE_DIR/models/.ollama\",\"dest\":\"$HOME/.ollama\"}" "MODEL-A" "run1"

if [[ -d "$BUNDLE_DIR/models/.ollama" ]] && [[ -n "$(ls -A "$BUNDLE_DIR/models/.ollama" 2>/dev/null)" ]]; then
  mkdir -p "$HOME/.ollama"
  if rsync -a "$BUNDLE_DIR/models/.ollama/" "$HOME/.ollama/" 2>&1; then
    MODEL_COUNT=$(find "$HOME/.ollama" -name "*.gguf" -o -name "*.bin" 2>/dev/null | wc -l || echo "0")
    MODEL_SIZE=$(du -sh "$HOME/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
    mark_success "models"
    log "✓ Models restored successfully ($MODEL_COUNT models, $MODEL_SIZE)"
    debug_log "install_offline.sh:models:success" "Models restored successfully" "{\"status\":\"success\",\"model_count\":$MODEL_COUNT,\"size\":\"$MODEL_SIZE\"}" "MODEL-A" "run1"
  else
    mark_failed "models"
    log "WARNING: Failed to restore models"
    debug_log "install_offline.sh:models:failed" "Failed to restore models" "{\"status\":\"failed\"}" "MODEL-B" "run1"
  fi
else
  mark_skipped "models"
  log "WARNING: No models found in bundle. Skipping model restoration."
  debug_log "install_offline.sh:models:skipped" "No models found in bundle" "{\"status\":\"skipped\"}" "MODEL-C" "run1"
fi

# ============
# 5) Install Continue.dev VSIX into VSCodium
# ============
log "Installing Continue VSIX into VSCodium..."
debug_log "install_offline.sh:extensions:continue_start" "Starting Continue extension installation" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "EXT-A" "run1"

VSIX_PATH="$(ls -1 "$BUNDLE_DIR"/continue/Continue.continue-*.vsix 2>/dev/null | head -n1)"
if [[ -n "$VSIX_PATH" ]] && [[ -f "$VSIX_PATH" ]]; then
  if codium --install-extension "$VSIX_PATH" --force 2>&1; then
    log "✓ Continue extension installed"
    debug_log "install_offline.sh:extensions:continue_success" "Continue extension installed" "{\"status\":\"success\"}" "EXT-A" "run1"
  else
    log "WARNING: Continue extension installation may have failed"
    debug_log "install_offline.sh:extensions:continue_failed" "Continue extension installation failed" "{\"status\":\"failed\"}" "EXT-B" "run1"
  fi
else
  log "WARNING: Continue extension VSIX not found"
  debug_log "install_offline.sh:extensions:continue_missing" "Continue extension VSIX not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
fi

# ============
# 6) Install Python extension into VSCodium
# ============
log "Installing Python extension into VSCodium..."
debug_log "install_offline.sh:extensions:python_start" "Starting Python extension installation" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "EXT-A" "run1"

PYTHON_VSIX="$(ls -1 "$BUNDLE_DIR"/extensions/ms-python.python-*.vsix 2>/dev/null | head -n1)"
if [[ -n "$PYTHON_VSIX" ]] && [[ -f "$PYTHON_VSIX" ]]; then
  if codium --install-extension "$PYTHON_VSIX" --force 2>&1; then
    log "✓ Python extension installed"
    debug_log "install_offline.sh:extensions:python_success" "Python extension installed" "{\"status\":\"success\"}" "EXT-A" "run1"
  else
    log "WARNING: Python extension installation may have failed"
    debug_log "install_offline.sh:extensions:python_failed" "Python extension installation failed" "{\"status\":\"failed\"}" "EXT-B" "run1"
  fi
else
  log "WARNING: Python extension VSIX not found"
  debug_log "install_offline.sh:extensions:python_missing" "Python extension VSIX not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
fi

# ============
# 7) Install Rust Analyzer extension into VSCodium
# ============
log "Installing Rust Analyzer extension into VSCodium..."
debug_log "install_offline.sh:extensions:rust_start" "Starting Rust Analyzer extension installation" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "EXT-A" "run1"

RUST_VSIX="$(ls -1 "$BUNDLE_DIR"/extensions/rust-lang.rust-analyzer-*.vsix 2>/dev/null | head -n1)"
if [[ -n "$RUST_VSIX" ]] && [[ -f "$RUST_VSIX" ]]; then
  if codium --install-extension "$RUST_VSIX" --force 2>&1; then
    log "✓ Rust Analyzer extension installed"
    mark_success "extensions"
    debug_log "install_offline.sh:extensions:rust_success" "Rust Analyzer extension installed" "{\"status\":\"success\"}" "EXT-A" "run1"
  else
    log "WARNING: Rust Analyzer extension installation may have failed"
    mark_failed "extensions"
    debug_log "install_offline.sh:extensions:rust_failed" "Rust Analyzer extension installation failed" "{\"status\":\"failed\"}" "EXT-B" "run1"
  fi
else
  log "WARNING: Rust Analyzer extension VSIX not found"
  mark_skipped "extensions"
  debug_log "install_offline.sh:extensions:rust_missing" "Rust Analyzer extension VSIX not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
fi

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
  debug_log "install_offline.sh:rust:start" "Starting Rust toolchain installation" "{\"rustup_init\":\"$RUSTUP_INIT\"}" "RUST-A" "run1"
  chmod +x "$RUSTUP_INIT"
  
  # Check if rust is already installed
  if command -v rustc >/dev/null 2>&1; then
    log "Rust appears to be already installed. Skipping rustup-init."
    mark_success "rust"
    debug_log "install_offline.sh:rust:already_installed" "Rust already installed" "{\"status\":\"success\"}" "RUST-A" "run1"
  else
    log "Running rustup-init (this will install Rust to ~/.cargo/bin)..."
    log "NOTE: rustup-init requires internet access to download the Rust toolchain."
    log "      If you are on an airgapped system, rustup-init will fail."
    log "      You can install Rust later when you have internet access, or"
    log "      use the system package manager: sudo apt-get install -y rustc cargo"
    
    # Try to run rustup-init, but don't fail if it can't download (offline)
    # rustup-init will fail gracefully if it can't reach the internet
    if "$RUSTUP_INIT" -y --default-toolchain stable --profile default 2>&1 | tee /tmp/rustup-init.log; then
      # Add cargo to PATH for current session
      if [[ -f "$HOME/.cargo/env" ]]; then
        source "$HOME/.cargo/env"
        mark_success "rust"
        log "✓ Rust toolchain installed. Cargo is available at ~/.cargo/bin"
        debug_log "install_offline.sh:rust:success" "Rust toolchain installed successfully" "{\"status\":\"success\"}" "RUST-A" "run1"
      else
        mark_failed "rust"
        log "WARNING: rustup-init completed but ~/.cargo/env not found"
        debug_log "install_offline.sh:rust:env_missing" "rustup-init completed but cargo env not found" "{\"status\":\"failed\"}" "RUST-B" "run1"
      fi
    else
      RUSTUP_ERROR=$(cat /tmp/rustup-init.log 2>/dev/null | grep -i "network\|download\|fetch\|connection" | head -1 || echo "")
      if [[ -n "$RUSTUP_ERROR" ]]; then
        mark_skipped "rust"
        log "WARNING: rustup-init failed (likely due to no internet access)."
        log "         This is expected on airgapped systems."
        log "         Install Rust later with: sudo apt-get install -y rustc cargo"
        log "         Or run rustup-init when you have internet access."
        debug_log "install_offline.sh:rust:network_error" "rustup-init failed due to network" "{\"status\":\"skipped\",\"error\":\"network\"}" "RUST-C" "run1"
      else
        mark_failed "rust"
        log "WARNING: rustup-init failed. Check /tmp/rustup-init.log for details."
        debug_log "install_offline.sh:rust:failed" "rustup-init failed" "{\"status\":\"failed\"}" "RUST-B" "run1"
      fi
      rm -f /tmp/rustup-init.log
    fi
  fi
else
  mark_skipped "rust"
  log "WARNING: rustup-init not found in bundle. Rust will not be installed."
  log "You can install Rust with: sudo apt-get install -y rustc cargo"
  debug_log "install_offline.sh:rust:missing" "rustup-init not found in bundle" "{\"status\":\"skipped\"}" "RUST-C" "run1"
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
  debug_log "install_offline.sh:python:start" "Starting Python package installation" "{\"bundle_dir\":\"$BUNDLE_DIR/python\"}" "PYTHON-A" "run1"
  
  # Check if pip is available
  if command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1; then
    PIP_CMD="python3 -m pip"
    if command -v pip3 >/dev/null 2>&1; then
      PIP_CMD="pip3"
    fi
    
    # If there's a requirements.txt, install from it (preferred method)
    # All packages should be pre-built as wheels, so installation should be fast
    if [[ -f "$BUNDLE_DIR/python/requirements.txt" ]]; then
      log "Installing from requirements.txt (all packages are pre-built)..."
      debug_log "install_offline.sh:python:requirements_start" "Installing from requirements.txt" "{\"requirements_file\":\"$BUNDLE_DIR/python/requirements.txt\"}" "PYTHON-A" "run1"
      
      if $PIP_CMD install --no-index --find-links "$BUNDLE_DIR/python" -r "$BUNDLE_DIR/python/requirements.txt" 2>&1; then
        mark_success "python"
        log "✓ Python packages installed successfully"
        debug_log "install_offline.sh:python:success" "Python packages installed successfully" "{\"status\":\"success\"}" "PYTHON-A" "run1"
      else
        PIP_EXIT=$?
        mark_failed "python"
        log "WARNING: Some packages from requirements.txt failed to install (exit code: $PIP_EXIT)."
        log "This should not happen as all packages were pre-built. Check for missing dependencies."
        debug_log "install_offline.sh:python:failed" "Python package installation failed" "{\"status\":\"failed\",\"exit_code\":$PIP_EXIT}" "PYTHON-B" "run1"
      fi
    else
      # Fallback: try to install all wheel files (pre-built packages)
      log "No requirements.txt found. Installing all pre-built wheels..."
      log "Note: Only wheels will be installed (source distributions should have been built during bundle creation)."
      debug_log "install_offline.sh:python:wheels_start" "Installing all wheels" "{\"bundle_dir\":\"$BUNDLE_DIR/python\"}" "PYTHON-A" "run1"
      
      if $PIP_CMD install --no-index --find-links "$BUNDLE_DIR/python" \
        $(find "$BUNDLE_DIR/python" -maxdepth 1 -name "*.whl" -type f -exec basename {} \;) \
        2>&1; then
        mark_success "python"
        log "✓ Python packages installed successfully"
        debug_log "install_offline.sh:python:success" "Python packages installed successfully" "{\"status\":\"success\"}" "PYTHON-A" "run1"
      else
        PIP_EXIT=$?
        mark_failed "python"
        log "WARNING: Package installation had some failures (exit code: $PIP_EXIT)."
        debug_log "install_offline.sh:python:failed" "Python package installation failed" "{\"status\":\"failed\",\"exit_code\":$PIP_EXIT}" "PYTHON-B" "run1"
      fi
    fi
  else
    mark_skipped "python"
    log "WARNING: pip3 not found. Python packages cannot be installed."
    log "Install python3-pip from the APT repo first, then re-run this section."
    debug_log "install_offline.sh:python:no_pip" "pip3 not found" "{\"status\":\"skipped\"}" "PYTHON-C" "run1"
  fi
else
  mark_skipped "python"
  log "No Python packages found in bundle. Skipping Python package installation."
  debug_log "install_offline.sh:python:no_packages" "No Python packages in bundle" "{\"status\":\"skipped\"}" "PYTHON-C" "run1"
fi

# ============
# Final Report
# ============
log ""
log "=========================================="
log "INSTALLATION COMPLETE"
log "=========================================="
log ""
log "Detailed Installation Report:"
log ""

# Report each component
log "Component Status:"
log "  APT Repository:     $(get_status apt_repo || echo 'unknown')"
log "  VSCodium:             $(get_status vscodium || echo 'unknown')"
log "  Ollama Binary:        $(get_status ollama || echo 'unknown')"
log "  Ollama Models:        $(get_status models || echo 'unknown')"
log "  VSCode Extensions:    $(get_status extensions || echo 'unknown')"
log "  Rust Toolchain:       $(get_status rust || echo 'unknown')"
log "  Python Packages:      $(get_status python || echo 'unknown')"
log ""

# Count successes/failures
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for component in apt_repo vscodium ollama models extensions rust python; do
  status=$(get_status "$component" 2>/dev/null || echo "")
  case "$status" in
    success) ((SUCCESS_COUNT++)) ;;
    failed) ((FAILED_COUNT++)) ;;
    skipped) ((SKIPPED_COUNT++)) ;;
  esac
done

log "Summary:"
log "  ✓ Successful: $SUCCESS_COUNT"
log "  ✗ Failed:     $FAILED_COUNT"
log "  ⊘ Skipped:    $SKIPPED_COUNT"
log ""

if [[ $FAILED_COUNT -gt 0 ]]; then
  log "WARNING: Some components failed to install. Check the logs above for details."
  log "Log files:"
  log "  - Console log: $CONSOLE_LOG"
  log "  - Debug log:   $DEBUG_LOG"
  log ""
fi

log "Next Steps:"
log " 1. Start Ollama: ollama serve"
log " 2. Verify GPU (if available):"
log "    - Check NVIDIA: nvidia-smi"
log "    - Check CUDA: nvcc --version"
log "    - Check Ollama logs: tail -f ~/.ollama/logs/server.log"
log "    - If GPU not detected, set: export OLLAMA_NUM_GPU=1"
log " 3. Verify Rust: rustc --version (if installed)"
log " 4. Verify Python: python3 --version && pip3 --version"
log " 5. Open VSCodium and verify extensions are working"
log ""
log "For troubleshooting, check:"
log "  - Console log: $CONSOLE_LOG"
log "  - Debug log:   $DEBUG_LOG"
log ""

debug_log "install_offline.sh:complete" "Installation script completed" "{\"success_count\":$SUCCESS_COUNT,\"failed_count\":$FAILED_COUNT,\"skipped_count\":$SKIPPED_COUNT,\"console_log\":\"$CONSOLE_LOG\",\"debug_log\":\"$DEBUG_LOG\"}" "INSTALL-A" "run1"
