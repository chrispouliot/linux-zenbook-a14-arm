# Linux on the ASUS Zenbook A14 X2E

Linux/NixOS hardware support for the **ASUS Zenbook A14 UX3407NA with Snapdragon X2 Elite**. This project includes a patched kernel, device tree, firmware integration, webcam support, internal speaker support, USB / suspend workarounds, and 4k144hz Displayport with DSC patches among many others.

The project builds an ARM64 NixOS installer ISO, which can be used to install either NixOS or Arch on your A14. It currently uses the pinned **7.2.0-rc5-next-20260731** Glymur kernel. Support is still evolving; see the [hardware notes](docs/hardware.md) and status below for current limitations. Earlier Snapdragon X1 A14 models are outside this project's scope.

This project is not responsible for the initial device tree mainlining or A14 support. This project builds on the existing work of others and exists mainly a guide with my own small personal patches to help others get Linux on their A14. Huge thank you to the Linux-MSM and Glymur kernel for the work to get the A14 up and running with Linux.

<details>
<summary><strong>Current hardware status</strong></summary>


Status reflects the currently used **NixOS configuration on the UX3407NA with the project's patched Glymur kernel and required firmware**. It does not mean the new installer ISO or every peripheral has been validated. Arch users also need the equivalent userspace configuration, particularly for audio.

Overall I use this as my daily driver and it works very well. Please note the USB 4 limitations.


| Feature | Status | Patches, workarounds or remaining limitations |
| --- | --- | --- |
| Internal display | Working with workarounds | The eDP link stays capped at HBR / 2.7 Gbit/s per lane; native 1920×1200 at 60 Hz uses 24 bpp after powered capability setup. Boot and suspend/wake have been tested. |
| Keyboard and Fn keys | Working with patches | Keyboard Fn-lock support enables the intended media-key and F1–F12 behavior. |
| Touchpad | Working | Uses the board device tree and early I2C/HID drivers. |
| Battery information and charging | Working | Uses the ASUS embedded-controller overlay and Qualcomm power-supply support. |
| Wi-Fi | Working with firmware | Requires QCC2072 runtime firmware and the ASUS-specific Windows board file. DFS-channel connectivity has shown problems; use a non-DFS channel if affected. |
| Bluetooth | Working with firmware and device-tree fix | Requires the matching Windows Bluetooth files and QCC2072 device description. |
| Internal speakers | Working with patches and configuration | Corrected codec mapping, stereo routing, AudioReach topology and ALSA/PipeWire configuration are included. SoundWire power management also has a workaround. |
| HDMI video | Working on tested setup | Uses the retained display/PHY fixes. Supported modes depend on the output path and its link limits. |
| HDMI audio | Working with patches and configuration | Requires the HDMI audio backend, topology, routing and hotplug helper. |
| USB peripherals | Working on tested connections | USB clock, power-domain and PHY fixes are included. Selected VIA hubs also use power-management workarounds. This does not establish USB4 support. |
| Dock Ethernet across suspend/resume | Working with patches on tested dock | Shared USB/DP PHY changes preserve the USB connection in the tested suspend/resume setup. Other docks still need testing. |
| USB-C DisplayPort / external-display hotplug | Working on tested setup; experimental | Port one through the tested Amazon Basics TB4/USB4 dock supports 4K144 with DSC and transparent LTTPR. Boot, standby, suspend and replug have passed on that setup. The second external controller retains an HBR2 cap; other docks and cable orientations still need testing. See [display status](docs/display/README.md). |
| Suspend/resume | Working with workarounds; setup-dependent | Uses s2idle, the internal-display link cap, USB-C power-domain retention and display/PHY fixes. External displays, docks and audio need testing in each setup. |
| CPU performance | Partial | CPU governors are available, but single-core performance remains below Windows in testing. The optional SCMI mailbox patch is diagnostic, not a proven fix. |
| Webcam | Working with patches | Backported Glymur camera drivers, a board description confirmed against the A14 firmware tables, and libcamera's software ISP through PipeWire. Tested in GNOME Snapshot; the privacy LED lights while streaming. Enabled by default, `camera.enable` turns it off. See [camera notes](docs/hardware.md#camera). |
| Internal microphone | Working | Uses the microphone paths in the AudioReach topology and the always-on Speaker + Mic UCM tree. Verified with a PipeWire recording and playback. |
| Hardware video decode | Working with patches | Ported upstream Glymur Iris video codec series with the OEM `qcvss8480.mbn` firmware; verified with ffmpeg's V4L2 decoder at about 480 fps for 1080p H.264. Enabled by default, `video.enable` turns it off. GStreamer and ffmpeg based players use it; desktop browsers do not. See [video notes](docs/hardware.md#video-decode). |
| USB4 | Not working | Native USB4 operation is not working. USB peripherals or display output working through a USB4-capable dock does not mean its USB4 features are operating. |

See [Included patches](#included-patches) for individual changes and [hardware notes](docs/hardware.md) for options and limitations. “Working” describes the tested setup, not a guarantee that all hardware combinations are issue-free.

</details>

## Before you start

You can create the ISO on **another Linux computer**, or **on the A14 itself while it is running Windows by using WSL2**. Both routes use Nix with flakes enabled; the guides include the setup steps. If the A14 is your only computer, start with the Windows installation steps. You will need the **Windows firmware files from your UX3407NA**. Follow the [firmware guide](docs/firmware.md), which includes collectors for Windows and Linux.

Firmware is required by both the installer and the installed system. Keep a backup of the extracted directory; it is not included in this public repository.

**Before changing Secure Boot or booting the USB**, complete the Windows and boot preparation below. It applies to all three installation routes.

<a id="windows-and-boot-preparation"></a>

<details>
<summary><strong>Before booting the installer: Windows encryption, PIN, BIOS and boot menu</strong></summary>

Windows Bitlocker won't function properly if you disable Secure Boot (required to boot Linux).
Read this before changing Secure Boot in your BIOS, whether you built the ISO on another computer or through WSL on the A14. If using WSL, finish building and writing the USB first; perform the encryption and firmware steps immediately before testing the USB.

**BitLocker recovery and your Windows sign-in PIN are different things.** Suspending BitLocker protection helps avoid recovery prompts caused by boot or firmware changes. It does not guarantee that Windows Hello will keep accepting your PIN. Fully decrypting the drive does not guarantee that either.

**1. Back up your files, firmware and Windows recovery information**

Keep copies of your important files and extracted A14 firmware somewhere separate from the Windows SSD and the USB drive you are about to overwrite.

If Windows encryption is enabled, retrieve its **48-digit BitLocker recovery key** and keep it accessible from another device or on paper. Match it to this device's key ID; do not rely on a copy stored only on the encrypted laptop. See [Microsoft's recovery-key instructions](https://support.microsoft.com/en-us/windows/security/encryption/find-your-bitlocker-recovery-key).

**2. Make sure you can sign into Windows without relying only on the PIN**

Know your Windows account password and confirm access to your Microsoft account's recovery email, phone or authenticator before changing firmware settings.

If your account has a password but Windows hides password sign-in, open **Settings → Accounts → Sign-in options** and turn off the Windows Hello-only sign-in setting if available. Lock the screen and test the password through **Sign-in options** before proceeding. For a passwordless account, confirm your account-recovery method instead. [Microsoft's sign-in options](https://support.microsoft.com/en-us/accounts-billing/security/sign-in-options-in-windows).

If Windows later reports that the PIN is unavailable, use password sign-in where offered, or the **I forgot my PIN / Set up my PIN** flow to verify your account and create a new PIN. This may require an internet connection. Do not treat decrypting the SSD as a fix for a Windows Hello problem. [Microsoft's PIN reset instructions](https://support.microsoft.com/en-us/windows/security/change-or-reset-your-pin-in-windows).

**3. Check encryption and choose suspension or decryption**

In **Windows PowerShell as Administrator**, check the Windows system drive:

```powershell
manage-bde -status C:
```

Check both **Conversion Status** and **Protection Status**. A suspended drive can still be encrypted: **Protection Off** alone does not mean decryption has finished. [Microsoft's status command](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/manage-bde-status).

| Your situation | What to do |
| --- | --- |
| The drive is already fully decrypted | No BitLocker suspension is needed. Keep the account-recovery preparation above. |
| You want to keep Windows encrypted while changing firmware settings | Temporarily suspend protection using option A below. |
| You deliberately want Windows encryption removed | Use option B and wait for decryption to finish. This is optional, not a requirement for building the ISO. |

**Option A — temporarily suspend protection**

On Windows editions providing the BitLocker PowerShell commands, run:

```powershell
Suspend-BitLocker -MountPoint "C:" -RebootCount 0
manage-bde -status C:
```

Confirm that protection is off before changing Secure Boot. `-RebootCount 0` keeps protection suspended until you manually resume it; the data remains encrypted, but its key is temporarily unprotected. Do not leave a retained Windows installation in this state indefinitely. [Microsoft's suspension instructions](https://learn.microsoft.com/en-us/troubleshoot/windows-client/windows-security/suspend-bitlocker-protection-non-microsoft-updates).

If that command is unavailable, check **Manage BitLocker → Suspend protection**. UI suspension may resume after a restart, so recheck its status before further changes. Some Windows Home devices expose only Device encryption; if suspension is unavailable, use the supported decryption option below or obtain instructions for that edition before changing Secure Boot.

**Option B — turn off encryption and decrypt the drive**

Choose the interface available on your Windows installation:

* **Device encryption:** open **Settings → Privacy & security → Device encryption**, turn it off, and confirm.
* **BitLocker Drive Encryption:** search for **Manage BitLocker**, choose **Turn off BitLocker** for the Windows drive, and confirm decryption.

Keep the laptop connected to power and wait for completion before changing Secure Boot. Check again with `manage-bde -status C:`; expect **Fully Decrypted** and **0.0% encrypted** (wording may be localized). Turning encryption off removes its protection of the Windows data at rest. [ASUS's decryption instructions](https://www.asus.com/support/faq/1047461/).

**4. Open BIOS/UEFI settings or the boot-device menu**

These are separate screens: BIOS/UEFI settings contain Secure Boot controls; the boot-device menu chooses the USB or an installed operating system.

| Goal | Keyboard method |
| --- | --- |
| Open BIOS/UEFI settings | With the laptop fully shut down, hold **F2**, press the power button, and keep holding F2 until the settings screen appears. |
| Select a boot device | With the installer USB connected and the laptop fully shut down, hold **Esc**, press the power button, and keep holding Esc until the boot menu appears. Select the USB's UEFI entry. |

Both startup shortcuts have been confirmed on this A14: **F2 opens BIOS/UEFI settings**, and **holding Esc at power-on opens the boot-device menu**. See [ASUS BIOS access](https://www.asus.com/us/support/faq/1008829/) and [ASUS USB boot selection](https://www.asus.com/support/faq/1013017/).

If you miss the key during a reboot, let Windows start, then shut down fully and use the hold-before-power-on method. Do not assume F7, F8 or F12 opens a menu: the expected menus were not available in the initial A14 testing.

**Windows restart method, without timing a keypress:**

Open **Settings → System → Recovery → Advanced startup → Restart now**. After Windows restarts:

* For BIOS/UEFI, choose **Troubleshoot → Advanced options → UEFI Firmware Settings → Restart**.
* For the installer, choose **Use a device** and select the USB's UEFI entry if listed.

If the USB is absent, connect it directly to the laptop, check that the image was written successfully, and retry. BIOS boot-priority or Boot Override controls can be used if present, but their availability varies; do not assume this A14 has the menus shown in ASUS's generic screenshots.

**5. Disable Secure Boot without clearing security keys**

After completing the Windows preparation, enter BIOS/UEFI and locate **Secure Boot**, often under **Security** or **Boot**. Set its enable/control setting to **Disabled**, then use the displayed **Save Changes and Exit** action. Labels and navigation depend on the firmware version. [ASUS Secure Boot guidance](https://www.asus.com/support/faq/1050047/).

**Leave the TPM enabled. Do not clear the TPM, delete Secure Boot keys, or reset all BIOS settings.** Those actions are not required to boot this installer and can create additional Windows sign-in or recovery problems.

For this project's unsigned installer and installed kernel, leave Secure Boot disabled unless you separately configure a supported signing setup.

**6. If keeping Windows, verify it and resume protection**

After the firmware change, boot Windows once and confirm you can sign in. If you suspended BitLocker, resume protection when the firmware/boot changes are complete:

```powershell
Resume-BitLocker -MountPoint "C:"
manage-bde -status C:
```

Check that protection is on and verify Windows starts with the boot settings you intend to keep. If recovery prompts recur, use the saved key and investigate the boot configuration; do not leave protection suspended as a permanent workaround. If you make more boot changes, suspend again beforehand. [Microsoft's resume instructions](https://learn.microsoft.com/en-us/troubleshoot/windows-client/windows-security/suspend-bitlocker-protection-non-microsoft-updates).

If you fully decrypted instead, this resume command does not re-encrypt the drive. Re-enabling encryption later is a separate Windows setup step.

**7. Boot the USB and return to your installation guide**

Use Esc at power-on or Windows Advanced Startup as described above. Select the USB's UEFI entry, keep the lid open, and initially disconnect external displays and docks.

Check the live system's keyboard, display, SSD and networking before changing any partitions. Booting the USB does not itself erase Windows; the later partitioning and formatting commands do.

Then continue with **step 5** of [Installing NixOS ARM](#installing-nixos-arm) or [Installing Arch Linux ARM](#installing-arch-linux-arm). Do not repeat firmware changes already completed here.

</details>

## Installation

<a id="installing-nixos-arm"></a>

<details>
<summary><strong>Installing NixOS ARM</strong></summary>

**Starting from Windows on the A14?** Complete [the WSL2 preparation guide](#installing-from-windows-wsl2) first, then return here at step 5.

This walkthrough installs NixOS on an A14 that does not already have Linux installed.

You will first build a custom installer on another Linux computer, boot it from USB, and install NixOS onto the A14’s SSD. The installed system includes the project’s patched kernel, device tree, firmware integration, and hardware configuration.

**You will need:**

* An ASUS Zenbook A14 **UX3407NA / Snapdragon X2 Elite**.
* Another Linux computer, either Intel/AMD x86-64 or ARM64.
* A spare USB drive large enough for the generated ISO.
* The required Windows firmware files from your A14.
* An internet connection during installation.

This example uses a fresh installation with an unencrypted ext4 filesystem and the GNOME desktop. For dual boot, encryption, or other disk layouts, adapt the partitioning steps before continuing.

**Installer status:** the ISO configuration has been evaluated, but the complete ISO build and physical USB boot still need validation. See [validation status](docs/validation.md).

---

**1. Prepare the build computer**

If your other computer already has Nix with flakes enabled, skip to step 2.

Nix is a package manager that can run alongside another Linux distribution. Installing it does not replace that computer’s operating system or normal package manager. Here, it provides the tools and dependencies needed to build the A14 installer.

On a typical systemd-based Linux distribution with SELinux disabled, run:

```bash
curl --proto '=https' --tlsv1.2 -L \
  https://nixos.org/nix/install \
  -o /tmp/install-nix

sh /tmp/install-nix --daemon
```

Run this from your normal user account. The installer requests administrator access when needed. See the [official Nix installation instructions](https://nixos.org/download/) for other host configurations.

Close your terminal, open a new one, and check:

```bash
nix --version
```

Enable flakes:

```bash
mkdir -p ~/.config/nix
nano ~/.config/nix/nix.conf
```

Add:

```ini
experimental-features = nix-command flakes
```

If this setting already exists, add the features to its existing line.

In Nano, save with **Ctrl+O**, press **Enter**, then exit with **Ctrl+X**.

---

**2. Download the project and prepare the firmware**

Install Git through your normal package manager if necessary, then run:

```bash
git clone https://github.com/chrispouliot/linux-zenbook-a14-arm.git
cd linux-zenbook-a14-arm
```

Follow [the firmware guide](docs/firmware.md) to collect the required files from the A14’s Windows installation or matching driver packages.

Copy the extracted directory onto the build computer. These examples assume it is located at:

```text
~/a14-firmware/
```

Already have the files? Reuse them.

Validate the directory:

```bash
nix run .#firmware -- validate "$HOME/a14-firmware" --strict
```

Resolve any missing files or reference-hash differences before continuing. The firmware guide explains how to handle another firmware version.

**Keep a separate backup of this directory before removing Windows.** The firmware is required by both the installer and the installed system.

---

**3. Build the A14 installer ISO**

From the project directory:

```bash
nix build .#iso \
  --override-input windows-firmware "path:$HOME/a14-firmware" \
  --no-write-lock-file \
  --out-link result-a14-iso \
  -L
```

Use the same command on an x86-64 or ARM64 Linux computer.

On ARM64, the build runs natively. On x86-64, the project cross-compiles an ARM64 installer. **Both produce an ISO for the A14.**

Keep the project’s pinned inputs unchanged for your first installation.

The first build can take considerable time and disk space, especially when cross-compiling. It may build parts of the live system as well as the kernel.

When it finishes, find the ISO with:

```bash
ls -lh result-a14-iso/iso/
```

The `.iso` file in that directory is your installer.

It contains your supplied Windows firmware. Keep the ISO private unless you have permission to redistribute those files.

---

**4. Write the ISO to USB**

Use your distribution’s disk-image writer to write the generated ISO to a spare USB drive.

For example, in GNOME Disks:

1. Select the USB drive.
2. Open its menu and choose **Restore Disk Image**.
3. Select the generated `.iso` file.
4. Check the selected drive’s model and capacity, then start writing.

**Writing the image erases the USB drive.**

Write the image directly; copying the ISO file onto an ordinary USB filesystem does not make it bootable.

---

**5. Boot the installer on the A14**

Complete [Windows encryption, PIN and boot preparation](#windows-and-boot-preparation) before changing Secure Boot. It covers backing up the recovery key, suspending BitLocker or optionally decrypting, and keeping a way to sign into Windows.

Use **F2 held at power-on** for BIOS/UEFI settings. For the USB boot menu, hold **Esc at power-on** until it appears. Windows **Advanced startup → Use a device** is an alternative, as explained in the preparation section. Select the USB's UEFI entry. If you already completed this preparation through the WSL guide, continue below.

For the first boot, keep the lid open and disconnect external displays and docks.

The installer starts in a terminal. Become root:

```bash
sudo -i
```

The remaining installation commands run from this root shell, so they do not need `sudo`.

Check the kernel and device tree:

```bash
uname -m
uname -r
tr '\0' '\n' < /sys/firmware/devicetree/base/compatible
```

Expect `aarch64`, with device-tree entries including:

```text
asus,zenbook-a14-ux3407na
qcom,glymur
```

Connect to Wi-Fi:

```bash
nmtui
```

Choose **Activate a connection**, select your network, and enter its password. A supported Ethernet adapter is another option.

Check connectivity:

```bash
curl -I https://nixos.org
```

Verify that the keyboard, display, networking, and SSD are accessible before changing partitions.

---

**6. Prepare the SSD**

List the disks:

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS
```

Identify the internal SSD by its model and capacity. Do not confuse it with the USB installer.

For a fresh installation, use a GPT partition table with:

| Partition            | Suggested size  | Partition type   | Filesystem | Mount point |
| -------------------- | --------------- | ---------------- | ---------- | ----------- |
| EFI system partition | 2 GiB           | EFI System       | FAT32      | `/boot`     |
| NixOS root partition | Remaining space | Linux filesystem | ext4       | `/`         |

Open the partition editor using the actual SSD device:

```bash
cfdisk /dev/REPLACE_WITH_SSD
```

An NVMe SSD might be `/dev/nvme0n1`.

**Deleting existing partitions and writing a new layout destroys the existing installation. These fresh-install instructions do not preserve Windows.**

In `cfdisk`, create the two partitions, set their types, review the layout, then choose **Write** and **Quit**.

If you want to keep Windows, shrink its partition from Windows first and follow [the dual-boot preparation notes](docs/installation.md). Keep the existing EFI and recovery partitions; do not run the EFI formatting command below on an existing Windows EFI partition.

Run `lsblk` again, then enter the actual partition paths:

```bash
read -r -p 'New EFI partition to format: ' a14_esp
read -r -p 'New NixOS root partition to format: ' a14_root
```

Review your selections:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$a14_esp" "$a14_root"
```

**The next two commands erase those partitions.** Run them only after confirming the selections:

```bash
mkfs.fat -F 32 "$a14_esp"
mkfs.ext4 -L nixos "$a14_root"
```

Mount the new installation:

```bash
mount "$a14_root" /mnt
mkdir -p /mnt/boot
mount "$a14_esp" /mnt/boot
```

`/mnt` now represents the future installed system. Its `/boot` directory is the EFI partition.

---

**7. Generate the disk configuration**

Run:

```bash
nixos-generate-config --root /mnt
```

This creates configuration files under `/mnt/etc/nixos`, including `hardware-configuration.nix`, which records the filesystems you just mounted.

Check it:

```bash
cat /mnt/etc/nixos/hardware-configuration.nix
```

It should contain entries for `/` and `/boot`.

Keep this generated file. It describes your actual disk layout and should not be replaced with someone else’s hardware configuration. See the [NixOS installation manual](https://nixos.org/manual/nixos/stable/#sec-installation-manual) for the general installation process.

---

**8. Add the A14 support and your settings**

The installer includes a copy of this project and the firmware you supplied.

Copy them into the new system:

```bash
mkdir -p /mnt/etc/nixos/hardware

cp -aL /etc/nixos-a14-source \
  /mnt/etc/nixos/hardware/nixos-a14

chmod -R u+w /mnt/etc/nixos/hardware/nixos-a14

a14-firmware copy /etc/a14-firmware \
  /mnt/etc/nixos/firmware
```

Copy the supplied starter configuration:

```bash
cp /etc/nixos-a14-source/examples/installed/flake.nix \
  /mnt/etc/nixos/flake.nix

cp /etc/nixos-a14-source/examples/installed/configuration.nix \
  /mnt/etc/nixos/configuration.nix
```

These commands replace the generated starter `configuration.nix` while keeping your generated `hardware-configuration.nix`.

The files now have these roles:

| File or directory            | Purpose                                                                         |
| ---------------------------- | ------------------------------------------------------------------------------- |
| `flake.nix`                  | Connects your configuration to the A14 hardware module and pinned dependencies. |
| `configuration.nix`          | Your username, desktop, hostname, and other preferences.                        |
| `hardware-configuration.nix` | Your detected filesystems and disk identifiers.                                 |
| `hardware/nixos-a14/`        | The hardware project copied from this installer.                                |
| `firmware/`                  | Your extracted Windows firmware.                                                |

Edit your personal settings:

```bash
nano /mnt/etc/nixos/configuration.nix
```

Find:

```nix
users.users.owner = {
```

Change `owner` to the username you want. For example:

```nix
users.users.alex = {
```

The example already enables:

* GNOME and its graphical login screen.
* NetworkManager.
* An administrator account through the `wheel` group.
* systemd-boot with device-tree installation.
* Nix flakes.

You can also add your timezone inside the main configuration:

```nix
time.timeZone = "America/Vancouver";
```

Leave `system.stateVersion` at the example’s initial installation value when performing future upgrades.

The flake supplies firmware using:

```nix
hardware.asus.zenbookA14.firmwareSource = ./firmware;
```

After installation, that directory will be `/etc/nixos/firmware`. NixOS handles installing the kernel, device tree, modules, and firmware into the system.

---

**9. Install NixOS and set your passwords**

Run:

```bash
nixos-install --flake /mnt/etc/nixos#a14
```

This builds the configured system, installs it onto the SSD, and sets up its bootloader.

Keep the laptop connected to power and the internet. Nix reuses matching available builds, but installation can still compile packages or the kernel—particularly when the USB image was cross-compiled on x86-64.

Set the root password when prompted.

Then set the password for the normal user you configured. For the example username `alex`:

```bash
nixos-enter --root /mnt -c 'passwd alex'
```

Replace `alex` if you chose another username.

Wait for installation to finish successfully before rebooting. If it fails, retain the error output and resolve it from the live environment.

---

**10. Reboot into your installed system**

Finish disk writes and unmount the SSD:

```bash
sync
umount -R /mnt
reboot
```

Remove the USB as the laptop restarts. Select the internal Linux boot option if necessary.

The example leaves EFI-variable writes disabled because of the firmware limitation observed on this hardware. It installs the bootloader files, including the ARM64 fallback path, but firmware boot selection may still need attention.

Log in through GNOME using your new account and password.

Check:

```bash
uname -r
nixos-version
```

Test the internal display, keyboard, touchpad, Wi-Fi, Bluetooth, audio, and battery information. Then test suspend/resume and your external displays or dock.

The installed system has its own kernel and firmware. It does not need the installer USB or Windows partition to run.

**Keep `/etc/nixos/firmware` and your separate firmware backup.** Future rebuilds still need the firmware source.

---

**Making changes afterward**

Your personal settings live in:

```text
/etc/nixos/configuration.nix
```

After editing them, apply the configuration with:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#a14
```

For kernel or hardware changes, prepare the next boot instead:

```bash
sudo nixos-rebuild boot --flake /etc/nixos#a14
sudo reboot
```

A reboot is required to start a different kernel. Keep a previous working generation available in the boot menu when testing changes.

The starter flake uses the local hardware-project copy from your installer. It will not automatically fetch later GitHub changes.

When you are ready to follow the public repository, change the `a14` input in `/etc/nixos/flake.nix` to:

```nix
a14.url = "github:chrispouliot/linux-zenbook-a14-arm";
```

Then update that input and prepare a new generation:

```bash
cd /etc/nixos
sudo nix flake update a14
sudo nixos-rebuild boot --flake .#a14
```

Review the project’s changes before rebooting into the new generation. Your firmware setting and personal configuration stay in place.

**Using Git for your configuration?** The initial directory is not Git-backed. Before adding it to a public repository, follow [the private firmware input instructions](docs/firmware.md#keep-firmware-outside-your-configuration-repository). Keep the Windows binaries out of public commits.

</details>


<a id="installing-arch-linux-arm"></a>

<details>
<summary><strong>Installing Arch Linux ARM</strong></summary>

**Starting from Windows on the A14?** Complete [the WSL2 preparation guide](#installing-from-windows-wsl2) first, then return here at step 5.

This walkthrough starts with:

* An ASUS Zenbook A14 **UX3407NA / Snapdragon X2 Elite**.
* Another computer running Linux, either Intel/AMD x86-64 or ARM64.
* A USB drive large enough for the generated ISO.
* The required firmware extracted from the A14’s Windows installation.
* An internet connection during installation.

You do not need Linux already installed on the A14.

**Status: experimental.** The project’s ISO configuration supports native ARM64 and x86-64-to-ARM64 builds, but this complete Arch installation procedure still needs hardware testing.

This example covers a fresh installation using an EFI partition and an unencrypted ext4 root partition. Preserving Windows, disk encryption, and more complex partition layouts require different partitioning instructions.

**How this works**

Your other Linux computer builds an ARM64 live ISO containing the patched Glymur kernel, A14 device tree, drivers, and firmware.

You boot that ISO on the A14, install an Arch Linux ARM base system onto its SSD, and copy the matching hardware files from the live environment into the installed system.

The live environment uses NixOS. The installed system uses Arch Linux ARM and `pacman`.

Nix is only required on the build computer. Installing Nix there adds a package manager and build service alongside your existing distribution; it does not replace your operating system.

---

**1. On the build computer: install Nix**

If Nix is already installed with flakes enabled, skip this step.

On a typical systemd-based Linux distribution with SELinux disabled, run the official installer from your normal account:

```bash
curl --proto '=https' --tlsv1.2 -L \
  https://nixos.org/nix/install \
  -o /tmp/install-nix

sh /tmp/install-nix --daemon
```

It will request administrator access where needed. See the [official Nix instructions](https://nixos.org/download/) for other host configurations.

Close your terminal, open a new one, and check:

```bash
nix --version
```

Enable flakes:

```bash
mkdir -p ~/.config/nix
nano ~/.config/nix/nix.conf
```

Add:

```ini
experimental-features = nix-command flakes
```

If the setting already exists, add these features to its existing line.

In Nano, save with **Ctrl+O**, press **Enter**, then exit with **Ctrl+X**.

---

**2. Download the project and prepare the firmware**

Install Git through your normal package manager if necessary, then run:

```bash
git clone https://github.com/chrispouliot/linux-zenbook-a14-arm.git
cd linux-zenbook-a14-arm
```

Follow [the firmware collection instructions](docs/firmware.md) to collect the files from the matching A14 Windows installation.

Place them in:

```text
~/a14-firmware/
```

If you already have the extracted files, reuse that directory.

Validate them:

```bash
nix run .#firmware -- validate "$HOME/a14-firmware" --strict
```

Resolve any missing files or reference-hash differences before continuing.

Keep a separate backup of these files before removing Windows. The firmware is needed by the installed system during normal operation.

---

**3. Build the bootable A14 ISO**

From the project directory:

```bash
nix build .#iso \
  --override-input windows-firmware "path:$HOME/a14-firmware" \
  --no-write-lock-file \
  --out-link result-a14-iso \
  -L
```

Use this same command on an x86-64 or ARM64 Linux build computer.

The project selects a native ARM64 build on ARM64 hosts and cross-compilation on x86-64 hosts. **The resulting ISO targets the A14 in both cases.** Do not add `--system aarch64-linux` to force the build on an x86-64 computer.

The first build can be substantial: it may compile parts of the live system as well as the kernel. Allow plenty of free disk space and keep the computer connected to power.

A successful build places the ISO under:

```text
result-a14-iso/iso/
```

List the exact filename:

```bash
ls -lh result-a14-iso/iso/
```

If the build fails, retain the error output. A successfully evaluated configuration is not a guarantee that every cross-compilation dependency will build.

This ISO contains your supplied Windows firmware. Keep it private unless you have permission to redistribute those files.

---

**4. Write the ISO to USB**

Use your distribution’s disk-image writer and select the generated `.iso` file.

For example, GNOME Disks provides **Restore Disk Image** after selecting the USB drive.

**Writing an image erases the selected USB drive.** Check its model and capacity before starting.

Write the image directly. Simply copying the `.iso` file onto an ordinary USB filesystem does not make the drive bootable.

---

**5. Boot the USB on the A14**

Complete [Windows encryption, PIN and boot preparation](#windows-and-boot-preparation) before changing Secure Boot. It covers backing up the recovery key, suspending BitLocker or optionally decrypting, and keeping a way to sign into Windows.

Use **F2 held at power-on** for BIOS/UEFI settings. For the USB boot menu, hold **Esc at power-on** until it appears. Windows **Advanced startup → Use a device** is an alternative, as explained in the preparation section. Select the USB's UEFI entry. If you already completed this preparation through the WSL guide, continue below.

Once the live environment starts, become root:

```bash
sudo -i
```

Check that it is running on ARM64:

```bash
uname -m
uname -r
```

The architecture should be `aarch64`.

Connect to the internet:

```bash
nmtui
```

Choose **Activate a connection**, select your network, and enter its password. Wired networking is another option.

Check connectivity:

```bash
curl -I https://archlinuxarm.org
```

**Check the keyboard, storage visibility, and networking before repartitioning.** If the live environment cannot reliably access the SSD or network, resolve that first.

---

**6. Load the installation tools**

Still in the A14 live environment:

```bash
nix shell \
  --inputs-from /etc/nixos-a14-source \
  nixpkgs#libarchive \
  nixpkgs#arch-install-scripts \
  nixpkgs#dosfstools \
  nixpkgs#e2fsprogs \
  --command bash
```

This opens a shell containing tools for extracting Arch, creating filesystems, and configuring the installed system.

Keep using this shell for the following steps.

The commands now execute on the ARM64 A14. No x86-to-ARM emulation is needed during installation.

---

**7. Prepare the SSD**

List the disks:

```bash
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS
```

Identify the A14’s internal SSD by its model and capacity. Do not confuse it with the installer USB.

For a fresh installation, use a GPT partition table with:

| Partition            | Suggested size  | Partition type   | Filesystem | Mount point |
| -------------------- | --------------- | ---------------- | ---------- | ----------- |
| EFI system partition | 2 GiB           | EFI System       | FAT32      | `/boot`     |
| Linux root partition | Remaining space | Linux filesystem | ext4       | `/`         |

Open the partition editor using the actual SSD device:

```bash
cfdisk /dev/REPLACE_WITH_SSD
```

For example, an NVMe SSD might be `/dev/nvme0n1`.

**Deleting existing partitions and writing a new layout destroys the existing installation. This fresh-install example does not preserve Windows.**

In `cfdisk`, create the two partitions, set their types, review the layout, then choose **Write** and **Quit**.

Run `lsblk` again and identify the resulting partition names.

Set these variables using your actual new partitions:

```bash
a14_esp=/dev/REPLACE_WITH_EFI_PARTITION
a14_root=/dev/REPLACE_WITH_ROOT_PARTITION
```

For example, they might be `/dev/nvme0n1p1` and `/dev/nvme0n1p2`.

Format and mount them:

```bash
mkfs.fat -F 32 "$a14_esp"
mkfs.ext4 "$a14_root"

mount "$a14_root" /mnt
mkdir -p /mnt/boot
mount "$a14_esp" /mnt/boot
```

These formatting commands erase the selected partitions.

---

**8. Install the Arch Linux ARM base system**

Arch Linux ARM supplies a generic AArch64 root-filesystem archive. We use its userspace and supply our own A14 kernel and boot configuration. [Arch Linux ARM generic installation](https://archlinuxarm.org/platforms/armv8/generic).

Download the archive onto the mounted SSD:

```bash
curl --fail --location \
  --proto '=https' --proto-redir '=https' \
  https://ca.us.mirror.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz \
  -o /mnt/ArchLinuxARM-aarch64-latest.tar.gz
```

Extract it as root using `bsdtar`:

```bash
bsdtar -xpf /mnt/ArchLinuxARM-aarch64-latest.tar.gz -C /mnt
```

If extraction reports errors, stop and resolve them.

Generate the filesystem mount configuration:

```bash
genfstab -U /mnt > /mnt/etc/fstab
cat /mnt/etc/fstab
```

Check that it contains the intended root filesystem and `/boot` partition.

---

**9. Copy the A14 kernel and hardware files**

We will reuse the files from the live system that just booted this laptop.

Record its kernel release:

```bash
a14_release=$(uname -r)
printf '%s\n' "$a14_release" > /mnt/etc/a14-kernel-release
```

Copy the kernel and already-overlaid device tree:

```bash
mkdir -p /mnt/boot/a14

cp -L /run/booted-system/kernel \
  /mnt/boot/a14/Image

cp -L \
  /run/booted-system/dtbs/qcom/glymur-asus-zenbook-a14-ux3407na.dtb \
  /mnt/boot/a14/a14.dtb
```

Copy the matching modules:

```bash
mkdir -p /mnt/usr/lib/modules

cp -rL \
  "/run/booted-system/kernel-modules/lib/modules/$a14_release" \
  /mnt/usr/lib/modules/
```

Copy the assembled firmware into a directory specific to this kernel release:

```bash
mkdir -p "/mnt/usr/lib/firmware/updates/$a14_release"

cp -rL /run/booted-system/firmware/. \
  "/mnt/usr/lib/firmware/updates/$a14_release/"
```

This includes both the supplied Windows firmware and firmware assembled by the project. It may take a while.

The `-L` options copy the actual contents behind Nix store links. The installed Arch system must have ordinary files available after the USB is removed.

Also retain the original Windows firmware source:

```bash
mkdir -p /mnt/root/a14-firmware-source

cp -rL /etc/a14-firmware/. \
  /mnt/root/a14-firmware-source/
```

---

**10. Enter the installed Arch system**

A *chroot* lets you run commands using the installed Arch filesystem while the live kernel continues running.

```bash
arch-chroot /mnt /usr/bin/env -i \
  HOME=/root \
  TERM="$TERM" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/bin \
  /bin/bash
```

`arch-chroot` provides access to devices and other essential runtime filesystems. [Arch chroot documentation](https://man.archlinux.org/man/arch-chroot.8.en).

**Until the explicit `exit` below, commands configure the Arch installation.**

Initialize the Arch Linux ARM package keys:

```bash
pacman-key --init
pacman-key --populate archlinuxarm
```

Update the system and install essential tools:

```bash
pacman -Syu mkinitcpio networkmanager sudo nano
```

Read the prompts and resolve any package or signature errors. Do not disable signature checking to bypass them.

Set the root password and replace the archive’s default `alarm` password:

```bash
passwd
passwd alarm
```

The `alarm` account is your initial normal user account. Add it to the administrator group:

```bash
usermod -aG wheel alarm
EDITOR=nano visudo
```

Uncomment the rule allowing members of `wheel` to run commands through `sudo`.

Set a hostname:

```bash
printf 'a14\n' > /etc/hostname
```

Choose your timezone; this example uses Vancouver:

```bash
ln -sf /usr/share/zoneinfo/America/Vancouver /etc/localtime
```

Edit the locale list:

```bash
nano /etc/locale.gen
```

Uncomment your preferred UTF-8 locale, such as `en_US.UTF-8 UTF-8`, then run:

```bash
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
```

Use the same locale in both places.

Configure networking:

```bash
systemctl disable systemd-networkd
systemctl disable sshd
systemctl enable NetworkManager systemd-resolved systemd-timesyncd
```

We will finish the DNS symlink after leaving the chroot.

---

**11. Create Arch’s early boot image**

The *initramfs* loads essential drivers and mounts the SSD before starting the installed system.

Create an A14-specific configuration:

```bash
cat > /etc/mkinitcpio-a14.conf <<'EOF'
MODULES=(
  tcsrcc-glymur
  phy_qcom_qmp_pcie
  phy_qcom_m31_eusb2
  phy_qcom_eusb2_repeater
  phy_qcom_qmp_usb
  phy_qcom_qmp_usbc
  gpi
  i2c_qcom_geni
  i2c_hid_of
  nvme
  usb_storage
  uas
)
BINARIES=()
FILES=()
HOOKS=(base udev modconf block keyboard filesystems fsck)
COMPRESSION="gzip"
EOF
```

This configuration is for the simple unencrypted installation described above. Graphics and audio drivers can load after the real root filesystem—and its firmware—is available.

Load the release name and index its drivers:

```bash
a14_release=$(cat /etc/a14-kernel-release)
depmod -a "$a14_release"
```

Create a preset so the image can be regenerated later:

```bash
mkdir -p /etc/mkinitcpio.d

cat > /etc/mkinitcpio.d/a14.preset <<EOF
ALL_config="/etc/mkinitcpio-a14.conf"
ALL_kver="$a14_release"
PRESETS=('default')
default_image="/boot/a14/initramfs.img"
EOF
```

Build it:

```bash
mkinitcpio -p a14
```

On ARM64, pass the kernel release through the preset, rather than asking `mkinitcpio` to identify it from an x86-style kernel image. [mkinitcpio documentation](https://man.archlinux.org/man/mkinitcpio.8.en).

Stop if this reports errors involving required modules or image generation.

Enable the embedded-controller driver:

```bash
mkdir -p /etc/modules-load.d
printf 'asus-glymur-ec\n' > /etc/modules-load.d/a14.conf
```

Leave the chroot:

```bash
exit
```

You are now back in the live environment.

Finish the installed system’s DNS configuration:

```bash
ln -sfn /run/systemd/resolve/stub-resolv.conf /mnt/etc/resolv.conf
```

---

**12. Install the bootloader**

Install systemd-boot from the live environment onto the new EFI partition:

```bash
bootctl --esp-path=/mnt/boot --variables=no install
```

This installs the ARM64 EFI loader, including the fallback loader path, without attempting to modify the firmware’s boot variables. [bootctl documentation](https://man.archlinux.org/man/bootctl.1.en).

Get the root filesystem’s UUID:

```bash
a14_root_uuid=$(blkid -s UUID -o value "$a14_root")
printf 'Root UUID: %s\n' "$a14_root_uuid"
```

It must print a nonempty UUID.

Create the boot entry:

```bash
mkdir -p /mnt/boot/loader/entries

cat > /mnt/boot/loader/entries/arch-a14.conf <<EOF
title Arch Linux ARM - A14 Glymur
linux /a14/Image
initrd /a14/initramfs.img
devicetree /a14/a14.dtb
options root=UUID=$a14_root_uuid rw rootwait console=tty1 consoleblank=0 pm_async=off mem_sleep_default=s2idle usbcore.quirks=2109:0817:k
EOF
```

Create the menu configuration:

```bash
cat > /mnt/boot/loader/loader.conf <<'EOF'
default arch-a14.conf
timeout 5
editor yes
EOF
```

The boot entry explicitly loads the kernel, Arch initramfs, and A14 device tree. These paths are relative to the EFI partition. [Boot Loader Specification](https://uapi-group.org/specifications/specs/boot_loader_specification/).

Check that the files exist:

```bash
ls -lh /mnt/boot/a14/
ls -l /mnt/boot/EFI/BOOT/BOOTAA64.EFI
cat /mnt/boot/loader/entries/arch-a14.conf
```

---

**13. Boot Arch for the first time**

Finish disk writes and unmount the installation:

```bash
sync
umount -R /mnt
reboot
```

Remove the USB as the laptop restarts.

Select the internal Linux boot option if necessary. This installation provides the standard ARM64 fallback loader at `EFI/BOOT/BOOTAA64.EFI`; whether firmware automatically selects it must be checked on the laptop.

Log in as `alarm` using the password you set.

Verify:

```bash
cat /etc/os-release
uname -r
```

You should now be running **Arch Linux ARM with the project’s Glymur kernel**.

Reconnect to Wi-Fi using:

```bash
sudo nmtui
```

Keep the installer USB. If the installed system fails to boot, it provides the same hardware-enabled environment for mounting the SSD and correcting the installation.

---

**14. Add a desktop**

After confirming the console installation boots and networking works, you can install a desktop from the Arch Linux ARM repositories.

For GNOME:

```bash
sudo pacman -Syu gnome gdm
sudo systemctl enable gdm
sudo reboot
```

Review the package-selection prompts. Desktop availability and graphics support depend on the ARM repositories’ current packages.

**Audio and other hardware integration**

This procedure transfers the kernel, device tree, firmware, and essential boot configuration.

The NixOS project also contains ALSA, PipeWire/WirePlumber, and device-rule configuration. Those NixOS modules do not automatically configure Arch. In particular, speakers and HDMI audio may require additional integration even when the kernel and firmware are present.

See [the hardware module](modules/default.nix) and [audio module](modules/audio.nix) for the configuration that needs to be ported and tested.

**Updating later**

Use `pacman` to update Arch’s applications and system packages.

The copied Glymur kernel is managed separately. An ordinary Arch update does not update this custom kernel, and the generic Arch kernel should not be assumed to support the A14.

For now, retain the working kernel and installer USB while preparing updates. A future Arch package for the kernel, device tree, and supporting configuration would make this easier to maintain.

Nix does not need to be installed on the A14 for this system to run. It can remain on your other Linux computer for future kernel and ISO builds.

</details>


<a id="installing-from-windows-wsl2"></a>

<details>
<summary><strong>Installing from Windows</strong></summary>

If your only computer is the A14 running Windows, you can build the installer on that same laptop using **Windows Subsystem for Linux 2 (WSL2)**.

WSL2 runs a Linux environment inside Windows. You will install Ubuntu in WSL, use Nix to build the A14 ISO, and write it to a USB drive from Windows. After booting the USB, you can install either NixOS or Arch Linux ARM using the guides above.

Windows remains your operating system while you prepare the installer. Installing Ubuntu in WSL does not repartition the SSD or replace Windows. On the ARM64 A14, an ARM64 Ubuntu environment uses the project's native ARM64 build.

**You will need:**

* The A14 running Windows 11 with administrator access and WSL2 support.
* An internet connection and substantial free SSD space for WSL, build dependencies, and the ISO.
* A spare USB drive large enough for the generated ISO.
* Your extracted Windows firmware and a separate backup of anything you want to keep.

**Status: experimental.** Nix documents installation under WSL2, but this project's complete ISO build under WSL and subsequent physical USB boot have not yet been tested. Keep Windows intact until the USB boots and you have checked the hardware needed for installation.

---

**1. Install Ubuntu through WSL2**

In Windows, open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu
```

Restart Windows if requested, then open **Ubuntu** from the Start menu. Complete its initial setup by choosing a Linux username and password. These are for the temporary build environment and can differ from your Windows account.

In PowerShell, check:

```powershell
wsl --list --verbose
```

Ubuntu should show **VERSION 2**. If it shows version 1, convert it:

```powershell
wsl --set-version Ubuntu 2
```

If installation or startup fails, follow [Microsoft's WSL installation instructions](https://learn.microsoft.com/en-us/windows/wsl/install) before continuing.

---

**2. Check Ubuntu and systemd**

In the **Ubuntu terminal**, run:

```bash
uname -m
ps -p 1 -o comm=
```

Expect `aarch64` and `systemd`. The second check confirms that the service manager needed by the Nix daemon is running.

Current Ubuntu WSL installations normally enable systemd. If the second command does not show it, edit this file inside Ubuntu:

```bash
sudo nano /etc/wsl.conf
```

Add the following, or update the setting under an existing `[boot]` section:

```ini
[boot]
systemd=true
```

Save with **Ctrl+O**, press **Enter**, then exit with **Ctrl+X**. Close Ubuntu, save any work in other WSL sessions, and run this in **PowerShell**:

```powershell
wsl --shutdown
```

Reopen Ubuntu and repeat the checks. See [Microsoft's systemd instructions](https://learn.microsoft.com/en-us/windows/wsl/systemd) if needed.

---

**3. Install Nix inside Ubuntu**

In the **Ubuntu terminal**, install the basic tools:

```bash
sudo apt update
sudo apt install git curl ca-certificates nano
```

Install Nix from your normal Ubuntu account:

```bash
curl --proto '=https' --tlsv1.2 -L \
  https://nixos.org/nix/install \
  -o /tmp/install-nix

sh /tmp/install-nix --daemon
```

Follow the prompts, then close and reopen Ubuntu. Check:

```bash
nix --version
```

Enable flakes:

```bash
mkdir -p ~/.config/nix
nano ~/.config/nix/nix.conf
```

Add the following setting, or add these features to its existing line:

```ini
experimental-features = nix-command flakes
```

This is the multi-user WSL2 installation described in the [official Nix instructions](https://nixos.org/download/).

---

**4. Download the project and collect the Windows firmware**

In **Ubuntu**, clone the project into your Linux home directory:

```bash
cd ~
git clone https://github.com/chrispouliot/linux-zenbook-a14-arm.git
cd linux-zenbook-a14-arm
```

Keep the project and builds here, rather than under `/mnt/c/`. This avoids the performance and filesystem differences of building directly on the Windows drive. [Microsoft's filesystem guidance](https://learn.microsoft.com/en-us/windows/wsl/filesystems).

In **Windows**, follow [the firmware collection guide](docs/firmware.md). Download and extract the project ZIP if you need a Windows-accessible copy of the collector. From that extracted project directory in an elevated PowerShell terminal, you can collect into your Windows user folder with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-A14Firmware.ps1 -Destination "$env:USERPROFILE\a14-firmware"
```

If you already have the extracted files, reuse them. If collection reports missing files, follow the firmware guide before proceeding.

Copy the resulting directory into Ubuntu. Run this in **Ubuntu**, replacing `YOUR_WINDOWS_USERNAME` with the actual Windows user-folder name:

```bash
cp -r "/mnt/c/Users/YOUR_WINDOWS_USERNAME/a14-firmware" \
  "$HOME/a14-firmware"
```

Adjust the source path if your files are stored elsewhere. The Windows folder name may differ from your display name or Ubuntu username.

Validate the copied files from the project directory:

```bash
nix run .#firmware -- validate "$HOME/a14-firmware" --strict
```

Resolve missing files or reference-hash differences before continuing. Keep a firmware backup outside both Windows and WSL, somewhere that will not be erased when you write the installer USB or install Linux.

---

**5. Build the A14 ISO inside WSL**

In **Ubuntu**, from `~/linux-zenbook-a14-arm`:

```bash
nix build .#iso \
  --override-input windows-firmware "path:$HOME/a14-firmware" \
  --no-write-lock-file \
  --out-link result-a14-iso \
  -L
```

Keep the pinned inputs unchanged for the first build. Since `uname -m` reported `aarch64`, Nix uses the native ARM64 build; no x86 cross-compilation is required.

The first build can take considerable time and disk space. Keep the A14 plugged in and prevent Windows from sleeping during the build. WSL uses a virtual disk stored on your Windows drive, so it consumes that drive's free space too.

When the build succeeds, list the ISO:

```bash
ls -lh result-a14-iso/iso/
```

If it fails, retain the error output. The WSL build route still needs validation; do not proceed as though a failed build produced a usable installer.

---

**6. Copy the ISO back to Windows**

In **Ubuntu**, replace the Windows username and copy the ISO into Downloads:

```bash
cp result-a14-iso/iso/*.iso \
  "/mnt/c/Users/YOUR_WINDOWS_USERNAME/Downloads/"
```

If Downloads is redirected elsewhere, use its actual path.

Wait for the copy to finish. The ISO should then be visible in Windows File Explorer. It contains your supplied Windows firmware; keep it private unless you have permission to redistribute those files.

---

**7. Write the USB from Windows**

Download the **Windows ARM64** version of [Rufus](https://rufus.ie/en/) and run it in Windows.

1. Insert your spare USB drive.
2. In Rufus, select that drive under **Device**.
3. Select the ISO you copied into Downloads.
4. Check the USB model and capacity, then choose **Start**.
5. If Rufus offers ISO Image mode or DD Image mode, choose **DD Image mode** for this installer to preserve the generated image layout.
6. Wait until writing is complete.

**Writing the image erases the selected USB drive.** Do not store your only firmware backup on the drive being overwritten. Rufus documents its image-writing modes in its [FAQ](https://github.com/pbatard/rufus/wiki/FAQ).

If Windows later offers to format a partition on the installer USB, cancel that prompt.

---

**8. Boot the USB and choose which distribution to install**

Now that the USB is ready, complete [Windows encryption, PIN and boot preparation](#windows-and-boot-preparation). Suspend BitLocker protection or deliberately decrypt as described there before disabling Secure Boot. Keep a working account-recovery method as well: changing encryption does not guarantee that the Windows Hello PIN will remain usable.

Use **F2 held at power-on** for BIOS/UEFI. Hold **Esc at power-on** for USB selection, or use Windows Advanced Startup as an alternative. Both F2 and Esc have been confirmed on this A14; the preparation section gives the full steps.

Keep the lid open and initially disconnect external displays and docks. Check that the live environment can use the keyboard, SSD, and network before modifying the SSD.

Then expand the guide for your chosen distribution and continue at its boot step:

| Install this system | Continue here |
| --- | --- |
| NixOS | [Installing NixOS ARM](#installing-nixos-arm), **step 5: Boot the installer on the A14** |
| Arch Linux ARM | [Installing Arch Linux ARM](#installing-arch-linux-arm), **step 5: Boot the USB on the A14** |

You have already completed the ISO-building and USB-writing steps. The same USB works as the live environment for either installation route.

**Run all SSD partitioning and installation commands after booting the USB, not inside WSL.** Removing Windows also removes WSL and the files stored inside it. Keep your backups separate and retain the installer USB for recovery.

</details>


## Included patches

These are the project's additions to the pinned Glymur kernel, including device-tree and audio files and the ordered platform patches under `patches/platform/`. Some display workarounds remain experimental. The older Python rewrites are now [eighteen platform patches](docs/display/PLATFORM.md), with the same resulting source. The four display patches form an ordered series and are not independent opt-in features; see [display integration and validation](docs/display/README.md). The SCMI mailbox patch and fixed-address ramoops diagnostics are **opt-in**; the camera and video codec support are on by default and can be turned off; other retained DP diagnostics remain part of the baseline.

<details>
<summary><strong>Show all patches and hardware adjustments</strong></summary>

| Patch or adjustment | What it does |
| --- | --- |
| [`a14-usb-fix.dtsi`](patches/a14-usb-fix.dtsi) | Supplies USB clock, power and interconnect settings; enables SCMI reply polling; selects the QCC2072 Bluetooth device type. |
| [`a14-audio-left-only.dtsi`](patches/a14-audio-left-only.dtsi) | Describes the two populated speaker codecs and adds the built-in HDMI audio backend. Despite the filename, these codecs serve both physical speakers. |
| [`a14-edp-hbr.dtsi`](patches/a14-edp-hbr.dtsi) | Limits the internal display link to 2.7 Gbit/s per lane to work around link-training failures after suspend. |
| [`a14-ec-overlay.dts`](patches/a14-ec-overlay.dts) | Adds the ASUS embedded controller and its interrupt/wakeup wiring, and enables UEFI RTC information. |
| [`a14-hdmi-topology.m4`](patches/a14-hdmi-topology.m4) | Builds the AudioReach topology with separate internal speaker, microphone and stereo HDMI paths. |
| [`a14-dp-boot-order-debug.patch`](patches/a14-dp-boot-order-debug.patch) | Adds USB/DisplayPort PHY initialization and mode-change logging to diagnose boot ordering. |
| [`a14-glymur-ucsi-dp-mux-race.patch`](patches/a14-glymur-ucsi-dp-mux-race.patch) | Prevents a UCSI USB-mode notification from overwriting the DisplayPort mux selection on Glymur. |
| [`a14-dp-hpd-replay.patch`](patches/a14-dp-hpd-replay.patch) | Remembers display hotplug state and replays it when the DRM bridge enables notifications, covering early boot events. |
| [`a14-dp-usb-preserve-bank0.patch`](patches/a14-dp-usb-preserve-bank0.patch) | Preserves USB-sensitive bank0 transmitter controls during the affected USB+DP startup sequence to avoid disrupting dock USB/Ethernet. |
| [`a14-display-dsc.patch`](patches/a14-display-dsc.patch) | Adds the DSC/FEC pipeline and 4K144 mode support. Apply with the rest of the ordered display series. |
| [`a14-display-lifecycle.patch`](patches/a14-display-lifecycle.patch) | Retains wake, AUX, HPD and link teardown corrections, diagnostics, and gated alternatives. |
| [`a14-display-transparent-lttpr.patch`](patches/a14-display-transparent-lttpr.patch) | Selects transparent repeater training for the guarded A14 port-one two-repeater dock topology. |
| [`a14-display-edp-depth.patch`](patches/a14-display-edp-depth.patch) | Finalizes the native internal panel's colour depth after powered capability setup, preserving its HBR link cap. |
| [Legacy dock recovery v4](display/options/dock-recovery-v4.nix) — optional | Overrides the personal v3 boot service only if its existing option is enabled. Currently disabled in the tested personal configuration; a docked boot passed without it and without the 30-second grace period. |
| [`a14-scmi-mailbox-set-test.patch`](patches/a14-scmi-mailbox-set-test.patch) — opt-in | Tests CPU performance requests through SCMI mailbox messages instead of fast-channel writes. It is not a proven performance fix. |
| [Camera driver backports](patches/camera/) | Fifteen commits from linux-msm `topic/glymur-laptops` and the September 2026 upstream Glymur camera series: PHY core helpers, the CSI2 PHY driver, CAMSS PHY-API and Glymur support, PM8010 camera PMIC support, and the Glymur CAMSS, CSIPHY, CCI and MCLK device-tree nodes. On by default; `camera.enable = false` drops them. |
| [`a14-camera.dtsi`](patches/a14-camera.dtsi) | Describes the OV02C10 front camera on CSIPHY4 with a PM8010 camera PMIC and the privacy LED, following the Zenbook A16 and CRD wiring and confirmed against the A14's firmware tables. |
| [Iris video codec backports](patches/video/) | Thirteen commits from the upstream "media: iris: Add support for glymur platform" v10 series, ported onto the pinned snapshot: context-bank devices, PAS firmware loading through a Linux-managed IOMMU, per-block clock and power tables, the Glymur power sequence and dual-core selection, Glymur platform data, and the Glymur/CRD device-tree nodes. On by default; `video.enable = false` drops them. |
| [`a14-iris.dtsi`](patches/a14-iris.dtsi) | Enables the video codec node with PAS-authenticated firmware, mirroring the CRD; verified on hardware. |
| [Video firmware handling](modules/video.nix) | Installs the generic linux-firmware VPU image; the OEM `qcvss8480.mbn` is an optional manifest entry installed when present, with a warning when it is missing. |
| [Camera userspace](modules/camera.nix) | Installs libcamera and v4l-utils, keeps PipeWire/WirePlumber enabled, and gives the video group access to udmabuf so the software-ISP camera appears to applications. |
| [External DP1 link limit](patches/platform/01-external-dp-hbr2.patch) | Caps the second external controller (`mdss_dp1`, af5c000) at HBR2 / 5.4 Gbit/s per lane. The working port-one dock path uses af54000 and can negotiate HBR3. |
| [Stereo speaker backend](patches/platform/02-audio-stereo.patch) | Restricts the WSA backend to two channels while retaining the existing four-channel audio frontend. |
| [Keyboard Fn-lock support](patches/platform/03-hid-fn-lock.patch) | Enables Fn-lock for the Zenbook keyboard, with media/brightness keys used directly and Fn for F1–F12. |
| [PMIC GLINK event logging](patches/platform/04-glink-diagnostics.patch) | Logs received and processed USB-C/display events to diagnose ordering and combined notifications. |
| [Display hotplug interrupt containment](patches/platform/05-hpd-irq-containment.patch) | Suppresses repeated IRQ-only notifications on the affected external port while retaining real plug/unplug events. |
| [Display connection and resume handling](patches/platform/06-dp-hpd-state.patch) | Avoids duplicate display discovery, cleans up failed connections, and forces external DP PHY reinitialization after suspend. |
| [DisplayPort bandwidth calculation](patches/platform/07-dp-link-bandwidth.patch) | Checks modes against actual physical-link capacity instead of treating the internal wide-bus optimization as extra bandwidth. |
| [AUX wrong-data-count handling](patches/platform/08-aux-wrong-data-count.patch) | Completes malformed AUX transfers with an error so DRM can retry promptly instead of waiting for a timeout. |
| [Glymur PHY programming corrections](patches/platform/09-phy-startup.patch) | Uses orientation-aware DP programming and preserves the required AUX configuration value during PHY startup. |
| [PHY startup diagnostics](patches/platform/09-phy-startup.patch) | Adds register and timeout diagnostics, including an extended 50 ms C_READY wait for investigating startup failures. |
| [PHY and link-clock error handling](patches/platform/09-phy-startup.patch) | Propagates startup failures and unwinds PHY power when a later stage fails, reducing invalid teardown sequences. |
| [USB-C power-domain retention](patches/platform/10-usb-domain-retention.patch) | Keeps both USB-C controller and combo-PHY power domains on across suspend to avoid controller faults and stalled display resume. |
| [Retained display disconnect events](patches/platform/11-hpd-disconnect-retention.patch) | Preserves a pending disconnect before the latest reconnect state, using stable worker snapshots and matching bridge replay. |
| [SAFE-detach workaround](patches/platform/12-phy-safe-detach.patch) — experimental | Defers shared-PHY reinitialization during a USB-C SAFE notification, leaving normal USB/DP teardown to release it. |
| [Live display check before link enable](patches/platform/13-dp-live-sink-check.patch) — experimental | Checks that an external display still responds over AUX before restoring its link, and cleans up if it has disappeared. |
| [`14-hpd-bootstrap.patch`](patches/platform/14-hpd-bootstrap.patch) | Preserves initial IRQ-tagged HPD during DP setup. |
| [`15-usb-dp-lifecycle.patch`](patches/platform/15-usb-dp-lifecycle.patch) | Retains the USB/DP lifecycle correction for the shared PHY. |
| [`16-phy-boot-mode.patch`](patches/platform/16-phy-boot-mode.patch) | Retains the experimental dock boot-mode programming behavior. |
| [`17-dpcd-probe.patch`](patches/platform/17-dpcd-probe.patch) | Retains the preliminary DPCD-probe override on af54000. |
| [`18-repeater-caps-recovery.patch`](patches/platform/18-repeater-caps-recovery.patch) | Retains the guarded repeater-capability recovery helper before the later display patches. |
| [Audio UCM and speaker routing](modules/audio.nix) | Removes nonexistent speaker paths, maps stereo audio to the populated channels, and provides configurable speaker gain. |
| [HDMI audio hotplug helper](modules/audio.nix) | Creates an HDMI output only while connected, keeping disconnected HDMI from breaking internal audio discovery. |
| [USB and audio autosuspend rules](modules/default.nix) | Keeps the affected SoundWire device and selected VIA USB hubs awake to avoid wake/reconnect problems. |
| [Kernel configuration](kernel.nix) | Enables platform drivers and diagnostic support, and disables Rust for the pinned snapshot's Rust/RCU build mismatch. |
| [Ramoops crash capture](modules/ramoops.nix) — opt-in | Adds the original reserved-memory crash logger and collection helper, only for the specifically validated 32 GiB memory layout. |
| [Installer device-tree support](vendor/README.md) | Adds the board device tree to the ISO and its GRUB boot entries so the installer starts with the correct hardware description. |

</details>

See [hardware notes and options](docs/hardware.md) and [validation status](docs/validation.md) for details. The ISO build and physical boot still need validation; successful configuration evaluation alone does not establish installer compatibility.

### Note

This guide is not responsible for any data loss or misuse. Please read and double check all commands you're running.
This is experimental.
