# Airgap Bundle Scripts

Scripts for creating and installing the airgap development environment bundle on System76 Pop!_OS systems.

## Overview

These scripts create a complete offline development environment bundle that can be transferred to an airgapped Pop!_OS system and installed without any internet connection.

**IMPORTANT**: `get_bundle.sh` **must** be run on a Linux system (Pop!_OS) with internet access. It builds all components (APT repos, Python wheels, Rust crates) on the online system, so the airgapped system only needs to install pre-built packages.

**Options for Running `get_bundle.sh`**:
- **UTM VM on Mac** with Pop!_OS installed (see [Creating the Bundle on Mac using UTM and Pop OS](#creating-the-bundle-on-mac-using-utm-and-pop-os) for detailed instructions)

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
export OLLAMA_MODELS="mistral:7b"
cd airgap
./get_bundle.sh
```

**Options:**

- `--skip-verification` - Skip SHA256 verification of downloads. If files already exist, accept them without verification. Useful when re-running the script and you trust existing downloads.

**Environment Variables:**

- `BUNDLE_DIR` - Output directory (default: `./airgap_bundle`)
- `OLLAMA_MODELS` - Space-separated list of models to bundle
- `MOVE_MODELS` - Set to `true` to move models instead of copy (saves disk space)
- `PYTHON_REQUIREMENTS` - Path to requirements.txt (default: `requirements.txt` in same directory)
- `RUST_CARGO_TOML` - Path to Cargo.toml (optional)
- `SKIP_VERIFICATION` - Set to `true` to skip verification (same as `--skip-verification` flag)

### `install_offline.sh`

Installs the airgap bundle on the target Pop!_OS system. **Only installs pre-built packages** - no compilation or building happens on the airgapped system.

### `uninstall_offline.sh`

Removes all components installed by `install_offline.sh`. This includes:

- APT packages (development tools and libraries)
- VSCodium (code editor)
- Ollama binary and models (with confirmation)
- VSCode extensions (Continue, Python, Rust Analyzer)
- Rust toolchain (if installed via rustup)
- Python packages (from bundle requirements.txt)
- APT source list entry
- Ollama GPU configuration from shell profiles

**Usage:**

```bash
./uninstall_offline.sh
```

The script will prompt for confirmation before removing components, and will ask separately about removing Ollama models (which can be large).

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
cd /path/to/airgap_llm
./install_offline.sh
```

**Options:**

- `--skip-verification` - Skip SHA256 verification of artifacts. If files already exist, accept them without verification. Useful when re-running the script and you trust existing files.
- `--allow-network` - Allow installation even if a network connection is detected. This overrides the airgap requirement check.

**Environment Variables:**

- `BUNDLE_DIR` - Bundle directory location (default: `./airgap_bundle`)
- `INSTALL_PREFIX` - Installation prefix for Ollama (default: `/usr/local/bin`)
- `SKIP_VERIFICATION` - Set to `true` to skip verification (same as `--skip-verification` flag)
- `ALLOW_NETWORK` - Set to `true` to allow network (same as `--allow-network` flag)

## Creating the Bundle on Mac using UTM and Pop OS

If you don't have a physical Pop!_OS machine with internet access, you can create the bundle using UTM (Virtualization Framework) on a Mac. This guide walks you through setting up Pop!_OS in a UTM VM with Intel emulation mode.

### Prerequisites

- **Mac** (Intel or Apple Silicon) with macOS 11.0 or later
- **UTM** virtualization software (free, available from Mac App Store or [utm.app](https://mac.getutm.app))
- **Pop!_OS ISO** (download from [System76](https://pop.system76.com/))
- **External drive** (USB or Thunderbolt) - minimum 100GB free space (200GB+ recommended)
- **Internet connection** on the Mac (for downloading Pop!_OS and running the bundle script)

### Step 1: Install UTM

1. **Download UTM**:
   - Option A: Install from Mac App Store (recommended for automatic updates)
   - Option B: Download from [utm.app](https://mac.getutm.app) and install manually

2. **Launch UTM** and grant necessary permissions when prompted

### Step 2: Download Pop!_OS ISO

1. Visit [pop.system76.com](https://pop.system76.com/)
2. Download the **Pop!_OS 22.04 LTS** (or latest stable) ISO for **Intel/AMD (64-bit)**
3. Save the ISO file (typically 2-3 GB) - you'll need it in the next step

### Step 3: Create UTM Virtual Machine

1. **Open UTM** and click **"Create a New Virtual Machine"**

2. **Choose "Virtualize"** (not "Emulate" - we'll configure emulation later)

3. **Select "Linux"** as the operating system

4. **Configure Hardware**:
   - **Memory**: Allocate at least **8 GB RAM** (16 GB recommended if available)
   - **CPU Cores**: Allocate at least **4 cores** (more if available)
   - Click **"Continue"**

5. **Choose "Boot from image"** and click **"Browse"**
   - Navigate to and select your downloaded Pop!_OS ISO file
   - Click **"Continue"**

6. **Storage**:
   - **Disk Size**: Create a virtual disk with at least **60 GB** (100 GB recommended)
   - This is for the Pop!_OS installation - the bundle will be on an external drive
   - Click **"Continue"**

7. **Review and Finish**:
   - Name the VM (e.g., "Pop OS Bundle Builder")
   - Click **"Save"**

### Step 4: Configure Intel Emulation Mode

**IMPORTANT**: `get_bundle.sh` requires Intel/AMD64 architecture. If you're on Apple Silicon Mac, you must enable Intel emulation.

1. **Select your VM** in UTM and click **"Edit"**

2. **Go to "System" tab**:
   - **Architecture**: Select **"x86_64"** (Intel emulation)
   - This enables Rosetta 2 emulation on Apple Silicon Macs
   - On Intel Macs, this ensures compatibility

3. **Optional - Performance Settings**:
   - Enable **"Use Hypervisor Framework"** (if available)
   - Enable **"Use Apple Virtualization"** (if available)
   - These improve performance but may not be available in emulation mode

4. **Click "Save"** to apply changes

### Step 5: Install Pop!_OS in the VM

1. **Start the VM** by clicking the **"Play"** button

2. **Boot from ISO**:
   - The VM should boot from the Pop!_OS ISO automatically
   - If not, you may need to select the ISO in the boot menu

3. **Install Pop!_OS**:
   - Select **"Try or Install Pop!_OS"** from the boot menu
   - Choose **"Install Pop!_OS"**
   - Follow the installation wizard:
     - Select language and keyboard layout
     - Choose installation type (Erase disk and install is fine for a VM)
     - Create a user account (remember your password!)
     - Wait for installation to complete (20-30 minutes)

4. **Complete Installation**:
   - When installation finishes, click **"Restart Now"**
   - The VM will reboot into the installed Pop!_OS

5. **First Boot Setup**:
   - Log in with the user account you created
   - Complete any initial setup prompts
   - Update the system (optional but recommended):
     ```bash
     sudo apt update && sudo apt upgrade -y
     ```

### Step 6: Connect External Drive to VM

1. **Prepare the External Drive**:
   - Connect your external drive to your Mac
   - **Format the drive** (if needed):
     - Use **Disk Utility** on Mac
     - Format as **exFAT** (for cross-platform compatibility) or **ext4** (Linux-native, better performance)
     - Name it something memorable (e.g., "AirgapBundle")

2. **Attach Drive to VM**:
   - **In UTM**, with the VM running, click the **"USB"** icon in the toolbar
   - Select your external drive from the list
   - The drive should now be accessible in the Pop!_OS VM

3. **Mount the Drive in Pop!_OS**:
   - Open **Files** (file manager) in Pop!_OS
   - The external drive should appear in the sidebar
   - Click it to mount (if not auto-mounted)
   - Note the mount path (typically `/media/[username]/[drive-name]` or `/mnt/[drive-name]`)

4. **Verify Access**:
   ```bash
   # List mounted drives
   lsblk
   
   # Check mount point (replace with your drive name)
   ls -la /media/$USER/[drive-name]
   ```

### Step 7: Transfer Scripts to External Drive

1. **Copy the airgap scripts** to the external drive:
   ```bash
   # Mount point (adjust to your drive's mount point)
   DRIVE_MOUNT="/media/$USER/[drive-name]"
   
   # Create directory on drive
   mkdir -p "$DRIVE_MOUNT/airgap"
   
   # Copy scripts (if you have them on a USB or network share)
   # Option 1: If scripts are on another USB drive
   cp -r /path/to/airgap/* "$DRIVE_MOUNT/airgap/"
   
   # Option 2: If you need to download/clone from a repository
   # (You'll need internet access in the VM for this)
   cd "$DRIVE_MOUNT"
   git clone [repository-url] airgap
   # OR download and extract a zip file
   ```

2. **Make scripts executable**:
   ```bash
   cd "$DRIVE_MOUNT/airgap"
   chmod +x get_bundle.sh install_offline.sh
   ```

### Step 8: Run get_bundle.sh

1. **Navigate to the scripts directory**:
   ```bash
   cd /media/$USER/[drive-name]/airgap
   ```

2. **Optional - Configure environment variables**:
   ```bash
   # Limit models to save space (optional)
   export OLLAMA_MODELS="mistral:7b-instruct"
   
   # Set bundle directory to external drive (optional, defaults to ./airgap_bundle)
   export BUNDLE_DIR="/media/$USER/[drive-name]/airgap_bundle"
   ```

3. **Run the bundle script**:
   ```bash
   ./get_bundle.sh
   ```

4. **Monitor Progress**:
   - The script will download and build all components
   - This process can take **several hours** depending on:
     - Internet speed
     - Number of models selected
     - System performance
   - The bundle will be created in `airgap_bundle/` directory (or `$BUNDLE_DIR` if set)

5. **Verify Bundle Creation**:
   ```bash
   # Check bundle size (should be 50-200GB+ depending on models)
   du -sh airgap_bundle/
   
   # Verify key components exist
   ls -la airgap_bundle/
   ```

### Step 9: Safely Eject and Transfer Drive

1. **Unmount the drive in Pop!_OS**:
   ```bash
   # Find the mount point
   mount | grep /media
   
   # Unmount (replace with your mount point)
   sudo umount /media/$USER/[drive-name]
   ```

2. **Eject from UTM**:
   - In UTM, click the **"USB"** icon
   - Select your drive and choose **"Eject"**

3. **Eject from Mac**:
   - In Finder, right-click the drive and select **"Eject"**
   - Wait for the eject to complete

4. **Physically Transfer**:
   - Disconnect the drive from your Mac
   - Connect it to your **airgapped Pop!_OS machine**

### Step 10: Install on Airgapped Machine

1. **Mount the drive** on the airgapped machine:
   ```bash
   # The drive should auto-mount, or manually mount:
   sudo mkdir -p /mnt/bundle_drive
   sudo mount /dev/sdX1 /mnt/bundle_drive  # Replace sdX1 with your device
   ```

2. **Navigate to bundle directory**:
   ```bash
   cd /mnt/bundle_drive/airgap_bundle
   # OR if bundle is in a subdirectory:
   cd /mnt/bundle_drive/airgap/airgap_bundle
   ```

3. **Make install script executable** (if needed):
   ```bash
   chmod +x install_offline.sh
   ```

4. **Run the installation**:
   ```bash
   sudo ./install_offline.sh
   ```

5. **Follow installation prompts**:
   - The script will install all pre-built packages
   - No internet connection is required
   - Installation typically takes 10-30 minutes

6. **Verify Installation**:
   ```bash
   # Check Ollama
   ollama --version
   
   # Check VSCodium
   codium --version
   
   # Check Rust
   rustc --version

   # Check Python
   python --version
   ```

### Troubleshooting

#### UTM Issues

- **VM won't start**: Ensure virtualization is enabled in System Settings → Privacy & Security
- **Slow performance**: Increase RAM/CPU allocation, disable unnecessary VM features
- **USB drive not detected**: Try disconnecting and reconnecting, or use a different USB port

#### Pop!_OS Installation Issues

- **Installation fails**: Ensure you allocated enough disk space (60GB+)
- **Boot issues**: Verify you selected x86_64 architecture in UTM settings
- **Network issues**: Check UTM network settings (NAT should work for internet access)

#### Drive Mounting Issues

- **Drive not visible**: Check `lsblk` to see if device is detected
- **Permission denied**: Use `sudo` or add your user to the `disk` group
- **Wrong filesystem**: Reformat as exFAT or ext4 if needed

#### Bundle Script Issues

- **Script fails with "not Linux" error**: Verify you're running in the VM, not on Mac host
- **Out of disk space**: Ensure external drive has 100GB+ free space
- **Download failures**: Check internet connection in VM, verify DNS settings

## Workflow Summary

1. **On Mac with UTM + Pop!_OS VM** (with internet):
   - Set up UTM VM with Pop!_OS in Intel emulation mode
   - Connect external drive to VM
   - Run `get_bundle.sh` to create the bundle on the external drive
   - Script builds APT repo, compiles Python packages into wheels, vendors Rust crates
   - All components are pre-built and ready for offline installation

2. **Transfer**: Physically move the external drive from Mac to airgapped machine

3. **On Airgapped System**:
   - Mount the external drive
   - Run `install_offline.sh` to install pre-built packages
   - Installation is fast - no compilation needed

4. **Start Using**: Launch Ollama and VSCodium (see [Running Ollama and VSCodium](docs/run_ollama.md))

## Requirements

- **Bundle Creation**: 
  - **Pop!_OS(amd64/x86_64) REQUIRED** - Can be physical machine or VM (see [UTM setup guide](#creating-the-bundle-on-mac-using-utm-and-pop-os))
  - Python 3
  - Internet connection
  - Build tools (installed automatically by script)
  - External drive (100GB+ free space) for bundle storage
- **Installation**: Pop!_OS or Ubuntu/Debian-based Linux (amd64), sudo access, external drive with bundle

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
  username@<ipaddress_of_mac_host>:/Volumes/T7_mac/airgapped_llm \
  /mnt/t7_mac \
  -o uid=$(id -u),gid=$(id -g),reconnect,allow_other,ServerAliveInterval=15,ServerAliveCountMax=3

# example
sshfs \
  richtobey@192.168.68.120:/Volumes/T7 \
  /mnt/t7 \
  -o uid=$(id -u),gid=$(id -g),reconnect,allow_other,ServerAliveInterval=15,ServerAliveCountMax=3


# unmount
fusermount -uz /mnt/t7_mac
```

### (Optional) Make it persistent with systemd (recommended)


Check:

```bash
findmnt /mnt/t7_mac
```