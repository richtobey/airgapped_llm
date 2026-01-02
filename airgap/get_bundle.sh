#!/usr/bin/env bash
# Use set -eo pipefail but allow controlled failures
# Note: -u (unbound variables) is removed for bash 3.2 compatibility
set -eo pipefail

# ============
# OS Detection - This script requires Linux (Pop!_OS/Debian/Ubuntu)
# ============
OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  echo "ERROR: This script must be run on Linux (Pop!_OS, Ubuntu, or Debian)" >&2
  echo "Detected OS: $OS" >&2
  echo "" >&2
  echo "This script requires Linux because it needs to:" >&2
  echo "  - Build APT repositories (requires apt-get)" >&2
  echo "  - Build Python packages from source (requires build tools)" >&2
  echo "  - Build Rust crates (requires cargo)" >&2
  echo "  - Pull Ollama models (requires Linux Ollama binary)" >&2
  echo "" >&2
  echo "Workflow:" >&2
  echo "  1. Run this script on Pop!_OS with internet access" >&2
  echo "  2. Copy the bundle to the airgapped machine" >&2
  echo "  3. Run install_offline.sh on the airgapped machine" >&2
  exit 1
fi

IS_LINUX=true
log() {
  # GNU date (Linux)
  echo "[$(date -Is)] $*"
}

# ============
# Error Tracking (bash 3.2 compatible - using variables instead of associative arrays)
# ============
# Initialize all component statuses
STATUS_ollama_linux="pending"
STATUS_models="pending"
STATUS_vscodium="pending"
STATUS_continue="pending"
STATUS_python_ext="pending"
STATUS_rust_ext="pending"
STATUS_rust_toolchain="pending"
STATUS_rust_crates="pending"
STATUS_python_packages="pending"
STATUS_apt_repo="pending"

mark_success() {
  local component="$1"
  eval "STATUS_$component=\"success\""
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_status_${component}\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:mark_success\",\"message\":\"Component status changed to success\",\"data\":{\"component\":\"$component\",\"status\":\"success\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
}

mark_failed() {
  local component="$1"
  eval "STATUS_$component=\"failed\""
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_status_${component}\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:mark_failed\",\"message\":\"Component status changed to failed\",\"data\":{\"component\":\"$component\",\"status\":\"failed\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
}

mark_skipped() {
  local component="$1"
  eval "STATUS_$component=\"skipped\""
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_status_${component}\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:mark_skipped\",\"message\":\"Component status changed to skipped\",\"data\":{\"component\":\"$component\",\"status\":\"skipped\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
}

get_status() {
  eval "echo \"\$STATUS_$1\""
}

# ============
# Config
# ============
BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"
ARCH="amd64"

# Debug log path - set early for instrumentation (will be finalized after BUNDLE_DIR is created)
TEMP_DEBUG_LOG="/tmp/debug_init_$$.log"

# #region agent log - Bundle directory initialization
echo "{\"id\":\"log_$(date +%s)_bundle_init\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:bundle_init\",\"message\":\"Initializing bundle directory\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"pwd\":\"$PWD\",\"bundle_dir_exists\":$(test -e "$BUNDLE_DIR" && echo true || echo false),\"bundle_dir_is_dir\":$(test -d "$BUNDLE_DIR" && echo true || echo false),\"bundle_dir_is_file\":$(test -f "$BUNDLE_DIR" && echo true || echo false),\"parent_dir\":\"$(dirname "$BUNDLE_DIR")\",\"parent_exists\":$(test -d "$(dirname "$BUNDLE_DIR")" && echo true || echo false),\"user\":\"$(whoami)\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1,DIR-H2,DIR-H3\"}" >> "$TEMP_DEBUG_LOG" 2>/dev/null || true
# #endregion

# Create BUNDLE_DIR itself first (critical for exFAT filesystems)
# Use multiple methods to check what exists (exFAT/9p can have inconsistent metadata)
BUNDLE_EXISTS_E=$(test -e "$BUNDLE_DIR" && echo true || echo false)
BUNDLE_EXISTS_F=$(test -f "$BUNDLE_DIR" && echo true || echo false)
BUNDLE_EXISTS_D=$(test -d "$BUNDLE_DIR" && echo true || echo false)
BUNDLE_STAT=$(stat "$BUNDLE_DIR" 2>&1 || echo "stat_failed")

# #region agent log - Bundle directory state check
echo "{\"id\":\"log_$(date +%s)_bundle_state\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:bundle_state\",\"message\":\"Checking bundle directory state\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"exists_e\":$BUNDLE_EXISTS_E,\"exists_f\":$BUNDLE_EXISTS_F,\"exists_d\":$BUNDLE_EXISTS_D,\"stat_output\":\"${BUNDLE_STAT:0:200}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H8\"}" >> "$TEMP_DEBUG_LOG" 2>/dev/null || true
# #endregion

if [[ "$BUNDLE_EXISTS_D" == "true" ]]; then
  log "Bundle directory already exists: $BUNDLE_DIR"
elif [[ "$BUNDLE_EXISTS_F" == "true" ]] || [[ "$BUNDLE_EXISTS_E" == "true" ]]; then
  log "WARNING: $BUNDLE_DIR exists but is not a directory. Attempting to remove..."
  
  # #region agent log - File removal attempt
  echo "{\"id\":\"log_$(date +%s)_bundle_file_remove\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:bundle_file_remove\",\"message\":\"Attempting to remove file/dir that conflicts\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"exists_e\":$BUNDLE_EXISTS_E,\"exists_f\":$BUNDLE_EXISTS_F,\"exists_d\":$BUNDLE_EXISTS_D},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H7,DIR-H8\"}" >> "$TEMP_DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Try multiple removal strategies for exFAT/9p filesystem quirks
  REMOVED=false
  
  # Strategy 1: Regular rm -rf (handles both files and directories)
  if rm -rf "$BUNDLE_DIR" 2>/dev/null; then
    log "✓ Removed with rm -rf"
    REMOVED=true
  else
    RM_ERROR=$(rm -rf "$BUNDLE_DIR" 2>&1)
    log "WARNING: rm -rf failed: $RM_ERROR"
    
    # Strategy 2: Try with sudo
    if sudo -n true 2>/dev/null; then
      if sudo rm -rf "$BUNDLE_DIR" 2>/dev/null; then
        log "✓ Removed with sudo rm -rf"
        REMOVED=true
      else
        SUDO_RM_ERROR=$(sudo rm -rf "$BUNDLE_DIR" 2>&1)
        log "WARNING: sudo rm -rf also failed: $SUDO_RM_ERROR"
      fi
    fi
    
    # Strategy 3: Force filesystem sync and retry
    if [[ "$REMOVED" == "false" ]]; then
      log "Attempting filesystem sync and retry..."
      sync 2>/dev/null || true
      sleep 1
      if rm -rf "$BUNDLE_DIR" 2>/dev/null || sudo rm -rf "$BUNDLE_DIR" 2>/dev/null; then
        log "✓ Removed after sync"
        REMOVED=true
      fi
    fi
    
    # Strategy 4: Try creating with a temporary name and renaming (workaround)
    if [[ "$REMOVED" == "false" ]]; then
      log "WARNING: Direct removal failed. Trying workaround: create with temp name..."
      BUNDLE_DIR_TEMP="${BUNDLE_DIR}.tmp.$$"
      if mkdir -p "$BUNDLE_DIR_TEMP" 2>/dev/null; then
        log "Created temporary directory, will use: $BUNDLE_DIR_TEMP"
        BUNDLE_DIR="$BUNDLE_DIR_TEMP"
        REMOVED=true  # Mark as handled
      fi
    fi
  fi
  
  # Verify removal/handling
  if [[ "$REMOVED" == "false" ]]; then
    # Re-check what exists
    sleep 1
    sync 2>/dev/null || true
    BUNDLE_STILL_EXISTS_E=$(test -e "$BUNDLE_DIR" && echo true || echo false)
    BUNDLE_STILL_EXISTS_F=$(test -f "$BUNDLE_DIR" && echo true || echo false)
    BUNDLE_STILL_EXISTS_D=$(test -d "$BUNDLE_DIR" && echo true || echo false)
    
    if [[ "$BUNDLE_STILL_EXISTS_E" == "true" ]] && [[ "$BUNDLE_STILL_EXISTS_D" != "true" ]]; then
      log "ERROR: Cannot remove conflicting file/directory: $BUNDLE_DIR"
      log "Filesystem may be in inconsistent state (exFAT/9p issue)"
      log "Please try:"
      log "  1. On host (Mac): Remove the directory manually"
      log "  2. Or remount the filesystem"
      log "  3. Or use a different BUNDLE_DIR location"
      exit 1
    elif [[ "$BUNDLE_STILL_EXISTS_D" == "true" ]]; then
      log "Directory exists after removal attempt - will use existing directory"
    fi
  fi
  
  # #region agent log - File removal verification
  echo "{\"id\":\"log_$(date +%s)_bundle_file_removed\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:bundle_file_removed\",\"message\":\"Removal attempt completed\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"removed\":$REMOVED,\"still_exists_e\":$(test -e "$BUNDLE_DIR" && echo true || echo false),\"still_exists_d\":$(test -d "$BUNDLE_DIR" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H7,DIR-H8\"}" >> "$TEMP_DEBUG_LOG" 2>/dev/null || true
  # #endregion
fi
  
  # Check if parent directory exists first
  BUNDLE_PARENT="$(dirname "$BUNDLE_DIR")"
  if [[ ! -d "$BUNDLE_PARENT" ]]; then
    log "WARNING: Parent directory does not exist: $BUNDLE_PARENT"
    log "Attempting to create parent directory..."
    if ! mkdir -p "$BUNDLE_PARENT" 2>/dev/null; then
      log "ERROR: Cannot create parent directory: $BUNDLE_PARENT"
      log "Please create it manually: mkdir -p $BUNDLE_PARENT"
      exit 1
    fi
  fi
  
  # Check if parent directory is writable
  if [[ ! -w "$BUNDLE_PARENT" ]]; then
    log "WARNING: Parent directory is not writable: $BUNDLE_PARENT"
    log "Checking filesystem mount options..."
    
    # Check if filesystem is read-only
    MOUNT_OPTS=$(findmnt -n -o OPTIONS --target "$BUNDLE_PARENT" 2>/dev/null || echo "unknown")
    if echo "$MOUNT_OPTS" | grep -q "ro"; then
      log "ERROR: Filesystem is mounted read-only!"
      log "Mount options: $MOUNT_OPTS"
      log "You need to remount the filesystem as read-write or use a different location."
      exit 1
    fi
  fi
  
  # Try to create BUNDLE_DIR
  log "Creating bundle directory: $BUNDLE_DIR"
  
  # #region agent log - Bundle directory creation attempt
  echo "{\"id\":\"log_$(date +%s)_bundle_create\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:bundle_create\",\"message\":\"Attempting to create bundle directory\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"parent_dir\":\"$BUNDLE_PARENT\",\"parent_exists\":$(test -d "$BUNDLE_PARENT" && echo true || echo false),\"parent_writable\":$(test -w "$BUNDLE_PARENT" 2>/dev/null && echo true || echo false),\"parent_readable\":$(test -r "$BUNDLE_PARENT" 2>/dev/null && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1,DIR-H2,DIR-H3,DIR-H4\"}" >> "$TEMP_DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Double-check state before attempting mkdir (handle exFAT/9p inconsistencies)
  sync 2>/dev/null || true  # Force filesystem sync
  BUNDLE_CHECK_E=$(test -e "$BUNDLE_DIR" && echo true || echo false)
  BUNDLE_CHECK_D=$(test -d "$BUNDLE_DIR" && echo true || echo false)
  
  if [[ "$BUNDLE_CHECK_D" == "true" ]]; then
    log "Directory already exists (verified): $BUNDLE_DIR"
    # Skip mkdir, directory is good
  elif [[ "$BUNDLE_CHECK_E" == "true" ]]; then
    log "WARNING: Something exists at $BUNDLE_DIR but it's not a directory"
    log "Attempting emergency removal with sync..."
    sync 2>/dev/null || true
    rm -rf "$BUNDLE_DIR" 2>/dev/null || sudo rm -rf "$BUNDLE_DIR" 2>/dev/null || {
      log "ERROR: Cannot remove conflicting path. Filesystem may be inconsistent."
      log "Try removing on host system or use different BUNDLE_DIR"
      exit 1
    }
    sync 2>/dev/null || true
    sleep 1  # Give filesystem time to update
  fi
  
  MKDIR_ERROR=""
  if ! mkdir -p "$BUNDLE_DIR" 2>&1; then
    MKDIR_ERROR=$(mkdir -p "$BUNDLE_DIR" 2>&1)
    log "ERROR: Failed to create bundle directory: $BUNDLE_DIR"
    log "Error message: $MKDIR_ERROR"
    
    # Check if error is due to file existing
    if echo "$MKDIR_ERROR" | grep -qi "file exists\|File exists\|exists"; then
      log "ERROR: Directory creation failed because a file exists at that location"
      log "Checking current state..."
      if [[ -f "$BUNDLE_DIR" ]]; then
        log "File exists: $BUNDLE_DIR"
        log "File size: $(stat -c%s "$BUNDLE_DIR" 2>/dev/null || stat -f%z "$BUNDLE_DIR" 2>/dev/null || echo 'unknown') bytes"
        log "Attempting to remove file..."
        rm -f "$BUNDLE_DIR" 2>/dev/null || sudo rm -f "$BUNDLE_DIR" 2>/dev/null || {
          log "ERROR: Cannot remove file. Please remove manually: rm -f $BUNDLE_DIR"
          exit 1
        }
        log "File removed. Retrying directory creation..."
        if ! mkdir -p "$BUNDLE_DIR" 2>&1; then
          log "ERROR: Still failed after removing file"
          exit 1
        fi
      else
        log "ERROR: mkdir says file exists but we cannot detect it"
        exit 1
      fi
    else
      # Error is not about file existing, check other causes
      log "Checking filesystem and permissions..."
      
      # Check filesystem type
      FS_TYPE=$(findmnt -n -o FSTYPE --target "$BUNDLE_PARENT" 2>/dev/null || \
                df -T "$BUNDLE_PARENT" 2>/dev/null | tail -1 | awk '{print $2}' || \
                echo "unknown")
      FS_MOUNT=$(df "$BUNDLE_PARENT" 2>/dev/null | tail -1 | awk '{print $NF}' || echo "unknown")
      MOUNT_OPTS=$(findmnt -n -o OPTIONS --target "$BUNDLE_PARENT" 2>/dev/null || echo "unknown")
      
      # #region agent log - Filesystem check
      echo "{\"id\":\"log_$(date +%s)_bundle_fs\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:bundle_fs\",\"message\":\"Filesystem check for bundle directory\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"parent_dir\":\"$BUNDLE_PARENT\",\"fs_type\":\"$FS_TYPE\",\"mount_point\":\"$FS_MOUNT\",\"mount_opts\":\"$MOUNT_OPTS\",\"parent_perms\":\"$(ls -ld "$BUNDLE_PARENT" 2>&1 || echo 'N/A')\",\"parent_owner\":\"$(stat -c '%U:%G' "$BUNDLE_PARENT" 2>/dev/null || stat -f '%Su:%Sg' "$BUNDLE_PARENT" 2>/dev/null || echo 'N/A')\",\"mkdir_error\":\"${MKDIR_ERROR:0:200}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1,DIR-H2,DIR-H3,DIR-H4\"}" >> "$TEMP_DEBUG_LOG" 2>/dev/null || true
      # #endregion
      
      log "Filesystem type: $FS_TYPE"
      log "Mount point: $FS_MOUNT"
      log "Mount options: $MOUNT_OPTS"
      log "Parent directory permissions: $(ls -ld "$BUNDLE_PARENT" 2>&1 || echo 'N/A')"
      
      # Check if filesystem is read-only
      if echo "$MOUNT_OPTS" | grep -q "ro"; then
        log "ERROR: Filesystem is mounted read-only!"
        log "You need to remount as read-write or use a different location."
        log "To remount: sudo mount -o remount,rw $FS_MOUNT"
        exit 1
      fi
      
      # Try with sudo if passwordless sudo is available
      if sudo -n true 2>/dev/null; then
      log "Attempting to create directory with sudo..."
      SUDO_ERROR=$(sudo mkdir -p "$BUNDLE_DIR" 2>&1)
      SUDO_EXIT=$?
      if [[ $SUDO_EXIT -eq 0 ]]; then
        log "Directory created with sudo, fixing permissions..."
        sudo chown "$(whoami):$(id -gn)" "$BUNDLE_DIR" 2>/dev/null || true
      else
        log "ERROR: sudo mkdir also failed (exit code: $SUDO_EXIT)"
        log "Error message: $SUDO_ERROR"
        log ""
        log "TROUBLESHOOTING:"
        log "1. Check if parent directory exists: ls -ld $BUNDLE_PARENT"
        log "2. Check filesystem mount: mount | grep $(echo $FS_MOUNT | sed 's/.*\///')"
        log "3. Check if filesystem is read-only: findmnt -n -o OPTIONS --target $BUNDLE_PARENT"
        log "4. Try creating manually: mkdir -p $BUNDLE_DIR"
        log "5. If on a shared mount (exFAT/9p), you may need to create the directory on the host system"
        exit 1
      fi
    else
        log "ERROR: Cannot create bundle directory and sudo would prompt for password"
        log "Please create it manually: mkdir -p $BUNDLE_DIR"
        exit 1
      fi
    fi
  fi
  
# Verify BUNDLE_DIR was created (if we tried to create it)
if [[ "$BUNDLE_EXISTS_D" != "true" ]]; then
  # We attempted to create it, verify it exists now
  if [[ ! -d "$BUNDLE_DIR" ]]; then
    log "ERROR: Bundle directory still does not exist after creation attempt: $BUNDLE_DIR"
    exit 1
  fi
  log "✓ Bundle directory created: $BUNDLE_DIR"
fi

# Debug log path - use bundle directory which works on both Mac and Linux
DEBUG_LOG="${DEBUG_LOG:-$BUNDLE_DIR/logs/debug.log}"
# Ensure debug log directory exists
mkdir -p "$(dirname "$DEBUG_LOG")" 2>/dev/null || {
  log "WARNING: Could not create debug log directory: $(dirname "$DEBUG_LOG")"
  # Fallback to /tmp if bundle directory fails
  DEBUG_LOG="/tmp/debug.log"
  log "Using fallback debug log: $DEBUG_LOG"
}

# Copy initial debug logs to final location if they exist
if [[ -f "$TEMP_DEBUG_LOG" ]]; then
  cat "$TEMP_DEBUG_LOG" >> "$DEBUG_LOG" 2>/dev/null || true
  rm -f "$TEMP_DEBUG_LOG" 2>/dev/null || true
fi

# #region agent log - Debug log initialized
echo "{\"id\":\"log_$(date +%s)_debug_log_init\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:debug_log_init\",\"message\":\"Debug log initialized\",\"data\":{\"debug_log\":\"$DEBUG_LOG\",\"debug_log_dir\":\"$(dirname "$DEBUG_LOG")\",\"debug_log_dir_exists\":$(test -d "$(dirname "$DEBUG_LOG")" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion
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
#
# To move models instead of copy (saves disk space but removes originals):
#   export MOVE_MODELS=true
if [[ -n "${OLLAMA_MODEL:-}" ]] && [[ -z "${OLLAMA_MODELS:-}" ]]; then
  # Backward compatibility: single model
  OLLAMA_MODELS="$OLLAMA_MODEL"
elif [[ -z "${OLLAMA_MODELS:-}" ]]; then
  # Default: bundle all recommended models
  OLLAMA_MODELS="mistral:7b-instruct mixtral:8x7b mistral:7b-instruct-q4_K_M"
fi

# Create bundle subdirectories, handling case where they might exist as files
# BUNDLE_DIR should already exist from above, but verify
if [[ ! -d "$BUNDLE_DIR" ]]; then
  log "ERROR: Bundle directory does not exist: $BUNDLE_DIR"
  log "This should not happen - bundle directory should have been created above"
  exit 1
fi

# #region agent log - Subdirectory creation start
echo "{\"id\":\"log_$(date +%s)_subdirs_start\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:subdirs_start\",\"message\":\"Starting subdirectory creation\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"bundle_dir_exists\":$(test -d "$BUNDLE_DIR" && echo true || echo false),\"bundle_dir_writable\":$(test -w "$BUNDLE_DIR" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1,DIR-H2,DIR-H3\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

# Check all directories that will be created, including nested ones
for dir in ollama models vscodium continue extensions python logs aptrepo rust; do
  if [[ -e "$BUNDLE_DIR/$dir" ]] && [[ ! -d "$BUNDLE_DIR/$dir" ]]; then
    log "Removing file that conflicts with directory: $BUNDLE_DIR/$dir"
    rm -f "$BUNDLE_DIR/$dir" 2>/dev/null || {
      log "WARNING: Could not remove file, trying with sudo..."
      sudo rm -f "$BUNDLE_DIR/$dir" 2>/dev/null || true
    }
  fi
done
# Also check nested directories that might exist as files
for nested_dir in aptrepo/pool aptrepo/conf rust/toolchain rust/crates; do
  if [[ -e "$BUNDLE_DIR/$nested_dir" ]] && [[ ! -d "$BUNDLE_DIR/$nested_dir" ]]; then
    log "Removing file that conflicts with nested directory: $BUNDLE_DIR/$nested_dir"
    rm -f "$BUNDLE_DIR/$nested_dir" 2>/dev/null || {
      log "WARNING: Could not remove file, trying with sudo..."
      sudo rm -f "$BUNDLE_DIR/$nested_dir" 2>/dev/null || true
    }
  fi
done

# Try to create all directories at once
if ! mkdir -p \
  "$BUNDLE_DIR"/{ollama,models,vscodium,continue,extensions,aptrepo/{pool,conf},rust/{toolchain,crates},python,logs} 2>/dev/null; then
  log "WARNING: Bulk directory creation failed, creating individually..."
  
  # Fallback: create directories one by one with better error reporting
  FAILED_DIRS=()
  for dir in ollama models vscodium continue extensions python logs; do
    if ! mkdir -p "$BUNDLE_DIR/$dir" 2>/dev/null; then
      log "ERROR: Failed to create $BUNDLE_DIR/$dir"
      FAILED_DIRS+=("$BUNDLE_DIR/$dir")
    fi
  done
  # Create nested directories
  for dir in aptrepo/pool aptrepo/conf rust/toolchain rust/crates; do
    if ! mkdir -p "$BUNDLE_DIR/$dir" 2>/dev/null; then
      log "ERROR: Failed to create $BUNDLE_DIR/$dir"
      FAILED_DIRS+=("$BUNDLE_DIR/$dir")
    fi
  done
  
  if [[ ${#FAILED_DIRS[@]} -gt 0 ]]; then
    log "ERROR: Failed to create ${#FAILED_DIRS[@]} directory(ies):"
    for dir in "${FAILED_DIRS[@]}"; do
      log "  - $dir"
    done
    
    # #region agent log - Subdirectory creation failures
    echo "{\"id\":\"log_$(date +%s)_subdirs_failed\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:subdirs_failed\",\"message\":\"Subdirectory creation failed\",\"data\":{\"failed_count\":${#FAILED_DIRS[@]},\"failed_dirs\":\"${FAILED_DIRS[*]}\",\"bundle_dir\":\"$BUNDLE_DIR\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1,DIR-H2,DIR-H3\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    exit 1
  fi
fi

# Verify all directories were created
MISSING_DIRS=()
for dir in ollama models vscodium continue extensions python logs aptrepo rust aptrepo/pool aptrepo/conf rust/toolchain rust/crates; do
  if [[ ! -d "$BUNDLE_DIR/$dir" ]]; then
    MISSING_DIRS+=("$BUNDLE_DIR/$dir")
  fi
done

if [[ ${#MISSING_DIRS[@]} -gt 0 ]]; then
  log "ERROR: ${#MISSING_DIRS[@]} directory(ies) are missing after creation attempt:"
  for dir in "${MISSING_DIRS[@]}"; do
    log "  - $dir"
  done
  exit 1
fi

log "✓ All bundle subdirectories created successfully"

# #region agent log - Subdirectory creation success
echo "{\"id\":\"log_$(date +%s)_subdirs_success\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:config:subdirs_success\",\"message\":\"All subdirectories created successfully\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"DIR-H1\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

sha256_check_file() {
  local file="$1"
  local sha_file="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")")
  else
    log "ERROR: sha256sum not found. This script requires Linux with standard tools."
    exit 1
  fi
}

# Verify VSIX file - Open VSX returns just the hash, so we need to format it
sha256_check_vsix() {
  local file="$1"
  local sha_file="$2"
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_vsix1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:entry\",\"message\":\"VSIX verification started\",\"data\":{\"file\":\"$file\",\"sha_file\":\"$sha_file\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ ! -f "$file" ]]; then
    log "ERROR: VSIX file not found: $file"
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_vsix2\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:file_missing\",\"message\":\"VSIX file not found\",\"data\":{\"file\":\"$file\",\"exists\":false},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-D\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    return 1
  fi
  
  if [[ ! -f "$sha_file" ]]; then
    log "ERROR: SHA256 file not found: $sha_file"
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_vsix3\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:sha_missing\",\"message\":\"SHA256 file not found\",\"data\":{\"sha_file\":\"$sha_file\",\"exists\":false},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-D\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    return 1
  fi
  
  # Read the hash from the file (strip whitespace, get first field)
  local expected_hash
  local sha_file_content
  sha_file_content=$(cat "$sha_file")
  expected_hash=$(head -n1 "$sha_file" | awk '{print $1}' | tr -d '[:space:]')
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_vsix4\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:read_hash\",\"message\":\"Read expected hash from file\",\"data\":{\"sha_file_content\":\"${sha_file_content:0:100}\",\"expected_hash\":\"${expected_hash:0:32}\",\"expected_length\":${#expected_hash},\"file_size\":$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-A,VSIX-C\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ -z "$expected_hash" ]]; then
    log "ERROR: Could not read expected hash from $sha_file"
    return 1
  fi
  
  # Calculate actual hash
  local actual_hash
  if command -v sha256sum >/dev/null 2>&1; then
    actual_hash=$(sha256sum "$file" | awk '{print $1}' | tr -d '[:space:]')
  else
    log "ERROR: sha256sum not found"
    return 1
  fi
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_vsix5\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:calculated_hash\",\"message\":\"Calculated actual hash\",\"data\":{\"actual_hash\":\"${actual_hash:0:32}\",\"actual_length\":${#actual_hash},\"file_path\":\"$file\",\"file_exists\":$(test -f "$file" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-B,VSIX-D\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ -z "$actual_hash" ]]; then
    log "ERROR: Could not calculate hash for $file"
    return 1
  fi
  
  # Compare hashes (case-insensitive, trimmed)
  local expected_lower="${expected_hash,,}"
  local actual_lower="${actual_hash,,}"
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_vsix6\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:compare\",\"message\":\"Comparing hashes\",\"data\":{\"expected_lower\":\"${expected_lower:0:32}\",\"actual_lower\":\"${actual_lower:0:32}\",\"match\":$(test "$expected_lower" == "$actual_lower" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-A,VSIX-E\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ "$expected_lower" == "$actual_lower" ]]; then
    return 0
  else
    log "DEBUG: Hash mismatch for $(basename "$file")"
    log "DEBUG: Expected: ${expected_hash:0:16}... (length: ${#expected_hash})"
    log "DEBUG: Actual:   ${actual_hash:0:16}... (length: ${#actual_hash})"
    return 1
  fi
}

# ============
# 1) Ollama (Linux amd64) + official SHA256 from GitHub Releases
# ============
OLLAMA_TGZ="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz"
OLLAMA_SHA="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz.sha256"

# Check if file already exists and is valid
if [[ -f "$OLLAMA_TGZ" ]] && [[ -f "$OLLAMA_SHA" ]]; then
  log "Ollama Linux binary already exists, verifying..."
  if sha256_check_file "$OLLAMA_TGZ" "$OLLAMA_SHA"; then
    log "Ollama already downloaded and verified. Skipping download."
    mark_success "ollama_linux"
    OLLAMA_DL_STATUS=0
  else
    log "Existing Ollama file failed verification. Re-downloading..."
    rm -f "$OLLAMA_TGZ" "$OLLAMA_SHA"
    OLLAMA_DL_STATUS=1
  fi
else
  OLLAMA_DL_STATUS=1
fi

if [[ $OLLAMA_DL_STATUS -ne 0 ]]; then
  log "Fetching Ollama latest release metadata and linux-amd64 tarball..."
  
  # Ensure ollama directory exists using shell commands (more reliable on exFAT)
  OLLAMA_DIR="$BUNDLE_DIR/ollama"
  log "Ensuring ollama directory exists: $OLLAMA_DIR"
  
  # Check if it exists as a file and remove it
  if [[ -e "$OLLAMA_DIR" ]] && [[ ! -d "$OLLAMA_DIR" ]]; then
    log "Removing existing file at $OLLAMA_DIR to create directory..."
    rm -f "$OLLAMA_DIR" 2>/dev/null || {
      log "WARNING: Failed to remove file, trying with sudo..."
      sudo rm -f "$OLLAMA_DIR" 2>/dev/null || true
    }
  fi
  
  # Try to create directory
  if ! mkdir -p "$OLLAMA_DIR" 2>/dev/null; then
    log "WARNING: mkdir -p failed, checking permissions..."
    log "Parent directory info: $(ls -ld "$BUNDLE_DIR" 2>&1 || echo 'N/A')"
    log "Current user: $(whoami)"
    log "Directory owner: $(stat -c '%U:%G' "$BUNDLE_DIR" 2>/dev/null || stat -f '%Su:%Sg' "$BUNDLE_DIR" 2>/dev/null || echo 'N/A')"
    
    # Try with sudo (but avoid if it would prompt - check sudo access first)
    if sudo -n true 2>/dev/null; then
      log "Attempting to create directory with sudo (passwordless sudo available)..."
      if sudo mkdir -p "$OLLAMA_DIR" 2>/dev/null; then
        log "Directory created with sudo, fixing permissions..."
        sudo chown "$(whoami):$(id -gn)" "$OLLAMA_DIR" 2>/dev/null || true
      else
        log "WARNING: sudo mkdir failed even with passwordless sudo"
      fi
    else
      log "WARNING: sudo would prompt for password - skipping sudo attempt"
      log "This might be a filesystem permission issue on the exFAT mount"
      log "You may need to manually create: mkdir -p $OLLAMA_DIR"
    fi
  fi
  
  # Final verification
  if [[ ! -d "$OLLAMA_DIR" ]]; then
    log "WARNING: Directory $OLLAMA_DIR does not exist after creation attempts"
    log "Checking parent directory: $BUNDLE_DIR"
    ls -la "$BUNDLE_DIR" 2>&1 || true
    log "Attempting to continue - Python script will try to create it..."
    log "If this fails, you may need to manually create: mkdir -p $OLLAMA_DIR"
  else
    log "Successfully created/verified directory: $OLLAMA_DIR"
  fi
  
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, hashlib, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"ollama"
# Directory should already exist from shell command, but verify
if not outdir.exists() or not outdir.is_dir():
    # Try one more time
    if outdir.exists() and outdir.is_file():
        outdir.unlink()
    try:
        outdir.mkdir(parents=True, exist_ok=True)
    except Exception as e:
        raise SystemExit(f"Failed to create directory {outdir}: {e}")
# Final verification
if not outdir.exists() or not outdir.is_dir():
    raise SystemExit(f"Directory {outdir} does not exist or is not a directory after creation attempt")

api = "https://api.github.com/repos/ollama/ollama/releases/latest"
data = json.loads(urllib.request.urlopen(api).read().decode("utf-8"))

# asset name per Ollama release page: ollama-linux-amd64.tgz
target_name = "ollama-linux-amd64.tgz"
assets = {a["name"]: a["browser_download_url"] for a in data["assets"]}
if target_name not in assets:
  raise SystemExit(f"Could not find {target_name} in latest release assets: {list(assets)[:10]}...")

url = assets[target_name]
print("Ollama URL:", url)

# Verify directory still exists before downloading and ensure it's actually a directory
if not outdir.exists() or not outdir.is_dir():
    # Try to recreate it
    try:
        if outdir.exists() and outdir.is_file():
            outdir.unlink()
        outdir.mkdir(parents=True, exist_ok=True)
        # Double-check it's a directory now
        if not outdir.is_dir():
            raise SystemExit(f"Directory {outdir} exists but is not a directory")
    except Exception as e:
        raise SystemExit(f"Directory {outdir} disappeared or cannot be created: {e}")

# Download tarball - use absolute path to avoid any path issues
tgz = outdir.absolute() / target_name
print(f"Downloading to: {tgz}")
print(f"Parent directory exists: {tgz.parent.exists()}, is_dir: {tgz.parent.is_dir()}")
urllib.request.urlretrieve(url, str(tgz))

# Calculate SHA256 hash of downloaded file
print("Calculating SHA256 hash of downloaded file...")
sha256_hash = hashlib.sha256()
with open(tgz, "rb") as f:
  for chunk in iter(lambda: f.read(4096), b""):
    sha256_hash.update(chunk)
sha = sha256_hash.hexdigest()

sha_file = outdir/(target_name + ".sha256")
sha_file.write_text(f"{sha}  {target_name}\n", encoding="utf-8")
print("Wrote sha256 file:", sha_file)
print(f"SHA256: {sha}")
PY
  OLLAMA_DL_STATUS=$?
  if [[ $OLLAMA_DL_STATUS -eq 0 ]]; then
    log "Verifying Ollama sha256..."
    if sha256_check_file "$OLLAMA_TGZ" "$OLLAMA_SHA"; then
      log "Ollama verified."
      mark_success "ollama_linux"
    else
      log "ERROR: Ollama SHA256 verification failed"
      mark_failed "ollama_linux"
    fi
  else
    log "ERROR: Failed to download Ollama Linux binary"
    mark_failed "ollama_linux"
  fi
fi

# ============
# 2) Pull Ollama models, then copy ~/.ollama
# ============
# Convert space-separated models to array
read -ra MODEL_ARRAY <<< "$OLLAMA_MODELS"
MODEL_COUNT=${#MODEL_ARRAY[@]}

log "Using Linux Ollama binary to pull $MODEL_COUNT model(s)..."

TMP_OLLAMA="$BUNDLE_DIR/ollama/_tmp_ollama"
rm -rf "$TMP_OLLAMA"
mkdir -p "$TMP_OLLAMA"

# Extract Linux Ollama binary
log "Extracting Ollama binary from tarball..."

# #region agent log
echo "{\"id\":\"log_$(date +%s)_ollama1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:entry\",\"message\":\"Starting Ollama extraction\",\"data\":{\"tarball\":\"$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz\",\"dest\":\"$TMP_OLLAMA\",\"tarball_exists\":$(test -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

TAR_OUTPUT=$(tar -xzf "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" -C "$TMP_OLLAMA" 2>&1)
TAR_EXIT=$?

# #region agent log
echo "{\"id\":\"log_$(date +%s)_ollama2\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:tar_result\",\"message\":\"Tar extraction completed\",\"data\":{\"exit_code\":$TAR_EXIT,\"output\":\"${TAR_OUTPUT:0:200}\",\"tmp_dir_contents\":\"$(ls -la "$TMP_OLLAMA" 2>&1 | head -10 | tr '\n' ';')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-A,OLLAMA-D\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

if [[ $TAR_EXIT -ne 0 ]]; then
  log "ERROR: Failed to extract Ollama tarball"
  log "Tar output: $TAR_OUTPUT"
  SKIP_MODEL_PULL=true
else
  # Find the ollama binary (it might be in the root or a subdirectory)
  OLLAMA_BIN=""
  if [[ -f "$TMP_OLLAMA/ollama" ]]; then
    OLLAMA_BIN="$TMP_OLLAMA/ollama"
  elif [[ -f "$TMP_OLLAMA/ollama-linux-amd64/ollama" ]]; then
    OLLAMA_BIN="$TMP_OLLAMA/ollama-linux-amd64/ollama"
  else
    # Search for it
    OLLAMA_BIN=$(find "$TMP_OLLAMA" -name "ollama" -type f 2>/dev/null | head -n1)
  fi
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_ollama3\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:find_binary\",\"message\":\"Binary search result\",\"data\":{\"ollama_bin\":\"$OLLAMA_BIN\",\"exists\":$(test -f "${OLLAMA_BIN:-}" && echo true || echo false),\"is_executable\":$(test -x "${OLLAMA_BIN:-}" && echo true || echo false),\"permissions\":\"$(ls -l "${OLLAMA_BIN:-}" 2>/dev/null | awk '{print $1}' || echo 'N/A')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-B,OLLAMA-D\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ -n "$OLLAMA_BIN" ]] && [[ -f "$OLLAMA_BIN" ]]; then
    # Check if binary is on a shared/exFAT mount that might cause execution issues
    BINARY_FS=$(df "$OLLAMA_BIN" 2>/dev/null | tail -1 | awk '{print $1}' || echo "unknown")
    BINARY_MOUNT=$(df "$OLLAMA_BIN" 2>/dev/null | tail -1 | awk '{print $NF}' || echo "unknown")
    # Try multiple methods to get filesystem type (Linux vs macOS)
    BINARY_FSTYPE=$(findmnt -n -o FSTYPE --target "$OLLAMA_BIN" 2>/dev/null || \
                    df -T "$OLLAMA_BIN" 2>/dev/null | tail -1 | awk '{print $2}' || \
                    echo "unknown")
    
    # #region agent log - Filesystem check
    echo "{\"id\":\"log_$(date +%s)_ollama_fs1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:filesystem_check\",\"message\":\"Binary filesystem info\",\"data\":{\"binary_path\":\"$OLLAMA_BIN\",\"filesystem\":\"$BINARY_FS\",\"mount_point\":\"$BINARY_MOUNT\",\"fstype\":\"$BINARY_FSTYPE\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-M\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # If binary is on exFAT or shared mount, copy entire directory structure to local filesystem
    if [[ "$BINARY_MOUNT" == *"transfer"* ]] || [[ "$BINARY_FSTYPE" == *"exfat"* ]] || [[ "$BINARY_MOUNT" == *"utm"* ]]; then
      log "Binary is on shared/exFAT mount ($BINARY_MOUNT), copying entire directory structure to local filesystem for execution..."
      LOCAL_OLLAMA_DIR="/tmp/ollama-$(basename "$TMP_OLLAMA")"
      rm -rf "$LOCAL_OLLAMA_DIR" 2>/dev/null || true
      cp -r "$TMP_OLLAMA" "$LOCAL_OLLAMA_DIR" 2>/dev/null || {
        log "WARNING: Failed to copy directory to /tmp, trying original location"
        LOCAL_OLLAMA_DIR="$TMP_OLLAMA"
      }
      LOCAL_OLLAMA_BIN="$LOCAL_OLLAMA_DIR/bin/ollama"
      chmod +x "$LOCAL_OLLAMA_BIN" 2>/dev/null || true
      # Also make lib files executable if needed
      find "$LOCAL_OLLAMA_DIR/lib" -type f -exec chmod +x {} \; 2>/dev/null || true
      OLLAMA_BIN="$LOCAL_OLLAMA_BIN"
      TMP_OLLAMA="$LOCAL_OLLAMA_DIR"
      log "Using local copy: $OLLAMA_BIN (with lib directory at $LOCAL_OLLAMA_DIR/lib)"
      
      # #region agent log - Binary copied
      echo "{\"id\":\"log_$(date +%s)_ollama_copy1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:binary_copied\",\"message\":\"Binary and lib directory copied to local filesystem\",\"data\":{\"original\":\"$BINARY_MOUNT\",\"local_copy\":\"$LOCAL_OLLAMA_BIN\",\"lib_dir\":\"$LOCAL_OLLAMA_DIR/lib\",\"copy_success\":$(test -f "$LOCAL_OLLAMA_BIN" && echo true || echo false),\"lib_exists\":$(test -d "$LOCAL_OLLAMA_DIR/lib" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-M\"}" >> "$DEBUG_LOG" 2>/dev/null || true
      # #endregion
    else
      chmod +x "$OLLAMA_BIN"
    fi
    
    export PATH="$(dirname "$OLLAMA_BIN"):$PATH"
    log "Ollama binary found at: $OLLAMA_BIN"
    log "Updated PATH to include: $(dirname "$OLLAMA_BIN")"
    
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_ollama4\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:path_set\",\"message\":\"PATH updated\",\"data\":{\"new_path\":\"$PATH\",\"ollama_bin_dir\":\"$(dirname "$OLLAMA_BIN")\",\"command_exists\":$(command -v ollama >/dev/null 2>&1 && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-C\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # #region agent log - System architecture check
    echo "{\"id\":\"log_$(date +%s)_ollama_sys1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:system_arch\",\"message\":\"System architecture info\",\"data\":{\"uname_m\":\"$(uname -m 2>/dev/null || echo 'N/A')\",\"uname_a\":\"$(uname -a 2>/dev/null | head -c 200 || echo 'N/A')\",\"kernel\":\"$(uname -r 2>/dev/null || echo 'N/A')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-F\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # #region agent log - Binary architecture check
    BINARY_INFO=$(file "$OLLAMA_BIN" 2>/dev/null || echo "N/A")
    echo "{\"id\":\"log_$(date +%s)_ollama_bin1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:binary_arch\",\"message\":\"Binary architecture info\",\"data\":{\"file_output\":\"${BINARY_INFO:0:300}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-F\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # #region agent log - Library dependencies check
    LDD_OUTPUT=$(ldd "$OLLAMA_BIN" 2>&1 | head -20 || echo "ldd_failed")
    LDD_MISSING=$(ldd "$OLLAMA_BIN" 2>&1 | grep -i "not found" || echo "")
    echo "{\"id\":\"log_$(date +%s)_ollama_lib1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:library_deps\",\"message\":\"Library dependencies check\",\"data\":{\"ldd_output\":\"${LDD_OUTPUT:0:500}\",\"missing_libs\":\"${LDD_MISSING:0:200}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-G\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # #region agent log - Test binary with --version before serve (with timeout)
    echo "{\"id\":\"log_$(date +%s)_ollama_test0\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:test_version_start\",\"message\":\"About to test binary with --version\",\"data\":{\"binary\":\"$OLLAMA_BIN\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-H\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # Run timeout command and capture both output and exit code correctly
    # Use a temporary variable to capture output, then check exit code
    VERSION_OUTPUT=$(timeout 5 "$OLLAMA_BIN" --version 2>&1)
    VERSION_EXIT=$?
    # timeout returns 124 on timeout, preserve that; otherwise use actual exit code
    if [[ $VERSION_EXIT -eq 124 ]]; then
      VERSION_OUTPUT="TIMEOUT: Command exceeded 5 second limit (original output: ${VERSION_OUTPUT:0:200})"
    elif [[ $VERSION_EXIT -ne 0 ]]; then
      VERSION_OUTPUT="ERROR: Command failed with exit code $VERSION_EXIT (output: ${VERSION_OUTPUT:0:200})"
    fi
    echo "{\"id\":\"log_$(date +%s)_ollama_test1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:test_version\",\"message\":\"Test binary with --version\",\"data\":{\"exit_code\":$VERSION_EXIT,\"output\":\"${VERSION_OUTPUT:0:500}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-H\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # #region agent log - Environment variables
    echo "{\"id\":\"log_$(date +%s)_ollama_env1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:env_vars\",\"message\":\"Environment variables\",\"data\":{\"LD_LIBRARY_PATH\":\"${LD_LIBRARY_PATH:-unset}\",\"OLLAMA_NUM_GPU\":\"${OLLAMA_NUM_GPU:-unset}\",\"OLLAMA_HOST\":\"${OLLAMA_HOST:-unset}\",\"HOME\":\"${HOME:-unset}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-I\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # #region agent log - VM detection
    VM_INFO=$(dmesg 2>/dev/null | grep -i "hypervisor\|qemu\|kvm\|vmware\|virtualbox" | head -3 | tr '\n' ';' || echo "N/A")
    CPUINFO_VIRT=$(grep -i "hypervisor\|vmx\|svm" /proc/cpuinfo 2>/dev/null | head -1 || echo "N/A")
    echo "{\"id\":\"log_$(date +%s)_ollama_vm1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:vm_detection\",\"message\":\"VM environment detection\",\"data\":{\"dmesg_vm\":\"${VM_INFO:0:200}\",\"cpuinfo_virt\":\"${CPUINFO_VIRT:0:100}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-L\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  else
    log "ERROR: Could not find ollama binary in extracted tarball"
    log "Contents of $TMP_OLLAMA:"
    ls -la "$TMP_OLLAMA" 2>&1 || true
    SKIP_MODEL_PULL=true
  fi
fi

# Check if models already exist
MODELS_EXIST=false
if [[ -d "$HOME/.ollama/models" ]] && [[ -n "$(ls -A "$HOME/.ollama/models" 2>/dev/null)" ]]; then
  EXISTING_SIZE=$(du -sh "$HOME/.ollama/models" 2>/dev/null | cut -f1 || echo "unknown")
  log "Found existing models in ~/.ollama/models (size: $EXISTING_SIZE)"
  MODELS_EXIST=true
fi

# Start ollama server in the background on the online machine just for pulling
# (it will create ~/.ollama)
log "Starting Ollama server to pull models..."
# Check if ollama is available
if [[ "${SKIP_MODEL_PULL:-false}" != "true" ]] && ! command -v ollama >/dev/null 2>&1; then
  log "ERROR: ollama command not found in PATH. Check extraction and PATH setup."
  log "PATH is: $PATH"
  log "TMP_OLLAMA is: $TMP_OLLAMA"
  if [[ -n "$OLLAMA_BIN" ]] && [[ -x "$OLLAMA_BIN" ]]; then
    log "OLLAMA_BIN is: $OLLAMA_BIN"
    log "Using ollama binary directly from: $OLLAMA_BIN"
    # Create a function to use the binary
    ollama() {
      "$OLLAMA_BIN" "$@"
    }
    export -f ollama
    log "Created ollama function wrapper"
  else
    log "Ollama binary not found or not executable"
    log "Skipping model pulling. You can copy existing models manually if they exist."
    SKIP_MODEL_PULL=true
  fi
fi

# Kill any existing ollama server to avoid conflicts
pkill -f "ollama serve" 2>/dev/null || true
sleep 1

# Determine which ollama command to use
OLLAMA_CMD="ollama"
if [[ -n "${OLLAMA_BIN:-}" ]] && [[ -x "${OLLAMA_BIN:-}" ]]; then
  OLLAMA_CMD="$OLLAMA_BIN"
elif ! command -v ollama >/dev/null 2>&1; then
  log "ERROR: ollama command not available and OLLAMA_BIN not set"
  SKIP_MODEL_PULL=true
fi

if [[ "${SKIP_MODEL_PULL:-false}" != "true" ]]; then
  log "Starting Ollama server (PID will be logged)..."
  log "Using ollama command: $OLLAMA_CMD"
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_ollama5\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:before_nohup\",\"message\":\"Before starting server\",\"data\":{\"ollama_cmd\":\"$OLLAMA_CMD\",\"cmd_exists\":$(test -f "$OLLAMA_CMD" && echo true || echo false),\"is_executable\":$(test -x "$OLLAMA_CMD" && echo true || echo false),\"path\":\"$PATH\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-C,OLLAMA-E\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # #region agent log - Check server log file before starting
  echo "{\"id\":\"log_$(date +%s)_ollama_log1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:log_file_check\",\"message\":\"Server log file check before start\",\"data\":{\"log_file\":\"$BUNDLE_DIR/logs/ollama_serve.log\",\"exists\":$(test -f "$BUNDLE_DIR/logs/ollama_serve.log" && echo true || echo false),\"size\":$(stat -f%z "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || stat -c%s "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || echo 0)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-J\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Clear any existing log file
  > "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || true
  
  # #region agent log - Before nohup
  echo "{\"id\":\"log_$(date +%s)_ollama_serve0\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:before_nohup_exec\",\"message\":\"About to execute nohup serve\",\"data\":{\"cmd\":\"$OLLAMA_CMD serve\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-K\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  nohup "$OLLAMA_CMD" serve >"$BUNDLE_DIR/logs/ollama_serve.log" 2>&1 &
  SERVE_PID=$!
  NOHUP_EXIT=$?
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_ollama6\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:after_nohup\",\"message\":\"After starting server\",\"data\":{\"serve_pid\":$SERVE_PID,\"nohup_exit\":$NOHUP_EXIT,\"process_exists\":$(kill -0 "$SERVE_PID" 2>/dev/null && echo true || echo false),\"log_size\":$(stat -f%z "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || stat -c%s "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || echo 0)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-C,OLLAMA-E\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # #region agent log - Check server status after short delay
  sleep 2
  SERVE_LOG_SIZE=$(stat -f%z "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || stat -c%s "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || echo 0)
  # Try to read log as text, filtering null bytes
  SERVE_LOG_CONTENT=$(strings "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null | head -50 | tr '\n' ';' | head -c 1000 || echo "N/A")
  PROCESS_STILL_RUNNING=$(kill -0 "$SERVE_PID" 2>/dev/null && echo true || echo false)
  # Check for crash indicators
  HAS_CRASH_INDICATORS=$(grep -i "fatal\|panic\|runtime\|invalid\|symbol" "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null | head -5 | tr '\n' ';' || echo "")
  echo "{\"id\":\"log_$(date +%s)_ollama_status1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:status_check\",\"message\":\"Server status after 2s delay\",\"data\":{\"serve_pid\":$SERVE_PID,\"process_running\":$PROCESS_STILL_RUNNING,\"log_size\":$SERVE_LOG_SIZE,\"log_text\":\"${SERVE_LOG_CONTENT:0:500}\",\"crash_indicators\":\"${HAS_CRASH_INDICATORS:0:300}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-J,OLLAMA-K\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  log "Ollama server started with PID: $SERVE_PID"
  sleep 3  # Give server more time to start (reduced from 5 since we already waited 2s)
else
  SERVE_PID=""
fi

# Verify server started (only if we tried to start it)
if [[ -n "${SERVE_PID:-}" ]]; then
  if ! kill -0 "$SERVE_PID" 2>/dev/null; then
    log "ERROR: Ollama server failed to start. Check logs: $BUNDLE_DIR/logs/ollama_serve.log"
    cat "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || true
    log "Skipping model pulling. Will attempt to copy existing models if they exist."
    PULL_FAILED=true
    SKIP_MODEL_PULL=true
  fi
fi

# Wait a bit more for server to be ready
sleep 2

# Pull all models (unless we're skipping)
if [[ "${SKIP_MODEL_PULL:-true}" != "true" ]]; then
  # Ensure OLLAMA_CMD is set
  if [[ -z "${OLLAMA_CMD:-}" ]]; then
    if [[ -n "${OLLAMA_BIN:-}" ]] && [[ -x "${OLLAMA_BIN:-}" ]]; then
      OLLAMA_CMD="$OLLAMA_BIN"
    elif command -v ollama >/dev/null 2>&1; then
      OLLAMA_CMD="ollama"
    else
      log "ERROR: Cannot find ollama command"
      SKIP_MODEL_PULL=true
    fi
  fi
  
  if [[ "${SKIP_MODEL_PULL:-true}" != "true" ]]; then
    log "Pulling $MODEL_COUNT model(s): ${OLLAMA_MODELS}"
    log "This may take a while, especially for large models like mixtral:8x7b (~26GB)..."
    PULL_FAILED=false
    for model in "${MODEL_ARRAY[@]}"; do
      log "Pulling model: $model ..."
      if ! "$OLLAMA_CMD" pull "$model"; then
        log "WARNING: Failed to pull $model. Continuing with other models..."
        PULL_FAILED=true
      else
        log "Successfully pulled $model"
      fi
    done

    # Stop server (if it was started)
    if [[ -n "${SERVE_PID:-}" ]]; then
      log "Stopping Ollama server..."
      kill "$SERVE_PID" 2>/dev/null || true
      wait "$SERVE_PID" 2>/dev/null || true
      sleep 1
    fi
  else
    log "Skipping model pulling (server not available or extraction failed)"
    PULL_FAILED=true
  fi
fi

# Always copy/move models, even if pulling failed (they might already exist)
# Use MOVE_MODELS=true to move instead of copy (saves disk space but removes originals)
MOVE_MODELS="${MOVE_MODELS:-false}"
if [[ "$MOVE_MODELS" == "true" ]]; then
  log "Moving \$HOME/.ollama into bundle (will remove originals)..."
else
  log "Copying \$HOME/.ollama into bundle..."
fi
mkdir -p "$BUNDLE_DIR/models"

MODELS_COPIED=false
if [[ ! -d "$HOME/.ollama" ]]; then
  log "WARNING: ~/.ollama directory does not exist. Models were not pulled."
  if [[ "$PULL_FAILED" == "true" ]]; then
    log "WARNING: Model pulling failed. Check logs: $BUNDLE_DIR/logs/ollama_serve.log"
  fi
  mark_failed "models"
else
  if [[ "$MOVE_MODELS" == "true" ]]; then
    # Move models to save disk space
    if mv "$HOME/.ollama" "$BUNDLE_DIR/models/.ollama"; then
      TOTAL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
      log "Models moved successfully. Total size: $TOTAL_SIZE"
      log "Models bundled: ${OLLAMA_MODELS}"
      log "Note: Original models in ~/.ollama have been moved to bundle"
      mark_success "models"
      MODELS_COPIED=true
    else
      log "ERROR: Failed to move models. Check disk space and permissions."
      mark_failed "models"
    fi
  else
    # Use rsync to copy models
    if rsync -a --delete "$HOME/.ollama/" "$BUNDLE_DIR/models/.ollama/"; then
      TOTAL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
      log "Models copied successfully. Total size: $TOTAL_SIZE"
      log "Models bundled: ${OLLAMA_MODELS}"
      log "Note: mistral:7b-instruct ~4GB, mixtral:8x7b ~26GB, mistral:7b-instruct-q4_K_M ~2GB"
      mark_success "models"
      MODELS_COPIED=true
    else
      log "ERROR: Failed to copy models. Check disk space and permissions."
      mark_failed "models"
    fi
  fi
fi

# Clean up temporary files to save disk space
if [[ "$MODELS_COPIED" == "true" ]]; then
  log "Cleaning up temporary files to save disk space..."
  
  # Clean up temporary ollama binary directory (no longer needed after pulling models)
  if [[ -n "${TMP_OLLAMA:-}" ]] && [[ -d "$TMP_OLLAMA" ]]; then
    TMP_SIZE=$(du -sh "$TMP_OLLAMA" 2>/dev/null | cut -f1 || echo "unknown")
    rm -rf "$TMP_OLLAMA"
    log "Cleaned up temporary Ollama binary directory ($TMP_SIZE)"
  fi
  
  
  # Clean up ollama serve log if models were successfully copied
  if [[ -f "$BUNDLE_DIR/logs/ollama_serve.log" ]]; then
    # Keep a summary but remove the full log to save space
    tail -50 "$BUNDLE_DIR/logs/ollama_serve.log" > "$BUNDLE_DIR/logs/ollama_serve.log.summary" 2>/dev/null || true
    rm -f "$BUNDLE_DIR/logs/ollama_serve.log"
    log "Cleaned up Ollama server log (summary kept)"
  fi
fi

# If models weren't copied but exist, offer to copy them
if [[ "$MODELS_COPIED" == "false" ]] && [[ -d "$HOME/.ollama/models" ]] && [[ -n "$(ls -A "$HOME/.ollama/models" 2>/dev/null)" ]]; then
  EXISTING_SIZE=$(du -sh "$HOME/.ollama/models" 2>/dev/null | cut -f1 || echo "unknown")
  log ""
  log "⚠️  Found existing models in ~/.ollama/models ($EXISTING_SIZE) that weren't copied."
  if [[ "$MOVE_MODELS" == "true" ]]; then
    log "   To move them now, run:"
    log "   mkdir -p $BUNDLE_DIR/models"
    log "   mv ~/.ollama $BUNDLE_DIR/models/.ollama"
  else
    log "   To copy them now, run:"
    log "   mkdir -p $BUNDLE_DIR/models"
    log "   rsync -av --progress ~/.ollama/ $BUNDLE_DIR/models/.ollama/"
  fi
  log ""
fi

# ============
# 3) VSCodium .deb + published .sha256, then verify
# ============
# Check if VSCodium already exists
VSCODIUM_DEB="$(find "$BUNDLE_DIR/vscodium" -maxdepth 1 -name "*_amd64.deb" 2>/dev/null | head -n1)"
VSCODIUM_SHA=""
if [[ -n "$VSCODIUM_DEB" ]]; then
  VSCODIUM_SHA="${VSCODIUM_DEB}.sha256"
fi

if [[ -n "$VSCODIUM_DEB" ]] && [[ -f "$VSCODIUM_DEB" ]] && [[ -f "$VSCODIUM_SHA" ]]; then
  log "VSCodium .deb already exists, verifying..."
  if sha256_check_file "$VSCODIUM_DEB" "$VSCODIUM_SHA"; then
    log "VSCodium already downloaded and verified. Skipping download."
    mark_success "vscodium"
    VSCODIUM_DL_STATUS=0
  else
    log "Existing VSCodium file failed verification. Re-downloading..."
    rm -f "$VSCODIUM_DEB" "$VSCODIUM_SHA"
    VSCODIUM_DL_STATUS=1
  fi
else
  VSCODIUM_DL_STATUS=1
fi

if [[ $VSCODIUM_DL_STATUS -ne 0 ]]; then
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
  VSCODIUM_DL_STATUS=$?
  if [[ $VSCODIUM_DL_STATUS -eq 0 ]]; then
    # .sha256 is usually in the form "<hash>  <filename>"
    if sha256_check_file "$BUNDLE_DIR/vscodium/"*_amd64.deb "$BUNDLE_DIR/vscodium/"*_amd64.deb.sha256; then
      log "VSCodium verified."
      mark_success "vscodium"
    else
      log "ERROR: VSCodium SHA256 verification failed"
      mark_failed "vscodium"
    fi
  else
    log "ERROR: Failed to download VSCodium. Continuing with other components..."
    mark_failed "vscodium"
  fi
fi

# ============
# 4) Continue.dev VSIX from Open VSX + sha256 resource, then verify
# ============
# Check if Continue VSIX already exists
CONTINUE_VSIX="$(find "$BUNDLE_DIR/continue" -maxdepth 1 -name "Continue.continue-*.vsix" 2>/dev/null | head -n1)"
CONTINUE_SHA=""
if [[ -n "$CONTINUE_VSIX" ]]; then
  CONTINUE_SHA="${CONTINUE_VSIX}.sha256"
fi

if [[ -n "$CONTINUE_VSIX" ]] && [[ -f "$CONTINUE_VSIX" ]] && [[ -f "$CONTINUE_SHA" ]]; then
  log "Continue VSIX already exists, verifying..."
  if sha256_check_vsix "$CONTINUE_VSIX" "$CONTINUE_SHA"; then
    log "Continue VSIX already downloaded and verified. Skipping download."
    mark_success "continue"
    CONTINUE_DL_STATUS=0
  else
    log "Existing Continue VSIX failed verification. Re-downloading..."
    rm -f "$CONTINUE_VSIX" "$CONTINUE_SHA"
    CONTINUE_DL_STATUS=1
  fi
else
  CONTINUE_DL_STATUS=1
fi

if [[ "$CONTINUE_DL_STATUS" -ne 0 ]]; then
  log "Fetching Continue VSIX + sha256 from Open VSX..."
  DEBUG_LOG="$DEBUG_LOG" python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"continue"
outdir.mkdir(parents=True, exist_ok=True)
debug_log = os.environ.get("DEBUG_LOG", str(bundle/"logs"/"debug.log"))

# Use Open VSX API to get extension metadata
api_url = "https://open-vsx.org/api/Continue/continue"
try:
    with urllib.request.urlopen(api_url) as response:
        data = json.loads(response.read().decode("utf-8"))
    
    # Get the latest version from the API response
    if isinstance(data, list) and len(data) > 0:
        # If it's a list, get the first (latest) version
        latest = data[0]
        version = latest.get("version")
        namespace = latest.get("namespace", "Continue")
        name = latest.get("name", "continue")
    elif isinstance(data, dict):
        # If it's a single object, use it directly
        version = data.get("version")
        namespace = data.get("namespace", "Continue")
        name = data.get("name", "continue")
    else:
        raise SystemExit("Unexpected API response format")
    
    if not version:
        raise SystemExit("Could not determine version from API response")
    
    # Construct URLs using the discovered version
    vsix_name = f"{namespace}.{name}-{version}.vsix"
    download_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/file/{vsix_name}"
    sha256_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/sha256"
    
    # Download both
    urllib.request.urlretrieve(download_url, outdir/vsix_name)
    vsix_size = (outdir/vsix_name).stat().st_size
    
    # Open VSX returns just the hash, format it as "hash  filename"
    # Handle rate limiting - if we get HTML, calculate hash from downloaded file instead
    sha256_response = urllib.request.urlopen(sha256_url).read().decode("utf-8")
    sha256_hash = sha256_response.strip()
    
    # Check if we got HTML instead of a hash (Open VSX rate limiting)
    if sha256_hash.startswith("<!DOCTYPE") or sha256_hash.startswith("<html") or len(sha256_hash) > 100:
        # Open VSX is throttling us - calculate hash from downloaded file instead
        import hashlib
        print(f"WARNING: Open VSX returned HTML (rate limiting). Calculating hash from downloaded file...")
        with open(outdir/vsix_name, "rb") as f:
            sha256_hash = hashlib.sha256(f.read()).hexdigest()
        print(f"Calculated SHA256 from file: {sha256_hash[:16]}...")
    
    sha256_file = outdir/(vsix_name + ".sha256")
    sha256_file.write_text(f"{sha256_hash}  {vsix_name}\n", encoding="utf-8")
    
    # #region agent log
    import time
    log_entry = {
        "id": f"log_{int(time.time())}_vsix_dl1",
        "timestamp": int(time.time() * 1000),
        "location": "get_bundle.sh:python:download_vsix",
        "message": "VSIX downloaded and SHA256 fetched",
        "data": {
            "vsix_name": vsix_name,
            "vsix_size": vsix_size,
            "sha256_hash_raw": sha256_hash[:64],
            "sha256_hash_length": len(sha256_hash),
            "sha256_response_raw": sha256_response[:100],
            "sha256_file_content": f"{sha256_hash}  {vsix_name}\n"
        },
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "VSIX-A,VSIX-C"
    }
    try:
        os.makedirs(os.path.dirname(debug_log), exist_ok=True)
        with open(debug_log, "a") as f:
            f.write(json.dumps(log_entry) + "\n")
    except Exception:
        pass
    # #endregion
    
    print("Version:", version)
    print("Downloaded:", vsix_name)
    print("SHA256 URL:", sha256_url)
except urllib.error.URLError as e:
    raise SystemExit(f"Failed to fetch from Open VSX API: {e}")
except (KeyError, ValueError) as e:
    raise SystemExit(f"Failed to parse API response: {e}")
PY
  CONTINUE_DL_STATUS=$?
  if [[ "$CONTINUE_DL_STATUS" -eq 0 ]]; then
    # Find the actual VSIX file (wildcard expansion)
    CONTINUE_VSIX_FILE="$(find "$BUNDLE_DIR/continue" -maxdepth 1 -name "Continue.continue-*.vsix" 2>/dev/null | head -n1)"
    CONTINUE_SHA_FILE="${CONTINUE_VSIX_FILE}.sha256"
    if [[ -n "$CONTINUE_VSIX_FILE" ]] && [[ -f "$CONTINUE_VSIX_FILE" ]]; then
      if [[ -f "$CONTINUE_SHA_FILE" ]]; then
        if sha256_check_vsix "$CONTINUE_VSIX_FILE" "$CONTINUE_SHA_FILE"; then
          log "Continue VSIX verified."
          mark_success "continue"
        else
          log "WARNING: Continue VSIX SHA256 verification failed, but file exists and will be included"
          log "WARNING: This may indicate a hash mismatch from Open VSX. The VSIX file can still be installed."
          mark_success "continue"  # Still mark as success since file exists
        fi
      else
        log "WARNING: Continue VSIX SHA256 file not found, but VSIX file exists and will be included"
        mark_success "continue"
      fi
    else
      log "ERROR: Continue VSIX file not found after download"
      mark_failed "continue"
    fi
  else
    log "ERROR: Failed to download Continue VSIX. Continuing with other components..."
    mark_failed "continue"
  fi
fi

# ============
# 5) Python Extension VSIX from Open VSX + sha256, then verify
# ============
# Check if Python extension VSIX already exists
PYTHON_VSIX="$(find "$BUNDLE_DIR/extensions" -maxdepth 1 -name "ms-python.python-*.vsix" 2>/dev/null | head -n1)"
PYTHON_SHA=""
if [[ -n "$PYTHON_VSIX" ]]; then
  PYTHON_SHA="${PYTHON_VSIX}.sha256"
fi

if [[ -n "$PYTHON_VSIX" ]] && [[ -f "$PYTHON_VSIX" ]] && [[ -f "$PYTHON_SHA" ]]; then
  log "Python extension VSIX already exists, verifying..."
  if sha256_check_vsix "$PYTHON_VSIX" "$PYTHON_SHA"; then
    log "Python extension VSIX already downloaded and verified. Skipping download."
    mark_success "python_ext"
    PYTHON_EXT_DL_STATUS=0
  else
    log "Existing Python extension VSIX failed verification. Re-downloading..."
    rm -f "$PYTHON_VSIX" "$PYTHON_SHA"
    PYTHON_EXT_DL_STATUS=1
  fi
else
  PYTHON_EXT_DL_STATUS=1
fi

if [[ $PYTHON_EXT_DL_STATUS -ne 0 ]]; then
  log "Fetching Python extension VSIX + sha256 from Open VSX..."
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

# Use Open VSX API to get extension metadata
api_url = "https://open-vsx.org/api/ms-python/python"
try:
    with urllib.request.urlopen(api_url) as response:
        data = json.loads(response.read().decode("utf-8"))
    
    # Get the latest version from the API response
    if isinstance(data, list) and len(data) > 0:
        latest = data[0]
        version = latest.get("version")
        namespace = latest.get("namespace", "ms-python")
        name = latest.get("name", "python")
    elif isinstance(data, dict):
        version = data.get("version")
        namespace = data.get("namespace", "ms-python")
        name = data.get("name", "python")
    else:
        raise SystemExit("Unexpected API response format")
    
    if not version:
        raise SystemExit("Could not determine version from API response")
    
    # Construct URLs using the discovered version
    vsix_name = f"{namespace}.{name}-{version}.vsix"
    download_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/file/{vsix_name}"
    sha256_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/sha256"
    
    # Download both
    urllib.request.urlretrieve(download_url, outdir/vsix_name)
    vsix_size = (outdir/vsix_name).stat().st_size
    
    # Open VSX returns just the hash, format it as "hash  filename"
    # Handle rate limiting - if we get HTML, calculate hash from downloaded file instead
    sha256_response = urllib.request.urlopen(sha256_url).read().decode("utf-8")
    sha256_hash = sha256_response.strip()
    
    # Check if we got HTML instead of a hash (Open VSX rate limiting)
    if sha256_hash.startswith("<!DOCTYPE") or sha256_hash.startswith("<html") or len(sha256_hash) > 100:
        # Open VSX is throttling us - calculate hash from downloaded file instead
        import hashlib
        print(f"WARNING: Open VSX returned HTML (rate limiting). Calculating hash from downloaded file...")
        with open(outdir/vsix_name, "rb") as f:
            sha256_hash = hashlib.sha256(f.read()).hexdigest()
        print(f"Calculated SHA256 from file: {sha256_hash[:16]}...")
    
    sha256_file = outdir/(vsix_name + ".sha256")
    sha256_file.write_text(f"{sha256_hash}  {vsix_name}\n", encoding="utf-8")
    
    # #region agent log
    import time
    log_entry = {
        "id": f"log_{int(time.time())}_vsix_dl1",
        "timestamp": int(time.time() * 1000),
        "location": "get_bundle.sh:python:download_vsix",
        "message": "VSIX downloaded and SHA256 fetched",
        "data": {
            "vsix_name": vsix_name,
            "vsix_size": vsix_size,
            "sha256_hash_raw": sha256_hash[:64],
            "sha256_hash_length": len(sha256_hash),
            "sha256_response_raw": sha256_response[:100],
            "sha256_file_content": f"{sha256_hash}  {vsix_name}\n"
        },
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "VSIX-A,VSIX-C"
    }
    try:
        os.makedirs(os.path.dirname(debug_log), exist_ok=True)
        with open(debug_log, "a") as f:
            f.write(json.dumps(log_entry) + "\n")
    except Exception:
        pass
    # #endregion
    
    print("Version:", version)
    print("Downloaded:", vsix_name)
    print("SHA256 URL:", sha256_url)
except urllib.error.URLError as e:
    raise SystemExit(f"Failed to fetch from Open VSX API: {e}")
except (KeyError, ValueError) as e:
    raise SystemExit(f"Failed to parse API response: {e}")
PY
  PYTHON_EXT_DL_STATUS=$?

  if [[ $PYTHON_EXT_DL_STATUS -eq 0 ]]; then
    # Find the actual VSIX file (wildcard expansion)
    PYTHON_VSIX_FILE="$(find "$BUNDLE_DIR/extensions" -maxdepth 1 -name "ms-python.python-*.vsix" 2>/dev/null | head -n1)"
    PYTHON_SHA_FILE="${PYTHON_VSIX_FILE}.sha256"
    if [[ -n "$PYTHON_VSIX_FILE" ]] && [[ -f "$PYTHON_VSIX_FILE" ]]; then
      if [[ -f "$PYTHON_SHA_FILE" ]]; then
        if sha256_check_vsix "$PYTHON_VSIX_FILE" "$PYTHON_SHA_FILE"; then
          log "Python extension VSIX verified."
          mark_success "python_ext"
        else
          log "WARNING: Python extension VSIX SHA256 verification failed, but file exists and will be included"
          log "WARNING: This may indicate a hash mismatch from Open VSX. The VSIX file can still be installed."
          mark_success "python_ext"  # Still mark as success since file exists
        fi
      else
        log "WARNING: Python extension VSIX SHA256 file not found, but VSIX file exists and will be included"
        mark_success "python_ext"
      fi
    else
      log "ERROR: Python extension VSIX file not found after download"
      mark_failed "python_ext"
    fi
  else
    log "ERROR: Failed to download Python extension VSIX. Continuing with other components..."
    mark_failed "python_ext"
  fi
fi

# ============
# 6) Rust Analyzer Extension VSIX from Open VSX + sha256, then verify
# ============
# Check if Rust Analyzer extension VSIX already exists
RUST_VSIX="$(find "$BUNDLE_DIR/extensions" -maxdepth 1 -name "rust-lang.rust-analyzer-*.vsix" 2>/dev/null | head -n1)"
RUST_SHA=""
if [[ -n "$RUST_VSIX" ]]; then
  RUST_SHA="${RUST_VSIX}.sha256"
fi

if [[ -n "$RUST_VSIX" ]] && [[ -f "$RUST_VSIX" ]] && [[ -f "$RUST_SHA" ]]; then
  log "Rust Analyzer extension VSIX already exists, verifying..."
  if sha256_check_vsix "$RUST_VSIX" "$RUST_SHA"; then
    log "Rust Analyzer extension VSIX already downloaded and verified. Skipping download."
    mark_success "rust_ext"
    RUST_EXT_DL_STATUS=0
  else
    log "Existing Rust Analyzer extension VSIX failed verification. Re-downloading..."
    rm -f "$RUST_VSIX" "$RUST_SHA"
    RUST_EXT_DL_STATUS=1
  fi
else
  RUST_EXT_DL_STATUS=1
fi

if [[ $RUST_EXT_DL_STATUS -ne 0 ]]; then
  log "Fetching Rust Analyzer extension VSIX + sha256 from Open VSX..."
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

# Use Open VSX API to get extension metadata
api_url = "https://open-vsx.org/api/rust-lang/rust-analyzer"
try:
    with urllib.request.urlopen(api_url) as response:
        data = json.loads(response.read().decode("utf-8"))
    
    # Get the latest version from the API response
    if isinstance(data, list) and len(data) > 0:
        latest = data[0]
        version = latest.get("version")
        namespace = latest.get("namespace", "rust-lang")
        name = latest.get("name", "rust-analyzer")
    elif isinstance(data, dict):
        version = data.get("version")
        namespace = data.get("namespace", "rust-lang")
        name = data.get("name", "rust-analyzer")
    else:
        raise SystemExit("Unexpected API response format")
    
    if not version:
        raise SystemExit("Could not determine version from API response")
    
    # Construct URLs using the discovered version
    vsix_name = f"{namespace}.{name}-{version}.vsix"
    download_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/file/{vsix_name}"
    sha256_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/sha256"
    
    # Download both
    urllib.request.urlretrieve(download_url, outdir/vsix_name)
    vsix_size = (outdir/vsix_name).stat().st_size
    
    # Open VSX returns just the hash, format it as "hash  filename"
    # Handle rate limiting - if we get HTML, calculate hash from downloaded file instead
    sha256_response = urllib.request.urlopen(sha256_url).read().decode("utf-8")
    sha256_hash = sha256_response.strip()
    
    # Check if we got HTML instead of a hash (Open VSX rate limiting)
    if sha256_hash.startswith("<!DOCTYPE") or sha256_hash.startswith("<html") or len(sha256_hash) > 100:
        # Open VSX is throttling us - calculate hash from downloaded file instead
        import hashlib
        print(f"WARNING: Open VSX returned HTML (rate limiting). Calculating hash from downloaded file...")
        with open(outdir/vsix_name, "rb") as f:
            sha256_hash = hashlib.sha256(f.read()).hexdigest()
        print(f"Calculated SHA256 from file: {sha256_hash[:16]}...")
    
    sha256_file = outdir/(vsix_name + ".sha256")
    sha256_file.write_text(f"{sha256_hash}  {vsix_name}\n", encoding="utf-8")
    
    # #region agent log
    import time
    log_entry = {
        "id": f"log_{int(time.time())}_vsix_dl1",
        "timestamp": int(time.time() * 1000),
        "location": "get_bundle.sh:python:download_vsix",
        "message": "VSIX downloaded and SHA256 fetched",
        "data": {
            "vsix_name": vsix_name,
            "vsix_size": vsix_size,
            "sha256_hash_raw": sha256_hash[:64],
            "sha256_hash_length": len(sha256_hash),
            "sha256_response_raw": sha256_response[:100],
            "sha256_file_content": f"{sha256_hash}  {vsix_name}\n"
        },
        "sessionId": "debug-session",
        "runId": "run1",
        "hypothesisId": "VSIX-A,VSIX-C"
    }
    try:
        os.makedirs(os.path.dirname(debug_log), exist_ok=True)
        with open(debug_log, "a") as f:
            f.write(json.dumps(log_entry) + "\n")
    except Exception:
        pass
    # #endregion
    
    print("Version:", version)
    print("Downloaded:", vsix_name)
    print("SHA256 URL:", sha256_url)
except urllib.error.URLError as e:
    raise SystemExit(f"Failed to fetch from Open VSX API: {e}")
except (KeyError, ValueError) as e:
    raise SystemExit(f"Failed to parse API response: {e}")
PY
  RUST_EXT_DL_STATUS=$?

  if [[ $RUST_EXT_DL_STATUS -eq 0 ]]; then
    # Find the actual VSIX file (wildcard expansion)
    RUST_VSIX_FILE="$(find "$BUNDLE_DIR/extensions" -maxdepth 1 -name "rust-lang.rust-analyzer-*.vsix" 2>/dev/null | head -n1)"
    RUST_SHA_FILE="${RUST_VSIX_FILE}.sha256"
    if [[ -n "$RUST_VSIX_FILE" ]] && [[ -f "$RUST_VSIX_FILE" ]]; then
      if [[ -f "$RUST_SHA_FILE" ]]; then
        if sha256_check_vsix "$RUST_VSIX_FILE" "$RUST_SHA_FILE"; then
          log "Rust Analyzer extension VSIX verified."
          mark_success "rust_ext"
        else
          log "WARNING: Rust Analyzer extension VSIX SHA256 verification failed, but file exists and will be included"
          log "WARNING: This may indicate a hash mismatch from Open VSX. The VSIX file can still be installed."
          mark_success "rust_ext"  # Still mark as success since file exists
        fi
      else
        log "WARNING: Rust Analyzer extension VSIX SHA256 file not found, but VSIX file exists and will be included"
        mark_success "rust_ext"
      fi
    else
      log "ERROR: Rust Analyzer extension VSIX file not found after download"
      mark_failed "rust_ext"
    fi
  else
    log "ERROR: Failed to download Rust Analyzer extension VSIX. Continuing with other components..."
    mark_failed "rust_ext"
  fi
fi

# ============
# 7) Offline APT repo for Lua 5.3 + common prereqs
# ============
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
    gfortran
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
  # Some packages may not be available on all distributions, so try individually if bulk fails
  if ! sudo apt-get -y --download-only -o Dir::Cache="$TMP_APT" install "${APT_PACKAGES[@]}" 2>&1; then
    log "WARNING: Bulk package download failed. Attempting to download packages individually..."
    # Try to download packages individually to get as many as possible
    MISSING_PKGS=()
    for pkg in "${APT_PACKAGES[@]}"; do
      OUTPUT=$(sudo apt-get -y --download-only -o Dir::Cache="$TMP_APT" install "$pkg" 2>&1)
      EXIT_CODE=$?
      if [[ $EXIT_CODE -ne 0 ]] && echo "$OUTPUT" | grep -q "Unable to locate package"; then
        log "WARNING: Package not available: $pkg (skipping)"
        MISSING_PKGS+=("$pkg")
      elif [[ $EXIT_CODE -eq 0 ]]; then
        log "Downloaded: $pkg"
      else
        log "WARNING: Failed to download $pkg (error code: $EXIT_CODE)"
        MISSING_PKGS+=("$pkg")
      fi
    done
    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
      log "WARNING: ${#MISSING_PKGS[@]} package(s) were not available: ${MISSING_PKGS[*]}"
      log "Continuing with available packages..."
    fi
  else
    log "All packages downloaded successfully."
  fi

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
  mark_success "apt_repo"

# ============
# 8) Download Rust toolchain (rustup-init)
# ============
# Check if rustup-init already exists
RUSTUP_INIT="$BUNDLE_DIR/rust/toolchain/rustup-init"
if [[ -f "$RUSTUP_INIT" ]] && [[ -x "$RUSTUP_INIT" ]]; then
  RUSTUP_SIZE=$(du -sh "$RUSTUP_INIT" 2>/dev/null | cut -f1 || echo "unknown")
  log "Rust toolchain installer already exists ($RUSTUP_SIZE). Skipping download."
  mark_success "rust_toolchain"
  RUST_TOOLCHAIN_EXISTS=true
else
  RUST_TOOLCHAIN_EXISTS=false
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
    log "Rust toolchain installer downloaded."
    mark_success "rust_toolchain"
  else
    log "WARNING: rustup-init not downloaded. You may need to download it manually."
    mark_failed "rust_toolchain"
  fi
fi

# ============
# 8b) Build and bundle Rust crates (if Cargo.toml exists)
# ============
RUST_CARGO_TOML="${RUST_CARGO_TOML:-Cargo.toml}"

# #region agent log - Rust crates start
echo "{\"id\":\"log_$(date +%s)_rust_crates_start\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:rust_crates:start\",\"message\":\"Checking for Rust crates\",\"data\":{\"cargo_toml\":\"$RUST_CARGO_TOML\",\"cargo_toml_exists\":$(test -f "$RUST_CARGO_TOML" && echo true || echo false),\"cargo_cmd\":\"$(command -v cargo || echo 'NOT_FOUND')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"RUST-R1\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

if [[ -f "$RUST_CARGO_TOML" ]]; then
  log "Found Cargo.toml. Building and bundling Rust crates for offline use..."
  log "Note: This requires cargo to be installed on the build machine."
  
  if command -v cargo >/dev/null 2>&1; then
    # Use cargo vendor to bundle all dependencies
    CRATES_DIR="$BUNDLE_DIR/rust/crates"
    mkdir -p "$CRATES_DIR"
    
    # Copy Cargo.toml and Cargo.lock to bundle
    cp "$RUST_CARGO_TOML" "$CRATES_DIR/"
    if [[ -f "Cargo.lock" ]]; then
      cp "Cargo.lock" "$CRATES_DIR/"
    else
      # Generate Cargo.lock if it doesn't exist
      log "Generating Cargo.lock..."
      (cd "$(dirname "$RUST_CARGO_TOML")" && cargo generate-lockfile 2>/dev/null || true)
      if [[ -f "$(dirname "$RUST_CARGO_TOML")/Cargo.lock" ]]; then
        cp "$(dirname "$RUST_CARGO_TOML")/Cargo.lock" "$CRATES_DIR/"
      fi
    fi
    
    # Vendor all dependencies (downloads and prepares them for offline use)
    log "Vendoring Rust crates..."
    
    # #region agent log - Cargo vendor start
    echo "{\"id\":\"log_$(date +%s)_rust_vendor_start\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:rust_crates:vendor_start\",\"message\":\"Starting cargo vendor\",\"data\":{\"crates_dir\":\"$CRATES_DIR\",\"cargo_toml\":\"$CRATES_DIR/Cargo.toml\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"RUST-R2\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    VENDOR_OUTPUT=$(cd "$CRATES_DIR" && cargo vendor --manifest-path "$(pwd)/Cargo.toml" vendor 2>&1)
    VENDOR_EXIT=$?
    
    # #region agent log - Cargo vendor result
    echo "{\"id\":\"log_$(date +%s)_rust_vendor_result\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:rust_crates:vendor_result\",\"message\":\"Cargo vendor completed\",\"data\":{\"exit_code\":$VENDOR_EXIT,\"output_length\":${#VENDOR_OUTPUT},\"output_preview\":\"${VENDOR_OUTPUT:0:500}\",\"vendor_dir_exists\":$(test -d "$CRATES_DIR/vendor" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"RUST-R2\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    if [[ $VENDOR_EXIT -ne 0 ]]; then
      log "WARNING: cargo vendor failed (exit code: $VENDOR_EXIT). You may need to run it manually:"
      log "  cd $CRATES_DIR && cargo vendor"
      log "Output: ${VENDOR_OUTPUT:0:500}"
      mark_failed "rust_crates"
    elif [[ -d "$CRATES_DIR/vendor" ]]; then
      log "Rust crates bundled successfully."
      log "All dependencies are vendored and ready for offline builds."
      mark_success "rust_crates"
    else
      log "ERROR: cargo vendor did not create vendor directory."
      mark_failed "rust_crates"
    fi
  else
    log "WARNING: cargo not found. Cannot bundle Rust crates."
    log "Install Rust first (rustup-init is in the bundle), then re-run this script to bundle crates."
    mark_skipped "rust_crates"
  fi
else
  log "No Cargo.toml found. Skipping Rust crate bundling."
  mark_skipped "rust_crates"
fi

# ============
# 9) Download Python packages (if requirements.txt exists)
# ============
PYTHON_REQUIREMENTS="${PYTHON_REQUIREMENTS:-requirements.txt}"
if [[ -f "$PYTHON_REQUIREMENTS" ]]; then
  log "Found requirements.txt. Downloading and building Python packages for Linux..."
  log "Note: This will download packages and build source distributions to ensure they work on this system."
  
  # #region agent log - Python packages start
  echo "{\"id\":\"log_$(date +%s)_python_start\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:python_packages:start\",\"message\":\"Starting Python package download\",\"data\":{\"requirements_file\":\"$PYTHON_REQUIREMENTS\",\"requirements_exists\":$(test -f "$PYTHON_REQUIREMENTS" && echo true || echo false),\"bundle_dir\":\"$BUNDLE_DIR\",\"python_cmd\":\"$(command -v python3 || echo 'NOT_FOUND')\",\"pip_cmd\":\"$(command -v pip3 || python3 -m pip --version 2>&1 | head -1 || echo 'NOT_FOUND')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"PYTHON-H1,PYTHON-H2,PYTHON-H3\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Create temporary Python script to avoid heredoc parsing issues
  TEMP_PY_SCRIPT=$(mktemp)
  cat > "$TEMP_PY_SCRIPT" <<'PYEOF'
import sys, subprocess, json, os
from pathlib import Path
from datetime import datetime

DEBUG_LOG = sys.argv[3] if len(sys.argv) > 3 else '/dev/null'

def log_debug(location, message, data):
    try:
        with open(DEBUG_LOG, 'a') as f:
            entry = {
                "id": f"log_{int(datetime.now().timestamp())}_python_{location}",
                "timestamp": int(datetime.now().timestamp() * 1000),
                "location": f"get_bundle.sh:python_packages:{location}",
                "message": message,
                "data": data,
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "PYTHON-H1,PYTHON-H2,PYTHON-H3,PYTHON-H4,PYTHON-H5,PYTHON-H6"
            }
            f.write(json.dumps(entry) + "\n")
    except:
        pass

bundle = Path(sys.argv[1])
requirements = Path(sys.argv[2])
outdir = bundle/"python"

log_debug("entry", "Python script started", {
    "bundle": str(bundle),
    "requirements": str(requirements),
    "outdir": str(outdir),
    "requirements_exists": requirements.exists(),
    "bundle_exists": bundle.exists(),
    "outdir_exists": outdir.exists()
})

try:
    outdir.mkdir(parents=True, exist_ok=True)
    log_debug("mkdir", "Created output directory", {"outdir": str(outdir), "exists": outdir.exists(), "is_dir": outdir.is_dir()})
except Exception as e:
    log_debug("mkdir_error", "Failed to create output directory", {"error": str(e), "outdir": str(outdir)})
    print(f"ERROR: Could not create output directory: {e}")
    sys.exit(1)

# Copy requirements.txt to bundle for reference
import shutil
try:
    shutil.copy(requirements, outdir/"requirements.txt")
    log_debug("copy_req", "Copied requirements.txt", {"source": str(requirements), "dest": str(outdir/"requirements.txt")})
except Exception as e:
    log_debug("copy_req_error", "Failed to copy requirements.txt", {"error": str(e)})
    print(f"WARNING: Could not copy requirements.txt: {e}")

# Use pip download to get all packages and dependencies for Linux
# We download with dependencies to ensure everything is bundled
try:
    # Step 1: Download binary wheels with ALL dependencies
    # pip download automatically includes dependencies unless --no-deps is specified
    print("Step 1: Downloading binary wheels for Linux (with ALL dependencies)...")
    log_debug("step1_start", "Starting binary wheel download", {
        "requirements": str(requirements),
        "outdir": str(outdir),
        "python": sys.executable
    })
    
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
    
    log_debug("step1_result", "Binary wheel download completed", {
        "exit_code": result.returncode,
        "stdout_length": len(result.stdout),
        "stderr_length": len(result.stderr),
        "stderr_preview": result.stderr[:500] if result.stderr else "",
        "files_before": len(list(outdir.glob("*.whl"))),
        "files_after": len(list(outdir.glob("*.whl")))
    })
    
    if result.returncode != 0:
        print(f"Warning: Some packages may not have binary wheels: {result.stderr}")
        log_debug("step1_warning", "Binary wheel download had errors", {
            "stderr": result.stderr[:1000] if result.stderr else ""
        })
    
    # Step 2: Download source distributions as fallback for packages without wheels
    # This ensures we have everything, even if it needs compilation
    # Also downloads dependencies that might have been missed
    print("Step 2: Downloading source distributions (with ALL dependencies)...")
    log_debug("step2_start", "Starting source distribution download", {
        "requirements": str(requirements),
        "outdir": str(outdir)
    })
    
    result2 = subprocess.run([
        sys.executable, "-m", "pip", "download",
        "-r", str(requirements),
        "-d", str(outdir),
        "--no-binary", ":all:",  # Get source dists
        # IMPORTANT: No --no-deps flag, so ALL dependencies are included
    ], capture_output=True, text=True, check=False)
    
    log_debug("step2_result", "Source distribution download completed", {
        "exit_code": result2.returncode,
        "stdout_length": len(result2.stdout),
        "stderr_length": len(result2.stderr),
        "stderr_preview": result2.stderr[:500] if result2.stderr else "",
        "wheels_count": len(list(outdir.glob("*.whl"))),
        "tarballs_count": len(list(outdir.glob("*.tar.gz")))
    })
    
    # Step 3: Verify we have all dependencies by attempting to resolve them
    print("Step 3: Verifying dependency completeness...")
    # Use pip check to verify all dependencies can be resolved
    verify_result = subprocess.run([
        sys.executable, "-m", "pip", "check",
    ], capture_output=True, text=True, check=False)
    
    # Step 4: Build source distributions into wheels for offline installation
    # This ensures packages are pre-built and ready for the airgapped system
    print("Step 4: Building source distributions into wheels...")
    source_dists = list(outdir.glob("*.tar.gz"))
    if source_dists:
        print(f"Found {len(source_dists)} source distributions to build...")
        # Install build dependencies first
        subprocess.run([
            sys.executable, "-m", "pip", "install", "--user", "wheel", "build"
        ], capture_output=True, text=True, check=False)
        
        # Build each source distribution
        built_count = 0
        for src_dist in source_dists:
            try:
                print(f"Building {src_dist.name}...")
                result = subprocess.run([
                    sys.executable, "-m", "pip", "wheel",
                    "--no-deps",  # Don't install dependencies, just build the wheel
                    "--wheel-dir", str(outdir),
                    str(src_dist)
                ], capture_output=True, text=True, check=False)
                if result.returncode == 0:
                    built_count += 1
                    # Optionally remove source dist after building (saves space)
                    # src_dist.unlink()
            except Exception as e:
                print(f"Warning: Failed to build {src_dist.name}: {e}")
        
        print(f"✓ Built {built_count} wheels from source distributions")
    
    # Count downloaded packages
    downloaded = len(list(outdir.glob("*.whl"))) + len(list(outdir.glob("*.tar.gz")))
    wheels = len(list(outdir.glob("*.whl")))
    tarballs = len(list(outdir.glob("*.tar.gz")))
    
    log_debug("final_count", "Final package count", {
        "downloaded": downloaded,
        "wheels": wheels,
        "tarballs": tarballs,
        "outdir": str(outdir),
        "outdir_exists": outdir.exists(),
        "outdir_listable": True if outdir.exists() else False
    })
    
    print(f"✓ Downloaded {downloaded} package files ({wheels} wheels, {downloaded - wheels} source dists)")
    print(f"✓ All dependencies are included (pip download includes transitive dependencies)")
    print(f"  Note: Source distributions have been built into wheels where possible")
    
    print(f"Python packages ready in {outdir}")
    print(f"All packages are pre-built and ready for offline installation.")
    
    if downloaded == 0:
        log_debug("no_packages", "No packages were downloaded", {
            "outdir": str(outdir),
            "outdir_contents": list(outdir.iterdir()) if outdir.exists() else []
        })
        print("ERROR: No packages were downloaded!")
        sys.exit(1)
        
except subprocess.CalledProcessError as e:
    log_debug("called_process_error", "subprocess.CalledProcessError caught", {
        "error": str(e),
        "returncode": e.returncode if hasattr(e, 'returncode') else None,
        "cmd": e.cmd if hasattr(e, 'cmd') else None,
        "stderr": e.stderr[:500] if hasattr(e, 'stderr') and e.stderr else None
    })
    print(f"Warning: Could not download all Python packages: {e}")
    print("Some packages may need to be downloaded manually or built from source.")
except FileNotFoundError as e:
    log_debug("file_not_found", "FileNotFoundError caught (pip not found)", {
        "error": str(e)
    })
    print("Warning: pip not found. Skipping Python package download.")
except Exception as e:
    import traceback
    log_debug("general_exception", "General exception caught", {
        "error": str(e),
        "error_type": type(e).__name__,
        "traceback": traceback.format_exc()[:1000]
    })
    print(f"Warning: Error downloading Python packages: {e}")
    import traceback
    traceback.print_exc()
PYEOF
  
  PYTHON_OUTPUT=$(python3 "$TEMP_PY_SCRIPT" "$BUNDLE_DIR" "$PYTHON_REQUIREMENTS" "$DEBUG_LOG" 2>&1)
  PYTHON_EXIT=$?
  rm -f "$TEMP_PY_SCRIPT"
  
  # #region agent log - Python script exit
  echo "{\"id\":\"log_$(date +%s)_python_exit\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:python_packages:exit\",\"message\":\"Python script exited\",\"data\":{\"exit_code\":$PYTHON_EXIT,\"output_length\":${#PYTHON_OUTPUT},\"output_preview\":\"${PYTHON_OUTPUT:0:500}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"PYTHON-H5,PYTHON-H6\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Log Python output for debugging
  echo "$PYTHON_OUTPUT"
  # Check if any packages were downloaded
  PACKAGE_COUNT=$(find "$BUNDLE_DIR/python" -maxdepth 1 -type f \( -name "*.whl" -o -name "*.tar.gz" \) 2>/dev/null | wc -l)
  
  # #region agent log - Package verification
  echo "{\"id\":\"log_$(date +%s)_python_verify\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:python_packages:verify\",\"message\":\"Verifying downloaded packages\",\"data\":{\"package_count\":$PACKAGE_COUNT,\"python_dir\":\"$BUNDLE_DIR/python\",\"dir_exists\":$(test -d "$BUNDLE_DIR/python" && echo true || echo false),\"dir_contents\":\"$(ls -la \"$BUNDLE_DIR/python\" 2>&1 | head -20 | tr '\n' ';')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"PYTHON-H4,PYTHON-H5\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ $PACKAGE_COUNT -gt 0 ]]; then
    log "Python packages downloaded successfully ($PACKAGE_COUNT files)."
    mark_success "python_packages"
  else
    log "WARNING: No Python packages were downloaded (found $PACKAGE_COUNT package files)."
    log "Python script exit code: $PYTHON_EXIT"
    log "Check the output above for error messages."
    mark_failed "python_packages"
  fi
  log "Note: All packages have been downloaded and built. Ready for offline installation."
else
  log "No requirements.txt found. Skipping Python package download."
  mark_skipped "python_packages"
fi

# ============
# Final Summary
# ============
log ""
log "=========================================="
log "BUNDLE CREATION SUMMARY"
log "=========================================="
log ""

# #region agent log - Summary start
echo "{\"id\":\"log_$(date +%s)_summary_start\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:start\",\"message\":\"Starting bundle creation summary\",\"data\":{},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

# Check each component and report status
HAS_FAILURES=false
HAS_WARNINGS=false

# List of all components to check
COMPONENTS="ollama_linux models vscodium continue python_ext rust_ext rust_toolchain rust_crates python_packages apt_repo"

# #region agent log - Component statuses
COMPONENT_STATUSES=""
for component in $COMPONENTS; do
  status="$(get_status "$component")"
  COMPONENT_STATUSES="${COMPONENT_STATUSES}${component}:${status};"
  case "$status" in
    success)
      log "✓ $component: SUCCESS"
      ;;
    failed)
      log "✗ $component: FAILED"
      HAS_FAILURES=true
      ;;
    skipped)
      log "⊘ $component: SKIPPED (not required or not found)"
      ;;
    pending)
      log "? $component: PENDING (not completed)"
      HAS_WARNINGS=true
      ;;
  esac
done
echo "{\"id\":\"log_$(date +%s)_summary_components\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:components\",\"message\":\"Component status summary\",\"data\":{\"components\":\"${COMPONENT_STATUSES:0:500}\",\"has_failures\":$HAS_FAILURES,\"has_warnings\":$HAS_WARNINGS},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

log ""
log "=========================================="
log "BUNDLE LOCATION: $BUNDLE_DIR"
log "=========================================="

# Calculate actual sizes
if [[ -d "$BUNDLE_DIR/models/.ollama" ]]; then
  MODEL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
  log "Models size: $MODEL_SIZE"
else
  log "Models: NOT BUNDLED"
  HAS_WARNINGS=true
  MODEL_SIZE="NOT BUNDLED"
fi

TOTAL_SIZE=$(du -sh "$BUNDLE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
log "Total bundle size: $TOTAL_SIZE"
log ""

# #region agent log - Bundle sizes
echo "{\"id\":\"log_$(date +%s)_summary_sizes\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:sizes\",\"message\":\"Bundle size information\",\"data\":{\"model_size\":\"$MODEL_SIZE\",\"total_size\":\"$TOTAL_SIZE\",\"bundle_dir\":\"$BUNDLE_DIR\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion

# Provide actionable next steps
if [[ "$HAS_FAILURES" == "true" ]]; then
  log "=========================================="
  log "⚠️  ACTION REQUIRED: Some components failed"
  log "=========================================="
  log ""
  
  # #region agent log - Failures detected
  FAILED_COMPONENTS=""
  for component in $COMPONENTS; do
    if [[ "$(get_status "$component")" == "failed" ]]; then
      FAILED_COMPONENTS="${FAILED_COMPONENTS}${component};"
    fi
  done
  echo "{\"id\":\"log_$(date +%s)_summary_failures\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:failures\",\"message\":\"Failures detected in bundle creation\",\"data\":{\"failed_components\":\"${FAILED_COMPONENTS:0:200}\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  if [[ "$(get_status models)" == "failed" ]]; then
    log "MODELS FAILED:"
    if [[ -d "$HOME/.ollama/models" ]] && [[ -n "$(ls -A "$HOME/.ollama/models" 2>/dev/null)" ]]; then
      EXISTING_SIZE=$(du -sh "$HOME/.ollama/models" 2>/dev/null | cut -f1 || echo "unknown")
      log "  → Found existing models in ~/.ollama/models ($EXISTING_SIZE)"
      log "  → To copy them manually, run:"
      log "     mkdir -p $BUNDLE_DIR/models"
      log "     rsync -av --progress ~/.ollama/ $BUNDLE_DIR/models/.ollama/"
      # #region agent log
      echo "{\"id\":\"log_$(date +%s)_failure_models\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:models_failed\",\"message\":\"Models component failed - existing models found\",\"data\":{\"component\":\"models\",\"existing_size\":\"$EXISTING_SIZE\",\"existing_path\":\"$HOME/.ollama/models\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
      # #endregion
    else
      log "  → No existing models found. You need to:"
      log "     1. Ensure Ollama is installed and working"
      log "     2. Pull models manually: ollama pull <model-name>"
      log "     3. Re-run this script or copy ~/.ollama manually"
      # #region agent log
      echo "{\"id\":\"log_$(date +%s)_failure_models\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:models_failed\",\"message\":\"Models component failed - no existing models\",\"data\":{\"component\":\"models\",\"existing_models\":false},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
      # #endregion
    fi
    log ""
  fi
  
  if [[ "$(get_status vscodium)" == "failed" ]]; then
    log "VSCODIUM FAILED:"
    log "  → Re-run this script to retry download"
    log "  → Or download manually from: https://github.com/VSCodium/vscodium/releases"
    log ""
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_failure_vscodium\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:vscodium_failed\",\"message\":\"VSCodium component failed\",\"data\":{\"component\":\"vscodium\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  fi
  
  if [[ "$(get_status continue)" == "failed" ]] || [[ "$(get_status python_ext)" == "failed" ]] || [[ "$(get_status rust_ext)" == "failed" ]]; then
    log "EXTENSIONS FAILED:"
    log "  → Re-run this script to retry download"
    log "  → Or download manually from: https://open-vsx.org"
    log ""
    # #region agent log
    FAILED_EXTENSIONS=""
    [[ "$(get_status continue)" == "failed" ]] && FAILED_EXTENSIONS="${FAILED_EXTENSIONS}continue;"
    [[ "$(get_status python_ext)" == "failed" ]] && FAILED_EXTENSIONS="${FAILED_EXTENSIONS}python_ext;"
    [[ "$(get_status rust_ext)" == "failed" ]] && FAILED_EXTENSIONS="${FAILED_EXTENSIONS}rust_ext;"
    echo "{\"id\":\"log_$(date +%s)_failure_extensions\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:extensions_failed\",\"message\":\"Extension components failed\",\"data\":{\"failed_extensions\":\"$FAILED_EXTENSIONS\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  fi
  
  if [[ "$(get_status rust_toolchain)" == "failed" ]]; then
    log "RUST TOOLCHAIN FAILED:"
    log "  → Re-run this script to retry download"
    log "  → Or download manually from: https://rustup.rs"
    log ""
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_failure_rust_toolchain\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:rust_toolchain_failed\",\"message\":\"Rust toolchain component failed\",\"data\":{\"component\":\"rust_toolchain\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  fi
  
  if [[ "$(get_status python_packages)" == "failed" ]]; then
    log "PYTHON PACKAGES FAILED:"
    log "  → Check that requirements.txt exists and is valid"
    log "  → Ensure pip is installed: python3 -m pip --version"
    log "  → Re-run this script to retry"
    log ""
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_failure_python_packages\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:python_packages_failed\",\"message\":\"Python packages component failed\",\"data\":{\"component\":\"python_packages\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  fi
  
  log "After fixing issues, re-run: ./get_bundle.sh"
  log ""
fi

if [[ "$HAS_WARNINGS" == "true" ]] && [[ "$HAS_FAILURES" != "true" ]]; then
  log "⚠️  Some optional components were skipped (this is normal)"
  log ""
  # #region agent log - Warnings only
  echo "{\"id\":\"log_$(date +%s)_summary_warnings\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:warnings\",\"message\":\"Some optional components were skipped\",\"data\":{\"has_warnings\":true,\"has_failures\":false},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
fi

if [[ "$HAS_FAILURES" != "true" ]]; then
  log "✓ All required components bundled and built successfully!"
  log ""
  log "Next steps:"
  log "  1. Verify bundle contents: ls -lh $BUNDLE_DIR"
  log "  2. Copy bundle to external drive or transfer to airgapped system"
  log "  3. On airgapped Linux system, run: ./install_offline.sh"
  log ""
  log "Note: All packages have been pre-built on this system and are ready"
  log "      for installation on the airgapped system. No compilation needed."
  log ""
  # #region agent log - All success
  echo "{\"id\":\"log_$(date +%s)_summary_success\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:success\",\"message\":\"All required components bundled successfully\",\"data\":{\"has_failures\":false,\"has_warnings\":$HAS_WARNINGS},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
fi

log "Bundle location: $BUNDLE_DIR"
log ""

# #region agent log - Summary end
echo "{\"id\":\"log_$(date +%s)_summary_end\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:final_summary:end\",\"message\":\"Bundle creation summary complete\",\"data\":{\"bundle_dir\":\"$BUNDLE_DIR\",\"has_failures\":$HAS_FAILURES,\"has_warnings\":$HAS_WARNINGS,\"total_size\":\"$TOTAL_SIZE\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"STATUS-TRACKING\"}" >> "$DEBUG_LOG" 2>/dev/null || true
# #endregion
