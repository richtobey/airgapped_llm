# UTM: Fix Console Output with SPICE Display

UTM uses SPICE display protocol which doesn't show console output (boot messages, password prompts) the same way QEMU's `-display cocoa` does.

## The Problem

**Your original QEMU script:**

```bash
-display cocoa -device virtio-vga
```

- Shows all console output in the main window
- Password prompt is visible ✅

**UTM's generated command:**

```bash
-spice ... -vga none -device virtio-gpu-gl-pci
```

- Uses SPICE protocol (remote desktop)
- `-vga none` means no VGA console output
- Password prompt is hidden ❌

## Solution: Add VGA Console Device

You need to add a VGA device that shows console output alongside the SPICE display.

### Method 1: Add Serial Console (Easiest)

1. **Open VM Settings** → **Serial** tab
2. **Enable Serial Port** or **Add Serial Port**
3. Configure to show in **separate window**
4. Save

This creates a serial console where boot messages and password prompt will appear.

### Method 2: Modify UTM QEMU Arguments (Advanced)

If UTM allows custom QEMU arguments:

1. **Open VM Settings** → **Advanced** tab
2. Look for **QEMU Arguments** or **Additional Arguments**
3. Add these arguments:

   ```bash
   -device VGA,vgamem_mb=16
   ```

   Or:

   ```bash
   -device virtio-vga,edid=on
   ```

4. Save and restart

**Note:** UTM might not allow this, or it might conflict with SPICE. Method 1 (serial console) is more reliable.

### Method 3: Use Both SPICE and VGA

If you can modify the QEMU command, you can have both:

1. Keep SPICE for the GUI (after boot)
2. Add VGA device for console output (during boot)

But this requires access to QEMU command line, which UTM doesn't easily expose.

## Recommended Solution: Serial Console + Boot Parameters

Since UTM uses SPICE, the best approach is:

### Step 1: Enable Serial Console

1. VM Settings → **Serial** tab
2. **Enable Serial Port**
3. Set to show in **separate window**
4. Save

### Step 2: Redirect Console to Serial

1. VM Settings → **Advanced** tab
2. Find **Boot Arguments** or **QEMU Arguments**
3. Add: `console=ttyS0,115200 console=tty1`
4. Save

### Step 3: Use Serial Console for Password

**IMPORTANT:** The password prompt appears **DURING BOOT**, not after the system boots!

1. **Start VM** (from powered off state)
2. **Immediately open serial console window**
3. **Watch the boot messages** - the password prompt appears **early in boot** (10-20 seconds after start)
4. **Look for messages like:**
   - `Please unlock disk [device name]:`
   - `Enter passphrase for [device]:`
   - Or similar LUKS unlock prompts
5. **Type password** when you see the prompt (characters won't show)
6. **Press Enter**
7. Wait for disk unlock, then GUI should appear

**Note:** If you're seeing a terminal/recovery mode, you've missed the password prompt. The prompt appears BEFORE the system boots into any mode.

## Why SPICE Doesn't Show Console

SPICE (Simple Protocol for Independent Computing Environments) is designed for:

- Remote desktop access
- Graphics/display forwarding
- **Not** for showing boot console output

The original QEMU script uses `-display cocoa` which:

- Shows all console output directly
- Displays boot messages and prompts
- Works like a native terminal

## Alternative: Change UTM Display Type

Some UTM display types might show console better:

1. **Try VGA display:**
   - VM Settings → **Display** tab
   - Change from **VirtIO-GPU** to **VGA**
   - VGA might show console output better
   - Save and test

2. **Try different VirtIO variants:**
   - **VirtIO** (not VirtIO-GPU)
   - **VirtIO 2D**
   - These might have better console support

## Quick Fix: Type Password Blind (During Boot)

Since the prompt is there but not visible, and it appears **during boot** (not after):

1. **Start VM from powered off state**
2. **Wait 10-20 seconds** (for boot to reach password prompt)
3. **Click in main VM window** (even if it looks black/blank)
4. **Type password** (blind - you won't see it)
5. **Press Enter**
6. **Wait 10-30 seconds** for disk unlock
7. GUI should then appear

**Timing is critical:** The prompt appears during early boot. If you wait too long, the system will boot into recovery/terminal mode instead, and you'll have missed the prompt.

**Try this sequence:**
- Start VM
- Count to 15 (seconds)
- Click in window, type password, Enter
- Wait for unlock

## Summary

**The Issue:**

- UTM uses SPICE (`-vga none`) which doesn't show console
- Your script uses `-display cocoa` which shows console
- Password prompt exists but isn't visible

**The Solution:**

1. **Enable Serial Console** (easiest)
2. **Add boot parameters** to redirect console to serial
3. **Use serial console** to enter password

Or use the "blind typing" method as a workaround.
