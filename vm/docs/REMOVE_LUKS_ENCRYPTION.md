# Remove LUKS Encryption from VM Disk

If you want to use UTM without dealing with password prompts, you can remove LUKS encryption from the VM disk. This allows UTM to boot directly without password.

## ⚠️ Important Warnings

1. **Backup First**: Removing encryption is a destructive operation. Make sure you have backups!
2. **Data Loss Risk**: If something goes wrong, you could lose data
3. **Time**: Decrypting a large disk can take hours
4. **Security**: Your disk will no longer be encrypted

## Prerequisites

- Boot the VM using QEMU script (`start_vm.sh`) - this shows the password prompt properly
- Have enough free space (you need space for decrypted data)
- Be patient - this process takes time

## Method 1: Decrypt Using cryptsetup-reencrypt (Recommended)

This is the safest method - it decrypts in place.

### Step 1: Boot VM with QEMU Script

1. **Boot VM using your QEMU script:**
   ```bash
   cd ~/vm-popos
   ./scripts/start_vm.sh
   ```
2. **Enter password** when prompted
3. **Log into Pop!_OS**

### Step 2: Check Current Encryption

1. **Open terminal in VM**
2. **Check encrypted devices:**
   ```bash
   lsblk
   sudo cryptsetup status /dev/mapper/* 2>/dev/null | grep -E "type|device"
   ```
3. **Find your encrypted device** (usually something like `/dev/mapper/sda2_crypt` or similar)

### Step 3: Decrypt the Disk

**LUKS2 doesn't support in-place decryption.** We need to copy the filesystem to an unencrypted partition.

1. **Check your current setup:**
   ```bash
   # See current layout
   sudo lsblk
   
   # Check what's encrypted and mounted
   mount | grep mapper
   # You should see something like: /dev/mapper/vda2_crypt on /
   ```

2. **Boot from Pop!_OS Live USB (Recommended Method)**

   Since you can't decrypt the root filesystem while it's mounted, boot from a live USB:
   
   a. **Boot VM from Pop!_OS ISO:**
      - Modify your QEMU script to boot from ISO temporarily
      - Or use UTM to boot from ISO
   
   b. **Open terminal in live environment**
   
   c. **Unlock the encrypted partition:**
      ```bash
      # Find the encrypted partition
      sudo lsblk
      # Usually /dev/vda2 or /dev/sda2
      
      # Unlock it
      sudo cryptsetup luksOpen /dev/vda2 encrypted_root
      ```
   
   d. **Mount both devices:**
      ```bash
      # Create mount points
      sudo mkdir -p /mnt/encrypted /mnt/unencrypted
      
      # Mount encrypted device
      sudo mount /dev/mapper/encrypted_root /mnt/encrypted
      
      # Format the partition as unencrypted (WARNING: This erases encryption!)
      sudo mkfs.ext4 -F /dev/vda2
      
      # Mount unencrypted partition
      sudo mount /dev/vda2 /mnt/unencrypted
      ```
   
   e. **Copy all data:**
      ```bash
      # Copy everything except special directories
      sudo rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/lost+found","/boot/*","/media/*","/home/*/.cache/*"} /mnt/encrypted/ /mnt/unencrypted/
      
      # This takes time! Be patient.
      ```

3. **Alternative: Copy from Running System (Less Safe)**

   If you can't boot from live USB, you can try copying while running, but this is risky:
   
   ```bash
   # Find your encrypted mapper device
   ENCRYPTED_MAPPER=$(mount | grep " / " | grep mapper | awk '{print $1}')
   # Usually: /dev/mapper/vda2_crypt
   
   # Create a backup location (needs free space!)
   # You'll need another partition or external drive
   sudo mkdir -p /mnt/backup
   # Mount another partition or external drive here
   
   # Copy filesystem
   sudo rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/lost+found","/boot/*"} / /mnt/backup/
   ```
   
   **Then** you'd need to boot from live USB to format and restore.

4. **Wait for copy** (this takes time - hours for large disks)

### Step 4: Complete the Decryption

After copying completes:

1. **If booted from live USB, chroot into the new system:**
   ```bash
   # Mount necessary filesystems
   sudo mount --bind /dev /mnt/unencrypted/dev
   sudo mount --bind /proc /mnt/unencrypted/proc
   sudo mount --bind /sys /mnt/unencrypted/sys
   sudo mount --bind /run /mnt/unencrypted/run
   
   # Chroot
   sudo chroot /mnt/unencrypted
   ```

2. **Update /etc/crypttab:**
   ```bash
   sudo nano /etc/crypttab
   ```
   **Remove or comment out** the line for your encrypted device:
   ```
   # sda2_crypt UUID=... none luks
   ```

3. **Update /etc/fstab:**
   ```bash
   sudo nano /etc/fstab
   ```
   **Change** the mount point from mapper device to direct partition:
   ```
   # Before:
   /dev/mapper/vda2_crypt / ext4 defaults 0 1
   
   # After:
   /dev/vda2 / ext4 defaults 0 1
   ```
   
   **Or use UUID** (more reliable):
   ```bash
   # Get UUID of unencrypted partition
   sudo blkid /dev/vda2
   ```
   Then in fstab:
   ```
   UUID=your-uuid-here / ext4 defaults 0 1
   ```

4. **Update initramfs:**
   ```bash
   sudo update-initramfs -u
   ```

5. **Update GRUB:**
   ```bash
   sudo update-grub
   ```

6. **Reboot** - system should boot without encryption

## Method 2: Fresh Install Without Encryption (Easier)

If you don't have critical data to preserve:

1. **Boot VM with QEMU script**
2. **Backup any important data** to external location
3. **Reinstall Pop!_OS** without encryption:
   - Boot from Pop!_OS ISO
   - During installation, choose "Erase disk and install"
   - **Don't enable encryption**
   - Complete installation
4. **VM will boot in UTM without password**

## Method 3: Keep Encryption But Make It Work Better

Instead of removing encryption, make it work better with UTM:

1. **Boot with QEMU script**
2. **Increase timeout** (see `UTM_LUKS_TIMEOUT.md`):
   ```bash
   sudo nano /etc/default/grub
   # Add: cryptdevice.timeout=60
   sudo update-grub
   ```
3. **Configure serial console** for LUKS:
   ```bash
   sudo nano /etc/initramfs-tools/conf.d/cryptroot
   # Add: CRYPTSETUP_OPTIONS="--tty=/dev/ttyS0"
   sudo update-initramfs -u
   ```
4. **UTM should work better** with longer timeout and serial console

## Verification

After removing encryption:

1. **Shut down VM**
2. **Start VM in UTM**
3. **Should boot directly** without password prompt
4. **No encryption** - disk is unencrypted

## Troubleshooting

### Decryption Fails

- **Check disk space** - need free space for decrypted data
- **Check for errors** in cryptsetup output
- **Try Option B** (header file method) if Option A fails
- **Restore from backup** if needed

### "LUKS2 decryption is supported with detached header device only" Error

If you get this error:
- **LUKS2 doesn't support in-place decryption** like LUKS1 does
- **You MUST use the copy method** (boot from live USB and copy filesystem)
- The `reencrypt --decrypt` command doesn't work with LUKS2 in-place

### "requires header option" Error

If you get this error:
- LUKS2 requires a detached header for decryption
- **Easier solution:** Use the copy method instead (boot from live USB)
- The copy method is safer and more reliable anyway

### System Won't Boot After Decryption

- **Boot from Pop!_OS ISO**
- **Chroot into system:**
  ```bash
  sudo mount /dev/sda2 /mnt
  sudo mount --bind /dev /mnt/dev
  sudo mount --bind /proc /mnt/proc
  sudo mount --bind /sys /mnt/sys
  sudo chroot /mnt
  ```
- **Fix fstab and crypttab** (see Step 4 above)
- **Update initramfs and GRUB**

### Still Asking for Password

- **Check /etc/crypttab** - make sure encrypted device is removed/commented
- **Check /etc/fstab** - should point to `/dev/sda2` not mapper device
- **Update initramfs** again: `sudo update-initramfs -u`

## Recommendation

**If you have important data:**
- Use Method 1 (decrypt in place) - safer
- Backup first!

**If you don't have important data:**
- Use Method 2 (fresh install) - easier and faster

**If you want to keep encryption:**
- Use Method 3 (fix timeout/serial) - keeps security

## Summary

**To remove encryption:**
1. Boot with QEMU script (shows password properly)
2. Decrypt the disk using cryptsetup
3. Update fstab, crypttab, initramfs, GRUB
4. Reboot - no more encryption

**Result:** UTM can boot the VM without password prompt!

