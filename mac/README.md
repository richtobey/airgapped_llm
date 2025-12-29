# Mac Testing Scripts

Scripts for downloading Pop!_OS ISO and setting up VMs with UTM on macOS for testing the airgap bundle scripts.

## Overview

These scripts help you download the Pop!_OS ISO and provide instructions for setting up a testing environment using UTM (a user-friendly virtualization app for macOS) to test the airgap bundle installation scripts before deploying to a physical System76 machine.

## Scripts

### `setup_mac_vm.sh`

Downloads the Pop!_OS ISO for use with UTM.

**Usage:**

```bash
cd mac
./setup_mac_vm.sh
```

**Environment Variables:**

- `VM_DIR` - Directory to store ISO (default: `$HOME/vm-popos`)
- `POPOS_VERSION` - Pop!_OS version (optional, auto-detects latest)

**What it does:**

- Detects your Mac's architecture (Intel or Apple Silicon)
- Downloads the appropriate Pop!_OS ISO
- Validates the ISO checksum
- Provides instructions for installing UTM and setting up the VM

### `cleanup_mac_vm.sh`

Removes the downloaded ISO and VM directory to start fresh.

**Usage:**

```bash
cd mac
./cleanup_mac_vm.sh [--force]
```

**Options:**

- `--force` - Skip confirmation prompts (use with caution)

**Examples:**

```bash
# Remove VM directory (with confirmation)
./cleanup_mac_vm.sh

# Remove everything without prompts
./cleanup_mac_vm.sh --force
```

**What it removes:**

- VM directory (`$VM_DIR`, default: `$HOME/vm-popos`)
  - ISO files
  - Any other files in the directory

**Safety features:**

- Prompts for confirmation (unless `--force` is used)
- Shows directory size before removal
- Preserves valid ISO files if checksum verifies

## Requirements

- macOS (Intel or Apple Silicon)
- Sufficient disk space (~5GB+ for ISO, ~60GB+ for VM)
- UTM (install from Mac App Store or https://mac.getutm.app/)

## Quick Start Guide

### Step 1: Download the ISO

```bash
cd mac
./setup_mac_vm.sh
```

This will download the Pop!_OS ISO to `$HOME/vm-popos/iso/pop-os.iso`.

### Step 2: Install UTM

1. Open the Mac App Store
2. Search for "UTM"
3. Click "Get" or "Install" to download and install UTM

Alternatively, download from: https://mac.getutm.app/

### Step 3: Create VM in UTM

1. Open UTM
2. Click the '+' button to create a new VM
3. Select "Virtualize" (not "Emulate")
4. Choose "Linux" as the operating system
5. Configure the VM:
   - Name: "Pop!_OS Airgap Test" (or your preferred name)
   - ISO Image: Browse and select the downloaded ISO at `$HOME/vm-popos/iso/pop-os.iso`
   - Memory: 4 GB or more (recommended)
   - CPUs: 2 or more cores (recommended)
   - Storage: 50 GB or more (recommended)
6. Click "Save"

### Step 4: Install Pop!_OS

1. In UTM, select your VM and click "Play" (▶) to start it
2. The VM will boot from the Pop!_OS ISO
3. Follow the installation wizard:
   - Select "Install Pop!_OS" from the boot menu
   - Choose language and keyboard layout
   - Connect to network (optional)
   - Choose "Erase disk and install Pop!_OS"
   - Create a user account
   - Complete the installation
4. After installation, the VM will reboot
5. Log in with the account you created.  Stop it and remove the iso and then reboot it.

### Step 5: Get Remote Resources to Install Locally on Air Gapped Computer

1. From Mac OS, run `./get_gundle.sh`.

### Step 6: Transfer Airgap Bundle to VM

**Option A: UTM Shared Folder (Easiest)**

1. In UTM, select your VM and click "Edit"
2. Go to "Sharing" tab
3. Enable "Directory Sharing" and select a folder on your Mac
4. In Pop!_OS, the shared folder appears at `/mnt/utm-shared`

### Step 6: Install Airgap Bundle

```bash
cd /path/to/airgap_bundle
sudo ./install_offline.sh
```

## Notes

- **NVIDIA Variant ISO**: This script uses the `amd64_nvidia` Pop!_OS ISO variant, even though Macs don't have NVIDIA GPUs. This is intentional:
  - We test the exact same ISO that will be deployed to System76 machines
  - The NVIDIA drivers won't cause issues - they simply won't be active/used on Mac
  - This ensures we test the same installation process and scripts as production
  - We're testing the airgap bundle installation, not GPU functionality
  
- **Architecture**: On Apple Silicon Macs, this script downloads x86_64 Pop!_OS ISO for emulation mode to test the exact scripts that will run in production
- **Performance**: Emulation mode on Apple Silicon is slower but necessary for accurate testing of production deployment scripts
- **UTM**: UTM is a user-friendly virtualization app for macOS that uses QEMU under the hood. It provides a GUI interface that's easier to use than command-line QEMU.

## Troubleshooting

### UTM won't start the VM

- Ensure UTM has necessary permissions in System Settings → Privacy & Security
- On Apple Silicon: UTM may need Rosetta 2 for x86_64 VMs (install if prompted)
- Check UTM logs: Window → Logs in UTM

### VM is very slow (Apple Silicon Macs with x86_64 guest)

- This is normal - x86_64 emulation is slower than native
- Consider using a Linux x86_64 machine for better performance
- Or use native ARM64 Pop!_OS if available

### Network not working in VM

- UTM uses NAT networking by default
- VM should have internet access automatically
- Check: `ping google.com` in VM

### Pop!_OS Installation Fails

- Ensure sufficient disk space allocated to VM (50GB+ recommended)
- Try increasing VM memory in UTM settings (4GB+ recommended)
- Verify ISO file is not corrupted: `ls -lh $HOME/vm-popos/iso/pop-os.iso`

## Documentation

See the main [README.md](../README.md) for complete documentation.
