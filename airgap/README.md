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
# to limit models downloaded
export OLLAMA_MODELS="mistral:7b-instruct"
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

Installs the following components:

- System libraries and development tools (from offline APT repo) - **pre-built .deb packages**
- VSCodium (code editor) - **pre-built .deb package**
- Ollama binary - **pre-built binary**
- Ollama AI models - **copied from bundle to ~/.ollama**
- Continue extension (AI coding assistant) - **pre-built VSIX**
- Python and Rust extensions - **pre-built VSIX files**
- Rust toolchain - **installed via bundled rustup-init**
- Rust crates - **vendored dependencies for offline builds**
- Python packages - **pre-built wheels, no compilation**

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

4. **Start Using**: Launch Ollama and VSCodium (see [Running Ollama and VSCodium](docs/run_ollama.md))

## Requirements

- **Bundle Creation**: **Pop!_OS/Ubuntu/Debian Linux (amd64) REQUIRED**, Python 3, Internet connection, Build tools (installed automatically)
- **Installation**: Pop!_OS or Ubuntu/Debian-based Linux (amd64), sudo access

## Backup and Restore of POP_OS

This process will preserve and enable a reset of the machine if there is any suspiction if there is any concern about corruption.

### Recommended: Clonezilla

**Clonezilla** is a free, open-source disk imaging tool that is the simplest and most reliable solution for backing up and restoring your airgapped system.

#### Quick Start

**You need TWO drives:**
1. **Clonezilla USB** (4-8 GB) - for booting Clonezilla
2. **Backup drive** (larger, see below) - where backups are stored

1. **Download Clonezilla Live** (on online machine):
   ```bash
   wget -O clonezilla-live-amd64.iso \
https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/3.3.0-33/clonezilla-live-3.3.0-33-amd64.iso/download
   ```

2. **Create Bootable Clonezilla USB** (small USB, 4-8 GB):
   ```bash
   sudo ./create_clonezilla_usb.sh clonezilla-live-3.3.0-33-amd64.iso /dev/sdb
   ```
   (Replace `/dev/sdb` with your USB device - find it with `lsblk`)

3. **Prepare Backup Drive** (separate, larger drive):
   - Connect external USB/HDD for backups
   - Size: At least 30-50% of your used disk space (for compressed backups)
   - Example: 200GB used = 60-100GB backup, so get 200GB+ drive
   - **Format:** ext4 (recommended) or exFAT (if cross-platform needed)

4. **Boot from Clonezilla USB**:
   - **Ensure Clonezilla USB is plugged in**
   - Power on or restart your computer
   - **Immediately press F11** (or your system's boot menu key) repeatedly during startup
   - In the boot menu, look for **"Boot Override"** or boot device selection
   - Select the Clonezilla USB device (may appear as "UEFI: USB" or similar)
   - If USB doesn't appear, ensure Secure Boot is disabled in BIOS/UEFI settings

5. **Create Backup**:
   - Once Clonezilla boots, select: `device-image` → `savedisk`
   - Enter backup name (e.g., `virgin_state_20240101`)
   - Select source disk (your system disk)
   - **Select backup location** (your backup drive, NOT the Clonezilla USB)
   - Start backup

6. **Restore from Backup**:
   - Boot from Clonezilla USB (using F11 boot override method above)
   - Select: `device-image` → `restoredisk`
   - Select backup image from your backup drive
   - Select target disk
   - Start restore

#### Prepare for Backup

Before creating a backup, gather system information:

```bash
./prepare_backup.sh virgin_state_20240101
```

**See [docs/BACKUP_RESTORE.md](docs/BACKUP_RESTORE.md) for complete Clonezilla documentation.**

## Documentation

See the main [README.md](../README.md) for complete documentation.

- [Backup and Restore Guide](docs/BACKUP_RESTORE.md)
- [System Libraries](docs/SYSTEM_LIBRARIES.md)
- [Package Review](docs/AIRGAP_REVIEW.md)
- [Running Ollama and VSCodium](docs/run_ollama.md)

## Connection Notes

On linux run:

```bash
sshfs \
  richtobey@192.168.68.88:/Volumes/T7_mac/airgapped_llm \
  /mnt/t7_mac \
  -o uid=$(id -u),gid=$(id -g),reconnect,allow_other,ServerAliveInterval=15,ServerAliveCountMax=3


# unmount
fusermount -uz /mnt/t7_mac
```

### (Optional) Make it persistent with systemd (recommended)


Check:

```bash
findmnt /mnt/t7_mac
```