# UTM to KVM Migration Guide

This directory contains scripts and instructions for migrating a Pop!_OS VM from UTM (Mac) to KVM (System76 Linux).

## Overview

This migration process converts your UTM VM running on Mac M1 ARM64 (with x86_64 emulation) to a native KVM VM on an x86_64 System76 Linux box. The VM will run much faster on native hardware with KVM acceleration.

## Migration Process

1. **Backup VM** (using scripts in `../backup/`)
2. **Transfer backup** to System76 machine
3. **Convert disk format** (if needed)
4. **Set up KVM VM** with proper configuration
5. **Verify and test** the migrated VM

## Requirements

### Source System (Mac)

- UTM VM with Pop!_OS (x86_64)
- Backup created using `../backup/backup_vm.sh`
- External drive or network access to transfer backup

### Target System (System76 Linux)

- System76 Pop!_OS or Ubuntu/Debian-based Linux (x86_64)
- KVM support enabled
- libvirt and qemu-kvm installed
- sudo/root access
- Sufficient disk space (50GB+ recommended)
- NVIDIA drivers (if using GPU passthrough)

## Quick Start

### Step 1: Backup Your UTM VM

On your Mac, first create a backup:

```bash
cd ../backup
./backup_vm.sh \
  ~/Library/Containers/com.utmapp.UTM/Data/Documents/PopOS.utm/Images/disk.qcow2 \
  /Volumes/ExternalDrive/backups \
  --compress
```

See `../backup/README.md` for detailed backup instructions.

### Step 2: Transfer Backup to System76

Transfer the backup to your System76 machine:

**Option A: External Drive**

- Copy backup directory to external drive
- Connect to System76 and copy to local storage

**Option B: Network Transfer**

```bash
# On Mac
scp -r /path/to/backup user@system76:/path/to/destination

# Or use rsync for resume capability
rsync -avz --progress /path/to/backup user@system76:/path/to/destination
```

### Step 3: Convert and Set Up KVM VM

On your System76 machine:

```bash
cd kvm

# Restore backup (if needed)
../backup/restore_vm.sh /path/to/backup /var/lib/libvirt/images/popos-vm.qcow2

# Convert disk format (if needed) and set up KVM VM
./convert_utm_to_kvm.sh /var/lib/libvirt/images/popos-vm.qcow2

# Set up KVM VM with proper configuration
./setup_kvm_vm.sh popos-vm /var/lib/libvirt/images/popos-vm.qcow2
```

### Step 4: Start and Verify VM

```bash
# Start the VM
virsh start popos-vm

# View console
virsh console popos-vm

# Or use virt-manager GUI
virt-manager
```

## Detailed Instructions

### Prerequisites on System76

#### 1. Check KVM Support

```bash
# Check if KVM is available
ls -l /dev/kvm

# Check CPU virtualization support
grep -E '(vmx|svm)' /proc/cpuinfo

# If not found, enable in BIOS/UEFI settings
```

#### 2. Install KVM and libvirt

```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients \
  bridge-utils virt-manager virt-viewer

# Add user to libvirt group
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER

# Log out and back in for groups to take effect
```

#### 3. Verify Installation

```bash
# Check libvirt service
sudo systemctl status libvirtd

# Verify user can access libvirt
virsh list --all
```

### Converting UTM Disk to KVM

#### Option A: Direct Conversion (Recommended)

If the backup is already in qcow2 format, you can use it directly:

```bash
# Restore backup (if compressed)
../backup/restore_vm.sh /path/to/backup /var/lib/libvirt/images/popos-vm.qcow2

# Or use the conversion script
./convert_utm_to_kvm.sh /path/to/restored-disk.qcow2
```

#### Option B: Format Conversion

If you need to convert disk format:

```bash
# Convert to qcow2 (if not already)
qemu-img convert -f qcow2 -O qcow2 \
  /path/to/utm-disk.qcow2 \
  /var/lib/libvirt/images/popos-vm.qcow2

# Optimize disk (optional, reduces size)
qemu-img convert -O qcow2 -o compression_type=zlib \
  /var/lib/libvirt/images/popos-vm.qcow2 \
  /var/lib/libvirt/images/popos-vm-optimized.qcow2
```

### Setting Up KVM VM

#### Automated Setup

Use the provided script:

```bash
./setup_kvm_vm.sh popos-vm /var/lib/libvirt/images/popos-vm.qcow2
```

This script will:

- Create VM with appropriate CPU/memory settings
- Configure network (NAT or bridge)
- Set up display (SPICE or VNC)
- Configure storage
- Enable necessary features

#### Manual Setup with virt-manager

1. Open virt-manager: `virt-manager`
2. Click "Create a new virtual machine"
3. Select "Import existing disk image"
4. Choose your converted disk
5. Configure:
   - **OS Type**: Linux
   - **Version**: Pop!_OS 22.04 (or your version)
   - **Memory**: 4GB+ (match original)
   - **CPUs**: 2+ cores
   - **Network**: NAT (default) or Bridge
   - **Display**: SPICE (recommended) or VNC
6. Finish and start VM

#### Manual Setup with virsh

```bash
# Create VM definition
virt-install \
  --name popos-vm \
  --ram 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/popos-vm.qcow2,format=qcow2 \
  --network network=default \
  --graphics spice \
  --video qxl \
  --import \
  --noautoconsole

# Or use the XML definition method (see setup_kvm_vm.sh)
```

### Post-Migration Configuration

#### 1. Update Network Configuration

The VM may need network reconfiguration:

```bash
# Inside the VM
sudo systemctl restart NetworkManager
# Or manually configure if needed
```

#### 2. Update Display Drivers

Install SPICE guest tools for better display:

```bash
# Inside the VM
sudo apt-get update
sudo apt-get install -y spice-vdagent spice-webdavd
sudo reboot
```

#### 3. Enable NVIDIA GPU (if applicable)

If your System76 has NVIDIA GPU and you want passthrough:

```bash
# On host, check GPU
lspci | grep -i nvidia

# Configure GPU passthrough (advanced, see NVIDIA docs)
# Or use NVIDIA driver inside VM
```

#### 4. Verify System

```bash
# Check disk space
df -h

# Check network
ping -c 3 google.com

# Check services
systemctl status

# Test applications
# (test your airgap bundle if installed)
```

## Troubleshooting

### VM Won't Start

**Problem**: `virsh start` fails

**Solutions**:

- Check KVM support: `ls -l /dev/kvm`
- Check user permissions: `groups` (should include libvirt, kvm)
- Check libvirt service: `sudo systemctl status libvirtd`
- Check disk path: `ls -lh /var/lib/libvirt/images/popos-vm.qcow2`
- Check VM definition: `virsh dominfo popos-vm`

### VM Starts but No Display

**Problem**: VM runs but no console/display

**Solutions**:
- Use virt-viewer: `virt-viewer popos-vm`
- Use virt-manager GUI
- Check SPICE/VNC settings: `virsh vncdisplay popos-vm`
- Install guest tools: `sudo apt-get install spice-vdagent`

### Network Not Working

**Problem**: VM has no network access

**Solutions**:

- Check network config: `virsh domiflist popos-vm`
- Restart network in VM: `sudo systemctl restart NetworkManager`
- Check libvirt network: `virsh net-list --all`
- Verify NAT is working: `virsh net-info default`

### Performance Issues

**Problem**: VM is slow

**Solutions**:

- Ensure KVM acceleration: `grep -E '(vmx|svm)' /proc/cpuinfo`
- Increase VM memory/CPUs if host has resources
- Use virtio drivers (should be automatic)
- Check host load: `top`, `htop`
- Disable unnecessary services in VM

### Disk Space Issues

**Problem**: Not enough space for VM

**Solutions**:

- Move VM disk: `virsh domblklist popos-vm`
- Use external storage
- Compress disk: `qemu-img convert -O qcow2 -c ...`
- Clean up old backups

### Boot Issues

**Problem**: VM won't boot or kernel panic

**Solutions**:

- Check boot order: `virsh dumpxml popos-vm | grep boot`
- Try different boot options
- Check disk integrity: `qemu-img check popos-vm.qcow2`
- Verify disk format: `qemu-img info popos-vm.qcow2`

## Advanced Configuration

### CPU Pinning

For better performance, pin VM CPUs:

```bash
virsh vcpupin popos-vm 0 0
virsh vcpupin popos-vm 1 1
```

### Memory Ballooning

Enable memory ballooning for dynamic memory:

```xml
<devices>
  <memballoon model='virtio'/>
</devices>
```

### GPU Passthrough

For NVIDIA GPU passthrough (advanced):

1. Enable IOMMU in BIOS
2. Configure kernel parameters
3. Bind GPU to vfio-pci
4. Pass through to VM

See NVIDIA and libvirt documentation for details.

### Storage Optimization

Optimize disk for better performance:

```bash
# Preallocate space (faster but uses more space)
qemu-img create -f qcow2 -o preallocation=full popos-vm.qcow2 50G

# Use raw format for best performance (no conversion overhead)
qemu-img convert -f qcow2 -O raw popos-vm.qcow2 popos-vm.raw
```

## Scripts

- `convert_utm_to_kvm.sh` - Convert UTM disk format for KVM
- `setup_kvm_vm.sh` - Set up KVM VM with proper configuration
- `migrate_vm.sh` - Complete migration workflow (combines all steps)

## Migration Checklist

- [ ] Backup UTM VM using `../backup/backup_vm.sh`
- [ ] Verify backup integrity
- [ ] Transfer backup to System76
- [ ] Install KVM and libvirt on System76
- [ ] Verify KVM support (`/dev/kvm` exists)
- [ ] Restore backup (if compressed)
- [ ] Convert disk format (if needed)
- [ ] Set up KVM VM
- [ ] Configure network
- [ ] Install SPICE guest tools
- [ ] Verify VM functionality
- [ ] Test applications (airgap bundle, etc.)
- [ ] Document new VM configuration

## Next Steps

After successful migration:

1. **Test thoroughly** - Ensure all applications work
2. **Update documentation** - Note any configuration changes
3. **Remove old UTM VM** - After confirming KVM VM works
4. **Optimize performance** - Tune CPU, memory, storage settings
5. **Set up backups** - Use KVM snapshot/backup tools

## Additional Resources

- [libvirt Documentation](https://libvirt.org/docs.html)
- [QEMU/KVM Documentation](https://www.qemu.org/documentation/)
- [System76 Support](https://support.system76.com/)
- [Pop!_OS Documentation](https://support.system76.com/articles/pop-os/)
