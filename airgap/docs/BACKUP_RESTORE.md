# System Backup and Restore Guide

This guide explains how to create backups of your airgapped Pop!_OS system and restore them using Clonezilla.

## Overview

**Clonezilla** is a free, open-source disk imaging and cloning tool that is the recommended solution for backing up and restoring your airgapped system. It provides:

- Full disk or partition backups
- Compression to save space
- Easy-to-use interface
- Reliable restore functionality
- Support for various filesystems
- Free and open source

## Drive Requirements

**Important:** You need TWO separate drives:

1. **Clonezilla USB Drive** (for booting Clonezilla)
   - **Size:** 4-8 GB minimum
   - **Purpose:** Contains Clonezilla bootable system only
   - **Reusable:** Can be used for multiple backups/restores
   - **Note:** Backups do NOT go on this drive

2. **Backup Storage Drive** (where backups are stored)
   - **Size:** Depends on your system (see below)
   - **Purpose:** Stores your backup images
   - **Format:** See filesystem recommendations below
   - **Note:** This is where your actual backups are saved

### Filesystem Format for Backup Storage Drive

**Recommended filesystems (in order of preference):**

1. **ext4** (Recommended)
   - Native Linux filesystem
   - Best performance and reliability
   - Supports large files (>4GB)
   - **Use for:** Linux/Pop!_OS systems

2. **exFAT** (If cross-platform needed)
   - Works on Windows and Linux
   - Supports large files (>4GB)
   - **Use if:** Need to access backups from Windows

3. **NTFS** (Windows compatibility)
   - Works on Windows and Linux
   - Supports large files
   - **Use if:** Primarily Windows, occasional Linux access

4. **FAT32** (Not recommended)
   - 4GB file size limit (backups will be split)
   - Slower performance
   - **Avoid** unless necessary for compatibility

**Note:** The Clonezilla USB itself doesn't need formatting - it's created directly from the ISO image.

### Backup Drive Size Calculation

For a **compressed backup** (recommended with gzip):
- **Minimum:** 30-50% of your used disk space
- **Example:** 500GB disk with 200GB used = ~60-100GB backup
- **Recommended:** At least 2x your used space (for multiple backups)

For an **uncompressed backup**:
- **Required:** Space equal to your entire disk size
- **Example:** 500GB disk = 500GB backup
- **Not recommended** unless you have plenty of space

**Recommendation:** Get a backup drive that's at least as large as your system disk, preferably larger if you want to keep multiple backups.

## Quick Start

### Step 1: Download Clonezilla Live

On an online machine, download Clonezilla Live ISO:

```bash
# Download latest Clonezilla Live
wget https://sourceforge.net/projects/clonezilla/files/clonezilla_live_stable/latest/clonezilla-live-*.iso

# Or visit: https://clonezilla.org/downloads.php
```

### Step 2: Create Bootable Clonezilla USB

**Use a small USB drive (4-8GB is fine)** - this is just for booting Clonezilla:

```bash
# Find your USB device
lsblk

# Create bootable USB (replace /dev/sdb with your USB device)
sudo ./create_clonezilla_usb.sh clonezilla-live-*.iso /dev/sdb

# Or manually:
sudo dd if=clonezilla-live-*.iso of=/dev/sdb bs=4M status=progress
```

**Note:** This USB only contains Clonezilla - your backups go on a separate drive.

### Step 3: Prepare Backup Storage Drive

**Use a separate, larger drive for backups** (USB drive, external HDD, etc.):

1. Connect your backup storage drive to the airgapped machine
2. Format the drive (if needed):

   **For ext4 (recommended):**
   ```bash
   sudo mkfs.ext4 -L "BACKUP" /dev/sdX1
   ```

   **For exFAT (if needed for cross-platform access):**
   ```bash
   # Install exfat-utils first:
   sudo apt-get install exfat-utils exfat-fuse
   sudo mkfs.exfat -n "BACKUP" /dev/sdX1
   ```

3. Ensure it has enough free space (see size calculation above)

**Note:** Clonezilla can also format the drive during backup setup if needed.

### Step 4: Boot from Clonezilla USB

**Using Boot Override (F11) - Recommended Method:**

The Boot Override menu allows you to temporarily boot from a USB device without changing your permanent boot order. This is the recommended method for booting Clonezilla.

**Steps:**

1. **Ensure Clonezilla USB is plugged in** - The USB must be connected before you power on the computer
2. **Power on or restart** your computer
3. **Immediately press F11** repeatedly as soon as you see the manufacturer logo or BIOS screen
   - Press F11 multiple times rapidly (don't wait)
   - Timing is important - start pressing as soon as the computer starts
4. **Boot menu appears** - You should see a boot device selection menu
5. **Look for "Boot Override"** or boot device selection
   - The menu may be labeled "Boot Menu", "Boot Override", or "Select Boot Device"
6. **Select Clonezilla USB**:
   - May appear as "UEFI: USB", "USB: Clonezilla", "USB Flash Drive", or similar
   - If you see both "UEFI: USB" and "USB" options, choose the **UEFI** option
   - Use arrow keys to navigate, Enter to select
7. **Clonezilla should start booting**

**Alternative Boot Menu Keys:**
- Some systems use different keys: **F12**, **F8**, **ESC**, or **DEL**
- Check your system's documentation or watch for on-screen prompts during boot

**If USB Doesn't Appear in Boot Menu:**

1. **USB must be plugged in before powering on** - Some systems only detect USB devices present during POST (Power-On Self-Test)
2. **Enter BIOS/UEFI Settings**:
   - Press F2, F10, DEL, or ESC during boot (varies by manufacturer)
   - Navigate to "Boot" or "Security" section
3. **Disable Secure Boot** (REQUIRED):
   - Find "Secure Boot" setting
   - Set to "Disabled" or "Off"
   - Clonezilla does not support Secure Boot
4. **Enable UEFI Boot Mode**:
   - Find "Boot Mode" or "CSM" (Compatibility Support Module) setting
   - Set to "UEFI" mode
   - Disable "Legacy Boot" or "CSM" if enabled
5. **Save and Exit**:
   - Press F10 to save (or follow on-screen prompts)
   - Computer will restart
6. **Try F11 boot menu again** - USB should now appear

**Note:** Boot Override (F11) is a one-time boot selection. It doesn't permanently change your boot order, so your system will boot normally from the hard drive on the next restart.

**Important:** The Clonezilla USB must be plugged in before powering on.

1. **Power on or restart** your airgapped machine
2. **Immediately press F11** (or your system's boot menu key) repeatedly during startup
   - Common boot menu keys: F11, F12, F8, ESC, DEL (varies by manufacturer)
   - Press repeatedly from the moment you see the manufacturer logo
3. **In the boot menu**, look for **"Boot Override"** or boot device selection menu
4. **Select the Clonezilla USB device**
   - May appear as "UEFI: USB", "USB: Clonezilla", or similar
   - If you see both UEFI and Legacy options, choose the UEFI option
5. **If USB doesn't appear in boot menu:**
   - Ensure USB is plugged in before powering on
   - Enter BIOS/UEFI settings (usually F2, F10, or DEL)
   - Disable **Secure Boot** (required for Clonezilla)
   - Enable **UEFI Boot** mode (disable Legacy/CSM mode)
   - Save and exit, then try F11 boot menu again

**Note:** Boot Override (F11) is a one-time boot selection that doesn't change your permanent boot order.

### Step 5: Create Backup

1. **After Clonezilla boots**, select **"device-image"** mode (for disk-to-image backup)
2. Choose **"savedisk"** (to save entire disk)
3. Enter a name for your backup (e.g., `virgin_state_20240101`)
4. Select the **source disk** (your system disk, e.g., `/dev/sda`)
5. Select **filesystem** (usually ext4 for Pop!_OS)
6. Choose **compression** (recommended: gzip to save space)
7. **Select backup location** - Choose your **backup storage drive** (NOT the Clonezilla USB)
8. Confirm and start backup

**Backup will be saved as:** `[backup_name]-[date].img.gz` on your backup storage drive

### Step 6: Restore from Backup

1. **Boot from Clonezilla USB** (using F11 boot override method above)
2. Select **"device-image"** mode
3. Choose **"restoredisk"** (to restore entire disk)
4. Select your **backup image** from the backup location
5. Select **target disk** (the disk to restore to)
6. Confirm and start restore

**Warning:** Restoring will overwrite all data on the target disk!

## Backup Strategies

### Strategy 1: Virgin State Backup

Create immediately after fresh Pop!_OS installation, before installing the airgap bundle:

1. Install Pop!_OS
2. Boot Clonezilla USB
3. Create backup named: `virgin_state_YYYYMMDD`
4. Store on external drive

### Strategy 2: Post-Installation Backup

Create after installing the airgap bundle:

1. Run `install_offline.sh` to install airgap bundle
2. Boot Clonezilla USB
3. Create backup named: `with_airgap_bundle_YYYYMMDD`
4. Store on external drive

### Strategy 3: Regular Backups

Create regular backups of your working system:

- Weekly backups: `weekly_YYYYMMDD`
- Monthly backups: `monthly_YYYYMMDD`
- Before major changes: `pre_change_YYYYMMDD`

## Clonezilla Options Explained

### Backup Modes

- **device-image**: Disk/partition to image file (recommended)
- **device-device**: Direct disk-to-disk cloning
- **part-image**: Partition to image file

### Compression Options

- **None**: Fastest, largest files
- **gzip**: Good balance (recommended)
- **bzip2**: Better compression, slower
- **xz**: Best compression, slowest

### Filesystem Support

**For the system being backed up:**
Clonezilla supports backing up from:
- ext2, ext3, ext4 (Linux)
- NTFS, FAT32 (Windows)
- HFS+ (macOS)
- And many more

**For the backup storage drive (where images are saved):**
- **ext4**: Best for Linux (recommended)
- **exFAT**: Good for cross-platform (Windows/Linux)
- **NTFS**: Good for Windows/Linux
- **FAT32**: Not recommended (4GB file limit)

## Storage Requirements Summary

### Clonezilla USB Drive
- **Size:** 4-8 GB (small USB drive is fine)
- **Purpose:** Boot Clonezilla only
- **Reusable:** Yes, for all backups/restores

### Backup Storage Drive
- **For compressed backups (gzip):** 30-50% of used disk space per backup
- **For uncompressed backups:** 100% of disk size per backup
- **For multiple backups:** Plan for 2-3x single backup size

### Examples

**Scenario 1: 500GB disk, 200GB used**
- Clonezilla USB: 4-8 GB
- Single compressed backup: ~60-100 GB
- Backup drive needed: At least 200-300 GB (for multiple backups)

**Scenario 2: 1TB disk, 500GB used**
- Clonezilla USB: 4-8 GB
- Single compressed backup: ~150-250 GB
- Backup drive needed: At least 500 GB - 1 TB (for multiple backups)

### Multiple Backups
- Keep 2-3 recent backups on backup drive
- Store oldest backup offsite
- Rotate backups monthly

## Best Practices

1. **Test Restores**: Periodically test restoring from backup to verify integrity
2. **Multiple Copies**: Keep backups in multiple locations
3. **Label Backups**: Clearly label backup media with dates and contents
4. **Verify Checksums**: Clonezilla automatically creates checksums
5. **Regular Backups**: Create backups before major changes
6. **Offsite Storage**: Keep at least one backup in a physically separate location

## Troubleshooting

### Clonezilla Won't Boot

**If USB doesn't appear in boot menu (F11):**

1. **Ensure USB is plugged in before powering on** - Some systems only detect USB devices present at POST
2. **Use Boot Override (F11)**:
   - Power on and immediately press F11 repeatedly
   - Look for "Boot Override" or boot device selection menu
   - Select the USB device (may show as "UEFI: USB" or similar)
3. **BIOS/UEFI Settings**:
   - Enter BIOS/UEFI (F2, F10, DEL, or ESC during boot)
   - **Disable Secure Boot** (required - Clonezilla doesn't support Secure Boot)
   - **Enable UEFI Boot mode** (disable Legacy/CSM mode)
   - Save and exit, then try F11 again
4. **Hardware troubleshooting**:
   - Verify USB was created correctly: `sudo fdisk -l /dev/sdb`
   - Try different USB port (USB 2.0 port often works better than USB 3.0)
   - Try different USB drive if available
   - Ensure USB is fully inserted
5. **Verify USB detection**:
   - Check if system detects USB: `lsblk | grep sdb` (replace sdb with your USB device)
   - Verify partition table: `sudo fdisk -l /dev/sdb`

### Backup Fails

- Check available space on backup drive
- Verify backup drive is properly mounted
- Check disk for errors: `fsck /dev/sda`
- Try different compression method

### Restore Fails

- Verify backup image integrity (Clonezilla checks automatically)
- Check target disk is large enough
- Ensure target disk is not mounted
- Try restoring without compression first

### System Won't Boot After Restore

- Verify bootloader was restored correctly
- Check BIOS/UEFI settings
- Ensure correct disk is set as boot device
- Try boot repair from live USB

## Advanced: Automated Backup Script

For convenience, you can create a simple script to automate Clonezilla commands:

```bash
#!/bin/bash
# Simple wrapper to prepare for Clonezilla backup
# Run this before booting Clonezilla USB

BACKUP_NAME="backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_LOCATION="/mnt/backup_drive"

echo "Backup preparation:"
echo "Name: $BACKUP_NAME"
echo "Location: $BACKUP_LOCATION"
echo ""
echo "Next steps:"
echo "1. Boot from Clonezilla USB"
echo "2. Select device-image -> savedisk"
echo "3. Use backup name: $BACKUP_NAME"
echo "4. Select backup location: $BACKUP_LOCATION"
```

## Clonezilla Alternatives (If Needed)

If Clonezilla doesn't work for your use case:

- **dd + gzip**: Simple command-line disk imaging
  ```bash
  sudo dd if=/dev/sda bs=4M status=progress | gzip > /mnt/backup/system.img.gz
  ```

- **rsync**: File-level backup (not disk image)
  ```bash
  sudo rsync -aAXH --info=progress2 / /mnt/backup/system_backup/
  ```

## Additional Resources

- [Clonezilla Official Site](https://clonezilla.org/)
- [Clonezilla Documentation](https://clonezilla.org/clonezilla-live/doc/)
- [Clonezilla FAQ](https://clonezilla.org/clonezilla-live/faq.php)
- [Pop!_OS Recovery](https://support.system76.com/articles/live-disk/)

## Summary

**Recommended Workflow:**

1. **Fresh Install** → Clonezilla backup → "virgin_state"
2. **Install Airgap Bundle** → Clonezilla backup → "with_airgap_bundle"
3. **Regular Use** → Clonezilla backup → "weekly_YYYYMMDD"
4. **Before Changes** → Clonezilla backup → "pre_change_YYYYMMDD"

Clonezilla is the simplest, most reliable solution for airgapped system backups.
