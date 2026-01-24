#!/usr/bin/env bash
# Use set -eo pipefail but allow controlled failures
# Note: -u (unbound variables) is removed for bash 3.2 compatibility
set -eo pipefail

# ============
# Logging Helper Function
# ============
debug_log() {
  local location="$1"
  local message="$2"
  local data="$3"
  local hypothesis_id="${4:-GENERAL}"
  local run_id="${5:-run1}"
  local session_id="${6:-debug-session}"
  
  # #region agent log
  local timestamp=$(date +%s)
  local log_entry="{\"id\":\"log_${timestamp}_$$\",\"timestamp\":${timestamp}000,\"location\":\"$location\",\"message\":\"$message\",\"data\":$data,\"sessionId\":\"$session_id\",\"runId\":\"$run_id\",\"hypothesisId\":\"$hypothesis_id\"}"
  # Use DEBUG_LOG if set, otherwise try to use BUNDLE_DIR if available, fallback to /tmp
  local log_file="${DEBUG_LOG:-${BUNDLE_DIR:-/tmp}/logs/debug.log}"
  # Ensure log directory exists
  mkdir -p "$(dirname "$log_file")" 2>/dev/null || true
  echo "$log_entry" >> "$log_file" 2>/dev/null || true
  # #endregion
}

# ============
# IMPORTANT: This script MUST be run on a machine WITH INTERNET ACCESS
# ============
# This script downloads all components from the internet and creates a bundle.
# The bundle is then transferred to the airgapped machine where install_offline.sh is run.
#
# Workflow:
#   1. Run get_bundle.sh on Pop!_OS/Ubuntu/Debian WITH internet (this script)
#   2. Transfer the bundle to the airgapped Intel Linux machine
#   3. Run install_offline.sh on the airgapped machine (no internet needed)
# ============

# ============
# OS Detection - This script requires Linux (Pop!_OS/Debian/Ubuntu)
# ============
OS="$(uname -s)"

# #region agent log
debug_log "get_bundle.sh:start" "Script started" "{\"os\":\"$OS\",\"pid\":$$,\"user\":\"$USER\",\"pwd\":\"$PWD\"}" "INIT-A" "run1"
# #endregion

if [[ "$OS" != "Linux" ]]; then
  # #region agent log
  debug_log "get_bundle.sh:os_check" "OS check failed - not Linux" "{\"detected_os\":\"$OS\",\"required_os\":\"Linux\"}" "INIT-B" "run1"
  # #endregion
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

# #region agent log
debug_log "get_bundle.sh:os_check" "OS check passed - Linux detected" "{\"os\":\"$OS\"}" "INIT-A" "run1"
# #endregion

IS_LINUX=true
log() {
  # GNU date (Linux)
  # Output goes to both console (via tee) and console log file
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
  eval "STATUS_$1=\"success\""
}

mark_failed() {
  eval "STATUS_$1=\"failed\""
}

mark_skipped() {
  eval "STATUS_$1=\"skipped\""
}

get_status() {
  eval "echo \"\$STATUS_$1\""
}

# ============
# Command-line argument parsing
# ============
SKIP_VERIFICATION="${SKIP_VERIFICATION:-false}"
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-verification)
      SKIP_VERIFICATION="true"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--skip-verification]"
      echo ""
      echo "Options:"
      echo "  --skip-verification    Skip SHA256 verification of downloads. If files exist,"
      echo "                        accept them without verification."
      echo "  --help, -h             Show this help message"
      echo ""
      echo "Environment Variables:"
      echo "  SKIP_VERIFICATION     Set to 'true' to skip verification (same as --skip-verification flag)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# ============
# Config
# ============
BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"
ARCH="amd64"
# Debug log path - use bundle directory which works on both Mac and Linux
DEBUG_LOG="${DEBUG_LOG:-$BUNDLE_DIR/logs/debug.log}"
# Console log path - captures all console output
CONSOLE_LOG="${CONSOLE_LOG:-$BUNDLE_DIR/logs/console.log}"
# Ensure log directories exist
mkdir -p "$(dirname "$DEBUG_LOG")" "$(dirname "$CONSOLE_LOG")" 2>/dev/null || true

# Store script start directory for cleanup operations
# We'll change to BUNDLE_DIR when running commands that might create files
SCRIPT_START_DIR="$PWD"

# #region agent log
debug_log "get_bundle.sh:config" "Configuration initialized" "{\"bundle_dir\":\"$BUNDLE_DIR\",\"arch\":\"$ARCH\",\"debug_log\":\"$DEBUG_LOG\",\"console_log\":\"$CONSOLE_LOG\"}" "INIT-C" "run1"
# #endregion

# Check network connectivity (this script requires internet access)
log "Checking network connectivity..."
if command -v curl >/dev/null 2>&1; then
  if curl -s --max-time 5 --connect-timeout 5 https://api.github.com >/dev/null 2>&1; then
    log "✓ Network connectivity OK"
    # #region agent log
    debug_log "get_bundle.sh:network_check" "Network connectivity verified" "{\"status\":\"ok\"}" "NETWORK-A" "run1"
    # #endregion
  else
    log "⚠️  WARNING: Cannot reach GitHub API. This script requires internet access."
    log "⚠️  If you're on an airgapped machine, you need to run get_bundle.sh on a machine WITH internet first."
    log "⚠️  The bundle created by get_bundle.sh is then transferred to the airgapped machine."
    # #region agent log
    debug_log "get_bundle.sh:network_check" "Network connectivity failed" "{\"status\":\"failed\",\"note\":\"script_requires_internet\"}" "NETWORK-B" "run1"
    # #endregion
  fi
elif command -v wget >/dev/null 2>&1; then
  if wget -q --spider --timeout=5 --tries=1 https://api.github.com 2>/dev/null; then
    log "✓ Network connectivity OK"
    # #region agent log
    debug_log "get_bundle.sh:network_check" "Network connectivity verified" "{\"status\":\"ok\"}" "NETWORK-A" "run1"
    # #endregion
  else
    log "⚠️  WARNING: Cannot reach GitHub API. This script requires internet access."
    log "⚠️  If you're on an airgapped machine, you need to run get_bundle.sh on a machine WITH internet first."
    log "⚠️  The bundle created by get_bundle.sh is then transferred to the airgapped machine."
    # #region agent log
    debug_log "get_bundle.sh:network_check" "Network connectivity failed" "{\"status\":\"failed\",\"note\":\"script_requires_internet\"}" "NETWORK-B" "run1"
    # #endregion
  fi
else
  log "⚠️  WARNING: Cannot check network connectivity (curl/wget not found). Proceeding anyway..."
  # #region agent log
  debug_log "get_bundle.sh:network_check" "Network check skipped - no tools available" "{\"status\":\"skipped\"}" "NETWORK-C" "run1"
  # #endregion
fi
log ""

# Set up console logging - redirect stdout and stderr to both console and log file
# This ensures all output goes to both screen and log file
# Note: This must be after BUNDLE_DIR is set and log directory is created
if [[ -n "$CONSOLE_LOG" ]]; then
  # Initialize console log file
  touch "$CONSOLE_LOG" 2>/dev/null || true
  # Redirect all output to both console and log file using tee
  exec > >(tee -a "$CONSOLE_LOG") 2>&1
  echo "=========================================="
  echo "Console output is being logged to: $CONSOLE_LOG"
  echo "Debug logs (JSON) are being logged to: $DEBUG_LOG"
  echo "=========================================="
  echo ""
fi
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

mkdir -p \
  "$BUNDLE_DIR"/{ollama,models,vscodium,continue,extensions,aptrepo/{pool,conf,_tmp},rust/{toolchain,crates},python,logs}

# Set OLLAMA_HOME to bundle directory so all Ollama data goes under airgap_bundle
# This ensures models and temp files are stored in the bundle, not in ~/.ollama or current directory
export OLLAMA_HOME="$BUNDLE_DIR/ollama/.ollama_home"
mkdir -p "$OLLAMA_HOME"

# #region agent log
debug_log "get_bundle.sh:init_dirs" "Bundle directories created" "{\"bundle_dir\":\"$BUNDLE_DIR\",\"dirs_created\":true}" "INIT-D" "run1"
# #endregion

sha256_check_file() {
  local file="$1"
  local sha_file="$2"
  
  # #region agent log
  debug_log "get_bundle.sh:sha256_check_file:entry" "SHA256 check started" "{\"file\":\"$file\",\"sha_file\":\"$sha_file\",\"skip_verification\":\"$SKIP_VERIFICATION\"}" "SHA-A" "run1"
  # #endregion
  
  # Check if file was verified in a previous run
  local verified_marker="${file}.verified"
  if [[ -f "$verified_marker" ]]; then
    log "File $(basename "$file") was verified in a previous run. Skipping verification."
    # #region agent log
    debug_log "get_bundle.sh:sha256_check_file:previously_verified" "File was verified previously" "{\"file\":\"$file\",\"verified_marker\":\"$verified_marker\",\"verified_date\":\"$(cat "$verified_marker" 2>/dev/null || echo 'unknown')\"}" "SHA-A" "run1"
    # #endregion
    return 0
  fi
  
  # Skip verification if flag is set
  if [[ "$SKIP_VERIFICATION" == "true" ]]; then
    if [[ -f "$file" ]]; then
      log "Skipping verification (--skip-verification flag set). Accepting existing file: $(basename "$file")"
      # #region agent log
      debug_log "get_bundle.sh:sha256_check_file:skipped" "SHA256 check skipped" "{\"file\":\"$file\",\"reason\":\"skip_verification_flag\"}" "SHA-A" "run1"
      # #endregion
      return 0
    else
      log "ERROR: File not found: $file"
      return 1
    fi
  fi
  
  if command -v sha256sum >/dev/null 2>&1; then
    local result
    result=$(cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")" 2>&1)
    local exit_code=$?
    
    # #region agent log
    debug_log "get_bundle.sh:sha256_check_file:result" "SHA256 check completed" "{\"file\":\"$file\",\"exit_code\":$exit_code,\"result\":\"${result:0:200}\"}" "SHA-A" "run1"
    # #endregion
    
    # If verification succeeded, create a marker file to indicate this file was verified
    if [[ $exit_code -eq 0 ]]; then
      local verified_marker="${file}.verified"
      echo "$(date -Is)" > "$verified_marker" 2>/dev/null || true
    fi
    
    return $exit_code
  else
    # #region agent log
    debug_log "get_bundle.sh:sha256_check_file:error" "sha256sum command not found" "{\"file\":\"$file\"}" "SHA-B" "run1"
    # #endregion
    log "ERROR: sha256sum not found. This script requires Linux with standard tools."
    exit 1
  fi
}

# Verify VSIX file - Open VSX returns just the hash, so we need to format it
sha256_check_vsix() {
  local file="$1"
  local sha_file="$2"
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_vsix1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:entry\",\"message\":\"VSIX verification started\",\"data\":{\"file\":\"$file\",\"sha_file\":\"$sha_file\",\"skip_verification\":\"$SKIP_VERIFICATION\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Check if file was verified in a previous run
  local verified_marker="${file}.verified"
  if [[ -f "$verified_marker" ]]; then
    log "File $(basename "$file") was verified in a previous run. Skipping verification."
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_vsix_prev\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:previously_verified\",\"message\":\"VSIX was verified previously\",\"data\":{\"file\":\"$file\",\"verified_marker\":\"$verified_marker\",\"verified_date\":\"$(cat "$verified_marker" 2>/dev/null || echo 'unknown')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    return 0
  fi
  
  # Skip verification if flag is set
  if [[ "$SKIP_VERIFICATION" == "true" ]]; then
    if [[ -f "$file" ]]; then
      log "Skipping verification (--skip-verification flag set). Accepting existing file: $(basename "$file")"
      # #region agent log
      echo "{\"id\":\"log_$(date +%s)_vsix_skip\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:sha256_check_vsix:skipped\",\"message\":\"VSIX verification skipped\",\"data\":{\"file\":\"$file\",\"reason\":\"skip_verification_flag\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"VSIX-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
      # #endregion
      return 0
    else
      log "ERROR: VSIX file not found: $file"
      return 1
    fi
  fi
  
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
    # If verification succeeded, create a marker file to indicate this file was verified
    local verified_marker="${file}.verified"
    echo "$(date -Is)" > "$verified_marker" 2>/dev/null || true
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
# Note: Ollama now uses .tar.zst format instead of .tgz
# We'll determine the actual filename from the GitHub API response
OLLAMA_ARCHIVE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst"
OLLAMA_TGZ="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz"  # Legacy name for compatibility
OLLAMA_SHA="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst.sha256"

# Check for existing Ollama archive (try both .tar.zst and .tgz for compatibility)
OLLAMA_EXISTING=""
if [[ -f "$OLLAMA_ARCHIVE" ]]; then
  OLLAMA_EXISTING="$OLLAMA_ARCHIVE"
elif [[ -f "$OLLAMA_TGZ" ]]; then
  OLLAMA_EXISTING="$OLLAMA_TGZ"
fi

# #region agent log
debug_log "get_bundle.sh:ollama:check_existing" "Checking for existing Ollama binary" "{\"archive\":\"$OLLAMA_ARCHIVE\",\"tgz\":\"$OLLAMA_TGZ\",\"sha\":\"$OLLAMA_SHA\",\"archive_exists\":$(test -f "$OLLAMA_ARCHIVE" && echo true || echo false),\"tgz_exists\":$(test -f "$OLLAMA_TGZ" && echo true || echo false),\"sha_exists\":$(test -f "$OLLAMA_SHA" && echo true || echo false)}" "OLLAMA-A" "run1"
# #endregion

# Check if file already exists and is valid
if [[ -n "$OLLAMA_EXISTING" ]]; then
  if [[ "$SKIP_VERIFICATION" == "true" ]]; then
    log "Ollama Linux binary already exists. Skipping verification (--skip-verification flag set)."
    mark_success "ollama_linux"
    OLLAMA_DL_STATUS=0
    # #region agent log
    debug_log "get_bundle.sh:ollama:existing_skipped" "Existing Ollama binary accepted without verification" "{\"status\":\"success\",\"file\":\"$OLLAMA_EXISTING\",\"skip_verification\":true}" "OLLAMA-A" "run1"
    # #endregion
  elif [[ -f "$OLLAMA_SHA" ]]; then
    log "Ollama Linux binary already exists, verifying..."
    if sha256_check_file "$OLLAMA_EXISTING" "$OLLAMA_SHA"; then
      log "Ollama already downloaded and verified. Skipping download."
      mark_success "ollama_linux"
      OLLAMA_DL_STATUS=0
      # #region agent log
      debug_log "get_bundle.sh:ollama:existing_valid" "Existing Ollama binary verified" "{\"status\":\"success\",\"file\":\"$OLLAMA_EXISTING\"}" "OLLAMA-A" "run1"
      # #endregion
    else
      log "Existing Ollama file failed verification. Re-downloading..."
      # #region agent log
      debug_log "get_bundle.sh:ollama:existing_invalid" "Existing Ollama binary failed verification" "{\"status\":\"failed_verification\",\"file\":\"$OLLAMA_EXISTING\"}" "OLLAMA-B" "run1"
      # #endregion
      rm -f "$OLLAMA_EXISTING" "$OLLAMA_SHA" "$OLLAMA_TGZ" "$OLLAMA_ARCHIVE" "${OLLAMA_EXISTING}.verified"
      OLLAMA_DL_STATUS=1
    fi
  else
    # File exists but no SHA - if skip flag is not set, we need to download to verify
    if [[ "$SKIP_VERIFICATION" != "true" ]]; then
      OLLAMA_DL_STATUS=1
      # #region agent log
      debug_log "get_bundle.sh:ollama:no_sha" "Ollama binary exists but no SHA file, will download to verify" "{\"status\":\"no_sha\"}" "OLLAMA-A" "run1"
      # #endregion
    fi
  fi
else
  OLLAMA_DL_STATUS=1
  # #region agent log
  debug_log "get_bundle.sh:ollama:not_found" "Ollama binary not found, will download" "{\"status\":\"not_found\"}" "OLLAMA-A" "run1"
  # #endregion
fi

if [[ $OLLAMA_DL_STATUS -ne 0 ]]; then
  log "Fetching Ollama latest release metadata and linux-amd64 tarball..."
  
  # #region agent log
  debug_log "get_bundle.sh:ollama:download_start" "Starting Ollama download" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "OLLAMA-C" "run1"
  # #endregion
  
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, hashlib, time, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"ollama"
outdir.mkdir(parents=True, exist_ok=True)
debug_log = os.environ.get("DEBUG_LOG", str(bundle/"logs"/"debug.log"))

def urlopen_with_retry(url, max_retries=3, timeout=30):
    """Open URL with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            response = urllib.request.urlopen(request, timeout=timeout)
            return response
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt  # Exponential backoff
                print(f"Attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
            else:
                print(f"ERROR: All {max_retries} attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=60):
    """Download file with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with open(filename, 'wb') as f:
                    f.write(response.read())
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Download attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
                # Remove partial file if it exists
                if os.path.exists(filename):
                    os.remove(filename)
            else:
                print(f"ERROR: All {max_retries} download attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

try:
    # GitHub API endpoint for latest release
    # Format: https://api.github.com/repos/{owner}/{repo}/releases/latest
    api = "https://api.github.com/repos/ollama/ollama/releases/latest"
    print(f"Fetching release metadata from GitHub API...")
    print(f"API URL: {api}")
    print(f"Note: This requires internet access. If this fails, ensure you're running get_bundle.sh on a machine WITH internet.")
    print(f"Verifying API endpoint is accessible...")
    
    # Try a simple connectivity test first
    try:
        test_response = urllib.request.urlopen(urllib.request.Request("https://api.github.com", headers={'User-Agent': 'get_bundle.sh/1.0'}), timeout=5)
        print(f"✓ GitHub API is reachable")
    except Exception as e:
        print(f"⚠️  WARNING: Cannot reach GitHub API: {e}")
        print(f"⚠️  This script requires internet access to download Ollama.")
        print(f"⚠️  Please ensure you're running this on a machine WITH internet connection.")
    
    response = urlopen_with_retry(api, max_retries=3, timeout=30)
    response_data = response.read().decode("utf-8")
    
    # Log response size for debugging
    print(f"API response received ({len(response_data)} bytes)")
    
    data = json.loads(response_data)
    
    # Log API response structure for debugging
    print(f"API Response received. Keys: {list(data.keys())}")
    if "tag_name" in data:
        print(f"Release tag: {data['tag_name']}")
    if "name" in data:
        print(f"Release name: {data['name']}")
    
    # Log available assets for debugging
    if "assets" in data:
        asset_names = [a["name"] for a in data["assets"]]
        print(f"Available assets ({len(asset_names)} total): {asset_names[:15]}")
        
        # Log asset details for the target file
        for asset in data["assets"]:
            if "ollama-linux-amd64" in asset.get("name", ""):
                print(f"Found matching asset: {asset['name']}")
                print(f"  Size: {asset.get('size', 'unknown')} bytes")
                print(f"  Download URL: {asset.get('browser_download_url', 'N/A')}")
    else:
        print(f"WARNING: No 'assets' key in API response.")
        print(f"Response preview: {str(data)[:500]}")
        raise SystemExit("API response missing 'assets' key. Response structure may have changed.")
    
    # Ollama now uses .tar.zst format (previously .tgz)
    # IMPORTANT: For Intel x86_64 machines, use standard amd64 build (NOT ROCm)
    # ROCm is only for AMD GPUs. Intel machines should use the standard build.
    target_name = None
    assets = {a["name"]: a["browser_download_url"] for a in data.get("assets", [])}
    
    # Priority order for Intel/AMD x86_64 CPUs:
    # 1. Standard .tar.zst (preferred for Intel machines)
    # 2. Legacy .tgz format
    # 3. ROCm .tar.zst (ONLY if standard versions not available - should not happen)
    preferred_names = [
        "ollama-linux-amd64.tar.zst",  # Standard version (CORRECT for Intel)
        "ollama-linux-amd64.tgz",      # Legacy format (also correct for Intel)
    ]
    
    # Try preferred names first (standard builds, no ROCm)
    for name in preferred_names:
        if name in assets:
            target_name = name
            print(f"Selected asset: {name} (standard build for Intel/AMD x86_64)")
            break
    
    # If standard builds not found, search for any non-ROCm amd64 build
    if not target_name:
        alternatives = [name for name in assets.keys() 
                       if "ollama" in name.lower() 
                       and "linux" in name.lower() 
                       and "amd64" in name.lower()
                       and "rocm" not in name.lower()]  # Explicitly exclude ROCm
        
        if alternatives:
            target_name = alternatives[0]
            print(f"Selected alternative (non-ROCm): {target_name}")
        else:
            # Last resort: check if ROCm is the only option (should warn user)
            rocm_alternatives = [name for name in assets.keys() 
                                if "ollama" in name.lower() 
                                and "linux" in name.lower() 
                                and "amd64" in name.lower()
                                and "rocm" in name.lower()]
            if rocm_alternatives:
                print("WARNING: Only ROCm version available. ROCm is for AMD GPUs.")
                print("WARNING: If you have an Intel machine, this may not work correctly.")
                print("WARNING: Consider using a different Ollama release or build.")
                target_name = rocm_alternatives[0]
                print(f"Using ROCm version as last resort: {target_name}")
            else:
                available = list(assets.keys())[:15] if assets else ["none"]
                raise SystemExit(f"Could not find suitable Ollama Linux amd64 asset. Available: {available}")
    
    url = assets[target_name]
    print(f"Ollama download URL: {url}")
    print(f"Target filename: {target_name}")
    
    # Download archive with retry
    archive = outdir/target_name
    print(f"Downloading {target_name} (this may take a while)...")
    urlretrieve_with_retry(url, str(archive), max_retries=3, timeout=600)  # Increased timeout for large files
    print(f"Download complete: {archive}")
except (urllib.error.URLError, TimeoutError, OSError) as e:
    print(f"ERROR: Network error downloading Ollama: {e}", file=sys.stderr)
    print(f"ERROR: This may indicate network connectivity issues.", file=sys.stderr)
    print(f"ERROR: The GitHub API URL being used is: https://api.github.com/repos/ollama/ollama/releases/latest", file=sys.stderr)
    print(f"ERROR: Please verify:", file=sys.stderr)
    print(f"  1. You have internet connectivity", file=sys.stderr)
    print(f"  2. GitHub is accessible (try: curl https://api.github.com)", file=sys.stderr)
    print(f"  3. No firewall/proxy is blocking GitHub", file=sys.stderr)
    print(f"  4. You're running get_bundle.sh on a machine WITH internet (not the airgapped machine)", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"ERROR: Failed to parse GitHub API response: {e}", file=sys.stderr)
    print(f"ERROR: The API response may have changed format or returned an error.", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Try to download official SHA256 file from GitHub releases first
sha_file = outdir/(target_name + ".sha256")
official_sha_url = None
if "sha256sum.txt" in assets:
    official_sha_url = assets["sha256sum.txt"]
    print(f"Found official SHA256 file in release, downloading...")
    try:
        sha_sum_file = outdir/"sha256sum.txt"
        urlretrieve_with_retry(official_sha_url, str(sha_sum_file), max_retries=3, timeout=60)
        # Extract hash for our specific file from sha256sum.txt
        with open(sha_sum_file, "r") as f:
            for line in f:
                if target_name in line:
                    # Format: hash  filename
                    parts = line.strip().split()
                    if len(parts) >= 2 and target_name in parts[1]:
                        official_hash = parts[0]
                        sha_file.write_text(f"{official_hash}  {target_name}\n", encoding="utf-8")
                        print(f"Using official SHA256 from release: {official_hash[:16]}...")
                        print(f"Wrote sha256 file: {sha_file}")
                        sha_sum_file.unlink()  # Remove temporary file
                        break
            else:
                print("WARNING: Official SHA256 file doesn't contain hash for our file, calculating our own...")
                official_sha_url = None  # Fall through to calculate our own
    except Exception as e:
        print(f"WARNING: Could not download official SHA256 file: {e}")
        print("Will calculate our own SHA256 hash instead...")
        official_sha_url = None

# If we didn't get official SHA256, calculate our own
if official_sha_url is None or not sha_file.exists():
    print("Calculating SHA256 hash of downloaded file...")
    sha256_hash = hashlib.sha256()
    with open(archive, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            sha256_hash.update(chunk)
    sha = sha256_hash.hexdigest()
    
    sha_file.write_text(f"{sha}  {target_name}\n", encoding="utf-8")
    print("Wrote sha256 file:", sha_file)
    print(f"SHA256: {sha}")
PY
  OLLAMA_DL_STATUS=$?
  
  # Find the actual downloaded file (could be .tar.zst or .tgz)
  OLLAMA_DOWNLOADED=""
  if [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst" ]]; then
    OLLAMA_DOWNLOADED="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst"
    OLLAMA_SHA="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst.sha256"
  elif [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" ]]; then
    OLLAMA_DOWNLOADED="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz"
    OLLAMA_SHA="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz.sha256"
  else
    # Find any ollama-linux-amd64 file
    OLLAMA_DOWNLOADED=$(find "$BUNDLE_DIR/ollama" -maxdepth 1 -name "ollama-linux-amd64*" -type f ! -name "*.sha256" 2>/dev/null | head -n1)
    if [[ -n "$OLLAMA_DOWNLOADED" ]]; then
      OLLAMA_SHA="${OLLAMA_DOWNLOADED}.sha256"
    fi
  fi
  
  # #region agent log
  debug_log "get_bundle.sh:ollama:download_complete" "Ollama download completed" "{\"exit_code\":$OLLAMA_DL_STATUS,\"downloaded_file\":\"$OLLAMA_DOWNLOADED\",\"file_exists\":$(test -f "$OLLAMA_DOWNLOADED" && echo true || echo false),\"sha_exists\":$(test -f "$OLLAMA_SHA" && echo true || echo false)}" "OLLAMA-C" "run1"
  # #endregion
  
  if [[ $OLLAMA_DL_STATUS -eq 0 ]] && [[ -n "$OLLAMA_DOWNLOADED" ]]; then
    log "Verifying Ollama sha256..."
    if sha256_check_file "$OLLAMA_DOWNLOADED" "$OLLAMA_SHA"; then
      log "Ollama verified."
      mark_success "ollama_linux"
      # #region agent log
      debug_log "get_bundle.sh:ollama:verify_success" "Ollama verification successful" "{\"status\":\"success\"}" "OLLAMA-C" "run1"
      # #endregion
    else
      log "ERROR: Ollama SHA256 verification failed"
      mark_failed "ollama_linux"
      # #region agent log
      debug_log "get_bundle.sh:ollama:verify_failed" "Ollama verification failed" "{\"status\":\"failed\"}" "OLLAMA-D" "run1"
      # #endregion
    fi
  else
    log "ERROR: Failed to download Ollama Linux binary"
    mark_failed "ollama_linux"
    # #region agent log
    debug_log "get_bundle.sh:ollama:download_failed" "Ollama download failed" "{\"exit_code\":$OLLAMA_DL_STATUS}" "OLLAMA-E" "run1"
    # #endregion
  fi
fi

# ============
# 2) Pull Ollama models, then copy ~/.ollama
# ============
# First, check for model directories in the script directory and copy them directly to final bundle location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Models go directly to final destination in bundle (not through OLLAMA_HOME temp location)
FINAL_MODEL_DIR="$BUNDLE_DIR/models/.ollama/models"
mkdir -p "$FINAL_MODEL_DIR"

# Look for model directories in the script directory (e.g., mistral:7b, mixtral:8x7b, etc.)
# These are Ollama model directories that should be copied directly to final bundle location
log "Checking for model directories in script directory: $SCRIPT_DIR"
for potential_model_dir in "$SCRIPT_DIR"/*; do
  if [[ -d "$potential_model_dir" ]] && [[ -n "$(basename "$potential_model_dir")" ]]; then
    MODEL_NAME=$(basename "$potential_model_dir")
    # Check if it looks like an Ollama model directory (has blobs subdirectory)
    if [[ -d "$potential_model_dir/blobs" ]] && [[ -n "$(ls -A "$potential_model_dir/blobs" 2>/dev/null)" ]]; then
      log "Found model directory: $MODEL_NAME"
      DEST_MODEL_DIR="$FINAL_MODEL_DIR/$MODEL_NAME"
      if [[ -d "$DEST_MODEL_DIR" ]]; then
        log "Model $MODEL_NAME already exists in bundle. Skipping copy."
      else
        if [[ "$MOVE_MODELS" == "true" ]]; then
          log "Moving model directory $MODEL_NAME directly to final bundle location..."
          if mv "$potential_model_dir" "$DEST_MODEL_DIR" 2>/dev/null; then
            log "Successfully moved $MODEL_NAME to bundle"
          else
            log "WARNING: Failed to move $MODEL_NAME, trying copy instead..."
            if cp -r "$potential_model_dir" "$DEST_MODEL_DIR" 2>/dev/null; then
              log "Successfully copied $MODEL_NAME to bundle"
            else
              log "ERROR: Failed to copy $MODEL_NAME to bundle"
            fi
          fi
        else
          log "Copying model directory $MODEL_NAME directly to final bundle location..."
          if cp -r "$potential_model_dir" "$DEST_MODEL_DIR" 2>/dev/null; then
            log "Successfully copied $MODEL_NAME to bundle"
          else
            log "ERROR: Failed to copy $MODEL_NAME to bundle"
          fi
        fi
      fi
    fi
  fi
done

# Convert space-separated models to array
read -ra MODEL_ARRAY <<< "$OLLAMA_MODELS"
MODEL_COUNT=${#MODEL_ARRAY[@]}

# #region agent log
debug_log "get_bundle.sh:models:init" "Model pulling initialized" "{\"model_count\":$MODEL_COUNT,\"models\":\"$OLLAMA_MODELS\",\"model_array\":\"${MODEL_ARRAY[*]}\"}" "MODEL-A" "run1"
# #endregion

log "Using Linux Ollama binary to pull $MODEL_COUNT model(s)..."

TMP_OLLAMA="$BUNDLE_DIR/ollama/_tmp_ollama"

# Check if extraction should be skipped
SKIP_EXTRACTION=false
if [[ "$SKIP_VERIFICATION" == "true" ]] && [[ -d "$TMP_OLLAMA" ]]; then
  # Check if binary already exists in extracted directory
  OLLAMA_BIN_CHECK=""
  if [[ -f "$TMP_OLLAMA/ollama" ]]; then
    OLLAMA_BIN_CHECK="$TMP_OLLAMA/ollama"
  elif [[ -f "$TMP_OLLAMA/ollama-linux-amd64/ollama" ]]; then
    OLLAMA_BIN_CHECK="$TMP_OLLAMA/ollama-linux-amd64/ollama"
  else
    OLLAMA_BIN_CHECK=$(find "$TMP_OLLAMA" -name "ollama" -type f 2>/dev/null | head -n1)
  fi
  
  if [[ -n "$OLLAMA_BIN_CHECK" ]] && [[ -f "$OLLAMA_BIN_CHECK" ]] && [[ -x "$OLLAMA_BIN_CHECK" ]]; then
    log "Ollama binary already extracted. Skipping extraction (--skip-verification flag set)."
    SKIP_EXTRACTION=true
    TAR_EXIT=0
  fi
fi

# Extract Linux Ollama binary (unless already extracted and skip flag is set)
if [[ "$SKIP_EXTRACTION" != "true" ]]; then
  rm -rf "$TMP_OLLAMA"
  mkdir -p "$TMP_OLLAMA"
  
  log "Extracting Ollama binary from archive..."
  
  # Find the actual archive file
  OLLAMA_ARCHIVE_FILE=""
  if [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst" ]]; then
    OLLAMA_ARCHIVE_FILE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tar.zst"
  elif [[ -f "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" ]]; then
    OLLAMA_ARCHIVE_FILE="$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz"
  else
    # Find any ollama-linux-amd64 archive
    OLLAMA_ARCHIVE_FILE=$(find "$BUNDLE_DIR/ollama" -maxdepth 1 -name "ollama-linux-amd64*" -type f ! -name "*.sha256" 2>/dev/null | head -n1)
  fi
  
  if [[ -z "$OLLAMA_ARCHIVE_FILE" ]] || [[ ! -f "$OLLAMA_ARCHIVE_FILE" ]]; then
    log "ERROR: Ollama archive not found in $BUNDLE_DIR/ollama/"
    log "Expected: ollama-linux-amd64.tar.zst or ollama-linux-amd64.tgz"
    SKIP_MODEL_PULL=true
  else
    log "Found Ollama archive: $OLLAMA_ARCHIVE_FILE"
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_ollama1\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:entry\",\"message\":\"Starting Ollama extraction\",\"data\":{\"archive\":\"$OLLAMA_ARCHIVE_FILE\",\"dest\":\"$TMP_OLLAMA\",\"archive_exists\":$(test -f "$OLLAMA_ARCHIVE_FILE" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  # Extract based on file type
  if [[ "$OLLAMA_ARCHIVE_FILE" == *.tar.zst ]]; then
    # Use zstd to decompress .tar.zst files
    if command -v zstd >/dev/null 2>&1 || command -v unzstd >/dev/null 2>&1; then
      ZSTD_CMD="zstd"
      command -v unzstd >/dev/null 2>&1 && ZSTD_CMD="unzstd"
      log "Extracting .tar.zst archive using $ZSTD_CMD..."
      log "This may take a few minutes for large archives..."
      # Use pipefail to catch errors in pipeline
      # Redirect output to a temp file to avoid buffering issues with large extractions
      # Use --no-same-owner and --no-same-permissions to avoid permission issues on network mounts
      TAR_OUTPUT_FILE="$BUNDLE_DIR/logs/extract_ollama.log"
      set -o pipefail 2>/dev/null || true
      # Extract and redirect output to file (don't capture in variable to avoid buffering)
      # Use tar options to ignore symlink timestamp errors (common on network mounts)
      if $ZSTD_CMD -dc "$OLLAMA_ARCHIVE_FILE" 2>&1 | tar --no-same-owner --no-same-permissions -xf - -C "$TMP_OLLAMA" >"$TAR_OUTPUT_FILE" 2>&1; then
        TAR_EXIT=0
      else
        TAR_EXIT=$?
      fi
      set +o pipefail 2>/dev/null || true
      
      # Read output from file for logging (limit size to avoid issues)
      if [[ -f "$TAR_OUTPUT_FILE" ]]; then
        TAR_OUTPUT=$(head -c 1000 "$TAR_OUTPUT_FILE" 2>/dev/null || echo "")
        # Clean up log file if extraction succeeded
        [[ $TAR_EXIT -eq 0 ]] && rm -f "$TAR_OUTPUT_FILE" 2>/dev/null || true
      else
        TAR_OUTPUT=""
      fi
      
      if [[ $TAR_EXIT -ne 0 ]]; then
        log "WARNING: Extraction exit code: $TAR_EXIT"
        if [[ -n "$TAR_OUTPUT" ]]; then
          log "Extraction output (first 500 chars): ${TAR_OUTPUT:0:500}"
        fi
        if [[ -f "$TAR_OUTPUT_FILE" ]]; then
          log "Full extraction log available at: $TAR_OUTPUT_FILE"
        fi
      else
        log "Extraction completed successfully"
      fi
    else
      log "ERROR: zstd or unzstd not found. Cannot extract .tar.zst file."
      log "Install zstd: sudo apt-get install zstd"
      SKIP_MODEL_PULL=true
      TAR_EXIT=1
    fi
  else
    # Standard .tgz extraction
    log "Extracting .tgz archive..."
    log "This may take a few minutes for large archives..."
    TAR_OUTPUT_FILE="$BUNDLE_DIR/logs/extract_ollama.log"
    # Use --no-same-owner and --no-same-permissions to avoid permission issues on network mounts
    if tar --no-same-owner --no-same-permissions -xzf "$OLLAMA_ARCHIVE_FILE" -C "$TMP_OLLAMA" >"$TAR_OUTPUT_FILE" 2>&1; then
      TAR_EXIT=0
    else
      TAR_EXIT=$?
    fi

    # Read output from file for logging
    if [[ -f "$TAR_OUTPUT_FILE" ]]; then
      TAR_OUTPUT=$(head -c 1000 "$TAR_OUTPUT_FILE" 2>/dev/null || echo "")
      # Clean up log file if extraction succeeded
      [[ $TAR_EXIT -eq 0 ]] && rm -f "$TAR_OUTPUT_FILE" 2>/dev/null || true
    else
      TAR_OUTPUT=""
    fi
    
    if [[ $TAR_EXIT -ne 0 ]]; then
      log "WARNING: Extraction exit code: $TAR_EXIT"
      if [[ -n "$TAR_OUTPUT" ]]; then
        log "Extraction output (first 500 chars): ${TAR_OUTPUT:0:500}"
      fi
      if [[ -f "$TAR_OUTPUT_FILE" ]]; then
        log "Full extraction log available at: $TAR_OUTPUT_FILE"
      fi
    else
      log "Extraction completed successfully"
    fi
  fi
  fi
  
  if [[ "$SKIP_EXTRACTION" != "true" ]]; then
    log "Extraction command finished with exit code: $TAR_EXIT"
    
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_ollama2\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:tar_result\",\"message\":\"Tar extraction completed\",\"data\":{\"exit_code\":$TAR_EXIT,\"output\":\"${TAR_OUTPUT:0:200}\",\"tmp_dir_contents\":\"$(ls -la "$TMP_OLLAMA" 2>&1 | head -10 | tr '\n' ';')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-A,OLLAMA-D\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
    
    # Check if extraction succeeded - even if exit code is non-zero, check if binary exists
    if [[ $TAR_EXIT -ne 0 ]]; then
      log "WARNING: Extraction command returned exit code $TAR_EXIT"
      log "Checking if extraction actually succeeded by looking for binary..."
      # Check if binary exists despite non-zero exit code (sometimes tar returns warnings as errors)
      if [[ -f "$TMP_OLLAMA/bin/ollama" ]] || find "$TMP_OLLAMA" -name "ollama" -type f 2>/dev/null | grep -q .; then
        log "Binary found despite non-zero exit code. Continuing..."
        TAR_EXIT=0  # Override exit code if binary exists
      else
        log "ERROR: Failed to extract Ollama tarball and binary not found"
        log "Tar output: ${TAR_OUTPUT:0:1000}"
        SKIP_MODEL_PULL=true
      fi
    fi
  else
    # Extraction was skipped, set TAR_EXIT to 0 since we're using existing binary
    TAR_EXIT=0
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_ollama2\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:skipped\",\"message\":\"Extraction skipped, using existing binary\",\"data\":{\"tmp_dir\":\"$TMP_OLLAMA\",\"skip_verification\":true},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-A\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  fi
fi

if [[ $TAR_EXIT -eq 0 ]]; then
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
    chmod +x "$OLLAMA_BIN"
    export PATH="$(dirname "$OLLAMA_BIN"):$PATH"
    log "Ollama binary found at: $OLLAMA_BIN"
    log "Updated PATH to include: $(dirname "$OLLAMA_BIN")"
    
    # Verify the binary is executable
    if [[ ! -x "$OLLAMA_BIN" ]]; then
      log "WARNING: Ollama binary is not executable, attempting to fix..."
      chmod +x "$OLLAMA_BIN" || log "ERROR: Failed to make binary executable"
    fi
    
    # #region agent log
    echo "{\"id\":\"log_$(date +%s)_ollama4\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:extract_ollama:path_set\",\"message\":\"PATH updated\",\"data\":{\"new_path\":\"$PATH\",\"ollama_bin_dir\":\"$(dirname "$OLLAMA_BIN")\",\"command_exists\":$(command -v ollama >/dev/null 2>&1 && echo true || echo false),\"binary_exists\":$(test -f "$OLLAMA_BIN" && echo true || echo false),\"binary_executable\":$(test -x "$OLLAMA_BIN" && echo true || echo false)},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-C\"}" >> "$DEBUG_LOG" 2>/dev/null || true
    # #endregion
  else
    log "ERROR: Could not find ollama binary in extracted tarball"
    log "Searching in: $TMP_OLLAMA"
    log "Contents of $TMP_OLLAMA:"
    ls -la "$TMP_OLLAMA" 2>&1 || true
    log "Searching recursively for 'ollama' binary:"
    find "$TMP_OLLAMA" -type f -name "*ollama*" 2>&1 | head -20 || true
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
# OLLAMA_HOME is set to $BUNDLE_DIR/ollama/.ollama_home so all data goes under airgap_bundle
log "Starting Ollama server to pull models..."
log "Ollama data will be stored in: $OLLAMA_HOME"
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
  
  # Change to bundle directory before starting server to ensure any artifacts go there
  OLD_PWD_SERVER="$PWD"
  cd "$BUNDLE_DIR" || cd "$OLD_PWD_SERVER" || true
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_ollama5\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:before_nohup\",\"message\":\"Before starting server\",\"data\":{\"ollama_cmd\":\"$OLLAMA_CMD\",\"cmd_exists\":$(test -f "$OLLAMA_CMD" && echo true || echo false),\"is_executable\":$(test -x "$OLLAMA_CMD" && echo true || echo false),\"path\":\"$PATH\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-C,OLLAMA-E\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  nohup "$OLLAMA_CMD" serve >"$BUNDLE_DIR/logs/ollama_serve.log" 2>&1 &
  
  # Restore directory
  cd "$OLD_PWD_SERVER" || true
  SERVE_PID=$!
  NOHUP_EXIT=$?
  
  # #region agent log
  echo "{\"id\":\"log_$(date +%s)_ollama6\",\"timestamp\":$(date +%s)000,\"location\":\"get_bundle.sh:start_server:after_nohup\",\"message\":\"After starting server\",\"data\":{\"serve_pid\":$SERVE_PID,\"nohup_exit\":$NOHUP_EXIT,\"process_exists\":$(kill -0 "$SERVE_PID" 2>/dev/null && echo true || echo false),\"log_content\":\"$(head -20 "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null | tr '\n' ';' || echo 'N/A')\"},\"sessionId\":\"debug-session\",\"runId\":\"run1\",\"hypothesisId\":\"OLLAMA-C,OLLAMA-E\"}" >> "$DEBUG_LOG" 2>/dev/null || true
  # #endregion
  
  log "Ollama server started with PID: $SERVE_PID"
  sleep 5  # Give server more time to start
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
# Note: SKIP_MODEL_PULL defaults to false (don't skip) unless explicitly set to true
if [[ "${SKIP_MODEL_PULL:-false}" != "true" ]]; then
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
  
  if [[ "${SKIP_MODEL_PULL:-false}" != "true" ]]; then
    log "Pulling $MODEL_COUNT model(s): ${OLLAMA_MODELS}"
    log "This may take a while, especially for large models like mixtral:8x7b (~26GB)..."
    log "Waiting for Ollama server to be ready..."
    
    # Wait for server to be ready by checking if it responds
    MAX_WAIT=30
    WAIT_COUNT=0
    while ! "$OLLAMA_CMD" list >/dev/null 2>&1 && [[ $WAIT_COUNT -lt $MAX_WAIT ]]; do
      sleep 1
      WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    
    if [[ $WAIT_COUNT -ge $MAX_WAIT ]]; then
      log "WARNING: Ollama server did not become ready after ${MAX_WAIT}s. Attempting to pull anyway..."
    else
      log "Ollama server is ready"
    fi
    
    PULL_FAILED=false
    for model in "${MODEL_ARRAY[@]}"; do
      # Check if model already exists when skip-verification is set
      SKIP_THIS_MODEL=false
      if [[ "$SKIP_VERIFICATION" == "true" ]]; then
        # Check if model exists using ollama list (server should be running by now)
        OLD_HOME="$HOME"
        export HOME="$OLLAMA_HOME"
        if "$OLLAMA_CMD" list 2>/dev/null | grep -q "^$model"; then
          log "Model $model already exists in bundle. Skipping pull (--skip-verification flag set)."
          SKIP_THIS_MODEL=true
        fi
        export HOME="$OLD_HOME"
      fi
      
      if [[ "$SKIP_THIS_MODEL" == "true" ]]; then
        log "Skipping pull for $model (already exists, --skip-verification flag set)"
        continue
      fi
      
      log "Pulling model: $model ..."
      # Unset OLLAMA_MODELS to prevent it from interfering with ollama pull command
      # OLLAMA_MODELS is only used by our script, not by Ollama itself
      # Temporarily set HOME to OLLAMA_HOME so Ollama uses it for ~/.ollama
      # This ensures models go to $BUNDLE_DIR/ollama/.ollama_home/.ollama/models/
      OLD_HOME="$HOME"
      export HOME="$OLLAMA_HOME"
      if ! (cd "$OLLAMA_HOME" && unset OLLAMA_MODELS && "$OLLAMA_CMD" pull "$model" 2>&1 | tee -a "$BUNDLE_DIR/logs/model_pull.log"); then
        log "WARNING: Failed to pull $model. Continuing with other models..."
        PULL_FAILED=true
      else
        log "Successfully pulled $model"
      fi
      # Restore HOME and PWD
      export HOME="$OLD_HOME"
      cd "$OLD_PWD" || true
      # Clean up any incorrectly placed model directories that might have been created during pull
      # Only remove if they were created during this pull (not pre-existing directories we copied earlier)
      SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      if [[ -d "$SCRIPT_DIR/$model" ]] && [[ "$SCRIPT_DIR/$model" != "$BUNDLE_DIR"* ]]; then
        # Check if this directory was already copied to bundle (check final bundle location)
        BUNDLE_MODEL_DIR="$BUNDLE_DIR/models/.ollama/models/$model"
        if [[ -d "$BUNDLE_MODEL_DIR" ]] && [[ -d "$BUNDLE_MODEL_DIR/blobs" ]]; then
          log "Model directory $model was already copied to bundle. Removing from script directory..."
          if [[ "$MOVE_MODELS" == "true" ]]; then
            # Already moved, just clean up
            rm -rf "$SCRIPT_DIR/$model" 2>/dev/null || true
          else
            # Was copied, safe to remove
            rm -rf "$SCRIPT_DIR/$model" 2>/dev/null || true
          fi
        else
          log "Cleaning up incorrectly placed model directory: $SCRIPT_DIR/$model"
          rm -rf "$SCRIPT_DIR/$model" 2>/dev/null || true
        fi
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

# #region agent log
HOME_OLLAMA_EXISTS=false
test -d "$HOME/.ollama" && HOME_OLLAMA_EXISTS=true || true
debug_log "get_bundle.sh:models:copy_start" "Starting model copy/move operation" "{\"move_models\":\"$MOVE_MODELS\",\"home_ollama_exists\":$HOME_OLLAMA_EXISTS,\"pull_failed\":\"${PULL_FAILED:-unknown}\"}" "MODEL-B" "run1"
# #endregion

if [[ "$MOVE_MODELS" == "true" ]]; then
  log "Moving \$HOME/.ollama into bundle (will remove originals)..."
else
  log "Copying \$HOME/.ollama into bundle..."
fi
mkdir -p "$BUNDLE_DIR/models"

MODELS_COPIED=false
# Check for models in OLLAMA_HOME/.ollama (where we told Ollama to store them via HOME override) first
# Then check OLLAMA_HOME directly, then fall back to ~/.ollama for backward compatibility
OLLAMA_SOURCE=""
if [[ -d "$OLLAMA_HOME/.ollama" ]] && [[ -n "$(ls -A "$OLLAMA_HOME/.ollama" 2>/dev/null)" ]]; then
  OLLAMA_SOURCE="$OLLAMA_HOME/.ollama"
  log "Found models in OLLAMA_HOME/.ollama: $OLLAMA_SOURCE"
elif [[ -d "$OLLAMA_HOME" ]] && [[ -n "$(ls -A "$OLLAMA_HOME" 2>/dev/null)" ]]; then
  OLLAMA_SOURCE="$OLLAMA_HOME"
  log "Found models in OLLAMA_HOME: $OLLAMA_SOURCE"
elif [[ -d "$HOME/.ollama" ]] && [[ -n "$(ls -A "$HOME/.ollama" 2>/dev/null)" ]]; then
  OLLAMA_SOURCE="$HOME/.ollama"
  log "Found models in ~/.ollama (fallback)"
fi

if [[ -z "$OLLAMA_SOURCE" ]]; then
  log "WARNING: No models found in $OLLAMA_HOME or ~/.ollama. Models were not pulled."
  if [[ "$PULL_FAILED" == "true" ]]; then
    log "WARNING: Model pulling failed. Check logs: $BUNDLE_DIR/logs/ollama_serve.log"
  fi
  mark_failed "models"
  # #region agent log
  debug_log "get_bundle.sh:models:copy_failed" "Models directory not found" "{\"ollama_home\":\"$OLLAMA_HOME\",\"home_ollama\":\"$HOME/.ollama\",\"ollama_home_exists\":$(test -d "$OLLAMA_HOME" && echo true || echo false),\"home_ollama_exists\":$(test -d "$HOME/.ollama" && echo true || echo false)}" "MODEL-C" "run1"
  # #endregion
else
  if [[ "$MOVE_MODELS" == "true" ]]; then
    # Move models to save disk space
    # #region agent log
    debug_log "get_bundle.sh:models:move_attempt" "Attempting to move models" "{\"source\":\"$OLLAMA_SOURCE\",\"dest\":\"$BUNDLE_DIR/models/.ollama\"}" "MODEL-D" "run1"
    # #endregion
    if mv "$OLLAMA_SOURCE" "$BUNDLE_DIR/models/.ollama"; then
      TOTAL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
      log "Models moved successfully. Total size: $TOTAL_SIZE"
      log "Models bundled: ${OLLAMA_MODELS}"
      log "Note: Original models have been moved to bundle"
      mark_success "models"
      MODELS_COPIED=true
      # #region agent log
      debug_log "get_bundle.sh:models:move_success" "Models moved successfully" "{\"total_size\":\"$TOTAL_SIZE\",\"dest_exists\":$(test -d "$BUNDLE_DIR/models/.ollama" && echo true || echo false)}" "MODEL-D" "run1"
      # #endregion
    else
      log "ERROR: Failed to move models. Check disk space and permissions."
      mark_failed "models"
      # #region agent log
      debug_log "get_bundle.sh:models:move_failed" "Failed to move models" "{\"exit_code\":$?}" "MODEL-E" "run1"
      # #endregion
    fi
  else
    # Use rsync to copy models
    # #region agent log
    debug_log "get_bundle.sh:models:copy_attempt" "Attempting to copy models" "{\"source\":\"$OLLAMA_SOURCE/\",\"dest\":\"$BUNDLE_DIR/models/.ollama/\"}" "MODEL-F" "run1"
    # #endregion
    if rsync -a --delete "$OLLAMA_SOURCE/" "$BUNDLE_DIR/models/.ollama/"; then
      TOTAL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
      log "Models copied successfully. Total size: $TOTAL_SIZE"
      log "Models bundled: ${OLLAMA_MODELS}"
      log "Note: mistral:7b-instruct ~4GB, mixtral:8x7b ~26GB, mistral:7b-instruct-q4_K_M ~2GB"
      mark_success "models"
      MODELS_COPIED=true
      # #region agent log
      debug_log "get_bundle.sh:models:copy_success" "Models copied successfully" "{\"total_size\":\"$TOTAL_SIZE\",\"dest_exists\":$(test -d "$BUNDLE_DIR/models/.ollama" && echo true || echo false)}" "MODEL-F" "run1"
      # #endregion
    else
      log "ERROR: Failed to copy models. Check disk space and permissions."
      mark_failed "models"
      # #region agent log
      debug_log "get_bundle.sh:models:copy_failed" "Failed to copy models" "{\"exit_code\":$?}" "MODEL-G" "run1"
      # #endregion
    fi
  fi
fi

# Clean up temporary files to save disk space
if [[ "$MODELS_COPIED" == "true" ]]; then
  log "Cleaning up temporary files to save disk space..."
  
  # Clean up temporary ollama binary directory (no longer needed after pulling models)
  if [[ -n "${TMP_OLLAMA:-}" ]] && [[ -d "$TMP_OLLAMA" ]]; then
    TMP_SIZE=$(du -sh "$TMP_OLLAMA" 2>/dev/null | cut -f1 || echo "unknown")
    if rm -rf "$TMP_OLLAMA" 2>/dev/null; then
      log "Cleaned up temporary Ollama binary directory ($TMP_SIZE)"
    else
      log "WARNING: Could not fully remove temporary directory (some files may be in use)"
      # Try to remove what we can
      find "$TMP_OLLAMA" -type f -delete 2>/dev/null || true
    fi
  fi
  
  # Clean up OLLAMA_HOME temp directory (models are now in bundle/models/.ollama)
  if [[ -n "${OLLAMA_HOME:-}" ]] && [[ -d "$OLLAMA_HOME" ]] && [[ "$OLLAMA_HOME" == "$BUNDLE_DIR"* ]]; then
    OLLAMA_HOME_SIZE=$(du -sh "$OLLAMA_HOME" 2>/dev/null | cut -f1 || echo "unknown")
    if rm -rf "$OLLAMA_HOME" 2>/dev/null; then
      log "Cleaned up temporary Ollama home directory ($OLLAMA_HOME_SIZE)"
    fi
  fi
  
  # Clean up any incorrectly placed model directories in the script's working directory
  # (These can be created if Ollama runs from the wrong directory before our fix)
  # Only remove directories that were created during pull, not pre-existing ones we copied
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  for model in "${MODEL_ARRAY[@]}"; do
    # Check if model directory exists in script directory (not in bundle)
    if [[ -d "$SCRIPT_DIR/$model" ]] && [[ "$SCRIPT_DIR/$model" != "$BUNDLE_DIR"* ]]; then
      # Check if this directory was already copied to bundle (check final bundle location)
      BUNDLE_MODEL_DIR="$BUNDLE_DIR/models/.ollama/models/$model"
      if [[ -d "$BUNDLE_MODEL_DIR" ]] && [[ -d "$BUNDLE_MODEL_DIR/blobs" ]]; then
        log "Model directory $model was already copied to bundle. Removing from script directory..."
        if [[ "$MOVE_MODELS" == "true" ]]; then
          # Already moved, just clean up
          rm -rf "$SCRIPT_DIR/$model" 2>/dev/null || log "WARNING: Could not remove $SCRIPT_DIR/$model"
        else
          # Was copied, safe to remove
          rm -rf "$SCRIPT_DIR/$model" 2>/dev/null || log "WARNING: Could not remove $SCRIPT_DIR/$model"
        fi
      else
        log "Cleaning up incorrectly placed model directory: $SCRIPT_DIR/$model"
        rm -rf "$SCRIPT_DIR/$model" 2>/dev/null || log "WARNING: Could not remove $SCRIPT_DIR/$model"
      fi
    fi
  done
  
  # Clean up ollama serve log if models were successfully copied
  if [[ -f "$BUNDLE_DIR/logs/ollama_serve.log" ]]; then
    # Keep a summary but remove the full log to save space
    tail -50 "$BUNDLE_DIR/logs/ollama_serve.log" > "$BUNDLE_DIR/logs/ollama_serve.log.summary" 2>/dev/null || true
    rm -f "$BUNDLE_DIR/logs/ollama_serve.log"
    log "Cleaned up Ollama server log (summary kept)"
  fi
fi

# Clean up APT temp directory after repo is built
if [[ -d "$BUNDLE_DIR/aptrepo/_tmp" ]]; then
  APT_TMP_SIZE=$(du -sh "$BUNDLE_DIR/aptrepo/_tmp" 2>/dev/null | cut -f1 || echo "unknown")
  if rm -rf "$BUNDLE_DIR/aptrepo/_tmp" 2>/dev/null; then
    log "Cleaned up APT temp directory ($APT_TMP_SIZE)"
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

if [[ -n "$VSCODIUM_DEB" ]] && [[ -f "$VSCODIUM_DEB" ]]; then
  if [[ "$SKIP_VERIFICATION" == "true" ]]; then
    log "VSCodium .deb already exists. Skipping verification (--skip-verification flag set)."
    mark_success "vscodium"
    VSCODIUM_DL_STATUS=0
  elif [[ -f "$VSCODIUM_SHA" ]]; then
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
    # File exists but no SHA - if skip flag is not set, we need to download to verify
    if [[ "$SKIP_VERIFICATION" != "true" ]]; then
      VSCODIUM_DL_STATUS=1
    fi
  fi
else
  VSCODIUM_DL_STATUS=1
fi

if [[ $VSCODIUM_DL_STATUS -ne 0 ]]; then
  log "Fetching VSCodium latest .deb + .sha256..."
  
  # #region agent log
  debug_log "get_bundle.sh:vscodium:download_start" "Starting VSCodium download" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "VSCODIUM-A" "run1"
  # #endregion
  
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, time, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"vscodium"
outdir.mkdir(parents=True, exist_ok=True)

def urlopen_with_retry(url, max_retries=3, timeout=30):
    """Open URL with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            response = urllib.request.urlopen(request, timeout=timeout)
            return response
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
            else:
                print(f"ERROR: All {max_retries} attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=120):
    """Download file with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with open(filename, 'wb') as f:
                    f.write(response.read())
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Download attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
                if os.path.exists(filename):
                    os.remove(filename)
            else:
                print(f"ERROR: All {max_retries} download attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

try:
    api = "https://api.github.com/repos/VSCodium/vscodium/releases/latest"
    print("Fetching VSCodium release metadata...")
    print(f"API URL: {api}")
    response = urlopen_with_retry(api, max_retries=3, timeout=30)
    data = json.loads(response.read().decode("utf-8"))
    assets = {a["name"]: a["browser_download_url"] for a in data.get("assets", [])}
    
    # Log available assets for debugging
    if assets:
        asset_names = list(assets.keys())[:10]
        print(f"Available assets: {asset_names}")
    else:
        print(f"WARNING: No assets found in API response. Response keys: {list(data.keys())}")
    
    # pick amd64 deb + its .sha256
    deb = next((n for n in assets if n.endswith("_amd64.deb")), None)
    sha = deb + ".sha256" if deb and (deb + ".sha256") in assets else None
    if not deb or not sha:
        available = list(assets.keys())[:10] if assets else ["none"]
        raise SystemExit(f"Could not find amd64 deb and sha256 in assets. Available: {available}")
    
    deb_url = assets[deb]
    sha_url = assets[sha]
    print(f"VSCodium .deb URL: {deb_url}")
    print(f"VSCodium .sha256 URL: {sha_url}")
    print(f"Downloading {deb}...")
    urlretrieve_with_retry(deb_url, str(outdir/deb), max_retries=3, timeout=300)
    print(f"Downloading {sha}...")
    urlretrieve_with_retry(sha_url, str(outdir/sha), max_retries=3, timeout=30)
    print("Downloaded:", deb, "and", sha)
except (urllib.error.URLError, TimeoutError, OSError) as e:
    print(f"ERROR: Network error downloading VSCodium: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
    sys.exit(1)
PY
  VSCODIUM_DL_STATUS=$?
  
  # #region agent log
  debug_log "get_bundle.sh:vscodium:download_complete" "VSCodium download completed" "{\"exit_code\":$VSCODIUM_DL_STATUS}" "VSCODIUM-A" "run1"
  # #endregion
  
  if [[ $VSCODIUM_DL_STATUS -eq 0 ]]; then
    # .sha256 is usually in the form "<hash>  <filename>"
    if sha256_check_file "$BUNDLE_DIR/vscodium/"*_amd64.deb "$BUNDLE_DIR/vscodium/"*_amd64.deb.sha256; then
      log "VSCodium verified."
      mark_success "vscodium"
      # #region agent log
      debug_log "get_bundle.sh:vscodium:verify_success" "VSCodium verification successful" "{\"status\":\"success\"}" "VSCODIUM-A" "run1"
      # #endregion
    else
      log "ERROR: VSCodium SHA256 verification failed"
      mark_failed "vscodium"
      # #region agent log
      debug_log "get_bundle.sh:vscodium:verify_failed" "VSCodium verification failed" "{\"status\":\"failed\"}" "VSCODIUM-B" "run1"
      # #endregion
    fi
  else
    log "ERROR: Failed to download VSCodium. Continuing with other components..."
    mark_failed "vscodium"
    # #region agent log
    debug_log "get_bundle.sh:vscodium:download_failed" "VSCodium download failed" "{\"exit_code\":$VSCODIUM_DL_STATUS}" "VSCODIUM-C" "run1"
    # #endregion
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

# Check if file exists but is suspiciously small (incomplete download)
# VSIX files are typically at least 1MB, so files under 100KB are likely incomplete
if [[ -n "$CONTINUE_VSIX" ]] && [[ -f "$CONTINUE_VSIX" ]]; then
  FILE_SIZE=$(stat -c%s "$CONTINUE_VSIX" 2>/dev/null || stat -f%z "$CONTINUE_VSIX" 2>/dev/null || echo 0)
  if [[ $FILE_SIZE -lt 100000 ]]; then
    log "Existing Continue VSIX is suspiciously small (${FILE_SIZE} bytes). Re-downloading..."
    rm -f "$CONTINUE_VSIX" "$CONTINUE_SHA"
    CONTINUE_DL_STATUS=1
  elif [[ "$SKIP_VERIFICATION" == "true" ]]; then
    log "Continue VSIX already exists. Skipping verification (--skip-verification flag set)."
    mark_success "continue"
    CONTINUE_DL_STATUS=0
  elif [[ -f "$CONTINUE_SHA" ]]; then
    log "Continue VSIX already exists, verifying..."
    if sha256_check_vsix "$CONTINUE_VSIX" "$CONTINUE_SHA"; then
      log "Continue VSIX already downloaded and verified. Skipping download."
      mark_success "continue"
      CONTINUE_DL_STATUS=0
    else
      log "Existing Continue VSIX failed verification. Re-downloading..."
      rm -f "$CONTINUE_VSIX" "$CONTINUE_SHA" "${CONTINUE_VSIX}.verified"
      CONTINUE_DL_STATUS=1
    fi
  else
    # File exists but no SHA256 - if skip flag is not set, need to download to get SHA256
    if [[ "$SKIP_VERIFICATION" != "true" ]]; then
      log "Continue VSIX exists but no SHA256 file. Re-downloading to verify..."
      rm -f "$CONTINUE_VSIX"
      CONTINUE_DL_STATUS=1
    else
      log "Continue VSIX already exists. Skipping verification (--skip-verification flag set)."
      mark_success "continue"
      CONTINUE_DL_STATUS=0
    fi
  fi
else
  CONTINUE_DL_STATUS=1
fi

if [[ "$CONTINUE_DL_STATUS" -ne 0 ]]; then
  log "Fetching Continue VSIX + sha256 from Open VSX..."
  
  # #region agent log
  debug_log "get_bundle.sh:continue:download_start" "Starting Continue VSIX download" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "CONTINUE-A" "run1"
  # #endregion
  
  DEBUG_LOG="$DEBUG_LOG" python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, os, time
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"continue"
outdir.mkdir(parents=True, exist_ok=True)
debug_log = os.environ.get("DEBUG_LOG", str(bundle/"logs"/"debug.log"))

def urlopen_with_retry(url, max_retries=3, timeout=30):
    """Open URL with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            response = urllib.request.urlopen(request, timeout=timeout)
            return response
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
            else:
                print(f"ERROR: All {max_retries} attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=60):
    """Download file with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with open(filename, 'wb') as f:
                    f.write(response.read())
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Download attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
                if os.path.exists(filename):
                    os.remove(filename)
            else:
                print(f"ERROR: All {max_retries} download attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

# Use Open VSX API to get extension metadata
api_url = "https://open-vsx.org/api/Continue/continue"
try:
    with urlopen_with_retry(api_url, max_retries=3, timeout=30) as response:
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
    print(f"VSIX download URL: {download_url}")
    print(f"SHA256 URL: {sha256_url}")
    print(f"Downloading {vsix_name}...")
    urlretrieve_with_retry(download_url, str(outdir/vsix_name), max_retries=3, timeout=120)
    vsix_size = (outdir/vsix_name).stat().st_size
    
    # Open VSX returns just the hash, format it as "hash  filename"
    # Handle rate limiting - if we get HTML, calculate hash from downloaded file instead
    sha256_response = urlopen_with_retry(sha256_url, max_retries=3, timeout=30).read().decode("utf-8")
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
except (urllib.error.URLError, TimeoutError, OSError) as e:
    raise SystemExit(f"Failed to fetch from Open VSX API (network error): {e}")
except (KeyError, ValueError) as e:
    raise SystemExit(f"Failed to parse API response: {e}")
PY
  CONTINUE_DL_STATUS=$?
  
  # #region agent log
  debug_log "get_bundle.sh:continue:download_complete" "Continue VSIX download completed" "{\"exit_code\":$CONTINUE_DL_STATUS}" "CONTINUE-A" "run1"
  # #endregion
  
  if [[ "$CONTINUE_DL_STATUS" -eq 0 ]]; then
    # Find the actual VSIX file (wildcard expansion)
    CONTINUE_VSIX_FILE="$(find "$BUNDLE_DIR/continue" -maxdepth 1 -name "Continue.continue-*.vsix" 2>/dev/null | head -n1)"
    CONTINUE_SHA_FILE="${CONTINUE_VSIX_FILE}.sha256"
    
    # #region agent log
    debug_log "get_bundle.sh:continue:find_files" "Searching for Continue VSIX files" "{\"vsix_file\":\"$CONTINUE_VSIX_FILE\",\"sha_file\":\"$CONTINUE_SHA_FILE\",\"vsix_exists\":$(test -f "$CONTINUE_VSIX_FILE" && echo true || echo false),\"sha_exists\":$(test -f "$CONTINUE_SHA_FILE" && echo true || echo false)}" "CONTINUE-B" "run1"
    # #endregion
    
    if [[ -n "$CONTINUE_VSIX_FILE" ]] && [[ -f "$CONTINUE_VSIX_FILE" ]]; then
      if [[ -f "$CONTINUE_SHA_FILE" ]]; then
        if sha256_check_vsix "$CONTINUE_VSIX_FILE" "$CONTINUE_SHA_FILE"; then
          log "Continue VSIX verified."
          mark_success "continue"
          # #region agent log
          debug_log "get_bundle.sh:continue:verify_success" "Continue VSIX verification successful" "{\"status\":\"success\"}" "CONTINUE-B" "run1"
          # #endregion
        else
          log "WARNING: Continue VSIX SHA256 verification failed, but file exists and will be included"
          log "WARNING: This may indicate a hash mismatch from Open VSX. The VSIX file can still be installed."
          mark_success "continue"  # Still mark as success since file exists
          # #region agent log
          debug_log "get_bundle.sh:continue:verify_warning" "Continue VSIX verification failed but continuing" "{\"status\":\"warning\"}" "CONTINUE-C" "run1"
          # #endregion
        fi
      else
        log "WARNING: Continue VSIX SHA256 file not found, but VSIX file exists and will be included"
        mark_success "continue"
        # #region agent log
        debug_log "get_bundle.sh:continue:sha_missing" "Continue VSIX SHA256 file missing" "{\"status\":\"warning\"}" "CONTINUE-D" "run1"
        # #endregion
      fi
    else
      log "ERROR: Continue VSIX file not found after download"
      mark_failed "continue"
      # #region agent log
      debug_log "get_bundle.sh:continue:file_not_found" "Continue VSIX file not found after download" "{\"status\":\"failed\"}" "CONTINUE-E" "run1"
      # #endregion
    fi
  else
    log "ERROR: Failed to download Continue VSIX. Continuing with other components..."
    mark_failed "continue"
    # #region agent log
    debug_log "get_bundle.sh:continue:download_failed" "Continue VSIX download failed" "{\"exit_code\":$CONTINUE_DL_STATUS}" "CONTINUE-F" "run1"
    # #endregion
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

# Check if file exists but is suspiciously small (incomplete download)
# VSIX files are typically at least 1MB, so files under 100KB are likely incomplete
if [[ -n "$PYTHON_VSIX" ]] && [[ -f "$PYTHON_VSIX" ]]; then
  FILE_SIZE=$(stat -c%s "$PYTHON_VSIX" 2>/dev/null || stat -f%z "$PYTHON_VSIX" 2>/dev/null || echo 0)
  if [[ $FILE_SIZE -lt 100000 ]]; then
    log "Existing Python extension VSIX is suspiciously small (${FILE_SIZE} bytes). Re-downloading..."
    rm -f "$PYTHON_VSIX" "$PYTHON_SHA"
    PYTHON_EXT_DL_STATUS=1
  elif [[ "$SKIP_VERIFICATION" == "true" ]]; then
    log "Python extension VSIX already exists. Skipping verification (--skip-verification flag set)."
    mark_success "python_ext"
    PYTHON_EXT_DL_STATUS=0
  elif [[ -f "$PYTHON_SHA" ]]; then
    log "Python extension VSIX already exists, verifying..."
    if sha256_check_vsix "$PYTHON_VSIX" "$PYTHON_SHA"; then
      log "Python extension VSIX already downloaded and verified. Skipping download."
      mark_success "python_ext"
      PYTHON_EXT_DL_STATUS=0
    else
      log "Existing Python extension VSIX failed verification. Re-downloading..."
      rm -f "$PYTHON_VSIX" "$PYTHON_SHA" "${PYTHON_VSIX}.verified"
      PYTHON_EXT_DL_STATUS=1
    fi
  else
    # File exists but no SHA256 - if skip flag is not set, need to download to get SHA256
    if [[ "$SKIP_VERIFICATION" != "true" ]]; then
      log "Python extension VSIX exists but no SHA256 file. Re-downloading to verify..."
      rm -f "$PYTHON_VSIX"
      PYTHON_EXT_DL_STATUS=1
    else
      log "Python extension VSIX already exists. Skipping verification (--skip-verification flag set)."
      mark_success "python_ext"
      PYTHON_EXT_DL_STATUS=0
    fi
  fi
else
  PYTHON_EXT_DL_STATUS=1
fi

if [[ $PYTHON_EXT_DL_STATUS -ne 0 ]]; then
  log "Fetching Python extension VSIX + sha256 from Open VSX..."
  
  # #region agent log
  debug_log "get_bundle.sh:python_ext:download_start" "Starting Python extension VSIX download" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "PYTHON-EXT-A" "run1"
  # #endregion
  
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, time, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

def urlopen_with_retry(url, max_retries=3, timeout=30):
    """Open URL with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            response = urllib.request.urlopen(request, timeout=timeout)
            return response
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
            else:
                print(f"ERROR: All {max_retries} attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=120):
    """Download file with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with open(filename, 'wb') as f:
                    f.write(response.read())
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Download attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
                if os.path.exists(filename):
                    os.remove(filename)
            else:
                print(f"ERROR: All {max_retries} download attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

# Use Open VSX API to get extension metadata
api_url = "https://open-vsx.org/api/ms-python/python"
try:
    with urlopen_with_retry(api_url, max_retries=3, timeout=30) as response:
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
    print(f"VSIX download URL: {download_url}")
    print(f"SHA256 URL: {sha256_url}")
    print(f"Downloading {vsix_name}...")
    urlretrieve_with_retry(download_url, str(outdir/vsix_name), max_retries=3, timeout=120)
    vsix_size = (outdir/vsix_name).stat().st_size
    
    # Open VSX returns just the hash, format it as "hash  filename"
    # Handle rate limiting - if we get HTML, calculate hash from downloaded file instead
    sha256_response = urlopen_with_retry(sha256_url, max_retries=3, timeout=30).read().decode("utf-8")
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
except (urllib.error.URLError, TimeoutError, OSError) as e:
    raise SystemExit(f"Failed to fetch from Open VSX API (network error): {e}")
except (KeyError, ValueError) as e:
    raise SystemExit(f"Failed to parse API response: {e}")
PY
  PYTHON_EXT_DL_STATUS=$?
  
  # #region agent log
  debug_log "get_bundle.sh:python_ext:download_complete" "Python extension VSIX download completed" "{\"exit_code\":$PYTHON_EXT_DL_STATUS}" "PYTHON-EXT-A" "run1"
  # #endregion

  if [[ $PYTHON_EXT_DL_STATUS -eq 0 ]]; then
    # Find the actual VSIX file (wildcard expansion)
    PYTHON_VSIX_FILE="$(find "$BUNDLE_DIR/extensions" -maxdepth 1 -name "ms-python.python-*.vsix" 2>/dev/null | head -n1)"
    PYTHON_SHA_FILE="${PYTHON_VSIX_FILE}.sha256"
    
    # #region agent log
    debug_log "get_bundle.sh:python_ext:find_files" "Searching for Python extension VSIX files" "{\"vsix_file\":\"$PYTHON_VSIX_FILE\",\"sha_file\":\"$PYTHON_SHA_FILE\",\"vsix_exists\":$(test -f "$PYTHON_VSIX_FILE" && echo true || echo false),\"sha_exists\":$(test -f "$PYTHON_SHA_FILE" && echo true || echo false)}" "PYTHON-EXT-B" "run1"
    # #endregion
    
    if [[ -n "$PYTHON_VSIX_FILE" ]] && [[ -f "$PYTHON_VSIX_FILE" ]]; then
      if [[ -f "$PYTHON_SHA_FILE" ]]; then
        if sha256_check_vsix "$PYTHON_VSIX_FILE" "$PYTHON_SHA_FILE"; then
          log "Python extension VSIX verified."
          mark_success "python_ext"
          # #region agent log
          debug_log "get_bundle.sh:python_ext:verify_success" "Python extension VSIX verification successful" "{\"status\":\"success\"}" "PYTHON-EXT-B" "run1"
          # #endregion
        else
          log "WARNING: Python extension VSIX SHA256 verification failed, but file exists and will be included"
          log "WARNING: This may indicate a hash mismatch from Open VSX. The VSIX file can still be installed."
          mark_success "python_ext"  # Still mark as success since file exists
          # #region agent log
          debug_log "get_bundle.sh:python_ext:verify_warning" "Python extension VSIX verification failed but continuing" "{\"status\":\"warning\"}" "PYTHON-EXT-C" "run1"
          # #endregion
        fi
      else
        log "WARNING: Python extension VSIX SHA256 file not found, but VSIX file exists and will be included"
        mark_success "python_ext"
        # #region agent log
        debug_log "get_bundle.sh:python_ext:sha_missing" "Python extension VSIX SHA256 file missing" "{\"status\":\"warning\"}" "PYTHON-EXT-D" "run1"
        # #endregion
      fi
    else
      log "ERROR: Python extension VSIX file not found after download"
      mark_failed "python_ext"
      # #region agent log
      debug_log "get_bundle.sh:python_ext:file_not_found" "Python extension VSIX file not found after download" "{\"status\":\"failed\"}" "PYTHON-EXT-E" "run1"
      # #endregion
    fi
  else
    log "ERROR: Failed to download Python extension VSIX. Continuing with other components..."
    mark_failed "python_ext"
    # #region agent log
    debug_log "get_bundle.sh:python_ext:download_failed" "Python extension VSIX download failed" "{\"exit_code\":$PYTHON_EXT_DL_STATUS}" "PYTHON-EXT-F" "run1"
    # #endregion
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

# Check if file exists but is suspiciously small (incomplete download)
# VSIX files are typically at least 1MB, so files under 100KB are likely incomplete
if [[ -n "$RUST_VSIX" ]] && [[ -f "$RUST_VSIX" ]]; then
  FILE_SIZE=$(stat -c%s "$RUST_VSIX" 2>/dev/null || stat -f%z "$RUST_VSIX" 2>/dev/null || echo 0)
  if [[ $FILE_SIZE -lt 100000 ]]; then
    log "Existing Rust Analyzer extension VSIX is suspiciously small (${FILE_SIZE} bytes). Re-downloading..."
    rm -f "$RUST_VSIX" "$RUST_SHA"
    RUST_EXT_DL_STATUS=1
  elif [[ "$SKIP_VERIFICATION" == "true" ]]; then
    log "Rust Analyzer extension VSIX already exists. Skipping verification (--skip-verification flag set)."
    mark_success "rust_ext"
    RUST_EXT_DL_STATUS=0
  elif [[ -f "$RUST_SHA" ]]; then
    log "Rust Analyzer extension VSIX already exists, verifying..."
    if sha256_check_vsix "$RUST_VSIX" "$RUST_SHA"; then
      log "Rust Analyzer extension VSIX already downloaded and verified. Skipping download."
      mark_success "rust_ext"
      RUST_EXT_DL_STATUS=0
    else
      log "Existing Rust Analyzer extension VSIX failed verification. Re-downloading..."
      rm -f "$RUST_VSIX" "$RUST_SHA" "${RUST_VSIX}.verified"
      RUST_EXT_DL_STATUS=1
    fi
  else
    # File exists but no SHA256 - if skip flag is not set, need to download to get SHA256
    if [[ "$SKIP_VERIFICATION" != "true" ]]; then
      log "Rust Analyzer extension VSIX exists but no SHA256 file. Re-downloading to verify..."
      rm -f "$RUST_VSIX"
      RUST_EXT_DL_STATUS=1
    else
      log "Rust Analyzer extension VSIX already exists. Skipping verification (--skip-verification flag set)."
      mark_success "rust_ext"
      RUST_EXT_DL_STATUS=0
    fi
  fi
else
  RUST_EXT_DL_STATUS=1
fi

if [[ $RUST_EXT_DL_STATUS -ne 0 ]]; then
  log "Fetching Rust Analyzer extension VSIX + sha256 from Open VSX..."
  
  # #region agent log
  debug_log "get_bundle.sh:rust_ext:download_start" "Starting Rust extension VSIX download" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "RUST-EXT-A" "run1"
  # #endregion
  
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, time, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)
debug_log = os.environ.get("DEBUG_LOG", str(bundle/"logs"/"debug.log"))

def urlopen_with_retry(url, max_retries=3, timeout=30):
    """Open URL with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            response = urllib.request.urlopen(request, timeout=timeout)
            return response
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
            else:
                print(f"ERROR: All {max_retries} attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=120):
    """Download file with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with open(filename, 'wb') as f:
                    f.write(response.read())
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Download attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
                if os.path.exists(filename):
                    os.remove(filename)
            else:
                print(f"ERROR: All {max_retries} download attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

# Use Open VSX API to get extension metadata
api_url = "https://open-vsx.org/api/rust-lang/rust-analyzer"
try:
    with urlopen_with_retry(api_url, max_retries=3, timeout=30) as response:
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
    print(f"Downloading {vsix_name}...")
    urlretrieve_with_retry(download_url, str(outdir/vsix_name), max_retries=3, timeout=120)
    vsix_size = (outdir/vsix_name).stat().st_size
    
    # Open VSX returns just the hash, format it as "hash  filename"
    # Handle rate limiting - if we get HTML, calculate hash from downloaded file instead
    sha256_response = urlopen_with_retry(sha256_url, max_retries=3, timeout=30).read().decode("utf-8")
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
except (urllib.error.URLError, TimeoutError, OSError) as e:
    raise SystemExit(f"Failed to fetch from Open VSX API (network error): {e}")
except (KeyError, ValueError) as e:
    raise SystemExit(f"Failed to parse API response: {e}")
PY
  RUST_EXT_DL_STATUS=$?
  
  # #region agent log
  debug_log "get_bundle.sh:rust_ext:download_complete" "Rust extension VSIX download completed" "{\"exit_code\":$RUST_EXT_DL_STATUS}" "RUST-EXT-A" "run1"
  # #endregion

  if [[ $RUST_EXT_DL_STATUS -eq 0 ]]; then
    # Find the actual VSIX file (wildcard expansion)
    RUST_VSIX_FILE="$(find "$BUNDLE_DIR/extensions" -maxdepth 1 -name "rust-lang.rust-analyzer-*.vsix" 2>/dev/null | head -n1)"
    RUST_SHA_FILE="${RUST_VSIX_FILE}.sha256"
    
    # #region agent log
    debug_log "get_bundle.sh:rust_ext:find_files" "Searching for Rust extension VSIX files" "{\"vsix_file\":\"$RUST_VSIX_FILE\",\"sha_file\":\"$RUST_SHA_FILE\",\"vsix_exists\":$(test -f "$RUST_VSIX_FILE" && echo true || echo false),\"sha_exists\":$(test -f "$RUST_SHA_FILE" && echo true || echo false)}" "RUST-EXT-B" "run1"
    # #endregion
    
    if [[ -n "$RUST_VSIX_FILE" ]] && [[ -f "$RUST_VSIX_FILE" ]]; then
      if [[ -f "$RUST_SHA_FILE" ]]; then
        if sha256_check_vsix "$RUST_VSIX_FILE" "$RUST_SHA_FILE"; then
          log "Rust Analyzer extension VSIX verified."
          mark_success "rust_ext"
          # #region agent log
          debug_log "get_bundle.sh:rust_ext:verify_success" "Rust extension VSIX verification successful" "{\"status\":\"success\"}" "RUST-EXT-B" "run1"
          # #endregion
        else
          log "WARNING: Rust Analyzer extension VSIX SHA256 verification failed, but file exists and will be included"
          log "WARNING: This may indicate a hash mismatch from Open VSX. The VSIX file can still be installed."
          mark_success "rust_ext"  # Still mark as success since file exists
          # #region agent log
          debug_log "get_bundle.sh:rust_ext:verify_warning" "Rust extension VSIX verification failed but continuing" "{\"status\":\"warning\"}" "RUST-EXT-C" "run1"
          # #endregion
        fi
      else
        log "WARNING: Rust Analyzer extension VSIX SHA256 file not found, but VSIX file exists and will be included"
        mark_success "rust_ext"
        # #region agent log
        debug_log "get_bundle.sh:rust_ext:sha_missing" "Rust extension VSIX SHA256 file missing" "{\"status\":\"warning\"}" "RUST-EXT-D" "run1"
        # #endregion
      fi
    else
      log "ERROR: Rust Analyzer extension VSIX file not found after download"
      mark_failed "rust_ext"
      # #region agent log
      debug_log "get_bundle.sh:rust_ext:file_not_found" "Rust extension VSIX file not found after download" "{\"status\":\"failed\"}" "RUST-EXT-E" "run1"
      # #endregion
    fi
  else
    log "ERROR: Failed to download Rust Analyzer extension VSIX. Continuing with other components..."
    mark_failed "rust_ext"
    # #region agent log
    debug_log "get_bundle.sh:rust_ext:download_failed" "Rust extension VSIX download failed" "{\"exit_code\":$RUST_EXT_DL_STATUS}" "RUST-EXT-F" "run1"
    # #endregion
  fi
fi

# ============
# 7) Offline APT repo for Lua 5.3 + common prereqs
# ============
log "Building local APT repo with development tools and dependencies..."

# Check if sudo is available and passwordless
SUDO_AVAILABLE=false
if command -v sudo >/dev/null 2>&1; then
  if sudo -n true 2>/dev/null; then
    SUDO_AVAILABLE=true
    log "Passwordless sudo available. Proceeding with APT repo build..."
  else
    log "WARNING: Sudo requires password. APT repo build requires sudo access."
    log "Attempting to configure passwordless sudo..."
    # #region agent log
    debug_log "get_bundle.sh:apt_repo:configure_sudo" "Attempting to configure passwordless sudo" "{\"status\":\"attempting\"}" "APT-N" "run1"
    # #endregion
    
    # Try to configure passwordless sudo (requires one-time password entry)
    # This will only work if the user can provide password interactively
    # For non-interactive sessions, we'll skip
    if [[ -t 0 ]] && [[ -t 1 ]]; then
      # Interactive session - try to configure sudo
      log "  Interactive session detected. Attempting to configure passwordless sudo..."
      log "  You may be prompted for your password once."
      # Check if the sudoers.d file already exists and is correct
      if [[ -f /etc/sudoers.d/admin-nopasswd ]] && sudo -n true 2>/dev/null; then
        log "✓ Passwordless sudo already configured"
        SUDO_AVAILABLE=true
        # #region agent log
        debug_log "get_bundle.sh:apt_repo:sudo_already_configured" "Passwordless sudo already configured" "{\"status\":\"success\"}" "APT-N" "run1"
        # #endregion
      elif sudo sh -c 'echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/admin-nopasswd && chmod 0440 /etc/sudoers.d/admin-nopasswd' 2>/dev/null; then
        if sudo -n true 2>/dev/null; then
          log "✓ Passwordless sudo configured successfully"
          SUDO_AVAILABLE=true
          # #region agent log
          debug_log "get_bundle.sh:apt_repo:sudo_configured" "Passwordless sudo configured successfully" "{\"status\":\"success\"}" "APT-N" "run1"
          # #endregion
        fi
      else
        log "  Could not configure passwordless sudo automatically (password required or permission denied)"
      fi
    else
      log "  Non-interactive session detected. Cannot configure passwordless sudo automatically."
    fi
    
    # If still not available, skip with helpful message
    if [[ "$SUDO_AVAILABLE" == "false" ]]; then
      log "Skipping APT repo build. You can:"
      log "  1. Configure passwordless sudo manually: sudo visudo and add: admin ALL=(ALL) NOPASSWD: ALL"
      log "  2. Run this script interactively with sudo access"
      log "  3. Manually download packages later"
      mark_skipped "apt_repo"
      # #region agent log
      debug_log "get_bundle.sh:apt_repo:sudo_unavailable" "Sudo not available, skipping APT repo" "{\"status\":\"skipped\"}" "APT-N" "run1"
      # #endregion
    fi
  fi
else
  log "WARNING: Sudo not found. APT repo build requires sudo access."
  log "Skipping APT repo build."
  mark_skipped "apt_repo"
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:sudo_missing" "Sudo command not found, skipping APT repo" "{\"status\":\"skipped\"}" "APT-N" "run1"
  # #endregion
fi

if [[ "$SUDO_AVAILABLE" == "true" ]]; then
# #region agent log
debug_log "get_bundle.sh:apt_repo:start" "Starting APT repo build" "{\"bundle_dir\":\"$BUNDLE_DIR\",\"apt_packages_count\":${#APT_PACKAGES[@]}}" "APT-A" "run1"
# #endregion
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
    zstd  # Required for extracting Ollama .tar.zst archives
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

  # #region agent log
  debug_log "get_bundle.sh:apt_repo:update_start" "Starting apt-get update" "{\"tmp_apt\":\"$TMP_APT\"}" "APT-B" "run1"
  # #endregion

  # Make sure apt metadata is fresh
  if sudo apt-get update -y; then
    APT_UPDATE_EXIT=0
  else
    APT_UPDATE_EXIT=$?
  fi
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:update_complete" "apt-get update completed" "{\"exit_code\":$APT_UPDATE_EXIT}" "APT-B" "run1"
  # #endregion
  
  if [[ $APT_UPDATE_EXIT -ne 0 ]]; then
    log "ERROR: apt-get update failed with exit code $APT_UPDATE_EXIT"
    log "Continuing anyway - package download may fail..."
  fi

  # Download (no install) into a temp cache, then copy .debs into the repo pool
  # Some packages may not be available on all distributions, so try individually if bulk fails
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:download_start" "Starting package download" "{\"package_count\":${#APT_PACKAGES[@]},\"tmp_apt\":\"$TMP_APT\"}" "APT-C" "run1"
  # #endregion
  
  if ! sudo apt-get -y --download-only -o Dir::Cache="$TMP_APT" install "${APT_PACKAGES[@]}" 2>&1; then
    log "WARNING: Bulk package download failed. Attempting to download packages individually..."
    
    # #region agent log
    debug_log "get_bundle.sh:apt_repo:bulk_failed" "Bulk package download failed, trying individually" "{\"package_count\":${#APT_PACKAGES[@]}}" "APT-D" "run1"
    # #endregion
    
    # Try to download packages individually to get as many as possible
    MISSING_PKGS=()
    for pkg in "${APT_PACKAGES[@]}"; do
      OUTPUT=$(sudo apt-get -y --download-only -o Dir::Cache="$TMP_APT" install "$pkg" 2>&1)
      EXIT_CODE=$?
      if [[ $EXIT_CODE -ne 0 ]] && echo "$OUTPUT" | grep -q "Unable to locate package"; then
        log "WARNING: Package not available: $pkg (skipping)"
        MISSING_PKGS+=("$pkg")
        # #region agent log
        debug_log "get_bundle.sh:apt_repo:pkg_missing" "Package not available" "{\"package\":\"$pkg\",\"exit_code\":$EXIT_CODE}" "APT-E" "run1"
        # #endregion
      elif [[ $EXIT_CODE -eq 0 ]]; then
        log "Downloaded: $pkg"
        # #region agent log
        debug_log "get_bundle.sh:apt_repo:pkg_success" "Package downloaded successfully" "{\"package\":\"$pkg\"}" "APT-F" "run1"
        # #endregion
      else
        log "WARNING: Failed to download $pkg (error code: $EXIT_CODE)"
        MISSING_PKGS+=("$pkg")
        # #region agent log
        debug_log "get_bundle.sh:apt_repo:pkg_failed" "Package download failed" "{\"package\":\"$pkg\",\"exit_code\":$EXIT_CODE}" "APT-G" "run1"
        # #endregion
      fi
    done
    if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
      log "WARNING: ${#MISSING_PKGS[@]} package(s) were not available: ${MISSING_PKGS[*]}"
      log "Continuing with available packages..."
      # #region agent log
      debug_log "get_bundle.sh:apt_repo:missing_summary" "Package download summary" "{\"missing_count\":${#MISSING_PKGS[@]},\"missing_packages\":\"${MISSING_PKGS[*]}\"}" "APT-H" "run1"
      # #endregion
    fi
  else
    log "All packages downloaded successfully."
    # #region agent log
    debug_log "get_bundle.sh:apt_repo:bulk_success" "Bulk package download successful" "{\"package_count\":${#APT_PACKAGES[@]}}" "APT-C" "run1"
    # #endregion
  fi

  mkdir -p "$BUNDLE_DIR/aptrepo/pool"
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:copy_start" "Copying .deb files to repo pool" "{\"source\":\"$TMP_APT/archives\",\"dest\":\"$BUNDLE_DIR/aptrepo/pool\"}" "APT-I" "run1"
  # #endregion
  
  DEB_COUNT=$(find "$TMP_APT/archives" -maxdepth 1 -type f -name "*.deb" 2>/dev/null | wc -l)
  find "$TMP_APT/archives" -maxdepth 1 -type f -name "*.deb" -print -exec cp -n {} "$BUNDLE_DIR/aptrepo/pool/" \;
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:copy_complete" "Debian packages copied to repo" "{\"deb_count\":$DEB_COUNT,\"pool_dir\":\"$BUNDLE_DIR/aptrepo/pool\"}" "APT-I" "run1"
  # #endregion

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

  # #region agent log
  debug_log "get_bundle.sh:apt_repo:metadata_created" "APT repo metadata created" "{\"distributions_file\":\"$BUNDLE_DIR/aptrepo/conf/distributions\"}" "APT-J" "run1"
  # #endregion

  # Build Packages index
  pushd "$BUNDLE_DIR/aptrepo" >/dev/null
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:index_start" "Building Packages index" "{\"repo_dir\":\"$BUNDLE_DIR/aptrepo\"}" "APT-K" "run1"
  # #endregion
  
  # Check if apt-ftparchive is available
  if ! command -v apt-ftparchive >/dev/null 2>&1; then
    log "WARNING: apt-ftparchive not found. Installing apt-utils..."
    sudo apt-get install -y apt-utils || {
      log "ERROR: Failed to install apt-utils. Cannot build Packages index."
      mark_failed "apt_repo"
      popd >/dev/null
      # #region agent log
      debug_log "get_bundle.sh:apt_repo:apt_utils_missing" "apt-ftparchive not available" "{\"status\":\"failed\"}" "APT-L" "run1"
      # #endregion
      # Continue to next section instead of exiting
    }
  fi
  
  # Check if pool directory has any .deb files
  DEB_FILES_IN_POOL=$(find pool -maxdepth 1 -type f -name "*.deb" 2>/dev/null | wc -l)
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:pool_check" "Checking pool directory" "{\"deb_count\":$DEB_FILES_IN_POOL}" "APT-M" "run1"
  # #endregion
  
  if [[ $DEB_FILES_IN_POOL -eq 0 ]]; then
    log "WARNING: No .deb files found in pool directory. APT repo will be empty."
    log "This may be normal if packages were not downloaded successfully."
    # Create empty Packages file so the repo structure is valid
    touch Packages
    gzip -kf Packages 2>/dev/null || true
    mark_failed "apt_repo"
    # #region agent log
    debug_log "get_bundle.sh:apt_repo:empty_pool" "Pool directory is empty" "{\"status\":\"failed\"}" "APT-M" "run1"
    # #endregion
  elif command -v apt-ftparchive >/dev/null 2>&1; then
    if apt-ftparchive packages pool > Packages 2>&1; then
      APT_INDEX_EXIT=0
    else
      APT_INDEX_EXIT=$?
      log "WARNING: apt-ftparchive failed with exit code $APT_INDEX_EXIT"
    fi
    
    if [[ $APT_INDEX_EXIT -eq 0 ]]; then
      gzip -kf Packages
      log "APT repo built."
      mark_success "apt_repo"
    else
      log "WARNING: Skipping Packages.gz creation due to index build failure"
      mark_failed "apt_repo"
    fi
  else
    log "ERROR: apt-ftparchive still not available after installation attempt"
    mark_failed "apt_repo"
    # #region agent log
    debug_log "get_bundle.sh:apt_repo:index_failed" "Packages index build failed" "{\"status\":\"failed\"}" "APT-K" "run1"
    # #endregion
  fi
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:index_complete" "Packages index build completed" "{\"packages_file\":\"$BUNDLE_DIR/aptrepo/Packages\",\"packages_gz_exists\":$(test -f "$BUNDLE_DIR/aptrepo/Packages.gz" && echo true || echo false),\"deb_count\":$DEB_FILES_IN_POOL}" "APT-K" "run1"
  # #endregion
  
  popd >/dev/null
  
  # #region agent log
  debug_log "get_bundle.sh:apt_repo:complete" "APT repo build completed successfully" "{\"status\":\"success\"}" "APT-A" "run1"
  # #endregion
fi  # End of SUDO_AVAILABLE check

# ============
# 8) Download Rust toolchain (rustup-init)
# ============
# Check if rustup-init already exists
RUSTUP_INIT="$BUNDLE_DIR/rust/toolchain/rustup-init"

# #region agent log
debug_log "get_bundle.sh:rust_toolchain:check" "Checking for existing Rust toolchain" "{\"rustup_init\":\"$RUSTUP_INIT\",\"exists\":$(test -f "$RUSTUP_INIT" && echo true || echo false),\"executable\":$(test -x "$RUSTUP_INIT" && echo true || echo false)}" "RUST-TOOLCHAIN-A" "run1"
# #endregion

if [[ -f "$RUSTUP_INIT" ]] && [[ -x "$RUSTUP_INIT" ]]; then
  RUSTUP_SIZE=$(du -sh "$RUSTUP_INIT" 2>/dev/null | cut -f1 || echo "unknown")
  log "Rust toolchain installer already exists ($RUSTUP_SIZE). Skipping download."
  mark_success "rust_toolchain"
  RUST_TOOLCHAIN_EXISTS=true
  # #region agent log
  debug_log "get_bundle.sh:rust_toolchain:exists" "Rust toolchain already exists" "{\"size\":\"$RUSTUP_SIZE\"}" "RUST-TOOLCHAIN-A" "run1"
  # #endregion
else
  RUST_TOOLCHAIN_EXISTS=false
  log "Downloading Rust toolchain installer..."
  
  # #region agent log
  debug_log "get_bundle.sh:rust_toolchain:download_start" "Starting Rust toolchain download" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "RUST-TOOLCHAIN-B" "run1"
  # #endregion
  
  python3 - <<'PY' "$BUNDLE_DIR"
import sys, urllib.request, time, os
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"rust"/"toolchain"
outdir.mkdir(parents=True, exist_ok=True)

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=120):
    """Download file with retry logic and timeout."""
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                with open(filename, 'wb') as f:
                    f.write(response.read())
            return
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            if attempt < max_retries:
                wait_time = 2 ** attempt
                print(f"Download attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
                if os.path.exists(filename):
                    os.remove(filename)
            else:
                print(f"ERROR: All {max_retries} download attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

# Download rustup-init for Linux x86_64
rustup_url = "https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
rustup_path = outdir/"rustup-init"

try:
    print("Downloading rustup-init...")
    urlretrieve_with_retry(rustup_url, str(rustup_path), max_retries=3, timeout=120)
    rustup_path.chmod(0o755)  # Make executable
    print("Downloaded rustup-init")
except (urllib.error.URLError, TimeoutError, OSError) as e:
    print(f"ERROR: Network error downloading rustup-init: {e}", file=sys.stderr)
    print("You may need to download it manually from https://rustup.rs/", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
    sys.exit(1)
PY
  # Verify rustup-init was downloaded
  if [[ -f "$BUNDLE_DIR/rust/toolchain/rustup-init" ]]; then
    # Also create a symlink/copy in the rust directory for easy access
    cp "$BUNDLE_DIR/rust/toolchain/rustup-init" "$BUNDLE_DIR/rust/rustup-init" 2>/dev/null || true
    log "Rust toolchain installer downloaded."
    mark_success "rust_toolchain"
    # #region agent log
    debug_log "get_bundle.sh:rust_toolchain:download_success" "Rust toolchain downloaded successfully" "{\"rustup_init\":\"$BUNDLE_DIR/rust/toolchain/rustup-init\",\"exists\":true,\"executable\":$(test -x "$BUNDLE_DIR/rust/toolchain/rustup-init" && echo true || echo false)}" "RUST-TOOLCHAIN-B" "run1"
    # #endregion
  else
    log "WARNING: rustup-init not downloaded. You may need to download it manually."
    mark_failed "rust_toolchain"
    # #region agent log
    debug_log "get_bundle.sh:rust_toolchain:download_failed" "Rust toolchain download failed" "{\"rustup_init\":\"$BUNDLE_DIR/rust/toolchain/rustup-init\",\"exists\":false}" "RUST-TOOLCHAIN-C" "run1"
    # #endregion
  fi
fi

# ============
# 8b) Build and bundle Rust crates (if Cargo.toml exists)
# ============
RUST_CARGO_TOML="${RUST_CARGO_TOML:-Cargo.toml}"

# #region agent log
debug_log "get_bundle.sh:rust_crates:check" "Checking for Cargo.toml" "{\"cargo_toml\":\"$RUST_CARGO_TOML\",\"exists\":$(test -f "$RUST_CARGO_TOML" && echo true || echo false)}" "RUST-CRATES-A" "run1"
# #endregion

if [[ -f "$RUST_CARGO_TOML" ]]; then
  log "Found Cargo.toml. Building and bundling Rust crates for offline use..."
  log "Note: This requires cargo to be installed on the build machine."
  
  # #region agent log
  debug_log "get_bundle.sh:rust_crates:cargo_check" "Checking for cargo command" "{\"cargo_exists\":$(command -v cargo >/dev/null 2>&1 && echo true || echo false)}" "RUST-CRATES-B" "run1"
  # #endregion
  
  # Check if cargo is available, try to install if not
  if ! command -v cargo >/dev/null 2>&1; then
    log "cargo is not installed. Attempting to install Rust toolchain..."
    # #region agent log
    debug_log "get_bundle.sh:rust_crates:install_cargo" "Attempting to install cargo" "{\"status\":\"attempting\"}" "RUST-CRATES-G" "run1"
    # #endregion
    
    CARGO_INSTALLED=false
    
    # Try 1: Use rustup-init if it exists in the bundle
    RUSTUP_INIT="$BUNDLE_DIR/rust/toolchain/rustup-init"
    if [[ -f "$RUSTUP_INIT" ]] && [[ -x "$RUSTUP_INIT" ]]; then
      log "  Found rustup-init in bundle. Installing Rust toolchain..."
      if "$RUSTUP_INIT" -y --default-toolchain stable --profile minimal >/dev/null 2>&1; then
        # Source cargo from rustup installation
        if [[ -f "$HOME/.cargo/env" ]]; then
          source "$HOME/.cargo/env"
        fi
        if command -v cargo >/dev/null 2>&1; then
          log "✓ Rust toolchain installed successfully via rustup-init"
          CARGO_INSTALLED=true
          # #region agent log
          debug_log "get_bundle.sh:rust_crates:cargo_installed_rustup" "cargo installed successfully via rustup-init" "{\"status\":\"success\"}" "RUST-CRATES-G" "run1"
          # #endregion
        fi
      fi
    fi
    
    # Try 2: Install via apt-get if rustup failed and sudo is available
    if [[ "$CARGO_INSTALLED" == "false" ]] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      log "  rustup-init not available or failed. Trying apt-get install rustc cargo (requires sudo)..."
      if sudo apt-get install -y rustc cargo >/dev/null 2>&1; then
        if command -v cargo >/dev/null 2>&1; then
          log "✓ Rust toolchain installed successfully via apt-get"
          CARGO_INSTALLED=true
          # #region agent log
          debug_log "get_bundle.sh:rust_crates:cargo_installed_apt" "cargo installed successfully via apt-get" "{\"status\":\"success\"}" "RUST-CRATES-G" "run1"
          # #endregion
        fi
      fi
    fi
    
    # If still not installed, skip with helpful message
    if [[ "$CARGO_INSTALLED" == "false" ]]; then
      log "WARNING: Failed to install cargo. Rust crate bundling requires cargo."
      log "Skipping Rust crate bundling. You can:"
      log "  1. Install Rust manually: sudo apt-get install -y rustc cargo"
      log "  2. Or use rustup: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
      log "  3. Then re-run this script"
      mark_skipped "rust_crates"
      # #region agent log
      debug_log "get_bundle.sh:rust_crates:cargo_install_failed" "cargo installation failed, skipping Rust crates" "{\"status\":\"skipped\"}" "RUST-CRATES-G" "run1"
      # #endregion
    fi
  fi
  
  # Check if cargo is now available (either was already there or just installed)
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
    
    # #region agent log
    debug_log "get_bundle.sh:rust_crates:vendor_start" "Starting cargo vendor" "{\"crates_dir\":\"$CRATES_DIR\",\"cargo_toml\":\"$CRATES_DIR/Cargo.toml\"}" "RUST-CRATES-C" "run1"
    # #endregion
    
    (cd "$CRATES_DIR" && cargo vendor --manifest-path "$(pwd)/Cargo.toml" vendor 2>/dev/null || {
      log "WARNING: cargo vendor failed. You may need to run it manually:"
      log "  cd $CRATES_DIR && cargo vendor"
      mark_failed "rust_crates"
      # #region agent log
      debug_log "get_bundle.sh:rust_crates:vendor_failed" "cargo vendor failed" "{\"crates_dir\":\"$CRATES_DIR\",\"exit_code\":$?}" "RUST-CRATES-D" "run1"
      # #endregion
      exit 1
    })
    
    if [[ -d "$CRATES_DIR/vendor" ]]; then
      log "Rust crates bundled successfully."
      log "All dependencies are vendored and ready for offline builds."
      mark_success "rust_crates"
      # #region agent log
      debug_log "get_bundle.sh:rust_crates:vendor_success" "cargo vendor completed successfully" "{\"vendor_dir\":\"$CRATES_DIR/vendor\",\"exists\":true}" "RUST-CRATES-C" "run1"
      # #endregion
    else
      log "ERROR: cargo vendor did not create vendor directory."
      mark_failed "rust_crates"
      # #region agent log
      debug_log "get_bundle.sh:rust_crates:vendor_no_dir" "vendor directory not created" "{\"vendor_dir\":\"$CRATES_DIR/vendor\",\"exists\":false}" "RUST-CRATES-E" "run1"
      # #endregion
    fi
  else
    log "WARNING: cargo not found. Cannot bundle Rust crates."
    log "Install Rust first (rustup-init is in the bundle), then re-run this script to bundle crates."
    mark_skipped "rust_crates"
    # #region agent log
    debug_log "get_bundle.sh:rust_crates:cargo_missing" "cargo command not found" "{\"status\":\"skipped\"}" "RUST-CRATES-F" "run1"
    # #endregion
  fi
else
  log "No Cargo.toml found. Skipping Rust crate bundling."
  mark_skipped "rust_crates"
  # #region agent log
  debug_log "get_bundle.sh:rust_crates:no_toml" "Cargo.toml not found" "{\"status\":\"skipped\"}" "RUST-CRATES-A" "run1"
  # #endregion
fi

# ============
# 9) Download Python packages (if requirements.txt exists)
# ============
PYTHON_REQUIREMENTS="${PYTHON_REQUIREMENTS:-requirements.txt}"

# #region agent log
debug_log "get_bundle.sh:python_packages:check" "Checking for requirements.txt" "{\"requirements_file\":\"$PYTHON_REQUIREMENTS\",\"exists\":$(test -f "$PYTHON_REQUIREMENTS" && echo true || echo false)}" "PYTHON-A" "run1"
# #endregion

if [[ -f "$PYTHON_REQUIREMENTS" ]]; then
  # Check if pip is available before attempting download
  if ! python3 -m pip --version >/dev/null 2>&1; then
    log "pip is not installed. Attempting to install pip..."
    # #region agent log
    debug_log "get_bundle.sh:python_packages:install_pip" "Attempting to install pip" "{\"status\":\"attempting\"}" "PYTHON-E" "run1"
    # #endregion
    
    PIP_INSTALLED=false
    
    # Try 1: ensurepip (doesn't require sudo, installs in user space)
    log "  Trying ensurepip (no sudo required)..."
    if python3 -m ensurepip --upgrade >/dev/null 2>&1; then
      if python3 -m pip --version >/dev/null 2>&1; then
        log "✓ pip installed successfully via ensurepip"
        PIP_INSTALLED=true
        # #region agent log
        debug_log "get_bundle.sh:python_packages:pip_installed_ensurepip" "pip installed successfully via ensurepip" "{\"status\":\"success\"}" "PYTHON-E" "run1"
        # #endregion
      fi
    fi
    
    # Try 2: Install via apt-get if ensurepip failed and sudo is available
    if [[ "$PIP_INSTALLED" == "false" ]] && command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      log "  ensurepip failed. Trying apt-get install python3-pip (requires sudo)..."
      if sudo apt-get install -y python3-pip >/dev/null 2>&1; then
        if python3 -m pip --version >/dev/null 2>&1; then
          log "✓ pip installed successfully via apt-get"
          PIP_INSTALLED=true
          # #region agent log
          debug_log "get_bundle.sh:python_packages:pip_installed_apt" "pip installed successfully via apt-get" "{\"status\":\"success\"}" "PYTHON-E" "run1"
          # #endregion
        fi
      fi
    fi
    
    # If still not installed, skip with helpful message
    if [[ "$PIP_INSTALLED" == "false" ]]; then
      log "WARNING: Failed to install pip. Python package download requires pip."
      log "Skipping Python package download. You can:"
      log "  1. Install pip manually: sudo apt-get install -y python3-pip"
      log "  2. Or install pip via ensurepip: python3 -m ensurepip --upgrade"
      log "  3. Then re-run this script"
      mark_skipped "python_packages"
      # #region agent log
      debug_log "get_bundle.sh:python_packages:pip_install_failed" "pip installation failed, skipping Python packages" "{\"status\":\"skipped\"}" "PYTHON-E" "run1"
      # #endregion
    fi
  fi
  
  # Check again if pip is now available (either was already there or just installed)
  if python3 -m pip --version >/dev/null 2>&1; then
    log "Found requirements.txt. Downloading and building Python packages for Linux..."
    log "Note: This will download packages and build source distributions to ensure they work on this system."
    
    # #region agent log
    debug_log "get_bundle.sh:python_packages:download_start" "Starting Python package download" "{\"bundle_dir\":\"$BUNDLE_DIR\",\"requirements_file\":\"$PYTHON_REQUIREMENTS\"}" "PYTHON-B" "run1"
    # #endregion
    
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
# We download with dependencies to ensure everything is bundled
try:
    # Step 1: Download binary wheels with ALL dependencies
    # pip download automatically includes dependencies unless --no-deps is specified
    # Download wheels for current platform (no platform restriction = current platform)
    print("Step 1: Downloading binary wheels for current Linux platform (with ALL dependencies)...")
    result = subprocess.run([
        sys.executable, "-m", "pip", "download",
        "-r", str(requirements),
        "-d", str(outdir),
        # No --platform flag = use current platform (most compatible)
        # No --only-binary flag = prefer wheels but allow source if needed
        # IMPORTANT: No --no-deps flag, so ALL transitive dependencies are included
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Warning: Binary wheel download had issues:")
        if result.stdout:
            print(f"  stdout: {result.stdout[:500]}")
        if result.stderr:
            print(f"  stderr: {result.stderr[:500]}")
    else:
        wheels_downloaded = len(list(outdir.glob("*.whl")))
        print(f"✓ Downloaded {wheels_downloaded} binary wheels")
    
    # Step 2: Download source distributions as fallback ONLY for packages without wheels
    # Check which packages from requirements don't have wheels, and only download source for those
    print("Step 2: Checking for packages without binary wheels...")
    existing_wheels = {f.stem.split('-')[0].lower().replace('_', '-') for f in outdir.glob("*.whl")}
    
    # Read requirements to see what packages we need
    required_packages = []
    with open(requirements, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                # Extract package name (handle formats like "package>=1.0", "package[extra]", etc.)
                pkg_name = line.split('[')[0].split('>=')[0].split('==')[0].split('!=')[0].split('<=')[0].split('<')[0].split('>')[0].strip()
                if pkg_name:
                    required_packages.append(pkg_name.lower().replace('_', '-'))
    
    # Find packages that don't have wheels
    missing_wheels = [pkg for pkg in required_packages if pkg not in existing_wheels]
    
    if missing_wheels:
        print(f"Step 2: Downloading source distributions for {len(missing_wheels)} packages without wheels...")
        # Only download source for packages that don't have wheels
        # Use --no-binary for specific packages, not :all:
        for pkg in missing_wheels:
            print(f"  Downloading source for {pkg}...")
            subprocess.run([
                sys.executable, "-m", "pip", "download",
                pkg,
                "-d", str(outdir),
                "--no-binary", pkg,  # Only this package as source
            ], capture_output=True, text=True, check=False)
    else:
        print("Step 2: All packages have binary wheels, skipping source downloads.")
    
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
    print(f"✓ Downloaded {downloaded} package files ({wheels} wheels, {downloaded - wheels} source dists)")
    print(f"✓ All dependencies are included (pip download includes transitive dependencies)")
    print(f"  Note: Source distributions have been built into wheels where possible")
    
    print(f"Python packages ready in {outdir}")
    print(f"All packages are pre-built and ready for offline installation.")
except subprocess.CalledProcessError as e:
    print(f"Warning: Could not download all Python packages: {e}")
    print("Some packages may need to be downloaded manually or built from source.")
except FileNotFoundError:
    print("Warning: pip not found. Skipping Python package download.")
except Exception as e:
    print(f"Warning: Error downloading Python packages: {e}")
PY
    # Check if any packages were downloaded
    PYTHON_PKG_COUNT=$(ls -A "$BUNDLE_DIR/python"/*.whl "$BUNDLE_DIR/python"/*.tar.gz 2>/dev/null | wc -l)
    
    # #region agent log
    debug_log "get_bundle.sh:python_packages:check_results" "Checking Python package download results" "{\"package_count\":$PYTHON_PKG_COUNT,\"python_dir\":\"$BUNDLE_DIR/python\"}" "PYTHON-C" "run1"
    # #endregion
    
    if [[ -n "$(ls -A "$BUNDLE_DIR/python"/*.whl "$BUNDLE_DIR/python"/*.tar.gz 2>/dev/null)" ]]; then
      log "Python packages downloaded successfully."
      mark_success "python_packages"
      # #region agent log
      debug_log "get_bundle.sh:python_packages:success" "Python packages downloaded successfully" "{\"package_count\":$PYTHON_PKG_COUNT,\"status\":\"success\"}" "PYTHON-C" "run1"
      # #endregion
      log "Note: All packages have been downloaded and built. Ready for offline installation."
    else
      log "WARNING: No Python packages were downloaded."
      log "This may be due to network issues, package availability, or pip errors."
      mark_failed "python_packages"
      # #region agent log
      debug_log "get_bundle.sh:python_packages:failed" "No Python packages downloaded" "{\"package_count\":$PYTHON_PKG_COUNT,\"status\":\"failed\"}" "PYTHON-D" "run1"
      # #endregion
    fi
  else
    # pip is still not available after installation attempt
    log "WARNING: pip is still not available after installation attempt."
    log "Skipping Python package download."
    mark_skipped "python_packages"
    # #region agent log
    debug_log "get_bundle.sh:python_packages:pip_unavailable" "pip still unavailable after installation attempt" "{\"status\":\"skipped\"}" "PYTHON-E" "run1"
    # #endregion
  fi  # End of pip availability check
else
  log "No requirements.txt found. Skipping Python package download."
  mark_skipped "python_packages"
  # #region agent log
  debug_log "get_bundle.sh:python_packages:skipped" "requirements.txt not found, skipping" "{\"status\":\"skipped\"}" "PYTHON-A" "run1"
  # #endregion
fi

# ============
# Final Summary
# ============
log ""
log "=========================================="
log "BUNDLE CREATION SUMMARY"
log "=========================================="
log ""

# #region agent log
debug_log "get_bundle.sh:summary:start" "Generating final summary" "{\"bundle_dir\":\"$BUNDLE_DIR\"}" "SUMMARY-A" "run1"
# #endregion

# Check each component and report status
HAS_FAILURES=false
HAS_WARNINGS=false

# List of all components to check
COMPONENTS="ollama_linux models vscodium continue python_ext rust_ext rust_toolchain rust_crates python_packages apt_repo"

for component in $COMPONENTS; do
  status="$(get_status "$component")"
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
fi

TOTAL_SIZE=$(du -sh "$BUNDLE_DIR" 2>/dev/null | cut -f1 || echo "unknown")
log "Total bundle size: $TOTAL_SIZE"
log ""

# Provide actionable next steps
if [[ "$HAS_FAILURES" == "true" ]]; then
  log "=========================================="
  log "⚠️  ACTION REQUIRED: Some components failed"
  log "=========================================="
  log ""
  
  if [[ "$(get_status models)" == "failed" ]]; then
    log "MODELS FAILED:"
    if [[ -d "$HOME/.ollama/models" ]] && [[ -n "$(ls -A "$HOME/.ollama/models" 2>/dev/null)" ]]; then
      EXISTING_SIZE=$(du -sh "$HOME/.ollama/models" 2>/dev/null | cut -f1 || echo "unknown")
      log "  → Found existing models in ~/.ollama/models ($EXISTING_SIZE)"
      log "  → To copy them manually, run:"
      log "     mkdir -p $BUNDLE_DIR/models"
      log "     rsync -av --progress ~/.ollama/ $BUNDLE_DIR/models/.ollama/"
    else
      log "  → No existing models found. You need to:"
      log "     1. Ensure Ollama is installed and working"
      log "     2. Pull models manually: ollama pull <model-name>"
      log "     3. Re-run this script or copy ~/.ollama manually"
    fi
    log ""
  fi
  
  if [[ "$(get_status vscodium)" == "failed" ]]; then
    log "VSCODIUM FAILED:"
    log "  → Re-run this script to retry download"
    log "  → Or download manually from: https://github.com/VSCodium/vscodium/releases"
    log ""
  fi
  
  if [[ "$(get_status continue)" == "failed" ]] || [[ "$(get_status python_ext)" == "failed" ]] || [[ "$(get_status rust_ext)" == "failed" ]]; then
    log "EXTENSIONS FAILED:"
    log "  → Re-run this script to retry download"
    log "  → Or download manually from: https://open-vsx.org"
    log ""
  fi
  
  if [[ "$(get_status rust_toolchain)" == "failed" ]]; then
    log "RUST TOOLCHAIN FAILED:"
    log "  → Re-run this script to retry download"
    log "  → Or download manually from: https://rustup.rs"
    log ""
  fi
  
  if [[ "$(get_status python_packages)" == "failed" ]]; then
    log "PYTHON PACKAGES FAILED:"
    log "  → Check that requirements.txt exists and is valid"
    log "  → Ensure pip is installed: python3 -m pip --version"
    log "  → Re-run this script to retry"
    log ""
  fi
  
  log "After fixing issues, re-run: ./get_bundle.sh"
  log ""
fi

if [[ "$HAS_WARNINGS" == "true" ]] && [[ "$HAS_FAILURES" != "true" ]]; then
  log "⚠️  Some optional components were skipped (this is normal)"
  log ""
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
fi

log "Bundle location: $BUNDLE_DIR"
log ""

# #region agent log
debug_log "get_bundle.sh:complete" "Script execution completed" "{\"bundle_dir\":\"$BUNDLE_DIR\",\"has_failures\":\"$HAS_FAILURES\",\"has_warnings\":\"$HAS_WARNINGS\",\"total_size\":\"$TOTAL_SIZE\"}" "SUMMARY-B" "run1"
# #endregion
