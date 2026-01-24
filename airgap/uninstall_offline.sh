#!/usr/bin/env bash
# Use set -eo pipefail but allow controlled failures
set -eo pipefail

# ============
# OS Detection - This script is for Debian/Linux only
# ============
OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  echo "ERROR: This script is designed for Debian/Linux systems only." >&2
  echo "Detected OS: $OS" >&2
  exit 1
fi

INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/bin}"
BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"

# ============
# Logging Setup
# ============
# Debug log path - structured JSON logging for debugging
DEBUG_LOG="${DEBUG_LOG:-$BUNDLE_DIR/logs/uninstall_offline_debug.log}"
# Console log path - captures all console output
CONSOLE_LOG="${CONSOLE_LOG:-$BUNDLE_DIR/logs/uninstall_offline_console.log}"
# Ensure log directories exist
mkdir -p "$(dirname "$DEBUG_LOG")" "$(dirname "$CONSOLE_LOG")" 2>/dev/null || true

# Structured debug logging (JSON format, similar to install_offline.sh)
debug_log() {
  local location="$1"
  local message="$2"
  local data="${3:-{}}"
  local hypothesis="${4:-UNINSTALL}"
  local run_id="${5:-run1}"
  local timestamp
  timestamp=$(date +%s)000
  
  local log_entry
  log_entry=$(cat <<EOF
{"id":"log_${timestamp}_${RANDOM}","timestamp":${timestamp},"location":"${location}","message":"${message}","data":${data},"sessionId":"uninstall-session","runId":"${run_id}","hypothesisId":"${hypothesis}"}
EOF
)
  echo "$log_entry" >> "${DEBUG_LOG}" 2>/dev/null || true
}

# Simple log function with timestamp
log() { 
  echo "[$(date -Is)] $*"
}

# Status tracking (similar to install_offline.sh)
mark_success() {
  eval "STATUS_$1=\"success\""
  debug_log "uninstall_offline.sh:$1:success" "Component removed successfully" "{\"component\":\"$1\",\"status\":\"success\"}" "UNINSTALL-A" "run1"
}

mark_failed() {
  eval "STATUS_$1=\"failed\""
  debug_log "uninstall_offline.sh:$1:failed" "Component removal failed" "{\"component\":\"$1\",\"status\":\"failed\"}" "UNINSTALL-B" "run1"
}

mark_skipped() {
  eval "STATUS_$1=\"skipped\""
  debug_log "uninstall_offline.sh:$1:skipped" "Component removal skipped" "{\"component\":\"$1\",\"status\":\"skipped\"}" "UNINSTALL-C" "run1"
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
STATUS_apt_source=""
STATUS_shell_config=""

# Set up console logging - redirect stdout and stderr to both console and log file
if [[ -n "$CONSOLE_LOG" ]]; then
  touch "$CONSOLE_LOG" 2>/dev/null || true
  exec > >(tee -a "$CONSOLE_LOG") 2>&1
  echo "=========================================="
  echo "Uninstallation started: $(date -Is)"
  echo "Console output is being logged to: $CONSOLE_LOG"
  echo "Debug logs (JSON) are being logged to: $DEBUG_LOG"
  echo "=========================================="
  echo ""
fi

# Log script start
debug_log "uninstall_offline.sh:start" "Uninstallation script started" "{\"install_prefix\":\"$INSTALL_PREFIX\",\"bundle_dir\":\"$BUNDLE_DIR\",\"os\":\"$OS\",\"user\":\"$USER\",\"pid\":$$}" "INIT-A" "run1"

# ============
# Confirmation Prompt
# ============
log ""
log "=========================================="
log "AIRGAP UNINSTALL SCRIPT"
log "=========================================="
log ""
log "This script will remove all components installed by install_offline.sh:"
log "  - APT packages (development tools, libraries)"
log "  - VSCodium (code editor)"
log "  - Ollama binary and models"
log "  - VSCode extensions (Continue, Python, Rust Analyzer)"
log "  - Rust toolchain (if installed via rustup)"
log "  - Python packages (from bundle requirements.txt)"
log "  - APT source list entry"
log "  - Ollama GPU configuration from shell profiles"
log ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
  log "Uninstall cancelled."
  exit 0
fi

log ""
log "Starting uninstallation..."

# ============
# 1) Remove APT source list entry
# ============
log "Removing APT source list entry..."
debug_log "uninstall_offline.sh:apt_source:start" "Starting APT source list removal" "{\"source_file\":\"/etc/apt/sources.list.d/airgap-local.list\"}" "APT-SOURCE-A" "run1"

if [[ -f /etc/apt/sources.list.d/airgap-local.list ]]; then
  if sudo rm -f /etc/apt/sources.list.d/airgap-local.list; then
    mark_success "apt_source"
    log "✓ Removed /etc/apt/sources.list.d/airgap-local.list"
    debug_log "uninstall_offline.sh:apt_source:success" "APT source list removed successfully" "{\"status\":\"success\"}" "APT-SOURCE-A" "run1"
  else
    mark_failed "apt_source"
    log "WARNING: Failed to remove APT source list entry"
    debug_log "uninstall_offline.sh:apt_source:failed" "Failed to remove APT source list" "{\"status\":\"failed\"}" "APT-SOURCE-B" "run1"
  fi
else
  mark_skipped "apt_source"
  log "  APT source list entry not found (may have been removed already)"
  debug_log "uninstall_offline.sh:apt_source:skipped" "APT source list not found" "{\"status\":\"skipped\"}" "APT-SOURCE-C" "run1"
fi

# ============
# 2) Remove APT packages
# ============
log ""
log "Removing APT packages..."
log "Note: This will remove packages that were installed by install_offline.sh"
log "      Some packages may be dependencies of other system packages."

debug_log "uninstall_offline.sh:apt_repo:start" "Starting APT package removal" "{\"package_count\":${#APT_PACKAGES[@]}}" "APT-A" "run1"

# List of packages installed by install_offline.sh
# Note: We only remove packages that were specifically installed by the installer
# System packages like git, python3, etc. are kept as they may be system dependencies
APT_PACKAGES=(
  lua5.3
  git-lfs
  build-essential
  cmake
  pkg-config
  python3-dev
  python3-pip
  python3-venv
  python3-setuptools
  libblas-dev
  liblapack-dev
  libopenblas-dev
  libatlas-base-dev
  libgfortran5
  gfortran
  libssl-dev
  libcrypto++-dev
  libpng-dev
  libjpeg-dev
  libtiff-dev
  libfreetype6-dev
  liblcms2-dev
  libwebp-dev
  libxml2-dev
  libxslt1-dev
  zlib1g-dev
  libbz2-dev
  liblzma-dev
  libsqlite3-dev
  libffi-dev
  libreadline-dev
  libncurses5-dev
  libncursesw5-dev
  libsndfile1-dev
  libavcodec-dev
  libavformat-dev
  libhdf5-dev
  libnetcdf-dev
  htop
  tree
  manpages-dev
  zstd
)

# Remove packages (use autoremove to clean up dependencies)
log "Removing installed packages..."
log "Note: System packages (git, python3, gcc, g++, make, vim, nano, wget, unzip, man-db, rsync, less, file) are kept"
log "      as they may be system dependencies. Only development packages are removed."

REMOVED_COUNT=0
FAILED_COUNT=0

for pkg in "${APT_PACKAGES[@]}"; do
  if dpkg -l | grep -q "^ii.*$pkg"; then
    if sudo apt-get remove -y "$pkg" 2>&1 | grep -q "removed\|not installed"; then
      ((REMOVED_COUNT++))
    else
      ((FAILED_COUNT++))
      log "  WARNING: Failed to remove $pkg (may be a dependency)"
    fi
  fi
done

if [[ $REMOVED_COUNT -gt 0 ]]; then
  log "✓ Removed $REMOVED_COUNT package(s)"
  mark_success "apt_repo"
  debug_log "uninstall_offline.sh:apt_repo:success" "APT packages removed successfully" "{\"removed_count\":$REMOVED_COUNT,\"failed_count\":$FAILED_COUNT}" "APT-A" "run1"
else
  if [[ $FAILED_COUNT -gt 0 ]]; then
    mark_failed "apt_repo"
    debug_log "uninstall_offline.sh:apt_repo:failed" "APT package removal had issues" "{\"removed_count\":$REMOVED_COUNT,\"failed_count\":$FAILED_COUNT}" "APT-B" "run1"
  else
    mark_skipped "apt_repo"
    debug_log "uninstall_offline.sh:apt_repo:skipped" "No packages to remove" "{\"status\":\"skipped\"}" "APT-C" "run1"
  fi
fi
if [[ $FAILED_COUNT -gt 0 ]]; then
  log "  $FAILED_COUNT package(s) could not be removed (may be dependencies)"
fi

# Clean up any orphaned dependencies
log "Cleaning up orphaned dependencies..."
sudo apt-get autoremove -y 2>&1 | grep -v "^$" || true
debug_log "uninstall_offline.sh:apt_repo:autoremove" "APT autoremove completed" "{\"status\":\"completed\"}" "APT-A" "run1"

# ============
# 3) Remove VSCodium
# ============
log ""
log "Removing VSCodium..."
debug_log "uninstall_offline.sh:vscodium:start" "Starting VSCodium removal" "{}" "VSCODE-A" "run1"

if command -v codium >/dev/null 2>&1 || dpkg -l | grep -q "^ii.*vscodium"; then
  if sudo apt-get remove -y vscodium 2>&1; then
    mark_success "vscodium"
    log "✓ VSCodium removed"
    debug_log "uninstall_offline.sh:vscodium:success" "VSCodium removed successfully" "{\"status\":\"success\"}" "VSCODE-A" "run1"
  else
    # Try dpkg if apt-get fails
    if sudo dpkg -r vscodium 2>&1; then
      mark_success "vscodium"
      log "✓ VSCodium removed (via dpkg)"
      debug_log "uninstall_offline.sh:vscodium:success" "VSCodium removed via dpkg" "{\"status\":\"success\",\"method\":\"dpkg\"}" "VSCODE-A" "run1"
    else
      mark_failed "vscodium"
      log "WARNING: Failed to remove VSCodium (may not be installed)"
      debug_log "uninstall_offline.sh:vscodium:failed" "Failed to remove VSCodium" "{\"status\":\"failed\"}" "VSCODE-B" "run1"
    fi
  fi
else
  mark_skipped "vscodium"
  log "  VSCodium not found (may have been removed already)"
  debug_log "uninstall_offline.sh:vscodium:skipped" "VSCodium not found" "{\"status\":\"skipped\"}" "VSCODE-C" "run1"
fi

# ============
# 4) Remove Ollama binary
# ============
log ""
log "Removing Ollama binary..."
debug_log "uninstall_offline.sh:ollama:start" "Starting Ollama binary removal" "{\"install_path\":\"$INSTALL_PREFIX/ollama\"}" "OLLAMA-A" "run1"

if [[ -f "$INSTALL_PREFIX/ollama" ]]; then
  if sudo rm -f "$INSTALL_PREFIX/ollama"; then
    mark_success "ollama"
    log "✓ Removed Ollama binary from $INSTALL_PREFIX/ollama"
    debug_log "uninstall_offline.sh:ollama:success" "Ollama binary removed successfully" "{\"status\":\"success\",\"path\":\"$INSTALL_PREFIX/ollama\"}" "OLLAMA-A" "run1"
  else
    mark_failed "ollama"
    log "WARNING: Failed to remove Ollama binary"
    debug_log "uninstall_offline.sh:ollama:failed" "Failed to remove Ollama binary" "{\"status\":\"failed\"}" "OLLAMA-B" "run1"
  fi
else
  mark_skipped "ollama"
  log "  Ollama binary not found at $INSTALL_PREFIX/ollama"
  debug_log "uninstall_offline.sh:ollama:skipped" "Ollama binary not found" "{\"status\":\"skipped\"}" "OLLAMA-C" "run1"
fi

# ============
# 5) Remove Ollama models (with confirmation)
# ============
log ""
debug_log "uninstall_offline.sh:models:start" "Starting Ollama models removal check" "{\"models_dir\":\"$HOME/.ollama\"}" "MODEL-A" "run1"

if [[ -d "$HOME/.ollama" ]] && [[ -n "$(ls -A "$HOME/.ollama" 2>/dev/null)" ]]; then
  OLLAMA_SIZE=$(du -sh "$HOME/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
  log "Ollama models directory found: $HOME/.ollama ($OLLAMA_SIZE)"
  debug_log "uninstall_offline.sh:models:found" "Ollama models directory found" "{\"size\":\"$OLLAMA_SIZE\",\"path\":\"$HOME/.ollama\"}" "MODEL-A" "run1"
  read -p "Remove Ollama models directory? This will delete all downloaded models. (yes/no): " REMOVE_MODELS
  if [[ "$REMOVE_MODELS" == "yes" ]]; then
    if rm -rf "$HOME/.ollama"; then
      mark_success "models"
      log "✓ Removed Ollama models directory"
      debug_log "uninstall_offline.sh:models:success" "Ollama models removed successfully" "{\"status\":\"success\",\"size\":\"$OLLAMA_SIZE\"}" "MODEL-A" "run1"
    else
      mark_failed "models"
      log "WARNING: Failed to remove Ollama models directory"
      debug_log "uninstall_offline.sh:models:failed" "Failed to remove Ollama models" "{\"status\":\"failed\"}" "MODEL-B" "run1"
    fi
  else
    mark_skipped "models"
    log "  Keeping Ollama models directory"
    debug_log "uninstall_offline.sh:models:skipped" "Ollama models kept by user" "{\"status\":\"skipped\",\"user_choice\":\"keep\"}" "MODEL-C" "run1"
  fi
else
  mark_skipped "models"
  log "  Ollama models directory not found or empty"
  debug_log "uninstall_offline.sh:models:skipped" "Ollama models directory not found" "{\"status\":\"skipped\"}" "MODEL-C" "run1"
fi

# ============
# 6) Remove VSCode extensions
# ============
log ""
log "Removing VSCode extensions..."
debug_log "uninstall_offline.sh:extensions:start" "Starting VSCode extension removal" "{}" "EXT-A" "run1"

if command -v codium >/dev/null 2>&1; then
  EXTENSIONS_REMOVED=0
  EXTENSIONS_FAILED=0
  
  # Remove Continue extension
  if codium --uninstall-extension Continue.continue 2>&1 | grep -q "uninstalled\|not installed"; then
    ((EXTENSIONS_REMOVED++))
    log "✓ Removed Continue extension"
    debug_log "uninstall_offline.sh:extensions:continue_success" "Continue extension removed" "{\"status\":\"success\"}" "EXT-A" "run1"
  else
    ((EXTENSIONS_FAILED++))
    log "  Continue extension not found or already removed"
    debug_log "uninstall_offline.sh:extensions:continue_skipped" "Continue extension not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
  fi
  
  # Remove Python extension
  if codium --uninstall-extension ms-python.python 2>&1 | grep -q "uninstalled\|not installed"; then
    ((EXTENSIONS_REMOVED++))
    log "✓ Removed Python extension"
    debug_log "uninstall_offline.sh:extensions:python_success" "Python extension removed" "{\"status\":\"success\"}" "EXT-A" "run1"
  else
    ((EXTENSIONS_FAILED++))
    log "  Python extension not found or already removed"
    debug_log "uninstall_offline.sh:extensions:python_skipped" "Python extension not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
  fi
  
  # Remove Rust Analyzer extension
  if codium --uninstall-extension rust-lang.rust-analyzer 2>&1 | grep -q "uninstalled\|not installed"; then
    ((EXTENSIONS_REMOVED++))
    log "✓ Removed Rust Analyzer extension"
    debug_log "uninstall_offline.sh:extensions:rust_success" "Rust Analyzer extension removed" "{\"status\":\"success\"}" "EXT-A" "run1"
  else
    ((EXTENSIONS_FAILED++))
    log "  Rust Analyzer extension not found or already removed"
    debug_log "uninstall_offline.sh:extensions:rust_skipped" "Rust Analyzer extension not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
  fi
  
  if [[ $EXTENSIONS_REMOVED -gt 0 ]]; then
    mark_success "extensions"
    debug_log "uninstall_offline.sh:extensions:summary" "Extension removal summary" "{\"removed\":$EXTENSIONS_REMOVED,\"failed\":$EXTENSIONS_FAILED}" "EXT-A" "run1"
  elif [[ $EXTENSIONS_FAILED -eq 3 ]]; then
    mark_skipped "extensions"
    debug_log "uninstall_offline.sh:extensions:all_skipped" "All extensions not found" "{\"status\":\"skipped\"}" "EXT-C" "run1"
  fi
else
  mark_skipped "extensions"
  log "  VSCodium not found, skipping extension removal"
  log "  Extensions may be in: ~/.config/VSCodium/User/extensions/"
  log "  You can manually remove them if needed"
  debug_log "uninstall_offline.sh:extensions:skipped" "VSCodium not found, skipping extensions" "{\"status\":\"skipped\"}" "EXT-C" "run1"
fi

# ============
# 7) Remove Rust toolchain
# ============
log ""
log "Removing Rust toolchain..."
debug_log "uninstall_offline.sh:rust:start" "Starting Rust toolchain removal" "{}" "RUST-A" "run1"

if command -v rustup >/dev/null 2>&1; then
  log "Removing rustup and Rust toolchain..."
  if rustup self uninstall -y 2>&1; then
    mark_success "rust"
    log "✓ Rust toolchain removed"
    debug_log "uninstall_offline.sh:rust:success" "Rust toolchain removed successfully" "{\"status\":\"success\",\"method\":\"rustup\"}" "RUST-A" "run1"
  else
    mark_failed "rust"
    log "WARNING: rustup self uninstall failed"
    log "  You may need to manually remove: ~/.cargo and ~/.rustup"
    debug_log "uninstall_offline.sh:rust:failed" "rustup self uninstall failed" "{\"status\":\"failed\"}" "RUST-B" "run1"
  fi
elif [[ -d "$HOME/.cargo" ]] || [[ -d "$HOME/.rustup" ]]; then
  log "Rust directories found but rustup command not available"
  debug_log "uninstall_offline.sh:rust:dirs_found" "Rust directories found but rustup not available" "{\"cargo_exists\":$(test -d "$HOME/.cargo" && echo true || echo false),\"rustup_exists\":$(test -d "$HOME/.rustup" && echo true || echo false)}" "RUST-A" "run1"
  read -p "Remove Rust directories (~/.cargo and ~/.rustup)? (yes/no): " REMOVE_RUST
  if [[ "$REMOVE_RUST" == "yes" ]]; then
    if rm -rf "$HOME/.cargo" "$HOME/.rustup"; then
      mark_success "rust"
      log "✓ Removed Rust directories"
      debug_log "uninstall_offline.sh:rust:success" "Rust directories removed successfully" "{\"status\":\"success\",\"method\":\"manual\"}" "RUST-A" "run1"
    else
      mark_failed "rust"
      log "WARNING: Failed to remove Rust directories"
      debug_log "uninstall_offline.sh:rust:failed" "Failed to remove Rust directories" "{\"status\":\"failed\"}" "RUST-B" "run1"
    fi
  else
    mark_skipped "rust"
    log "  Keeping Rust directories"
    debug_log "uninstall_offline.sh:rust:skipped" "Rust directories kept by user" "{\"status\":\"skipped\",\"user_choice\":\"keep\"}" "RUST-C" "run1"
  fi
else
  mark_skipped "rust"
  log "  Rust toolchain not found"
  debug_log "uninstall_offline.sh:rust:skipped" "Rust toolchain not found" "{\"status\":\"skipped\"}" "RUST-C" "run1"
fi

# ============
# 8) Remove Python packages
# ============
log ""
log "Removing Python packages..."
debug_log "uninstall_offline.sh:python:start" "Starting Python package removal" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "PYTHON-A" "run1"

# Try to find requirements.txt from the bundle
REQUIREMENTS_FILE=""

if [[ -f "$BUNDLE_DIR/python/requirements.txt" ]]; then
  REQUIREMENTS_FILE="$BUNDLE_DIR/python/requirements.txt"
elif [[ -f "./airgap_bundle/python/requirements.txt" ]]; then
  REQUIREMENTS_FILE="./airgap_bundle/python/requirements.txt"
fi

if [[ -n "$REQUIREMENTS_FILE" ]] && [[ -f "$REQUIREMENTS_FILE" ]]; then
  log "Found requirements.txt: $REQUIREMENTS_FILE"
  debug_log "uninstall_offline.sh:python:requirements_found" "Requirements file found" "{\"requirements_file\":\"$REQUIREMENTS_FILE\"}" "PYTHON-A" "run1"
  
  if command -v pip3 >/dev/null 2>&1 || python3 -m pip --version >/dev/null 2>&1; then
    PIP_CMD="python3 -m pip"
    if command -v pip3 >/dev/null 2>&1; then
      PIP_CMD="pip3"
    fi
    
    log "Uninstalling Python packages from requirements.txt..."
    # Read package names from requirements.txt and uninstall them
    # Handle both "package" and "package==version" formats
    PACKAGE_LIST=$(grep -v "^#" "$REQUIREMENTS_FILE" | grep -v "^$" | sed 's/[<>=!].*$//')
    PACKAGE_COUNT=$(echo "$PACKAGE_LIST" | wc -l | tr -d ' ')
    debug_log "uninstall_offline.sh:python:uninstall_start" "Starting package uninstall" "{\"package_count\":$PACKAGE_COUNT}" "PYTHON-A" "run1"
    
    # Cache dpkg output once (much faster than running dpkg -l for each package)
    log "  Checking for system packages..."
    DPKG_PYTHON_PACKAGES=$(dpkg -l 2>/dev/null | grep -E "^ii.*python[3]?-" | awk '{print $2}' | sed 's/^python[3]-//')
    debug_log "uninstall_offline.sh:python:dpkg_cache" "Cached system package list" "{\"system_package_count\":$(echo "$DPKG_PYTHON_PACKAGES" | wc -l | tr -d ' ')}" "PYTHON-A" "run1"
    
    # Uninstall packages one at a time to avoid cascading failures
    # Use sudo since packages were installed with --break-system-packages
    REMOVED_COUNT=0
    FAILED_COUNT=0
    SKIPPED_COUNT=0
    
    while IFS= read -r package; do
      [[ -z "$package" ]] && continue
      
      # #region agent log
      echo "{\"id\":\"log_$(date +%s)_${RANDOM}\",\"timestamp\":$(date +%s)000,\"location\":\"uninstall_offline.sh:python:package_check\",\"message\":\"Checking package\",\"data\":{\"package\":\"$package\"},\"sessionId\":\"uninstall-session\",\"runId\":\"run1\",\"hypothesisId\":\"PYTHON-A\"}" >> "${DEBUG_LOG}" 2>/dev/null || true
      # #endregion
      
      # First check if it's a system package (installed via apt) - skip these
      # Use cached dpkg output for faster checking
      if echo "$DPKG_PYTHON_PACKAGES" | grep -qE "^${package}$"; then
        log "  ⊘ Skipping $package (system package, managed by apt)"
        debug_log "uninstall_offline.sh:python:package_system" "Package is system package" "{\"package\":\"$package\",\"reason\":\"apt_managed\"}" "PYTHON-C" "run1"
        ((SKIPPED_COUNT++))
        continue
      fi
      
      # Check if package is actually installed by pip (pip show doesn't support --break-system-packages)
      if ! $PIP_CMD show "$package" >/dev/null 2>&1; then
        log "  Skipping $package (not installed by pip)"
        debug_log "uninstall_offline.sh:python:package_skipped" "Package not installed by pip" "{\"package\":\"$package\",\"reason\":\"not_found\"}" "PYTHON-C" "run1"
        ((SKIPPED_COUNT++))
        continue
      fi
      
      # Try to uninstall with sudo (required for system packages installed with --break-system-packages)
      log "  Uninstalling $package..."
      # #region agent log
      echo "{\"id\":\"log_$(date +%s)_${RANDOM}\",\"timestamp\":$(date +%s)000,\"location\":\"uninstall_offline.sh:python:package_uninstall_start\",\"message\":\"Starting uninstall\",\"data\":{\"package\":\"$package\"},\"sessionId\":\"uninstall-session\",\"runId\":\"run1\",\"hypothesisId\":\"PYTHON-A\"}" >> "${DEBUG_LOG}" 2>/dev/null || true
      # #endregion
      
      UNINSTALL_OUTPUT=$(sudo $PIP_CMD uninstall -y --break-system-packages "$package" 2>&1)
      UNINSTALL_EXIT=$?
      
      # #region agent log
      echo "{\"id\":\"log_$(date +%s)_${RANDOM}\",\"timestamp\":$(date +%s)000,\"location\":\"uninstall_offline.sh:python:package_uninstall_result\",\"message\":\"Uninstall result\",\"data\":{\"package\":\"$package\",\"exit_code\":$UNINSTALL_EXIT,\"output_length\":${#UNINSTALL_OUTPUT}},\"sessionId\":\"uninstall-session\",\"runId\":\"run1\",\"hypothesisId\":\"PYTHON-A\"}" >> "${DEBUG_LOG}" 2>/dev/null || true
      # #endregion
      
      if [[ $UNINSTALL_EXIT -eq 0 ]]; then
        log "    ✓ Removed $package"
        debug_log "uninstall_offline.sh:python:package_removed" "Package removed successfully" "{\"package\":\"$package\",\"status\":\"success\"}" "PYTHON-A" "run1"
        ((REMOVED_COUNT++))
      else
        # Check error output for permission errors or other issues
        if echo "$UNINSTALL_OUTPUT" | grep -qi "permission denied\|permissionerror"; then
          log "    ⊘ Skipped $package (permission error - may be system package or protected)"
          debug_log "uninstall_offline.sh:python:package_permission" "Package removal permission denied" "{\"package\":\"$package\",\"reason\":\"permission_denied\",\"error\":\"$(echo "$UNINSTALL_OUTPUT" | head -n 1 | sed 's/"/\\"/g')\"}" "PYTHON-C" "run1"
          ((SKIPPED_COUNT++))
        else
          log "    ✗ Failed to remove $package"
          log "      Error: $(echo "$UNINSTALL_OUTPUT" | head -n 1)"
          debug_log "uninstall_offline.sh:python:package_failed" "Package removal failed" "{\"package\":\"$package\",\"status\":\"failed\",\"exit_code\":$UNINSTALL_EXIT,\"error\":\"$(echo "$UNINSTALL_OUTPUT" | head -n 1 | sed 's/"/\\"/g')\"}" "PYTHON-B" "run1"
          ((FAILED_COUNT++))
        fi
      fi
    done <<< "$PACKAGE_LIST"
    
    # Report results
    if [[ $REMOVED_COUNT -gt 0 ]]; then
      log "✓ Removed $REMOVED_COUNT Python package(s)"
    fi
    if [[ $SKIPPED_COUNT -gt 0 ]]; then
      log "⊘ Skipped $SKIPPED_COUNT package(s) (system packages or not installed)"
    fi
    if [[ $FAILED_COUNT -gt 0 ]]; then
      log "✗ Failed to remove $FAILED_COUNT package(s)"
    fi
    
    if [[ $FAILED_COUNT -eq 0 ]] && [[ $REMOVED_COUNT -gt 0 ]]; then
      mark_success "python"
      debug_log "uninstall_offline.sh:python:success" "Python packages removed successfully" "{\"removed\":$REMOVED_COUNT,\"skipped\":$SKIPPED_COUNT,\"failed\":$FAILED_COUNT}" "PYTHON-A" "run1"
    elif [[ $REMOVED_COUNT -gt 0 ]] || [[ $SKIPPED_COUNT -gt 0 ]]; then
      mark_success "python"
      log "  Note: Some packages were skipped (system packages) or failed, but this is expected"
      debug_log "uninstall_offline.sh:python:partial_success" "Partial success with some skipped/failed" "{\"removed\":$REMOVED_COUNT,\"skipped\":$SKIPPED_COUNT,\"failed\":$FAILED_COUNT}" "PYTHON-A" "run1"
    else
      mark_failed "python"
      log "WARNING: All Python packages failed to uninstall"
      debug_log "uninstall_offline.sh:python:failed" "All packages failed to uninstall" "{\"removed\":$REMOVED_COUNT,\"skipped\":$SKIPPED_COUNT,\"failed\":$FAILED_COUNT}" "PYTHON-B" "run1"
    fi
  else
    mark_skipped "python"
    log "  pip3 not found, skipping Python package removal"
    debug_log "uninstall_offline.sh:python:no_pip" "pip3 not found" "{\"status\":\"skipped\"}" "PYTHON-C" "run1"
  fi
else
  mark_skipped "python"
  log "  requirements.txt not found, cannot determine which Python packages to remove"
  log "  You may need to manually uninstall Python packages if needed"
  debug_log "uninstall_offline.sh:python:no_requirements" "Requirements file not found" "{\"status\":\"skipped\",\"bundle_dir\":\"$BUNDLE_DIR\"}" "PYTHON-C" "run1"
fi

# ============
# 9) Remove Ollama GPU configuration from shell profiles
# ============
log ""
log "Removing Ollama GPU configuration from shell profiles..."
debug_log "uninstall_offline.sh:shell_config:start" "Starting shell profile cleanup" "{}" "SHELL-A" "run1"

PROFILES_MODIFIED=false

# Remove from .bashrc
if [[ -f "$HOME/.bashrc" ]] && grep -q "OLLAMA_NUM_GPU" "$HOME/.bashrc"; then
  # Remove the section added by installer
  if sed -i '/# Ollama GPU configuration (added by airgap installer)/,/^export OLLAMA_NUM_GPU=1$/d' "$HOME/.bashrc" 2>/dev/null || \
     sed -i '/OLLAMA_NUM_GPU/d' "$HOME/.bashrc" 2>/dev/null; then
    PROFILES_MODIFIED=true
    log "✓ Removed Ollama GPU configuration from ~/.bashrc"
    debug_log "uninstall_offline.sh:shell_config:bashrc_removed" "Removed from .bashrc" "{\"status\":\"success\"}" "SHELL-A" "run1"
  else
    log "WARNING: Failed to remove from ~/.bashrc"
    debug_log "uninstall_offline.sh:shell_config:bashrc_failed" "Failed to remove from .bashrc" "{\"status\":\"failed\"}" "SHELL-B" "run1"
  fi
fi

# Remove from .zshrc
if [[ -f "$HOME/.zshrc" ]] && grep -q "OLLAMA_NUM_GPU" "$HOME/.zshrc"; then
  # Remove the section added by installer
  if sed -i '/# Ollama GPU configuration (added by airgap installer)/,/^export OLLAMA_NUM_GPU=1$/d' "$HOME/.zshrc" 2>/dev/null || \
     sed -i '/OLLAMA_NUM_GPU/d' "$HOME/.zshrc" 2>/dev/null; then
    PROFILES_MODIFIED=true
    log "✓ Removed Ollama GPU configuration from ~/.zshrc"
    debug_log "uninstall_offline.sh:shell_config:zshrc_removed" "Removed from .zshrc" "{\"status\":\"success\"}" "SHELL-A" "run1"
  else
    log "WARNING: Failed to remove from ~/.zshrc"
    debug_log "uninstall_offline.sh:shell_config:zshrc_failed" "Failed to remove from .zshrc" "{\"status\":\"failed\"}" "SHELL-B" "run1"
  fi
fi

if [[ "$PROFILES_MODIFIED" == "true" ]]; then
  mark_success "shell_config"
  debug_log "uninstall_offline.sh:shell_config:success" "Shell profile cleanup completed" "{\"status\":\"success\"}" "SHELL-A" "run1"
else
  mark_skipped "shell_config"
  log "  No Ollama GPU configuration found in shell profiles"
  debug_log "uninstall_offline.sh:shell_config:skipped" "No GPU configuration found" "{\"status\":\"skipped\"}" "SHELL-C" "run1"
fi

# ============
# 10) Clean up APT cache
# ============
log ""
log "Cleaning up APT cache..."
debug_log "uninstall_offline.sh:apt_cache:start" "Starting APT cache cleanup" "{}" "APT-CACHE-A" "run1"

sudo apt-get clean 2>&1 | grep -v "^$" || true
log "✓ APT cache cleaned"
debug_log "uninstall_offline.sh:apt_cache:success" "APT cache cleaned" "{\"status\":\"success\"}" "APT-CACHE-A" "run1"

# ============
# Final Summary
# ============
log ""
log "=========================================="
log "UNINSTALLATION COMPLETE"
log "=========================================="
log ""
log "Detailed Uninstallation Report:"
log ""

# Report each component
log "Component Status:"
log "  APT Source List:      $(get_status apt_source || echo 'unknown')"
log "  APT Packages:         $(get_status apt_repo || echo 'unknown')"
log "  VSCodium:             $(get_status vscodium || echo 'unknown')"
log "  Ollama Binary:         $(get_status ollama || echo 'unknown')"
log "  Ollama Models:         $(get_status models || echo 'unknown')"
log "  VSCode Extensions:     $(get_status extensions || echo 'unknown')"
log "  Rust Toolchain:        $(get_status rust || echo 'unknown')"
log "  Python Packages:       $(get_status python || echo 'unknown')"
log "  Shell Configuration:  $(get_status shell_config || echo 'unknown')"
log ""

# Count successes/failures
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for component in apt_source apt_repo vscodium ollama models extensions rust python shell_config; do
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
  log "WARNING: Some components failed to remove. Check the logs above for details."
  log "Log files:"
  log "  - Console log: $CONSOLE_LOG"
  log "  - Debug log:   $DEBUG_LOG"
  log ""
fi

log "Note: Some components may require a shell restart to take effect."
log "      Ollama models were kept (unless you chose to remove them)."
log ""
log "To completely clean up, you may also want to:"
log "  - Remove ~/.ollama (if you kept it)"
log "  - Remove ~/.config/VSCodium/ (VSCodium user data)"
log "  - Remove ~/.cargo and ~/.rustup (if Rust removal failed)"
log ""

debug_log "uninstall_offline.sh:complete" "Uninstallation script completed" "{\"success_count\":$SUCCESS_COUNT,\"failed_count\":$FAILED_COUNT,\"skipped_count\":$SKIPPED_COUNT,\"console_log\":\"$CONSOLE_LOG\",\"debug_log\":\"$DEBUG_LOG\"}" "UNINSTALL-A" "run1"
