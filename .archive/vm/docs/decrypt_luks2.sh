#!/usr/bin/env bash
# Script to remove LUKS2 encryption by copying filesystem
# Run this from Pop!_OS Live USB environment

set -euo pipefail

echo "=========================================="
echo "LUKS2 Decryption Script"
echo "=========================================="
echo ""
echo "This script will:"
echo "1. Unlock your encrypted partition"
echo "2. Copy filesystem to unencrypted partition"
echo "3. Update system configuration"
echo ""
echo "WARNING: This will remove encryption!"
echo "Make sure you have backups!"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Detect encrypted partition
echo ""
echo "Detecting encrypted partition..."
ENCRYPTED_PART=""
if lsblk | grep -q "vda2.*crypt"; then
    ENCRYPTED_PART="/dev/vda2"
elif lsblk | grep -q "sda2.*crypt"; then
    ENCRYPTED_PART="/dev/sda2"
else
    echo "ERROR: Could not detect encrypted partition"
    echo "Please specify manually:"
    read -p "Encrypted partition (e.g., /dev/vda2): " ENCRYPTED_PART
fi

echo "Using partition: $ENCRYPTED_PART"

# Unlock encrypted partition
echo ""
echo "Unlocking encrypted partition..."
echo "Enter your LUKS password:"
sudo cryptsetup luksOpen "$ENCRYPTED_PART" encrypted_root

# Create mount points
echo ""
echo "Creating mount points..."
sudo mkdir -p /mnt/encrypted /mnt/unencrypted

# Mount encrypted device
echo "Mounting encrypted device..."
sudo mount /dev/mapper/encrypted_root /mnt/encrypted

# Format partition as unencrypted
echo ""
echo "WARNING: Formatting partition as unencrypted (this removes encryption!)"
read -p "Continue? (yes/no): " confirm
if [[ "$confirm" != "yes" ]]; then
    echo "Aborted."
    sudo umount /mnt/encrypted
    sudo cryptsetup luksClose encrypted_root
    exit 1
fi

echo "Formatting $ENCRYPTED_PART as ext4 (unencrypted)..."
sudo mkfs.ext4 -F "$ENCRYPTED_PART"

# Mount unencrypted partition
echo "Mounting unencrypted partition..."
sudo mount "$ENCRYPTED_PART" /mnt/unencrypted

# Copy filesystem
echo ""
echo "Copying filesystem..."
echo "This will take a while (hours for large disks)..."
sudo rsync -aAXv --progress \
    --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/lost+found","/boot/*","/media/*","/home/*/.cache/*"} \
    /mnt/encrypted/ /mnt/unencrypted/

echo ""
echo "Copy complete! Updating system configuration..."

# Mount necessary filesystems for chroot
sudo mount --bind /dev /mnt/unencrypted/dev
sudo mount --bind /proc /mnt/unencrypted/proc
sudo mount --bind /sys /mnt/unencrypted/sys
sudo mount --bind /run /mnt/unencrypted/run

# Chroot and update configuration
sudo chroot /mnt/unencrypted bash <<'CHROOT_EOF'
# Update crypttab (remove encrypted device)
if [ -f /etc/crypttab ]; then
    echo "Updating /etc/crypttab..."
    sed -i.bak 's/^[^#].*crypt/# &/' /etc/crypttab
fi

# Update fstab (change from mapper to direct partition)
if [ -f /etc/fstab ]; then
    echo "Updating /etc/fstab..."
    # Get UUID of unencrypted partition
    UUID=$(blkid -s UUID -o value /dev/vda2 2>/dev/null || blkid -s UUID -o value /dev/sda2)
    if [ -n "$UUID" ]; then
        # Replace mapper device with UUID
        sed -i.bak "s|/dev/mapper/[^ ]*|UUID=$UUID|g" /etc/fstab
    else
        # Fallback to device name
        sed -i.bak 's|/dev/mapper/[^ ]*|/dev/vda2|g' /etc/fstab
        sed -i.bak 's|/dev/mapper/[^ ]*|/dev/sda2|g' /etc/fstab
    fi
fi

# Update initramfs
echo "Updating initramfs..."
update-initramfs -u

# Update GRUB
echo "Updating GRUB..."
update-grub

echo "Configuration updated!"
CHROOT_EOF

# Unmount
echo ""
echo "Unmounting..."
sudo umount /mnt/unencrypted/{dev,proc,sys,run}
sudo umount /mnt/unencrypted
sudo umount /mnt/encrypted
sudo cryptsetup luksClose encrypted_root

echo ""
echo "=========================================="
echo "Decryption complete!"
echo "=========================================="
echo ""
echo "Your system is now unencrypted."
echo "Reboot and it should boot without password prompt."
echo ""
echo "Next steps:"
echo "1. Shut down the VM"
echo "2. Start VM in UTM"
echo "3. It should boot directly without password"

