import urllib.request
import urllib.error
import time
import os
import sys
import json
from datetime import datetime

# Debug configuration
DEBUG_LOG_PATH = os.environ.get("DEBUG_LOG", "debug_trace.log")

def log_debug(location, message, data, hypothesis_id="GENERAL"):
    try:
        timestamp = int(time.time() * 1000)
        log_entry = {
            "id": f"log_{timestamp}_{os.getpid()}",
            "timestamp": timestamp,
            "location": location,
            "message": message,
            "data": data,
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": hypothesis_id
        }
        # #region agent log
        log_dir = os.path.dirname(DEBUG_LOG_PATH)
        if log_dir and not os.path.exists(log_dir):
            os.makedirs(log_dir, exist_ok=True)
            
        with open(DEBUG_LOG_PATH, "a") as f:
            f.write(json.dumps(log_entry) + "\n")
        # #endregion
    except Exception:
        pass

def urlopen_with_retry(url, max_retries=3, timeout=30):
    """Open URL with retry logic and timeout."""
    log_debug("scripts/utils.py:urlopen_with_retry", "Function entry", {"url": url, "max_retries": max_retries}, "Hypothesis1")
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            log_debug("scripts/utils.py:urlopen_with_retry", "Attempting connection", {"attempt": attempt, "url": url}, "Hypothesis1")
            response = urllib.request.urlopen(request, timeout=timeout)
            log_debug("scripts/utils.py:urlopen_with_retry", "Connection successful", {"code": response.getcode(), "url": url}, "Hypothesis1")
            return response
        except (urllib.error.URLError, TimeoutError, OSError) as e:
            error_msg = str(e)
            log_debug("scripts/utils.py:urlopen_with_retry", "Connection failed", {"attempt": attempt, "error": error_msg}, "Hypothesis1")
            if attempt < max_retries:
                wait_time = 2 ** attempt  # Exponential backoff
                print(f"Attempt {attempt} failed: {error_msg}. Retrying in {wait_time} seconds...")
                print(f"  URL: {url}")
                time.sleep(wait_time)
            else:
                print(f"ERROR: All {max_retries} attempts failed for URL: {url}")
                print(f"ERROR: Last error: {error_msg}")
                raise

def urlretrieve_with_retry(url, filename, max_retries=3, timeout=120):
    """Download file with retry logic, timeout, and integrity verification."""
    log_debug("scripts/utils.py:urlretrieve_with_retry", "Function entry", {"url": url, "filename": filename}, "Hypothesis1")
    for attempt in range(1, max_retries + 1):
        try:
            request = urllib.request.Request(url)
            request.add_header('User-Agent', 'get_bundle.sh/1.0')
            with urllib.request.urlopen(request, timeout=timeout) as response:
                # Get expected file size from Content-Length header if available
                expected_size = response.headers.get('Content-Length')
                log_debug("scripts/utils.py:urlretrieve_with_retry", "Got headers", {"content_length": expected_size}, "Hypothesis2")
                if expected_size:
                    expected_size = int(expected_size)
                
                # Download file in chunks to handle large files
                downloaded_size = 0
                with open(filename, 'wb') as f:
                    while True:
                        chunk = response.read(8192)  # 8KB chunks
                        if not chunk:
                            break
                        f.write(chunk)
                        downloaded_size += len(chunk)
                
                log_debug("scripts/utils.py:urlretrieve_with_retry", "Download complete", {"downloaded_size": downloaded_size, "expected_size": expected_size}, "Hypothesis2")

                # Verify file size matches Content-Length if available
                if expected_size and downloaded_size != expected_size:
                    raise IOError(f"Download incomplete: expected {expected_size} bytes, got {downloaded_size} bytes")
                
                # Verify file is not empty
                if downloaded_size == 0:
                    raise IOError("Downloaded file is empty")
                
                # Basic ZIP file validation (VSIX files are ZIP archives)
                if filename.endswith('.vsix') or filename.endswith('.zip'):
                    import zipfile
                    try:
                        with zipfile.ZipFile(filename, 'r') as zf:
                            # Try to read the central directory to verify ZIP integrity
                            zf.testzip()
                        log_debug("scripts/utils.py:urlretrieve_with_retry", "Zip verification passed", {"filename": filename}, "Hypothesis1")
                    except zipfile.BadZipFile:
                        log_debug("scripts/utils.py:urlretrieve_with_retry", "Zip verification failed", {"filename": filename}, "Hypothesis1")
                        raise IOError(f"Downloaded file is not a valid ZIP archive: {filename}")
                
                return
        except (urllib.error.URLError, TimeoutError, OSError, IOError) as e:
            error_msg = str(e)
            log_debug("scripts/utils.py:urlretrieve_with_retry", "Download error", {"error": error_msg, "attempt": attempt}, "Hypothesis1")
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
