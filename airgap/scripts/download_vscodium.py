import json, sys, urllib.request, time, os
from pathlib import Path
# Add current directory to path to allow importing utils if run directly
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from utils import urlopen_with_retry, urlretrieve_with_retry

if len(sys.argv) < 2:
    print("Usage: python3 download_vscodium.py <bundle_dir>")
    sys.exit(1)

bundle = Path(sys.argv[1])
outdir = bundle/"vscodium"
outdir.mkdir(parents=True, exist_ok=True)

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
