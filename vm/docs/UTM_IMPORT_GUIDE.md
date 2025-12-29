# Importing VM into UTM on macOS

This guide explains how to import the QEMU VM created by `install_vm.sh` into UTM on macOS.

## Pre-requisites

From the Mac App store, install UTM Virtual Machines.  It's $10.

## Locating the VM Disk Image

The VM disk image should be in one of these locations:

1. **Installed location** (after running `install_vm.sh`):
   ```
   ~/vm-popos/drive/popos-airgap.qcow2
   ```

## Import Existing Disk Image in UTM

### Step 1: Open UTM and Create New VM

1. Open **UTM** application
2. Click **"+"** button or **File > New**
3. Select **"Virtualize"** (not Emulate, since we're using an existing disk)

### Step 2: Import Disk Image

1. Choose **"Linux"** as the operating system
2. Select **"Use an existing disk image"**
3. Click **"Browse"** and navigate to:
   - `~/vm-popos/popos-airgap.qcow2`
4. Select the `popos-airgap.qcow2` file

### Step 3: Configure VM Settings

**Hardware:**
- **Memory**: 16GB (4096 MB) or more
- **CPU Cores**: 8 or more
- **Architecture**: x86_64 (amd64) - **Important!** The VM is x86_64 regardless of your Mac's architecture

**Storage:**
- The disk image should already be attached
- **CRITICAL**: Ensure it's set as the **first boot device** in the boot order
- Go to **Drives** tab and make sure the disk is at the top of the boot order
- If you see a CD/DVD drive in the boot order, remove it or move it below the disk
- Ensure disk interface is set to **VirtIO** (not IDE or SATA) - this matches the original QEMU script

**Network:**
- **Network Mode**: Shared Network (NAT) or Bridged (if you need external access). For air gapped you can leave it off.

**Display:**
- **Display**: **VirtIO-GPU** (NOT default) - This is critical for Pop!_OS GUI to work
- If VirtIO-GPU is not available, try "VirtIO" or "VirtIO 2D"
- **Resolution**: 1280x720 or higher (1280x720 matches the original QEMU script)

**Input:**
- Enable **USB Tablet** support - This provides better mouse integration
- Go to **Input** settings and enable USB tablet mode

**Serial Console (IMPORTANT for Encrypted Disks):**
- If your disk is encrypted (LUKS), you **must** enable serial console to see the password prompt
- Go to **Serial** tab (or **Advanced** → **Serial**)
- **Enable Serial Port** or **Add Serial Port**
- Set it to show in a **separate window** or make it visible
- This allows you to see the encryption password prompt during boot

### Step 4: Save and Start

1. Click **"Save"** to create the VM
2. **Before starting**, double-check these critical settings:
   - Boot order: Disk is first
   - Display: VirtIO-GPU (not default)
   - Input: USB Tablet enabled
3. Click **"Play"** to start the VM
4. If you see a black screen or no GUI:
   - Wait 30-60 seconds for Pop!_OS to boot
   - Try pressing keys or moving mouse
   - Check the troubleshooting section below

## Important Notes

### Architecture
- **The VM is x86_64/amd64** regardless of whether you're on Intel or Apple Silicon Mac
- On Apple Silicon Macs, UTM will use x86_64 emulation (slower but functional)
- This is intentional - the VM matches the production System76 environment

### Performance
- **Apple Silicon Macs**: Expect slower performance due to x86_64 emulation
- **Intel Macs**: Should run reasonably well with native x86_64 support
- Consider allocating more RAM (6-8GB) if you have it available

### Network Access
- The VM uses NAT networking by default
- If you need to access the VM from your Mac, you may need to configure port forwarding
- Or use SSH from within the VM

### First Boot
- Pop!_OS should already be installed in the VM
- If you see installation prompts, the VM may not have been fully set up
- Check that the disk image is complete and not corrupted

## Troubleshooting

### Encrypted Disk - Password Prompt Not Showing

**If your disk is encrypted (LUKS) and you're not seeing the password prompt:**

1. **Enable Serial Console:**
   - Open VM settings → **Serial** tab (or **Advanced** → **Serial**)
   - **Enable Serial Port** or **Add Serial Port**
   - Set it to show in a **separate window** or **terminal tab**
   - Save settings

2. **Access the Console:**
   - When VM starts, look for a **console** or **terminal** button in UTM
   - Or check if a separate console window opened
   - The password prompt appears here (before GUI loads)

3. **Enter Password:**
   - Type your encryption password (characters won't show as you type - this is normal)
   - Press Enter
   - Wait 10-30 seconds for disk to unlock
   - GUI should then appear

4. **If Console Still Not Visible:**
   - In VM settings → **Advanced** tab
   - Look for **Console** or **Serial Console** options
   - Enable **Show Console on Boot** or similar
   - Save and restart VM

### VM Won't Boot to GUI (Black Screen or No Display)

This is the most common issue when switching from QEMU to UTM. Try these steps:

1. **Check Boot Order:**
   - Open VM settings in UTM
   - Go to **Drives** tab
   - Ensure your disk image (`popos-airgap.qcow2`) is at the **top** of the boot order
   - Remove any CD/DVD drives from boot order if present
   - Save settings

2. **Fix Display Settings:**
   - Go to **Display** settings
   - Change display type to **VirtIO-GPU** (or VirtIO if VirtIO-GPU not available)
   - Set resolution to **1280x720** or higher
   - Save settings

3. **Enable USB Tablet:**
   - Go to **Input** settings
   - Enable **USB Tablet** mode for better mouse support
   - This matches the original QEMU script configuration

4. **Check VM is Actually Running:**
   - Look at the VM window - is it black or showing something?
   - Try pressing keys (Ctrl+Alt+F1, F2, etc.) to switch to console
   - Check UTM's console output for errors

5. **Force Boot from Disk:**
   - In UTM, right-click the VM
   - Select **Boot from Disk** or similar option
   - This forces the VM to boot from the hard disk instead of any other device

6. **Check Disk Interface:**
   - In **Drives** settings, ensure the disk is using **VirtIO** interface (not IDE or SATA)
   - This matches the original QEMU script: `-drive "file=...,if=virtio"`

### VM Won't Boot at All
- Verify the disk image exists and is not corrupted
- Check that the disk is set as the boot device in UTM settings
- Ensure architecture is set to x86_64 (amd64)
- Try booting with verbose output enabled in UTM settings

### Slow Performance
- On Apple Silicon: This is expected with x86_64 emulation
- Try allocating more RAM (6-8GB)
- Reduce CPU cores if system is struggling
- Close other applications to free up resources