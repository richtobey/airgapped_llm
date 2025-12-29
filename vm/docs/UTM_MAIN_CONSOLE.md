# UTM: Show Password Prompt in Main Console

If your password prompt appears in the GUI when using QEMU's `start_vm.sh` script, but not in UTM, the issue is that UTM isn't showing the main console properly.

## The Situation

- **QEMU (`start_vm.sh`)**: Password prompt appears in main GUI window ✅
- **UTM**: Password prompt doesn't appear (but it's there, just not visible) ❌

The password prompt goes to the **main console (tty1)**, which QEMU shows automatically but UTM might not.

## Solution 1: Fix Display Settings (Try This First)

The main console should be visible in the main VM window. Try these display settings:

### Step 1: Try Different Display Types

1. **Open VM Settings** → **Display** tab
2. **Try these display types in order:**
   - **VirtIO-GPU** (recommended for Pop!_OS)
   - **VirtIO** or **VirtIO 2D**
   - **VGA** (fallback - shows console better)
   - **QXL** (another option)

3. **Save** and restart VM
4. **Look at the main VM window** - the password prompt should appear there

### Step 2: Check Resolution and Settings

1. In **Display** settings:
   - Set resolution to **1280x720** or higher
   - Enable **Full Screen** option if available (sometimes helps)
   - Disable any "Hide Console" or "Graphics Only" options

2. Save and test

### Step 3: Try Typing Password "Blind"

If the prompt is there but not visible:

1. **Start the VM**
2. **Wait 10-20 seconds** for boot to reach password prompt
3. **Click in the main VM window** (to focus it)
4. **Type your password** (you won't see it - this is normal)
5. **Press Enter**
6. **Wait 10-30 seconds** for disk unlock
7. GUI should appear

## Solution 2: Use Serial Console (If Main Console Doesn't Work)

If you can't get the main console to show the prompt, redirect it to serial:

### Step 1: Enable Serial Console

1. VM Settings → **Serial** tab
2. **Enable Serial Port** or **Add Serial Port**
3. Set to show in **separate window**
4. Save

### Step 2: Redirect Console to Serial

1. VM Settings → **Advanced** tab
2. Find **Boot Arguments** or **QEMU Arguments**
3. Add: `console=ttyS0,115200 console=tty1`
4. Save

### Step 3: Use Serial Console

1. Start VM
2. Open serial console window
3. Password prompt should appear there
4. Type password and press Enter

## Solution 3: Modify GRUB to Show Prompt Better

If the prompt is there but hard to see, you can modify GRUB:

1. **Boot into recovery mode:**
   - Start VM, hold **Shift** during boot
   - Select **Advanced options** → **Recovery mode**

2. **Edit GRUB:**
   ```bash
   sudo nano /etc/default/grub
   ```

3. **Remove "quiet" and "splash"** from `GRUB_CMDLINE_LINUX_DEFAULT`:
   ```
   GRUB_CMDLINE_LINUX_DEFAULT=""
   ```
   Or keep it minimal:
   ```
   GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200"
   ```

4. **Update GRUB:**
   ```bash
   sudo update-grub
   ```

5. **Reboot** - the prompt should be more visible

## Why QEMU Works But UTM Doesn't

**QEMU (`start_vm.sh`):**
- Uses `-display cocoa -device virtio-vga` which shows all console output
- Console output (including password prompt) appears in main window automatically
- No special configuration needed

**UTM:**
- Uses **SPICE display protocol** (`-spice ... -vga none -device virtio-gpu-gl-pci`)
- SPICE is designed for remote desktop/graphics, **not console output**
- The `-vga none` means no VGA console is shown
- Password prompt exists but SPICE doesn't display it
- **Solution**: Use serial console or type password "blind"

See `UTM_SPICE_CONSOLE_FIX.md` for detailed explanation of the SPICE issue.

## Quick Checklist

- [ ] Tried different display types (VirtIO-GPU, VGA, etc.)
- [ ] Checked main VM window carefully (prompt might be there)
- [ ] Tried typing password "blind" in main window
- [ ] Enabled serial console as backup
- [ ] Added boot parameters to redirect console
- [ ] Modified GRUB to remove quiet/splash

## Recommended Approach

1. **First**: Try Solution 1 (fix display settings) - this matches how QEMU works
2. **If that doesn't work**: Try typing password "blind" - it's likely there
3. **Last resort**: Use Solution 2 (serial console) - works but less convenient

The goal is to make UTM show the console like QEMU does automatically.
