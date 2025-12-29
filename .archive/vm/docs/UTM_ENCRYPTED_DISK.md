# UTM: Encrypted Disk Password Prompt

If your Pop!_OS VM has an encrypted disk (LUKS) and you're not seeing the password prompt in UTM, follow these steps.

## The Problem

- Your disk is encrypted with LUKS
- Pop!_OS shows the password prompt **before the GUI loads** (during boot)
- **When using QEMU directly** (your `start_vm.sh` script), the password prompt appears in the main GUI window
- **In UTM**, the main console might not be visible or configured properly, so the prompt doesn't show
- Without the password, the system can't unlock the disk and falls back to recovery/terminal mode

## Solution Options

The password prompt appears on the **main console (tty1)**, not serial. UTM needs to show this console properly.

### Solution 1: Make Main Console Visible (Try This First)

Since the password prompt appears in the main console (like in QEMU), UTM needs to show it:

1. **Check Display Settings:**
   - Open VM settings → **Display** tab
   - Try different display types: **VirtIO-GPU**, **VirtIO**, or even **VGA**
   - Some display types show console output better than others
   - Save and restart VM

2. **Check Main VM Window:**
   - Start the VM
   - **Look carefully at the main VM window** - the prompt might be there but hard to see
   - Try clicking in the window to focus it
   - The prompt appears early in boot (10-20 seconds after start)

3. **Try Typing Password "Blind":**
   - Wait 10-20 seconds after VM starts
   - **Click in the main VM window** (even if it looks black)
   - **Type your password** (you won't see characters - this is normal)
   - **Press Enter**
   - Wait for disk unlock

### Solution 2: Enable Serial Console + Redirect Console

If the main console isn't visible, redirect it to serial:

1. **Enable Serial Port:**
   - Open VM settings → **Serial** tab
   - **Enable Serial Port** or **Add Serial Port**
   - Configure it to show in a **separate window**
   - Save

2. **Add Boot Parameters to Redirect Console:**
   - Go to **Advanced** tab
   - Find **Boot Arguments** or **QEMU Arguments**
   - Add: `console=ttyS0,115200 console=tty1`
   - Save

3. **Start VM and Use Serial Console:**
   - Start the VM
   - Open the serial console window in UTM
   - Password prompt should appear there
   - Type password and press Enter

## Alternative: UTM Console View

If Serial Port doesn't work, try UTM's built-in console:

1. In UTM, look at the VM window
2. Check for a **console** icon or button in the toolbar
3. Some UTM versions have a **View** menu with **Console** option
4. Enable it to see the boot console

## Troubleshooting

### Password Prompt Not Showing in Serial Console

**This is the most common issue!** The LUKS password prompt goes to tty1 (main console) by default, not the serial console. Here are solutions:

#### Solution 1: Add Kernel Boot Parameters (RECOMMENDED)

You need to redirect the console to serial using kernel boot parameters:

1. **Open VM Settings** in UTM
2. Go to **Advanced** tab (or look for **Boot** or **QEMU** settings)
3. Find **Boot Arguments** or **QEMU Arguments** field
4. Add these kernel parameters:
   ```
   console=ttyS0,115200 console=tty1
   ```
   This tells the kernel to send output to both serial (ttyS0) and main console (tty1)

5. **Alternative boot parameters** (if above doesn't work):
   ```
   console=ttyS0,115200n8
   ```
   Or:
   ```
   console=serial0,115200 console=tty1
   ```

6. Save settings and restart VM
7. The password prompt should now appear in the serial console

#### Solution 2: Try Typing Password "Blind" in Main Window

Sometimes the prompt is there but not visible:

1. **Start the VM**
2. **Wait 10-20 seconds** for boot to reach the password prompt
3. **Click in the main VM window** (even if it looks black)
4. **Type your password** (blind - you won't see it)
5. **Press Enter**
6. Wait for disk unlock

#### Solution 3: Switch to Console TTY in Main Window

1. **Start the VM**
2. **Press Ctrl+Alt+F1** (or F2, F3) in the main VM window
3. This switches to console TTY where the password prompt might be visible
4. Type password and press Enter

#### Solution 4: Modify GRUB Boot Configuration

If you can boot into recovery mode, you can modify GRUB:

1. Boot VM and hold **Shift** during boot to access GRUB menu
2. Select recovery mode or edit boot entry
3. Add `console=ttyS0,115200` to kernel line
4. Boot and password prompt should appear in serial console

### Console Still Not Showing

1. **Check UTM Version:**
   - Make sure you're using a recent version of UTM
   - Older versions might not have good console support

2. **Try Different Display Settings:**
   - In VM settings → **Display** tab
   - Try different display types (VirtIO-GPU, VirtIO, etc.)
   - Sometimes the console appears in the main window with certain display settings

3. **Check Boot Messages:**
   - The password prompt might appear briefly
   - Try pausing the VM right after it starts
   - Look carefully at the boot messages

### Password Not Working

- Make sure you're typing the correct password
- Check for Caps Lock
- The password is the one you set during Pop!_OS installation
- If you forgot it, you'll need to use the recovery options

### After Entering Password

- Wait for disk unlock (10-30 seconds)
- GUI should appear
- You may need to log in to Pop!_OS
- If GUI still doesn't appear, check the other troubleshooting steps in `UTM_FIX_GUI.md`

## Why This Happens

In QEMU (which your `start_vm.sh` script uses):
- The password prompt appears in the **main console (tty1)**
- QEMU's `-display cocoa` shows this console output in the main window automatically
- The prompt is visible because QEMU displays all console output

In UTM:
- UTM wraps QEMU but may not show console output in the main window properly
- Display settings might hide or not render the console properly
- The prompt is there, but you can't see it due to display configuration

## Quick Checklist

- [ ] Serial Port enabled in UTM VM settings
- [ ] Console window/tab is visible
- [ ] VM is started
- [ ] Console is focused (clicked on)
- [ ] Password entered (no characters shown is normal)
- [ ] Waited for disk unlock
- [ ] GUI appeared

If you've done all these and still have issues, the problem might be with display settings - see `UTM_FIX_GUI.md` for more troubleshooting.

