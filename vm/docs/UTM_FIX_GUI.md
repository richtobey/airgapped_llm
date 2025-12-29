# Quick Fix: UTM VM Not Showing GUI

If your VM imported into UTM but doesn't show the GUI (black screen), follow these steps in order:

## Critical Settings to Check

### 1. Boot Order (MOST IMPORTANT)

1. Open UTM
2. Right-click your VM → **Edit**
3. Go to **Drives** tab
4. **Move your disk image to the TOP** of the boot order
5. Remove or disable any CD/DVD drives from boot order
6. Click **Save**

### 2. Display Settings

1. In VM settings, go to **Display** tab
2. Change **Display** from "Default" to **"VirtIO-GPU"**
   - If VirtIO-GPU not available, try "VirtIO" or "VirtIO 2D"
3. Set resolution to **1280x720** or higher
4. Click **Save**

### 3. Disk Interface

1. In **Drives** tab, click on your disk
2. Ensure **Interface** is set to **"VirtIO"** (not IDE or SATA)
3. This matches the original QEMU script configuration
4. Click **Save**

### 4. USB Tablet (for better mouse)

1. Go to **Input** tab
2. Enable **USB Tablet** mode
3. Click **Save**

## After Making Changes

1. **Stop the VM** if it's running
2. **Start the VM** again
3. Wait 30-60 seconds for Pop!_OS to boot
4. If still black screen, try:
   - Pressing keys (Ctrl+Alt+F1, F2, etc.) to switch to console
   - Check if you can see a console/login prompt

## If Still Not Working

### Check VM is Actually Booting

1. In UTM, look at the VM window
2. Try pressing **Ctrl+Alt+F1** to switch to console
3. If you see a login prompt, the VM is working but display settings are wrong
4. Go back and fix Display settings (step 2 above)

### Force Boot from Disk

1. Right-click VM in UTM
2. Look for **"Boot from Disk"** or **"Force Boot"** option
3. Select it to force boot from hard disk

### Verify Disk Image

Make sure your disk image is at:
```
~/vm-popos/disk/popos-airgap.qcow2
```

Or check the path you imported from.

## Encrypted Disk (LUKS) - Password Prompt Not Showing

If your disk is encrypted and you're not seeing the password prompt:

### The Problem
- Pop!_OS with encrypted disk shows password prompt **before GUI loads**
- UTM might hide this prompt or not show it in the main window
- The prompt appears in the boot console, not the GUI

### Solution: Enable Serial Console

1. **Open VM Settings** in UTM
2. Go to **Serial** tab (or **Advanced** → **Serial**)
3. **Enable Serial Port** or **Add Serial Port**
4. Set it to show in a **separate window** or **terminal tab**
5. Save settings

### Alternative: Use UTM's Console View

1. When VM starts, look for a **console** or **terminal** button in UTM
2. Click it to see the boot console
3. The password prompt should be visible there
4. Type your encryption password (it won't show characters as you type - this is normal)
5. Press Enter

### If Console Still Not Showing

1. In VM settings, go to **Advanced** tab
2. Look for **Console** or **Serial Console** options
3. Enable **Show Console on Boot** or similar
4. Save and restart VM

### After Entering Password

Once you enter the encryption password:
- Wait 10-30 seconds for the system to unlock the disk
- The GUI should then appear
- You may need to log in to Pop!_OS

## Summary: What Changed from QEMU Script

The original QEMU script (`start_vm.sh`) uses these settings that UTM might not set automatically:

- **Display**: `-display cocoa` + `-device virtio-vga` → UTM needs **VirtIO-GPU**
- **Disk**: `-drive "file=...,if=virtio"` → UTM needs **VirtIO interface**
- **Input**: `-device usb-tablet` → UTM needs **USB Tablet enabled**
- **Boot**: Disk must be first in boot order
- **Console**: QEMU shows boot console automatically → UTM needs **Serial Console enabled**

Fix these 5 things and your VM should boot to GUI!
