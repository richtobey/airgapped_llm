import json, sys, urllib.request, hashlib, time, os
from pathlib import Path
# Add current directory to path to allow importing utils if run directly
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from utils import urlopen_with_retry, urlretrieve_with_retry

if len(sys.argv) < 2:
    print("Usage: python3 download_ollama.py <bundle_dir>")
    sys.exit(1)

bundle = Path(sys.argv[1])
outdir = bundle/"ollama"
outdir.mkdir(parents=True, exist_ok=True)
debug_log = os.environ.get("DEBUG_LOG", str(bundle/"logs"/"get_bundle_debug.log"))

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
