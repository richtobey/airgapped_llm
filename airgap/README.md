# Airgap Bundle Scripts

Scripts for creating and installing the airgap development environment bundle on System76 Pop!_OS systems.

## Overview

These scripts create a complete offline development environment bundle that can be transferred to an airgapped Pop!_OS system and installed without any internet connection.

## Scripts

### `get_bundle.sh`

Creates the airgap bundle containing:
- Ollama (local LLM server)
- VSCodium (code editor)
- Continue extension (AI coding assistant)
- Python and Rust extensions
- System libraries (APT repo)
- Python packages
- Rust toolchain
- AI models (Mistral, Mixtral)

**Usage:**
```bash
cd airgap
./get_bundle.sh
```

**Environment Variables:**
- `BUNDLE_DIR` - Output directory (default: `./airgap_bundle`)
- `OLLAMA_MODELS` - Space-separated list of models to bundle
- `PYTHON_REQUIREMENTS` - Path to requirements.txt (default: `requirements.txt` in same directory)
- `RUST_CARGO_TOML` - Path to Cargo.toml (optional)

### `install_offline.sh`

Installs the airgap bundle on the target Pop!_OS system.

**Usage:**
```bash
cd /path/to/airgap_bundle
./install_offline.sh
```

**Environment Variables:**
- `BUNDLE_DIR` - Bundle directory location (default: `./airgap_bundle`)
- `INSTALL_PREFIX` - Installation prefix for Ollama (default: `/usr/local/bin`)

## Workflow

1. **On Online Machine**: Run `get_bundle.sh` to create the bundle
2. **Transfer**: Copy `airgap_bundle/` to external drive/USB
3. **On Airgapped System**: Run `install_offline.sh` to install everything
4. **Start Using**: Launch Ollama and VSCodium

## Requirements

- **Bundle Creation**: macOS or Linux, Python 3, Internet connection
- **Installation**: Pop!_OS or Ubuntu/Debian-based Linux (amd64), sudo access

## Documentation

See the main [README.md](../README.md) for complete documentation.

