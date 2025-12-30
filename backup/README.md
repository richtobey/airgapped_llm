# Physical System Backup and Restore

This directory contains scripts to create a bootable USB key with backup and restore tools for your physical System76 Pop!_OS system.

## Overview

Before making major changes to your System76 machine, it's essential to create a complete backup. This solution provides:

- **Bootable USB Key**: Pop!_OS live environment with backup tools
- **Full Disk Backup**: Complete system image including partition table and bootloader
- **Restore Script**: Restore entire system from backup
- **Verification**: Checksums and integrity checks

## Requirements

### For Creating Backup USB (on Mac or Linux)

- macOS or Linux system
- USB drive (16GB+ recommended, will be formatted)
- Internet connection (to download Pop!_OS ISO)
- Admin/sudo access

### For Backup Process (on System76)

- Physical System76 machine with Pop!_OS installed
- External USB drive for backup (50GB+ free space recommended)
- Bootable backup USB (created with `create_backup_usb.sh`)
- Time: ~30-60 minutes depending on disk size

### For Restore Process

- Backup files on external drive
- Bootable backup USB
- Target System76 machine
- Time: ~30-60 minutes depending on backup size

## Quick Start

### Step 1: Create Bootable Backup USB

On your Mac or Linux system:

```bash
cd backup
./create_backup_usb.sh
```

This script will:

1. Download Pop!_OS ISO (if not present)
2. Format USB drive (WARNING: erases all data)
3. Create bootable USB with backup tools
4. Copy backup/restore scripts to USB

**IMPORTANT**: The USB drive will be completely erased. Backup any important data first.

### Step 2: Boot from USB and Backup System

1. **Shut down the System76 machine completely**
2. Insert the bootable USB into the System76 machine
3. Boot from USB (usually F12 or similar during boot)
4. Once in Pop!_OS live environment:

```bash
# Identify your system disk
sudo ./identify_disks.sh

# Mount your external backup drive
sudo mkdir -p /mnt/backup-drive
sudo mount /dev/sdX1 /mnt/backup-drive  # Replace sdX1 with your backup drive

# Run backup script
sudo ./backup_system.sh /dev/sda /mnt/backup-drive --compress
```

The backup script will:

- Create compressed backup of entire disk
- Backup partition table
- Generate checksums for verification
- Create metadata file with system information

### Step 3: Verify Backup

```bash
# Verify backup integrity
./verify_backup.sh /mnt/backup-drive/system76-backup-YYYYMMDD-HHMMSS
```

### Step 4: Restore (if needed)

If you need to restore the system:

```bash
# Boot from USB again
# Mount backup drive
sudo mount /dev/sdX1 /mnt/backup-drive

# Identify target disk
sudo ./identify_disks.sh

# Restore system
sudo ./restore_system.sh /mnt/backup-drive/system76-backup-YYYYMMDD-HHMMSS /dev/sda
```

## Detailed Instructions

### Creating the Backup USB

#### Option A: Automated Script (Recommended)

```bash
cd backup
chmod +x create_backup_usb.sh
./create_backup_usb.sh
```

The script will prompt you for:

- USB device path (e.g., `/dev/disk2` on Mac, `/dev/sdb` on Linux)
- Pop!_OS ISO location (downloads if not provided)
- Confirmation before formatting

#### Option B: Manual Creation

1. Download Pop!_OS ISO:

   ```bash
   cd backup
   # Use mac_vm/setup_mac_vm.sh or download manually
   ```

2. Create bootable USB:

   ```bash
   # On Mac: Use balenaEtcher or Disk Utility
   # On Linux: Use dd or balenaEtcher
   ```

3. Copy scripts to USB:

   ```bash
   # Mount USB
   # Copy scripts
   cp backup_system.sh restore_system.sh verify_backup.sh identify_disks.sh /Volumes/BACKUP_USB/
   chmod +x /Volumes/BACKUP_USB/*.sh
   ```

### Identifying Your System Disk

Before backing up, identify which disk contains your Pop!_OS installation:

```bash
sudo ./identify_disks.sh
```

This will show:

- All available disks
- Disk sizes and models
- Mount points
- Which disk is the system disk (marked with warning)

**Always double-check** the disk identifier before proceeding!

### Backing Up the System

From bootable USB or directly on System76:

```bash
# Basic backup (uncompressed)
sudo ./backup_system.sh /dev/sda /mnt/backup-drive

# With compression (recommended, saves space)
sudo ./backup_system.sh /dev/sda /mnt/backup-drive --compress

# With xz compression (better compression, slower)
sudo ./backup_system.sh /dev/sda /mnt/backup-drive --compress-type xz

# Skip filesystem check (faster, but less safe)
sudo ./backup_system.sh /dev/sda /mnt/backup-drive --compress --skip-fs-check
```

#### Backup Options

- `--compress`: Use compression (gzip by default, saves space)
- `--compress-type TYPE`: Compression type: `gzip` or `xz` (xz is better but slower)
- `--verify`: Verify backup after creation
- `--skip-fs-check`: Skip filesystem check before backup (faster but less safe)

### Restoring the System

**WARNING**: Restore will completely erase the target disk!

```bash
# Boot from USB
# Mount backup drive
sudo mount /dev/sdX1 /mnt/backup-drive

# Identify target disk
sudo ./identify_disks.sh

# Restore system (requires multiple confirmations)
sudo ./restore_system.sh /mnt/backup-drive/system76-backup-YYYYMMDD-HHMMSS /dev/sda
```

The restore script will:

- Restore partition table
- Restore full disk image
- Restore bootloader (GRUB)
- Require multiple confirmations for safety

#### Restore Options

- `--no-verify`: Skip backup verification before restore
- `--force`: Skip safety confirmations (DANGEROUS - not recommended)
- `--skip-bootloader`: Don't restore bootloader (advanced use only)

## Backup Structure

A backup directory contains:

```text
system76-backup-YYYYMMDD-HHMMSS/
├── system-disk.img.gz          # Compressed disk image (or .xz or .img if uncompressed)
├── partition-table.bin          # Binary partition table backup
├── partition-table.txt          # Text partition table backup
├── backup-metadata.json         # System information and metadata
├── checksums.sha256             # Checksums for verification
└── backup.log                   # Backup process log
```

## Verification

Always verify backups after creation:

```bash
./verify_backup.sh /mnt/backup-drive/system76-backup-YYYYMMDD-HHMMSS
```

This checks:

- Checksum integrity
- File completeness
- Metadata validity
- Partition table backup (if present)

## Troubleshooting

### USB Won't Boot

- Ensure USB is formatted correctly
- Try different USB port (prefer USB 3.0)
- Verify ISO was written correctly
- Check BIOS/UEFI boot settings
- Disable Secure Boot if needed

### Backup Fails

- Check disk space: `df -h`
- Verify system disk is not mounted (boot from USB)
- Check file permissions
- Try uncompressed backup first
- Ensure backup drive is mounted correctly

### Restore Fails

- Verify backup integrity first: `./verify_backup.sh`
- Check target disk has sufficient space
- Ensure target disk is not mounted
- Try uncompressed restore if compressed fails
- Check bootloader installation logs

### Can't Identify System Disk

- Use `lsblk` to list all block devices
- Check `/proc/partitions` for partition information
- Look for disk with root (`/`) mount point
- Check disk labels: `lsblk -f`
- Use `fdisk -l` to see partition tables

### Bootloader Issues After Restore

If system won't boot after restore:

1. Boot from live USB
2. Mount root partition: `sudo mount /dev/sdaX /mnt`
3. Install GRUB:

   ```bash
   sudo mount --bind /dev /mnt/dev
   sudo mount --bind /proc /mnt/proc
   sudo mount --bind /sys /mnt/sys
   sudo chroot /mnt grub-install /dev/sda
   sudo chroot /mnt update-grub
   ```

4. Unmount and reboot

## Best Practices

1. **Always verify backups** before deleting originals
2. **Test restore** on a test system if possible
3. **Keep multiple backups** (especially before major changes)
4. **Store backups off-site** or on separate drives
5. **Document backup locations** and dates
6. **Compress backups** to save space (use `--compress`)
7. **Regular backups** before system updates or major changes
8. **Label backup drives** with dates and system names

## Scripts

- `create_backup_usb.sh` - Create bootable USB with backup tools
- `identify_disks.sh` - Identify disks for backup/restore (safety helper)
- `backup_system.sh` - Full disk image backup of physical system
- `restore_system.sh` - Restore full disk image to physical system
- `verify_backup.sh` - Verify backup integrity

## Disk Size Considerations

Full disk backups can be large:

- **50GB disk**: ~25GB compressed backup (gzip)
- **100GB disk**: ~50GB compressed backup (gzip)
- **500GB disk**: ~250GB compressed backup (gzip)
- **1TB disk**: ~500GB compressed backup (gzip)

xz compression provides better compression (30-40% smaller) but is slower.

## Security Notes

- Backups contain all system data including any sensitive information
- Store backups securely (encrypted if needed)
- Use secure transfer methods when moving backups
- Consider encrypting backup files: `gpg --symmetric backup-file.img.gz`
- Keep backups in secure physical location

## Next Steps

After creating a backup:

1. Verify backup integrity
2. Test restore on a test system if possible
3. Store backup in safe location
4. Document backup location and date
5. Create regular backup schedule

## Migration Notes

If you're migrating from a VM (UTM) to physical System76:

1. First backup your VM using the VM backup scripts (if still available)
2. Then backup your physical System76 system using these scripts
3. Keep both backups until migration is complete and verified
