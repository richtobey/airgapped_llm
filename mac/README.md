# Mac Testing Scripts

Scripts for setting up QEMU and Pop!_OS VMs on macOS for testing the airgap bundle scripts.

## Overview

These scripts help you set up a testing environment on macOS to test the airgap bundle installation scripts before deploying to a physical System76 machine.

## Scripts

### `setup_mac_vm.sh`

Sets up QEMU and creates a Pop!_OS VM on macOS for testing.

**Usage:**

```bash
cd mac
./setup_mac_vm.sh
```

**Environment Variables:**

- `VM_DIR` - VM directory (default: `$HOME/vm-popos`)
- `VM_DISK_SIZE` - VM disk size (default: `50G`)
- `VM_MEMORY` - VM RAM (default: `4G`)
- `VM_CPUS` - VM CPU count (default: `2`)
- `POPOS_VERSION` - Pop!_OS version (optional)

### `cleanup_mac_vm.sh`

Removes the VM directory and optionally QEMU installation to start fresh.

**Usage:**

```bash
cd mac
./cleanup_mac_vm.sh [--remove-qemu] [--force]
```

**Options:**

- `--remove-qemu` - Also remove QEMU installed via Homebrew (optional)
- `--force` - Skip confirmation prompts (use with caution)

**Examples:**

```bash
# Remove VM directory only (keeps QEMU)
./cleanup_mac_vm.sh

# Remove VM directory and QEMU
./cleanup_mac_vm.sh --remove-qemu

# Remove everything without prompts
./cleanup_mac_vm.sh --remove-qemu --force
```

**What it removes:**

- VM directory (`$VM_DIR`, default: `$HOME/vm-popos`)
  - ISO files
  - VM disk images
  - Logs and scripts
- QEMU installation (if `--remove-qemu` is used)

**Safety features:**

- Checks if VM is running before removal
- Prompts for confirmation (unless `--force` is used)
- Shows directory size before removal

## Requirements

- macOS (Intel or Apple Silicon)
- Homebrew installed
- Sufficient disk space (~60GB+)

## Notes

- **NVIDIA Variant ISO**: This script uses the `amd64_nvidia` Pop!_OS ISO variant, even though Macs don't have NVIDIA GPUs. This is intentional:
  - We test the exact same ISO that will be deployed to System76 machines
  - The NVIDIA drivers won't cause issues - they simply won't be active/used on Mac
  - This ensures we test the same installation process and scripts as production
  - We're testing the airgap bundle installation, not GPU functionality
  
- **Architecture**: On Apple Silicon Macs, this script uses x86_64 Pop!_OS in emulation mode to test the exact scripts that will run in production
- **Performance**: Emulation mode is slower but necessary for accurate testing of production deployment scripts

## Documentation

See the main [README.md](../README.md) for complete documentation.
