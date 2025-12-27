# System Libraries Included in Airgap Bundle

This document explains all system libraries included in the APT repository and why they're needed for Python packages.

## Build Tools

| Package | Purpose |
|---------|---------|
| `build-essential` | Meta-package containing gcc, g++, make, and other essential build tools |
| `gcc` | GNU C Compiler - required for compiling C extensions |
| `g++` | GNU C++ Compiler - required for compiling C++ extensions |
| `make` | Build automation tool |
| `cmake` | Cross-platform build system |
| `pkg-config` | Tool for managing compile and link flags for libraries |

## Math & Linear Algebra Libraries

**Required for:** numpy, scipy, pandas, scikit-learn

| Package | Purpose |
|---------|---------|
| `libblas-dev` | Basic Linear Algebra Subprograms - fundamental linear algebra operations |
| `liblapack-dev` | Linear Algebra Package - advanced linear algebra routines |
| `libopenblas-dev` | Optimized BLAS implementation (OpenBLAS) - faster than standard BLAS |
| `libatlas-base-dev` | Automatically Tuned Linear Algebra Software - optimized BLAS/LAPACK |
| `libgfortran5` | GNU Fortran runtime library - required by many scientific packages |
| `libgfortran-dev` | GNU Fortran development files - for compiling Fortran code |

**Why multiple BLAS implementations?** Different packages may prefer different implementations. Having multiple ensures compatibility.

## SSL/TLS Libraries

**Required for:** requests, httpx, cryptography, urllib3

| Package | Purpose |
|---------|---------|
| `libssl-dev` | OpenSSL development files - for SSL/TLS support in Python packages |
| `libcrypto++-dev` | Crypto++ library - alternative cryptography library |

## Image Processing Libraries

**Required for:** matplotlib, pillow, sphinx (for image rendering)

| Package | Purpose |
|---------|---------|
| `libpng-dev` | PNG image format support |
| `libjpeg-dev` | JPEG image format support |
| `libtiff-dev` | TIFF image format support |
| `libfreetype6-dev` | Font rendering library - required for text in images/plots |
| `liblcms2-dev` | Color management library |
| `libwebp-dev` | WebP image format support |

## XML/HTML Processing

**Required for:** lxml, beautifulsoup4

| Package | Purpose |
|---------|---------|
| `libxml2-dev` | XML parsing library |
| `libxslt1-dev` | XSLT transformation library |

## Compression Libraries

**Required for:** Various packages that handle compressed data

| Package | Purpose |
|---------|---------|
| `zlib1g-dev` | zlib compression library (gzip) |
| `libbz2-dev` | bzip2 compression library |
| `liblzma-dev` | LZMA/XZ compression library |

## Database Libraries

**Required for:** sqlite3 (Python standard library), psycopg2 (PostgreSQL)

| Package | Purpose |
|---------|---------|
| `libsqlite3-dev` | SQLite database development files |

## System Libraries

**Required for:** Various Python packages

| Package | Purpose |
|---------|---------|
| `libffi-dev` | Foreign Function Interface - for calling C functions from Python |
| `libreadline-dev` | Command line editing library - improves Python REPL experience |
| `libncurses5-dev` | Terminal control library |
| `libncursesw5-dev` | Wide character version of ncurses |

## Audio/Video Libraries

**Required for:** Audio/video processing packages (if needed)

| Package | Purpose |
|---------|---------|
| `libsndfile1-dev` | Audio file format library |
| `libavcodec-dev` | FFmpeg codec library - for video processing |
| `libavformat-dev` | FFmpeg format library - for video container formats |

## Scientific Data Formats

**Required for:** pandas (HDF5), scientific computing packages

| Package | Purpose |
|---------|---------|
| `libhdf5-dev` | HDF5 data format library - for large scientific datasets |
| `libnetcdf-dev` | NetCDF data format library - for climate/scientific data |

## Python Package Dependencies Verification

### How Dependencies Are Downloaded

The bundle script uses `pip download` which:

1. **Automatically includes ALL dependencies** - By default, `pip download` includes transitive dependencies (dependencies of dependencies)
2. **Downloads binary wheels first** - Fast installation, no compilation needed
3. **Falls back to source distributions** - For packages without wheels, downloads source code
4. **Verifies completeness** - Uses `pip install --dry-run` to verify all dependencies are available

### Verification Process

The script performs three steps:

1. **Step 1**: Download binary wheels with all dependencies
   ```bash
   pip download -r requirements.txt --platform linux_x86_64 --only-binary :all:
   ```
   - Includes ALL transitive dependencies automatically
   - No `--no-deps` flag means dependencies are included

2. **Step 2**: Download source distributions as fallback
   ```bash
   pip download -r requirements.txt --no-binary :all:
   ```
   - Ensures packages without wheels are available
   - Also includes all dependencies

3. **Step 3**: Verify dependency completeness
   ```bash
   pip install --dry-run -r requirements.txt --find-links <bundle> --no-index
   ```
   - Checks that all dependencies can be resolved
   - Warns if anything is missing

### What Gets Bundled

For each package in `requirements.txt`:
- ✅ The package itself (binary wheel or source)
- ✅ All direct dependencies
- ✅ All transitive dependencies (dependencies of dependencies)
- ✅ Build dependencies (if needed for source distributions)

### Example: numpy Dependency Chain

If you have `numpy>=1.26.0` in requirements.txt, the bundle includes:
- `numpy` itself
- Direct dependencies: (minimal, numpy is mostly self-contained)
- System libraries: libblas, liblapack (provided by APT packages)
- Build dependencies: gcc, gfortran (for source distributions)

### Example: pandas Dependency Chain

If you have `pandas>=2.1.0`, the bundle includes:
- `pandas` itself
- Direct dependencies: `numpy`, `pytz`, `python-dateutil`, etc.
- Transitive dependencies: All dependencies of numpy, pytz, etc.
- System libraries: libhdf5 (for HDF5 support), libblas/liblapack (via numpy)

## Summary

✅ **All Python package dependencies ARE downloaded** - The script uses `pip download` without `--no-deps`, which automatically includes all transitive dependencies.

✅ **All system libraries ARE included** - The comprehensive APT package list covers:
- Math/linear algebra (numpy, scipy)
- SSL/TLS (requests, httpx)
- Image processing (matplotlib, pillow)
- XML/HTML (lxml, beautifulsoup4)
- Compression (various)
- Database (sqlite3)
- Scientific data formats (HDF5, NetCDF)

✅ **Build tools ARE included** - gcc, g++, make, cmake for compiling source distributions

## Troubleshooting

If a Python package fails to install:

1. **Check system libraries**: Ensure the required `-dev` package is installed
2. **Check build tools**: Ensure `build-essential` is installed
3. **Check Python version**: Ensure Python 3.x matches the target system
4. **Check logs**: Look at pip install output for specific missing libraries

Most common missing libraries:
- `libffi-dev` - For packages using ctypes
- `libssl-dev` - For packages using SSL/TLS
- `libxml2-dev` - For packages parsing XML
- `libblas-dev` / `liblapack-dev` - For numpy/scipy

All of these are now included in the bundle! 🎉

