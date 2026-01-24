import json, sys, urllib.request, time, os
from pathlib import Path
# Add current directory to path to allow importing utils if run directly
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
from utils import urlopen_with_retry, urlretrieve_with_retry

if len(sys.argv) < 4:
    print("Usage: python3 download_extension.py <bundle_dir> <extension_id> <output_subdir>")
    print("Example: python3 download_extension.py ./bundle ms-python/python extensions")
    sys.exit(1)

bundle = Path(sys.argv[1])
extension_id = sys.argv[2]
output_subdir = sys.argv[3]

outdir = bundle/output_subdir
outdir.mkdir(parents=True, exist_ok=True)
debug_log = os.environ.get("DEBUG_LOG", str(bundle/"logs"/"get_bundle_debug.log"))

# Use Open VSX API to get extension metadata
api_url = f"https://open-vsx.org/api/{extension_id}"
try:
    print(f"Fetching metadata for {extension_id}...")
    with urlopen_with_retry(api_url, max_retries=3, timeout=30) as response:
        data = json.loads(response.read().decode("utf-8"))
    
    # Get the latest version from the API response
    if isinstance(data, list) and len(data) > 0:
        latest = data[0]
        version = latest.get("version")
        namespace = latest.get("namespace")
        name = latest.get("name")
    elif isinstance(data, dict):
        version = data.get("version")
        namespace = data.get("namespace")
        name = data.get("name")
    else:
        raise SystemExit("Unexpected API response format")
    
    if not version:
        raise SystemExit("Could not determine version from API response")
    
    # Construct URLs using the discovered version
    vsix_name = f"{namespace}.{name}-{version}.vsix"
    
    # Try to find a valid download URL
    download_url = None
    
    # Method 1: Check 'files' -> 'download' in API response (most reliable)
    if isinstance(data, dict):
        files = data.get("files", {})
        if isinstance(files, dict) and "download" in files:
            download_url = files["download"]
            print(f"Using download URL from API response: {download_url}")
    elif isinstance(data, list) and len(data) > 0:
        latest_data = data[0]
        files = latest_data.get("files", {})
        if isinstance(files, dict) and "download" in files:
            download_url = files["download"]
            print(f"Using download URL from API response: {download_url}")
            
    # Method 2: Fallback to constructed URL if API didn't provide one
    if not download_url:
        download_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/file/{vsix_name}"
        print(f"Constructed download URL: {download_url}")

    sha256_url = f"https://open-vsx.org/api/{namespace}/{name}/{version}/sha256"
    
    # Download both
    print(f"VSIX download URL: {download_url}")
    print(f"SHA256 URL: {sha256_url}")
    print(f"Downloading {vsix_name}...")
    
    # Try downloading VSIX with retry
    try:
        urlretrieve_with_retry(download_url, str(outdir/vsix_name), max_retries=3, timeout=120)
    except IOError as e:
        # Check if it's a rate limit issue (small file that isn't a zip)
        if "not a valid ZIP archive" in str(e):
            print(f"WARNING: Download failed validation: {e}")
            print("Checking if we got an error page...")
            try:
                with open(outdir/vsix_name, 'r', errors='ignore') as f:
                    content = f.read(500)
                    if "<!DOCTYPE html>" in content or "<html" in content:
                        print("Received HTML instead of VSIX. Likely rate limited by Open VSX.")
                        print("Waiting 10 seconds before retrying...")
                        time.sleep(10)
                        urlretrieve_with_retry(download_url, str(outdir/vsix_name), max_retries=3, timeout=120)
                    else:
                        raise
            except Exception:
                raise e
        else:
            raise e

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
    
    # Log to debug log
    log_entry = {
        "id": f"log_{int(time.time())}_vsix_dl",
        "timestamp": int(time.time() * 1000),
        "location": "scripts/download_extension.py",
        "message": "VSIX downloaded",
        "data": {
            "extension_id": extension_id,
            "vsix_name": vsix_name,
            "vsix_size": vsix_size,
            "sha256_hash": sha256_hash
        },
        "sessionId": "debug-session",
        "runId": "run1"
    }
    try:
        os.makedirs(os.path.dirname(debug_log), exist_ok=True)
        with open(debug_log, "a") as f:
            f.write(json.dumps(log_entry) + "\n")
    except Exception:
        pass
    
    print("Version:", version)
    print("Downloaded:", vsix_name)
except (urllib.error.URLError, TimeoutError, OSError) as e:
    print(f"ERROR: Network error downloading {extension_id}: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Unexpected error: {e}", file=sys.stderr)
    sys.exit(1)
