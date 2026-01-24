import sys, urllib.request, time, os
from pathlib import Path
# Add current directory to path to allow importing utils if run directly
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from utils import urlretrieve_with_retry

if len(sys.argv) < 2:
    print("Usage: python3 download_rust_toolchain.py <bundle_dir>")
    sys.exit(1)

bundle = Path(sys.argv[1])
outdir = bundle/"rust"/"toolchain"
outdir.mkdir(parents=True, exist_ok=True)

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
