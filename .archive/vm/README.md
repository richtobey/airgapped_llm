# VM Bundle Scripts

Scripts for creating QEMU/KVM virtual machine bundles with Pop!_OS pre-installed, containing the airgap development environment.

## Overview

These scripts create a complete VM bundle that includes:
- QEMU/KVM virtual machine configuration
- Pop!_OS ISO and installation
- Nested airgap bundle (created by calling `airgap/get_bundle.sh`)

This allows you to test the airgap bundle in a VM before deploying to a physical System76 machine.

## Scripts

### `get_vm_bundle.sh`

Creates a VM bundle containing:
- Pop!_OS ISO (x86_64)
- VM disk image with Pop!_OS installed
- Nested airgap bundle
- QEMU configuration files

**Usage:**
```bash
cd vm
./get_vm_bundle.sh
```

**Environment Variables:**
- `VM_BUNDLE_DIR` - Output directory (default: `./vm_bundle`)
- `VM_DISK_SIZE` - VM disk size (default: `50G`)
- `VM_MEMORY` - VM RAM (default: `4G`)
- `VM_CPUS` - VM CPU count (default: `2`)
- `POPOS_VERSION` - Pop!_OS version/ISO URL (optional)
- `PREINSTALL_AIRGAP` - Pre-install airgap bundle in VM (default: `true`)
- All `airgap/get_bundle.sh` variables also apply

### `install_vm.sh`

Installs QEMU/KVM on the airgapped host and sets up the VM.

**Usage:**
```bash
cd /path/to/vm_bundle
./install_vm.sh
```

**Environment Variables:**
- `VM_BUNDLE_DIR` - VM bundle directory (default: `./vm_bundle`)
- `VM_INSTALL_DIR` - VM installation directory (default: `~/.local/share/vm/popos-airgap`)

### Helper Scripts (`scripts/`)

- `create_vm_image.sh` - Creates VM disk images
- `install_popos_vm.sh` - Automated Pop!_OS installation in VM

## Architecture

**Target Architecture**: Always x86_64/amd64

**Host Support**:
- x86_64 Linux: Uses KVM acceleration (fast)
- ARM64 Mac: Uses x86_64 emulation (slower but functional)
- x86_64 Mac: Uses TCG emulation (slower)

## Workflow

1. **On Online Machine**: Run `get_vm_bundle.sh` to create VM bundle
2. **Transfer**: Copy `vm_bundle/` to airgapped system
3. **On Airgapped System**: Run `install_vm.sh` to set up VM
4. **Start VM**: Use `scripts/start_vm.sh` to launch the VM
5. **Inside VM**: Install airgap bundle if not pre-installed

## Requirements

- **Bundle Creation**: macOS or Linux, QEMU installed, Internet connection
- **Installation**: Linux with QEMU/KVM support, sudo access
- **Disk Space**: ~60GB+ for VM bundle

## Documentation

See the main [README.md](../README.md) for complete documentation.

