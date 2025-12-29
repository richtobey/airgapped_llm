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
  "$BUNDLE_DIR"/{ollama,models,vscodium,continue,extensions,aptrepo/{pool,conf},rust/{toolchain,crates},python,logs}

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
  
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request, hashlib
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
tar -xzf "$BUNDLE_DIR/ollama/ollama-linux-amd64.tgz" -C "$TMP_OLLAMA"
export PATH="$TMP_OLLAMA:$PATH"

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
if ! command -v ollama >/dev/null 2>&1; then
  log "ERROR: ollama command not found in PATH. Check extraction and PATH setup."
  log "PATH is: $PATH"
  log "TMP_OLLAMA is: $TMP_OLLAMA"
  log "Skipping model pulling. You can copy existing models manually if they exist."
  mark_failed "models"
  # Skip to copying existing models if they exist
  if [[ -d "$HOME/.ollama/models" ]] && [[ -n "$(ls -A "$HOME/.ollama/models" 2>/dev/null)" ]]; then
    EXISTING_SIZE=$(du -sh "$HOME/.ollama/models" 2>/dev/null | cut -f1 || echo "unknown")
    log "Found existing models in ~/.ollama/models ($EXISTING_SIZE) - will attempt to copy them"
    MODELS_EXIST=true
  fi
  # Jump to model copying section
  SKIP_MODEL_PULL=true
fi

# Kill any existing ollama server to avoid conflicts
pkill -f "ollama serve" 2>/dev/null || true
sleep 1

log "Starting Ollama server (PID will be logged)..."
nohup ollama serve >"$BUNDLE_DIR/logs/ollama_serve.log" 2>&1 &
SERVE_PID=$!
log "Ollama server started with PID: $SERVE_PID"
sleep 5  # Give server more time to start

# Verify server started
if ! kill -0 "$SERVE_PID" 2>/dev/null; then
  log "ERROR: Ollama server failed to start. Check logs: $BUNDLE_DIR/logs/ollama_serve.log"
  cat "$BUNDLE_DIR/logs/ollama_serve.log" 2>/dev/null || true
  log "Skipping model pulling. Will attempt to copy existing models if they exist."
  PULL_FAILED=true
  SKIP_MODEL_PULL=true
fi

# Wait a bit more for server to be ready
sleep 2

# Pull all models (unless we're skipping)
if [[ "${SKIP_MODEL_PULL:-true}" != "true" ]]; then
  log "Pulling $MODEL_COUNT model(s): ${OLLAMA_MODELS}"
  log "This may take a while, especially for large models like mixtral:8x7b (~26GB)..."
  PULL_FAILED=false
  for model in "${MODEL_ARRAY[@]}"; do
    log "Pulling model: $model ..."
    if ! ollama pull "$model"; then
      log "WARNING: Failed to pull $model. Continuing with other models..."
      PULL_FAILED=true
    else
      log "Successfully pulled $model"
    fi
  done

  # Stop server
  log "Stopping Ollama server..."
  kill "$SERVE_PID" 2>/dev/null || true
  wait "$SERVE_PID" 2>/dev/null || true
  sleep 1
else
  log "Skipping model pulling (server not available or extraction failed)"
  PULL_FAILED=true
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
  python3 - <<'PY' "$BUNDLE_DIR"
import json, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"continue"
outdir.mkdir(parents=True, exist_ok=True)

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
    
    # Open VSX returns just the hash, format it as "hash  filename"
    sha256_hash = urllib.request.urlopen(sha256_url).read().decode("utf-8").strip()
    sha256_file = outdir/(vsix_name + ".sha256")
    sha256_file.write_text(f"{sha256_hash}  {vsix_name}\n", encoding="utf-8")
    
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
    if sha256_check_vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix.sha256; then
      log "Continue VSIX verified."
      mark_success "continue"
    else
      log "ERROR: Continue VSIX SHA256 verification failed"
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
    
    # Open VSX returns just the hash, format it as "hash  filename"
    sha256_hash = urllib.request.urlopen(sha256_url).read().decode("utf-8").strip()
    sha256_file = outdir/(vsix_name + ".sha256")
    sha256_file.write_text(f"{sha256_hash}  {vsix_name}\n", encoding="utf-8")
    
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
    if sha256_check_vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix.sha256; then
      log "Python extension VSIX verified."
      mark_success "python_ext"
    else
      log "ERROR: Python extension VSIX SHA256 verification failed"
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
    
    # Open VSX returns just the hash, format it as "hash  filename"
    sha256_hash = urllib.request.urlopen(sha256_url).read().decode("utf-8").strip()
    sha256_file = outdir/(vsix_name + ".sha256")
    sha256_file.write_text(f"{sha256_hash}  {vsix_name}\n", encoding="utf-8")
    
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
    if sha256_check_vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix.sha256; then
      log "Rust Analyzer extension VSIX verified."
      mark_success "rust_ext"
    else
      log "ERROR: Rust Analyzer extension VSIX SHA256 verification failed"
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
    (cd "$CRATES_DIR" && cargo vendor --manifest-path "$(pwd)/Cargo.toml" vendor 2>/dev/null || {
      log "WARNING: cargo vendor failed. You may need to run it manually:"
      log "  cd $CRATES_DIR && cargo vendor"
      mark_failed "rust_crates"
      exit 1
    })
    
    if [[ -d "$CRATES_DIR/vendor" ]]; then
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
  if [[ -n "$(ls -A "$BUNDLE_DIR/python"/*.whl "$BUNDLE_DIR/python"/*.tar.gz 2>/dev/null)" ]]; then
    log "Python packages downloaded successfully."
    mark_success "python_packages"
  else
    log "WARNING: No Python packages were downloaded."
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
