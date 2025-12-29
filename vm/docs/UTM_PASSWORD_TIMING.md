# UTM: Password Prompt Timing - When It Appears

If you're seeing a terminal/recovery mode but no password prompt, you've likely **missed the prompt**. It appears **during boot**, not after.

## When the Password Prompt Appears

The LUKS password prompt appears **very early in the boot process**:

```
1. VM starts
2. BIOS/UEFI boot (2-3 seconds)
3. GRUB bootloader (1-2 seconds)
4. Kernel starts loading (2-3 seconds)
5. ⚠️ PASSWORD PROMPT APPEARS HERE (10-20 seconds after VM start)
6. Disk unlocks (10-30 seconds)
7. System continues booting
8. GUI appears
```

**If you miss step 5, the system boots into recovery/terminal mode instead.**

## The Problem: Seeing Terminal Twice

If you're seeing "the same terminal 2 times" (main window + serial console), this means:

- ✅ Serial console is working
- ✅ System has booted
- ❌ **You missed the password prompt** (it appeared earlier, during boot)

The password prompt appears **BEFORE** the terminal you're seeing.

## Solution: Watch Boot Messages Carefully

### Method 1: Watch Serial Console from Start

1. **Open serial console window FIRST** (before starting VM)
2. **Start VM from powered off state**
3. **Watch serial console immediately** - don't wait
4. **Look for boot messages:**
   ```
   Loading Linux...
   Loading initial ramdisk...
   [Then password prompt appears]
   Please unlock disk /dev/sda2:
   ```
5. **Type password IMMEDIATELY** when you see the prompt (it may flash quickly!)
6. **Press Enter**

**If prompt flashes too fast (< 1 second):** See `UTM_LUKS_TIMEOUT.md` to increase the timeout.

### Method 2: Type Password Blind (Timed) - FAST!

If the prompt flashes too fast (< 1 second), you need to type immediately:

1. **Start VM from powered off**
2. **Have password ready** (type it in a text editor first to practice)
3. **Count to 12** (seconds) - start typing BEFORE prompt appears
4. **Click in main VM window** (or serial console)
5. **Type password FAST** (blind - you won't see it)
6. **Press Enter immediately**
7. **Wait 20-30 seconds**
8. GUI should appear

**Timing is critical:**
- Start typing at 12 seconds (before prompt appears)
- Finish typing by 15 seconds (when prompt is waiting)
- If prompt flashes in < 1 second, you need to type even faster or increase timeout (see `UTM_LUKS_TIMEOUT.md`)

**If this doesn't work:** The timeout is too short. You MUST increase it using the methods in `UTM_LUKS_TIMEOUT.md`.

### Method 3: Configure Cryptsetup to Use Serial

You can configure the system to always use serial console for LUKS:

1. **Boot into recovery mode** (if you're already there)
2. **Edit cryptsetup configuration:**
   ```bash
   sudo nano /etc/crypttab
   ```
3. **Add serial console option** (if not already there)
4. **Edit initramfs hooks:**
   ```bash
   sudo nano /etc/initramfs-tools/conf.d/cryptroot
   ```
5. **Add:**
   ```
   CRYPTSETUP_OPTIONS="--tty=/dev/ttyS0"
   ```
6. **Update initramfs:**
   ```bash
   sudo update-initramfs -u
   ```
7. **Reboot** - password prompt should appear in serial console

## How to Tell If You Missed It

**Signs you missed the password prompt:**
- System boots into recovery/terminal mode
- You see login prompts or recovery menus
- System is asking for recovery options
- No GUI appears

**Signs the prompt is waiting:**
- VM window is black/blank
- Boot messages stopped
- Nothing is happening
- System is waiting for input

## Troubleshooting

### Serial Console Shows Same Terminal

If serial console shows the same terminal as main window:

1. **This means you're past the password prompt**
2. **The system already booted** (probably into recovery mode)
3. **You need to:**
   - Power off VM completely
   - Start fresh
   - Watch boot messages from the very beginning
   - Look for password prompt in first 20 seconds

### Can't See Prompt in Serial Console

1. **Check boot parameters:**
   - Advanced tab → Boot Arguments
   - Should have: `console=ttyS0,115200 console=tty1`
   
2. **Try typing password blind** (Method 2 above)

3. **Check if prompt is in main window:**
   - Try typing password in main window instead
   - The prompt might be there but not visible

### System Keeps Booting to Recovery

If system always boots to recovery mode:

1. **You're consistently missing the password prompt**
2. **Try Method 2** (blind typing with timing)
3. **Or configure cryptsetup** (Method 3) to use serial

## Best Practice

**Recommended approach:**

1. **Enable serial console** (Settings → Serial)
2. **Add boot parameters** (`console=ttyS0,115200`)
3. **Open serial console window** BEFORE starting VM
4. **Start VM from powered off**
5. **Watch serial console from the very first second**
6. **Look for password prompt in first 20 seconds**
7. **Type password immediately when you see it**

The key is **watching from the start** - don't wait until you see a terminal, because by then it's too late!

