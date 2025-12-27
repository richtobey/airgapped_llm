# Airgapped Package Installation Guide

## Python Packages

### ✅ What WILL Work

**All packages in `requirements.txt` will be installable** because:

1. **Binary wheels are bundled**: Packages with pre-built Linux wheels are downloaded and bundled
2. **Source distributions are bundled**: Packages without wheels are downloaded as source code
3. **All dependencies are included**: The script downloads transitive dependencies
4. **Build tools are available**: `gcc`, `g++`, `python3-dev` are in the APT repo for compiling source distributions

### ⚠️ Potential Issues

1. **Compilation time**: Source distributions need to be compiled on the target system
   - This requires build tools (already in APT repo)
   - May take longer to install
   - **All necessary system libraries are now included in the APT repo** (see SYSTEM_LIBRARIES.md)

2. **System library dependencies**: ✅ **All required system libraries are now included**
   - Math libraries: libblas, liblapack, libopenblas, libatlas (for numpy, scipy, pandas)
   - SSL/TLS: libssl-dev (for requests, httpx, cryptography)
   - Image processing: libpng, libjpeg, libfreetype (for matplotlib, pillow, sphinx)
   - XML/HTML: libxml2, libxslt (for lxml, beautifulsoup4)
   - Compression: zlib, bzip2, lzma (for various packages)
   - And many more - see SYSTEM_LIBRARIES.md for complete list

3. **Platform-specific packages**: Some packages may not have Linux wheels
   - These will be downloaded as source and compiled
   - Should work, but may take longer

### 📦 How It Works

The bundle script:
1. Downloads binary wheels for Linux (preferred - fast installation)
2. Downloads source distributions as fallback (for packages without wheels)
3. Includes ALL dependencies automatically
4. Stores everything in `bundle/python/`

Installation on airgapped system:
- Uses `pip install --no-index --find-links` to install from bundle
- Binary wheels install instantly
- Source distributions compile automatically (build tools required)

## Rust Packages (Crates)

### ✅ What WILL Work

**Rust crates CAN be bundled** if you provide a `Cargo.toml`:

1. **Toolchain is bundled**: `rustup-init` downloads and installs Rust
2. **Crates can be vendored**: Use `cargo vendor` to bundle all dependencies
3. **Offline builds work**: Once vendored, `cargo build --offline` works

### ⚠️ Current Status

**Rust crates are NOT automatically bundled** unless:
- You have a `Cargo.toml` file in the script directory
- OR set `RUST_CARGO_TOML` environment variable
- AND `cargo` is installed on the build machine (Mac)

### 📦 How to Bundle Rust Crates

**Option 1: Automatic (if you have Cargo.toml)**
```bash
# Place Cargo.toml in the same directory as get_bundle.sh
# The script will auto-detect and bundle crates
./get_bundle.sh
```

**Option 2: Manual bundling**
```bash
# On your Mac (with cargo installed):
cd your-rust-project
cargo vendor vendor/
tar czf rust-crates.tar.gz vendor/ Cargo.toml Cargo.lock

# Copy to bundle manually:
cp rust-crates.tar.gz airgap_bundle/rust/crates/
```

**Option 3: On target system (if you have internet temporarily)**
```bash
# On Pop!_OS before going airgapped:
cd your-rust-project
cargo vendor vendor/
# Then copy vendor/ directory to your project
```

### 🔧 Using Bundled Rust Crates

After installation, to use vendored crates in your Rust project:

1. Copy vendored crates to your project:
   ```bash
   cp -r $BUNDLE_DIR/rust/crates/vendor your-project/
   cp $BUNDLE_DIR/rust/crates/Cargo.toml your-project/
   cp $BUNDLE_DIR/rust/crates/Cargo.lock your-project/
   ```

2. Add to your `Cargo.toml`:
   ```toml
   [source.crates-io]
   replace-with = "vendored-sources"
   
   [source.vendored-sources]
   directory = "vendor"
   ```

3. Build offline:
   ```bash
   cargo build --offline --frozen
   ```

## Summary

| Package Type | Status | Notes |
|-------------|--------|-------|
| **Python packages** | ✅ Fully supported | All packages + dependencies bundled. Source dists compile automatically. |
| **Rust toolchain** | ✅ Fully supported | rustup-init bundled and installs automatically. |
| **Rust crates** | ⚠️ Manual setup needed | Requires Cargo.toml and cargo on build machine. Or bundle manually. |

## Recommendations

1. **For Python**: Your `requirements.txt` will work completely offline
2. **For Rust**: 
   - If you have a Rust project, create `Cargo.toml` before running `get_bundle.sh`
   - Or bundle crates manually using `cargo vendor`
   - Or temporarily connect the target system to vendor crates before going airgapped

## Adding More Packages

### Python
- Edit `requirements.txt` and re-run `get_bundle.sh`
- All dependencies are automatically included

### Rust
- Add dependencies to `Cargo.toml`
- Re-run `get_bundle.sh` (if cargo is available)
- Or use `cargo vendor` manually

