import sys, subprocess, shutil, os
from pathlib import Path

if len(sys.argv) < 3:
    print("Usage: python3 download_python_packages.py <bundle_dir> <requirements_file>")
    sys.exit(1)

bundle = Path(sys.argv[1])
requirements = Path(sys.argv[2])

# Use a clean site-packages directory
outdir = bundle/"python"/"site-packages"
if outdir.exists():
    shutil.rmtree(outdir)
outdir.mkdir(parents=True, exist_ok=True)

# Copy requirements.txt to bundle for reference
shutil.copy(requirements, bundle/"python"/"requirements.txt")

print(f"Installing Python packages to {outdir}...")
print("This ensures all dependencies are resolved and installed for the target system.")

try:
    # pip install --target installs everything into the directory
    # We use --ignore-installed to ensure we get a fresh copy of everything
    # We use --no-compile to avoid .pyc files which might be python-version specific
    cmd = [
        sys.executable, "-m", "pip", "install",
        "-r", str(requirements),
        "--target", str(outdir),
        "--upgrade",
        "--no-compile",
        "--ignore-installed"
    ]
    
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    
    if result.returncode != 0:
        print(f"Error installing packages:")
        print(result.stderr)
        # Don't exit immediately, let the shell script handle the failure
        # But we print output for debugging
        print(result.stdout)
        sys.exit(1)
    else:
        print(result.stdout)
    
    # Count installed packages (top-level directories/egg-infos)
    pkg_count = len(list(outdir.glob("*-info")))
    print(f"✓ Installed approximately {pkg_count} packages to bundle")
    
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
