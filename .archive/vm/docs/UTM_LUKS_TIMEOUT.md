# UTM: Fix LUKS Password Prompt Timeout (Flashing Too Fast)

If the password prompt flashes for less than 1 second and disappears, the LUKS timeout is too short. We need to increase it.

## The Problem

- Password prompt appears but disappears in < 1 second
- System times out and boots into recovery mode
- Not enough time to type password

## Solution: Increase LUKS Timeout

You need to configure cryptsetup to wait longer for the password.

### Method 1: Modify Cryptsetup Configuration (Recommended)

Boot into recovery mode and modify the cryptsetup configuration:

1. **Boot into recovery mode** (you're probably already there)
2. **Edit cryptsetup initramfs configuration:**
   ```bash
   sudo nano /etc/initramfs-tools/conf.d/cryptroot
   ```
3. **Add or modify these lines:**
   ```
   CRYPTSETUP_OPTIONS="--tty=/dev/ttyS0"
   CRYPTSETUP_TIMEOUT=60
   ```
   - `--tty=/dev/ttyS0` - Use serial console
   - `TIMEOUT=60` - Wait 60 seconds (adjust as needed)

4. **Also check/edit:**
   ```bash
   sudo nano /etc/crypttab
   ```
   - Make sure your encrypted device is listed
   - Add `noauto` option if you want more control

5. **Update initramfs:**
   ```bash
   sudo update-initramfs -u
   ```

6. **Reboot** - password prompt should wait longer

### Method 2: Modify GRUB Kernel Parameters

Add timeout parameter to kernel boot line:

1. **Boot into recovery mode**
2. **Edit GRUB:**
   ```bash
   sudo nano /etc/default/grub
   ```
3. **Find `GRUB_CMDLINE_LINUX_DEFAULT`** and add:
   ```
   cryptdevice.timeout=60
   ```
   Example:
   ```
   GRUB_CMDLINE_LINUX_DEFAULT="quiet splash cryptdevice.timeout=60 console=ttyS0,115200"
   ```

4. **Update GRUB:**
   ```bash
   sudo update-grub
   ```

5. **Reboot** - prompt should wait 60 seconds

### Method 3: Edit GRUB at Boot Time (Temporary)

If you can't boot into recovery mode properly:

1. **Start VM**
2. **Hold Shift** during boot to access GRUB menu
3. **Press E** to edit boot entry
4. **Find the line starting with `linux`** (kernel line)
5. **Add to the end:**
   ```
   cryptdevice.timeout=60
   ```
6. **Press Ctrl+X** to boot with these parameters
7. **Password prompt should wait 60 seconds**

**Note:** This is temporary - you'll need to do this every boot unless you modify GRUB permanently (Method 2).

### Method 4: Use Systemd-boot (If Pop!_OS Uses It)

If Pop!_OS uses systemd-boot instead of GRUB:

1. **Boot into recovery mode**
2. **Edit systemd-boot config:**
   ```bash
   sudo nano /boot/efi/loader/entries/pop_os.conf
   ```
   (Path might vary - check `/boot/efi/loader/entries/`)

3. **Add to `options` line:**
   ```
   cryptdevice.timeout=60
   ```

4. **Reboot**

## Quick Fix: Type Password Immediately

Since the prompt flashes so fast, try this:

1. **Start VM from powered off**
2. **Have your password ready** (type it out in a text editor first to copy)
3. **As soon as VM starts, immediately:**
   - Click in serial console (or main window)
   - Start typing password (don't wait to see prompt)
   - Type fast!
   - Press Enter
4. **Repeat if it times out** - try again with faster typing

## Recommended Configuration

For UTM with serial console, use this combination:

1. **Enable serial console** in UTM
2. **Add boot parameters:**
   ```
   console=ttyS0,115200 console=tty1 cryptdevice.timeout=60
   ```
3. **Modify cryptsetup** (Method 1 above) to use serial and longer timeout
4. **Update initramfs**

This gives you:
- Password prompt in serial console (visible)
- 60 second timeout (plenty of time)
- Reliable unlocking

## Troubleshooting

### Still Timing Out Too Fast

- Increase timeout value: `cryptdevice.timeout=120` (2 minutes)
- Check if `update-initramfs` completed successfully
- Verify cryptsetup config file was saved correctly

### Can't Boot Into Recovery Mode

- Try holding Shift during boot
- Or use GRUB edit method (Method 3) at boot time
- Or boot from Pop!_OS ISO and chroot into installed system

### Password Prompt Still Not Visible

- Make sure serial console is enabled in UTM
- Check boot parameters include `console=ttyS0,115200`
- Try typing password "blind" in serial console even if you don't see prompt

## Summary

**The Issue:**
- LUKS timeout is too short (< 1 second)
- Prompt flashes and disappears
- Not enough time to enter password

**The Fix:**
1. **Increase timeout** using `cryptdevice.timeout=60` in GRUB
2. **Configure cryptsetup** to use serial console
3. **Update initramfs** to apply changes
4. **Reboot** - prompt should wait 60 seconds

This should give you plenty of time to see and enter the password!

