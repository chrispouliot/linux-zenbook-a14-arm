# Build the ISO and install NixOS

Target: ASUS Zenbook A14 **UX3407NA, Snapdragon X2 Elite / Glymur**.
This extracted installer still needs a physical USB boot test. It is based on
the source project's kernel and device-tree ISO boot approach.

## 1. Prepare firmware and the build machine

Keep a backup of Windows and the extracted firmware before changing partitions.
For a dual boot, shrink Windows from within Windows and leave the EFI system
partition and Windows/recovery partitions intact. Have Secure Boot disabled for
this unsigned custom kernel/installer. Keep any needed Windows recovery key
available when changing firmware boot settings.

Follow [firmware.md](firmware.md). You should have a directory containing all
13 required files. On the Linux build machine, unpack this project and enter its
`nixos-a14` directory. Use Nix with flakes enabled; NixOS builders can set:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Build on an AArch64 Linux machine for native compilation and ordinary ARM64
substitutes. Building on x86_64 Linux uses cross compilation and may take much
longer, with more packages built locally. macOS/Windows are not build hosts
exposed by this flake; use a Linux VM or Linux builder. Do not update the pinned
inputs before the initial baseline test. Allow substantial free disk space for
kernel sources, build tools and the ISO.

## 2. Validate, evaluate, then build

Set this to the actual firmware directory; it must be an absolute path:

```bash
a14_firmware_dir="$HOME/a14-firmware"
python3 scripts/firmware.py validate "$a14_firmware_dir" --strict
```

On an ARM64 Linux builder:

```bash
nix eval .#packages.aarch64-linux.iso.drvPath --raw \
  --override-input windows-firmware "path:$a14_firmware_dir" \
  --no-write-lock-file
nix build .#packages.aarch64-linux.iso \
  --override-input windows-firmware "path:$a14_firmware_dir" \
  --no-write-lock-file -L
```

On an x86_64 Linux builder:

```bash
nix eval .#packages.x86_64-linux.iso.drvPath --raw \
  --override-input windows-firmware "path:$a14_firmware_dir" \
  --no-write-lock-file
nix build .#packages.x86_64-linux.iso \
  --override-input windows-firmware "path:$a14_firmware_dir" \
  --no-write-lock-file -L
```

`nix build .#iso` is shorthand for the matching local architecture output. Both
produce an ARM64 ISO under `result/iso/`. Do not publish an ISO containing factory
Windows firmware without resolving its redistribution terms.

The ISO boot module is pinned and patched to include/load the UX3407NA device
tree. A normal generic ARM64 NixOS ISO is not an interchangeable substitute.

## 3. Write and boot the USB

Use a disk-image writer such as GNOME Disks' **Restore Disk Image** to write the
ISO to a spare USB drive. Select the USB drive carefully: writing the image
replaces its contents. Boot its ARM64 UEFI entry from the laptop's boot device
selection. Boot-menu key availability can vary; use the firmware's USB boot
selection or Windows Advanced Startup's **Use a device** if needed.

Initially test with the lid open and without an external display/dock. At the
installer terminal, verify the model and kernel:

```bash
uname -a
tr '\0' '\n' < /sys/firmware/devicetree/base/compatible
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
```

The compatible list should include `asus,zenbook-a14-ux3407na` and `qcom,glymur`.
If it does not, stop and investigate the ISO/device-tree boot path.
Use `nmtui` to connect to Wi-Fi, or a supported Ethernet adapter. Network access
is expected during installation for flake inputs and packages. The included
firmware and module source do not make this an offline installer.

## 4. Prepare the target partitions

Use `lsblk` and a partition editor such as `cfdisk` to identify the internal
drive and create a Linux root partition in the space you prepared. The commands
below assume ext4 root and an existing FAT EFI system partition.
Do not format Windows, recovery or the existing EFI partition.

Enter the actual partition device paths when prompted. Confirm them against
`lsblk` before the formatting command:

```bash
read -r -p 'Linux root partition to FORMAT (for example /dev/nvme0n1p6): ' a14_root_partition
read -r -p 'Existing EFI system partition to KEEP (for example /dev/nvme0n1p1): ' a14_efi_partition
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$a14_root_partition" "$a14_efi_partition"
```

Only after confirming these are the intended partitions:

```bash
sudo mkfs.ext4 -L nixos "$a14_root_partition"
sudo mount "$a14_root_partition" /mnt
sudo mkdir -p /mnt/boot
sudo mount "$a14_efi_partition" /mnt/boot
sudo nixos-generate-config --root /mnt
```

For a completely blank disk, first create and format an EFI system partition as
FAT32 in addition to Linux root. The preservation instructions above assume a
working Windows EFI partition. Encryption and custom filesystem layouts belong
in your own disk configuration and need their own setup steps.

## 5. Supply the hardware module and firmware to the target

The ISO carries both sources. Copy them locally so installation does not depend
on this repository having been published on GitHub:

```bash
sudo mkdir -p /mnt/etc/nixos/hardware
sudo cp -aL /etc/nixos-a14-source /mnt/etc/nixos/hardware/nixos-a14
sudo chmod -R u+w /mnt/etc/nixos/hardware/nixos-a14
sudo a14-firmware copy /etc/a14-firmware /mnt/etc/nixos/firmware
sudo cp /etc/nixos-a14-source/examples/installed/flake.nix /mnt/etc/nixos/flake.nix
sudo cp /etc/nixos-a14-source/examples/installed/configuration.nix /mnt/etc/nixos/configuration.nix
```

These last two commands install the supplied example on a **new installation**.
If `/mnt/etc/nixos` already contains a personal configuration, merge the hardware
import and firmware option into it instead of replacing it. Keep the freshly
generated `hardware-configuration.nix`; it identifies your actual partitions.

Edit the example:

```bash
sudo nano /mnt/etc/nixos/configuration.nix
```

Change `users.users.owner` to your desired username and adjust the desktop and
hostname if desired. The example selects GNOME and systemd-boot, enables device
tree installation, and leaves EFI-variable writes disabled to match the
firmware limitation seen on the source machine. It does not set passwords.

The example flake uses the local shared module at `./hardware/nixos-a14` and
`./firmware`. This directory is not initially Git-backed, so both are included
without tracking files. If you later initialize Git, follow the private firmware
input instructions before publishing your configuration.

## 6. Install and set passwords

```bash
sudo nixos-install --flake /mnt/etc/nixos#a14
```

Set the root password when the installer prompts. Then set the password for the
normal user you chose (replace `owner` if you renamed it):

```bash
sudo nixos-enter --root /mnt -c 'passwd owner'
```

After installation succeeds, reboot and remove the installer USB. The installed
system will have its own kernel, device tree and firmware closure. It does not
need the USB or Windows partition at runtime, but retain your extracted firmware
backup for rebuilding.

## 7. First-boot checks

Check internal display, keyboard/touchpad, Wi-Fi, Bluetooth, speakers/microphone
and battery information. Then test suspend/resume with the lid open, followed
by HDMI and the intended USB-C dock. Keep an older boot generation available
when testing future hardware updates. A reboot is required to run a new kernel;
`nixos-rebuild switch` alone does not replace the running kernel.

Normal future rebuilds use the same firmware source:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#a14
```

The copied local hardware input will not fetch GitHub updates automatically.
After publication and baseline testing, change its URL to the desired GitHub
repository and update only that input with `nix flake update a14`, then build and
test the new generation. Keep the tested kernel pin until deliberately moving
to a newer kernel release.

## From another flake: ISO API

```nix
packages.aarch64-linux.iso = a14.lib.mkIso {
  firmwareSource = ./firmware;
  extraModules = [ { networking.hostName = "my-a14-installer"; } ];
};
packages.x86_64-linux.iso = a14.lib.mkIso {
  buildSystem = "x86_64-linux";
  firmwareSource = ./firmware;
};
```

For the complete NixOS configuration rather than the ISO derivation, use
`a14.lib.mkInstaller` with the same arguments. Its result exposes
`config.system.build.isoImage`.
