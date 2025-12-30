# Airgap Bundle Scripts

Scripts for creating and installing the airgap development environment bundle on System76 Pop!_OS systems.

## Overview

These scripts create a complete offline development environment bundle that can be transferred to an airgapped Pop!_OS system and installed without any internet connection.

**IMPORTANT**: `get_bundle.sh` **must** be run on a Linux system (Pop!_OS/Ubuntu/Debian) with internet access. It builds all components (APT repos, Python wheels, Rust crates) on the online system, so the airgapped system only needs to install pre-built packages.

## Scripts

### `get_bundle.sh`

Creates the airgap bundle containing:

- Ollama (local LLM server)
- VSCodium (code editor)
- Continue extension (AI coding assistant)
- Python and Rust extensions
- System libraries (APT repo) - **built on online system**
- Python packages - **pre-built as wheels**
- Rust toolchain
- Rust crates - **vendored for offline builds**
- AI models (Mistral, Mixtral)

**Requirements**: Must be run on **Pop!_OS/Ubuntu/Debian Linux** with internet access.

**Usage:**

```bash
cd airgap
./get_bundle.sh
```

**Environment Variables:**

- `BUNDLE_DIR` - Output directory (default: `./airgap_bundle`)
- `OLLAMA_MODELS` - Space-separated list of models to bundle
- `MOVE_MODELS` - Set to `true` to move models instead of copy (saves disk space)
- `PYTHON_REQUIREMENTS` - Path to requirements.txt (default: `requirements.txt` in same directory)
- `RUST_CARGO_TOML` - Path to Cargo.toml (optional)

### `install_offline.sh`

Installs the airgap bundle on the target Pop!_OS system. **Only installs pre-built packages** - no compilation or building happens on the airgapped system.

**Usage:**

```bash
cd /path/to/airgap_bundle
./install_offline.sh
```

**Environment Variables:**

- `BUNDLE_DIR` - Bundle directory location (default: `./airgap_bundle`)
- `INSTALL_PREFIX` - Installation prefix for Ollama (default: `/usr/local/bin`)

## Workflow

1. **On Online Pop!_OS Machine** (with internet):
   - Run `get_bundle.sh` to create the bundle
   - Script builds APT repo, compiles Python packages into wheels, vendors Rust crates
   - All components are pre-built and ready for offline installation

2. **Transfer**: Copy `airgap_bundle/` to external drive/USB

3. **On Airgapped System**:
   - Run `install_offline.sh` to install pre-built packages
   - Installation is fast - no compilation needed

4. **Start Using**: Launch Ollama and VSCodium

## Requirements

- **Bundle Creation**: **Pop!_OS/Ubuntu/Debian Linux (amd64) REQUIRED**, Python 3, Internet connection, Build tools (installed automatically)
- **Installation**: Pop!_OS or Ubuntu/Debian-based Linux (amd64), sudo access

## Documentation

See the main [README.md](../README.md) for complete documentation.
