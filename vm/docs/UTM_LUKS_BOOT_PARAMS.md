# UTM: Fix LUKS Password Prompt with Boot Parameters

If the LUKS password prompt doesn't show in the serial console, you need to redirect console output to serial using kernel boot parameters.

## The Problem

- LUKS password prompt goes to **tty1** (main console) by default
- Serial console is **ttyS0** (different device)
- Without redirection, the prompt won't appear in serial console

## Solution: Add Kernel Boot Parameters

### Step 1: Access UTM Boot Settings

1. **Open UTM**
2. **Right-click your VM** → **Edit**
3. Go to **Advanced** tab
   - Look for **Boot Arguments**, **QEMU Arguments**, or **Kernel Parameters**
   - In some UTM versions, this might be under **QEMU** or **System** settings

### Step 2: Add Console Redirection Parameters

Add these parameters to redirect console to serial:

**Option 1 (Recommended):**
```
console=ttyS0,115200 console=tty1
```

**Option 2 (If Option 1 doesn't work):**
```
console=ttyS0,115200n8
```

**Option 3 (Alternative format):**
```
console=serial0,115200 console=tty1
```

**What these do:**
- `console=ttyS0,115200` - Send console output to serial port (ttyS0) at 115200 baud
- `console=tty1` - Also keep main console (tty1) for fallback
- `115200n8` - 115200 baud, no parity, 8 data bits (standard serial config)

### Step 3: Save and Test

1. **Save** the VM settings
2. **Start the VM**
3. **Open the serial console** in UTM
4. **Wait for boot** - password prompt should now appear in serial console
5. **Type password** and press Enter

## Alternative: Modify GRUB Configuration

If you can't add boot parameters in UTM, modify GRUB inside the VM:

### Method 1: Boot into Recovery Mode

1. **Start VM** and hold **Shift** during boot to access GRUB menu
2. Select **Advanced options** or **Recovery mode**
3. Boot into recovery/rescue mode
4. Edit `/etc/default/grub`:
   ```bash
   sudo nano /etc/default/grub
   ```
5. Find the line starting with `GRUB_CMDLINE_LINUX_DEFAULT` and add:
   ```
   console=ttyS0,115200
   ```
   Example:
   ```
   GRUB_CMDLINE_LINUX_DEFAULT="quiet splash console=ttyS0,115200"
   ```
6. Save and update GRUB:
   ```bash
   sudo update-grub
   ```
7. Reboot - password prompt should now appear in serial console

### Method 2: Edit GRUB at Boot Time

1. **Start VM** and hold **Shift** during boot
2. In GRUB menu, press **E** to edit boot entry
3. Find the line starting with `linux` (kernel line)
4. Add `console=ttyS0,115200` to the end of that line
5. Press **Ctrl+X** to boot with these parameters
6. Password prompt should appear in serial console

**Note:** This is temporary - you'll need to do this every boot unless you modify GRUB permanently (Method 1).

## Verify Serial Console is Working

To test if serial console is working:

1. Boot VM and access serial console
2. You should see boot messages scrolling
3. If you see boot messages but no password prompt, the redirection isn't working
4. Try different boot parameter formats (see options above)

## Troubleshooting

### Boot Parameters Not Taking Effect

- Make sure you saved the VM settings
- Restart the VM completely (not just resume)
- Check UTM version - older versions might not support boot parameters
- Try adding parameters in different locations (Advanced, QEMU, System tabs)

### Still No Password Prompt

1. **Verify serial console is enabled** (Serial tab in UTM settings)
2. **Check serial console window is open** and focused
3. **Try typing password blind** in main VM window (see Solution 2 in UTM_ENCRYPTED_DISK.md)
4. **Try switching TTY** with Ctrl+Alt+F1 in main window

### Password Prompt Appears But Can't Type

- Make sure serial console window is **focused** (clicked on)
- Try clicking in the console window before typing
- Some UTM versions require you to enable keyboard input in serial console settings

## Quick Reference

**Boot Parameters to Add:**
```
console=ttyS0,115200 console=tty1
```

**Where to Add:**
- UTM VM Settings → Advanced → Boot Arguments / QEMU Arguments

**Serial Console Settings:**
- UTM VM Settings → Serial → Enable Serial Port

**Test:**
- Start VM → Open Serial Console → Should see boot messages and password prompt

