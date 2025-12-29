#!/usr/bin/env bash
set -euo pipefail

# Script to download missing bundle components
# Run this if get_bundle.sh didn't download everything

BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"

log() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "[$(date +"%Y-%m-%dT%H:%M:%S%z")] $*"
  else
    echo "[$(date -Is)] $*"
  fi
}

sha256_check_file() {
  local file="$1"
  local sha_file="$2"
  if [[ "$(uname -s)" == "Linux" ]] && command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")")
  elif command -v shasum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && shasum -a 256 -c "$(basename "$sha_file")")
  elif command -v sha256sum >/dev/null 2>&1; then
    (cd "$(dirname "$file")" && sha256sum -c "$(basename "$sha_file")")
  else
    log "ERROR: Neither sha256sum nor shasum found"
    exit 1
  fi
}

mkdir -p "$BUNDLE_DIR"/{vscodium,continue,extensions,rust/toolchain,python,logs}

# ============
# 1) VSCodium .deb + published .sha256, then verify
# ============
if [[ -z "$(ls -A "$BUNDLE_DIR/vscodium" 2>/dev/null)" ]]; then
  log "Downloading VSCodium latest .deb + .sha256..."
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
  sha256_check_file "$BUNDLE_DIR/vscodium/"*_amd64.deb "$BUNDLE_DIR/vscodium/"*_amd64.deb.sha256
  log "VSCodium verified."
else
  log "VSCodium already downloaded, skipping..."
fi

# ============
# 2) Continue.dev VSIX from Open VSX + sha256 resource, then verify
# ============
if [[ -z "$(ls -A "$BUNDLE_DIR/continue" 2>/dev/null)" ]]; then
  log "Downloading Continue VSIX + sha256 from Open VSX..."
  python3 - <<'PY' "$BUNDLE_DIR"
import re, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"continue"
outdir.mkdir(parents=True, exist_ok=True)

page_url = "https://open-vsx.org/extension/Continue/continue"
html = urllib.request.urlopen(page_url).read().decode("utf-8", errors="ignore")

m_ver = re.search(r'"version"\s*:\s*"([^"]+)"', html)
version = m_ver.group(1) if m_ver else None
if not version:
  m = re.search(r'/api/Continue/continue/([^/]+)/file/', html)
  version = m.group(1) if m else None
if not version:
  raise SystemExit("Could not determine Continue extension version from Open VSX page HTML.")

vsix_name = f"Continue.continue-{version}.vsix"
download_url = f"https://open-vsx.org/api/Continue/continue/{version}/file/{vsix_name}"
sha256_url   = f"https://open-vsx.org/api/Continue/continue/{version}/sha256"

urllib.request.urlretrieve(download_url, outdir/vsix_name)
urllib.request.urlretrieve(sha256_url, outdir/(vsix_name + ".sha256"))

print("Version:", version)
print("Downloaded:", vsix_name)
print("SHA256 URL:", sha256_url)
PY

  log "Verifying Continue VSIX sha256..."
  sha256_check_file "$BUNDLE_DIR/continue/"Continue.continue-*.vsix "$BUNDLE_DIR/continue/"Continue.continue-*.vsix.sha256
  log "Continue VSIX verified."
else
  log "Continue VSIX already downloaded, skipping..."
fi

# ============
# 3) Python Extension VSIX from Open VSX + sha256, then verify
# ============
if [[ -z "$(ls -A "$BUNDLE_DIR/extensions" 2>/dev/null)" ]] || [[ -z "$(ls -A "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix 2>/dev/null)" ]]; then
  log "Downloading Python extension VSIX + sha256 from Open VSX..."
  python3 - <<'PY' "$BUNDLE_DIR"
import re, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

page_url = "https://open-vsx.org/extension/ms-python/python"
html = urllib.request.urlopen(page_url).read().decode("utf-8", errors="ignore")

m_ver = re.search(r'"version"\s*:\s*"([^"]+)"', html)
version = m_ver.group(1) if m_ver else None
if not version:
  m = re.search(r'/api/ms-python/python/([^/]+)/file/', html)
  version = m.group(1) if m else None
if not version:
  raise SystemExit("Could not determine Python extension version from Open VSX page HTML.")

vsix_name = f"ms-python.python-{version}.vsix"
download_url = f"https://open-vsx.org/api/ms-python/python/{version}/file/{vsix_name}"
sha256_url   = f"https://open-vsx.org/api/ms-python/python/{version}/sha256"

urllib.request.urlretrieve(download_url, outdir/vsix_name)
urllib.request.urlretrieve(sha256_url, outdir/(vsix_name + ".sha256"))

print("Version:", version)
print("Downloaded:", vsix_name)
print("SHA256 URL:", sha256_url)
PY

  log "Verifying Python extension VSIX sha256..."
  sha256_check_file "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix "$BUNDLE_DIR/extensions/"ms-python.python-*.vsix.sha256
  log "Python extension VSIX verified."
else
  log "Python extension VSIX already downloaded, skipping..."
fi

# ============
# 4) Rust Analyzer Extension VSIX from Open VSX + sha256, then verify
# ============
if [[ -z "$(ls -A "$BUNDLE_DIR/extensions" 2>/dev/null)" ]] || [[ -z "$(ls -A "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix 2>/dev/null)" ]]; then
  log "Downloading Rust Analyzer extension VSIX + sha256 from Open VSX..."
  python3 - <<'PY' "$BUNDLE_DIR"
import re, sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"extensions"
outdir.mkdir(parents=True, exist_ok=True)

page_url = "https://open-vsx.org/extension/rust-lang/rust-analyzer"
html = urllib.request.urlopen(page_url).read().decode("utf-8", errors="ignore")

m_ver = re.search(r'"version"\s*:\s*"([^"]+)"', html)
version = m_ver.group(1) if m_ver else None
if not version:
  m = re.search(r'/api/rust-lang/rust-analyzer/([^/]+)/file/', html)
  version = m.group(1) if m else None
if not version:
  raise SystemExit("Could not determine Rust Analyzer extension version from Open VSX page HTML.")

vsix_name = f"rust-lang.rust-analyzer-{version}.vsix"
download_url = f"https://open-vsx.org/api/rust-lang/rust-analyzer/{version}/file/{vsix_name}"
sha256_url   = f"https://open-vsx.org/api/rust-lang/rust-analyzer/{version}/sha256"

urllib.request.urlretrieve(download_url, outdir/vsix_name)
urllib.request.urlretrieve(sha256_url, outdir/(vsix_name + ".sha256"))

print("Version:", version)
print("Downloaded:", vsix_name)
print("SHA256 URL:", sha256_url)
PY

  log "Verifying Rust Analyzer extension VSIX sha256..."
  sha256_check_file "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix "$BUNDLE_DIR/extensions/"rust-lang.rust-analyzer-*.vsix.sha256
  log "Rust Analyzer extension VSIX verified."
else
  log "Rust Analyzer extension VSIX already downloaded, skipping..."
fi

# ============
# 5) Download Rust toolchain (rustup-init)
# ============
if [[ ! -f "$BUNDLE_DIR/rust/toolchain/rustup-init" ]] && [[ ! -f "$BUNDLE_DIR/rust/rustup-init" ]]; then
  log "Downloading Rust toolchain installer..."
  python3 - <<'PY' "$BUNDLE_DIR"
import sys, urllib.request
from pathlib import Path

bundle = Path(sys.argv[1])
outdir = bundle/"rust"/"toolchain"
outdir.mkdir(parents=True, exist_ok=True)

rustup_url = "https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init"
rustup_path = outdir/"rustup-init"

try:
    urllib.request.urlretrieve(rustup_url, rustup_path)
    rustup_path.chmod(0o755)
    print("Downloaded rustup-init")
except Exception as e:
    raise SystemExit(f"Could not download rustup-init: {e}")
PY

  if [[ -f "$BUNDLE_DIR/rust/toolchain/rustup-init" ]]; then
    cp "$BUNDLE_DIR/rust/toolchain/rustup-init" "$BUNDLE_DIR/rust/rustup-init" 2>/dev/null || true
    log "Rust toolchain installer downloaded."
  fi
else
  log "Rust toolchain installer already downloaded, skipping..."
fi

# ============
# 6) Download Python packages (if requirements.txt exists)
# ============
PYTHON_REQUIREMENTS="${PYTHON_REQUIREMENTS:-requirements.txt}"
if [[ -f "$PYTHON_REQUIREMENTS" ]] && [[ -z "$(ls -A "$BUNDLE_DIR/python" 2>/dev/null)" ]]; then
  log "Found requirements.txt. Downloading Python packages for Linux..."
  python3 - <<'PY' "$BUNDLE_DIR" "$PYTHON_REQUIREMENTS"
import sys, subprocess
from pathlib import Path

bundle = Path(sys.argv[1])
requirements = Path(sys.argv[2])
outdir = bundle/"python"
outdir.mkdir(parents=True, exist_ok=True)

import shutil
shutil.copy(requirements, outdir/"requirements.txt")

try:
    print("Step 1: Downloading binary wheels for Linux (with ALL dependencies)...")
    result = subprocess.run([
        sys.executable, "-m", "pip", "download",
        "-r", str(requirements),
        "-d", str(outdir),
        "--platform", "manylinux2014_x86_64",
        "--platform", "manylinux1_x86_64",
        "--platform", "linux_x86_64",
        "--only-binary", ":all:",
        "--python-version", "3",
    ], capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Warning: Some packages may not have binary wheels: {result.stderr}")
    
    print("Step 2: Downloading source distributions (with ALL dependencies)...")
    subprocess.run([
        sys.executable, "-m", "pip", "download",
        "-r", str(requirements),
        "-d", str(outdir),
        "--no-binary", ":all:",
    ], capture_output=True, text=True, check=False)
    
    downloaded = len(list(outdir.glob("*.whl"))) + len(list(outdir.glob("*.tar.gz")))
    print(f"✓ Downloaded {downloaded} package files (wheels and source distributions)")
    print(f"Downloaded Python packages to {outdir}")
except subprocess.CalledProcessError as e:
    print(f"Warning: Could not download all Python packages: {e}")
except FileNotFoundError:
    print("Warning: pip not found. Skipping Python package download.")
except Exception as e:
    print(f"Warning: Error downloading Python packages: {e}")
PY
  log "Python packages downloaded (if any)."
elif [[ ! -f "$PYTHON_REQUIREMENTS" ]]; then
  log "No requirements.txt found. Skipping Python package download."
else
  log "Python packages already downloaded, skipping..."
fi

log "DONE. Missing components downloaded to: $BUNDLE_DIR"

