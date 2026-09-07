# Linux on the ASUS Zenbook A14 X2E

Linux/NixOS hardware support for the **ASUS Zenbook A14 UX3407NA with Snapdragon X2 Elite**. Import one module to use the patched kernel, device tree, firmware integration, and audio, USB and suspend workarounds. Your applications, desktop and power governor settings stay in your own configuration.

The project also builds an ARM64 NixOS installer ISO. It currently uses the pinned **7.2.0-rc5-next-20260731** Glymur kernel. Support is still evolving; see the [hardware notes](docs/hardware.md) for current limitations, including external display link limits. Earlier Snapdragon X1 A14 models are outside this project's scope.

## Before you start

You'll need Nix with flakes enabled and the **Windows firmware files from your UX3407NA**. Already have the extracted files? Keep using them. Otherwise, follow the [firmware guide](docs/firmware.md), which includes collectors for Windows and Linux.

Firmware is required by both the installer and the installed system. Keep a backup of the extracted directory; it is not included in this public repository.

## Use with your NixOS flake

Add the hardware module to your system's module list and point it at your firmware directory. For example, with firmware in `/etc/nixos/firmware`:

```nix
{
  inputs = {
    a14.url = "github:chrispouliot/linux-zenbook-a14-arm";

    # Start with the project's tested Nixpkgs version.
    nixpkgs.follows = "a14/nixpkgs";
  };

  outputs = { nixpkgs, a14, ... }: {
    nixosConfigurations.a14 = nixpkgs.lib.nixosSystem {
      modules = [
        a14.nixosModules.default
        ./hardware-configuration.nix
        ./configuration.nix

        {
          hardware.asus.zenbookA14.firmwareSource = ./firmware;
        }
      ];
    };
  };
}
```

Keep your own disk, bootloader, user and desktop configuration in the imported files. The module selects ARM64 and the custom kernel automatically, so remove any competing `boot.kernelPackages` assignment. If using systemd-boot, ensure `boot.loader.systemd-boot.installDeviceTree = true;` is enabled.

For an existing flake, you can keep your current `nixpkgs` input. The hardware module uses its own pinned build dependencies; leave its Nixpkgs input pinned for the initial setup.

**Using Git?** The `./firmware` example requires those files to be tracked in the local flake source. To keep the binaries outside a public configuration repository, use the [private firmware input example](docs/firmware.md#keep-firmware-outside-your-configuration-repository).

Build the configuration for your next boot:

```bash
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

After it succeeds, reboot to load the selected kernel. Keep a previous working boot generation available while testing. See the [example configuration](examples/installed/) and [module options](docs/hardware.md) for desktop setup and optional hardware settings.

## Build an installer ISO

On a Linux machine with Nix and flakes enabled:

```bash
git clone https://github.com/chrispouliot/linux-zenbook-a14-arm.git
cd linux-zenbook-a14-arm

# Set this to your extracted firmware directory.
a14_firmware_dir="$HOME/a14-firmware"

nix run .#firmware -- validate "$a14_firmware_dir" --strict

nix build .#iso \
  --override-input windows-firmware "path:$a14_firmware_dir" \
  --no-write-lock-file -L
```

The ISO appears in **`result/iso/`**. On an ARM64 Linux machine it builds natively; on an x86_64 Linux machine it cross-compiles an ARM64 installer. Cross builds can take considerably longer. Strict firmware validation checks the known reference files; the [firmware guide](docs/firmware.md) explains how to handle another firmware version.

To install:

1. Write the ISO to a spare USB drive using a disk-image writer.
2. Boot its UEFI entry on the A14 with Secure Boot disabled.
3. Follow the [installation guide](docs/installation.md) to prepare your Linux partitions, copy the module and firmware to the target configuration, and run `nixos-install`.

The installer includes the supplied firmware at `/etc/a14-firmware`. The guide shows how to copy it into the installed configuration so it remains available after removing the USB drive. The ISO contains your Windows firmware; keep it private unless you have permission to redistribute those files.

You can also expose an ISO from your own flake:

```nix
packages.aarch64-linux.iso = a14.lib.mkIso {
  firmwareSource = ./firmware;
};
```

For an x86_64 Linux builder, use `packages.x86_64-linux.iso` and add `buildSystem = "x86_64-linux";` inside the same call.

## Included patches

These are the project's additions to the pinned Glymur kernel, including device-tree and audio files and the changes applied directly by `kernel.nix`. Some display workarounds remain experimental. The SCMI mailbox patch and fixed-address ramoops diagnostics are **opt-in**; other retained DP diagnostics remain part of the baseline.

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
| [`a14-scmi-mailbox-set-test.patch`](patches/a14-scmi-mailbox-set-test.patch) — opt-in | Tests CPU performance requests through SCMI mailbox messages instead of fast-channel writes. It is not a proven performance fix. |
| [External DP1 link limit](kernel.nix#L73) | Caps the affected external DisplayPort controller at 2.7 Gbit/s per lane as a link-training workaround. |
| [Stereo speaker backend](kernel.nix#L110) | Restricts the WSA backend to two channels while retaining the existing four-channel audio frontend. |
| [Keyboard Fn-lock support](kernel.nix#L195) | Enables Fn-lock for the Zenbook keyboard, with media/brightness keys used directly and Fn for F1–F12. |
| [PMIC GLINK event logging](kernel.nix#L271) | Logs received and processed USB-C/display events to diagnose ordering and combined notifications. |
| [Display hotplug interrupt containment](kernel.nix#L415) | Suppresses repeated IRQ-only notifications on the affected external port while retaining real plug/unplug events. |
| [Display connection and resume handling](kernel.nix#L477) | Avoids duplicate display discovery, cleans up failed connections, and forces external DP PHY reinitialization after suspend. |
| [DisplayPort bandwidth calculation](kernel.nix#L594) | Checks modes against actual physical-link capacity instead of treating the internal wide-bus optimization as extra bandwidth. |
| [AUX wrong-data-count handling](kernel.nix#L663) | Completes malformed AUX transfers with an error so DRM can retry promptly instead of waiting for a timeout. |
| [Glymur PHY programming corrections](kernel.nix#L793) | Uses orientation-aware DP programming and preserves the required AUX configuration value during PHY startup. |
| [PHY startup diagnostics](kernel.nix#L812) | Adds register and timeout diagnostics, including an extended 50 ms C_READY wait for investigating startup failures. |
| [PHY and link-clock error handling](kernel.nix#L738) | Propagates startup failures and unwinds PHY power when a later stage fails, reducing invalid teardown sequences. |
| [USB-C power-domain retention](kernel.nix#L1257) | Keeps both USB-C controller and combo-PHY power domains on across suspend to avoid controller faults and stalled display resume. |
| [Retained display disconnect events](kernel.nix#L1368) | Preserves a pending disconnect before the latest reconnect state, using stable worker snapshots and matching bridge replay. |
| [SAFE-detach workaround](kernel.nix#L1591) — experimental | Defers shared-PHY reinitialization during a USB-C SAFE notification, leaving normal USB/DP teardown to release it. |
| [Live display check before link enable](kernel.nix#L1677) — experimental | Checks that an external display still responds over AUX before restoring its link, and cleans up if it has disappeared. |
| [Audio UCM and speaker routing](modules/audio.nix) | Removes nonexistent speaker paths, maps stereo audio to the populated channels, and provides configurable speaker gain. |
| [HDMI audio hotplug helper](modules/audio.nix) | Creates an HDMI output only while connected, keeping disconnected HDMI from breaking internal audio discovery. |
| [USB and audio autosuspend rules](modules/default.nix) | Keeps the affected SoundWire device and selected VIA USB hubs awake to avoid wake/reconnect problems. |
| [Kernel configuration](kernel.nix#L10) | Enables platform drivers and diagnostic support, and disables Rust for the pinned snapshot's Rust/RCU build mismatch. |
| [Ramoops crash capture](modules/ramoops.nix) — opt-in | Adds the original reserved-memory crash logger and collection helper, only for the specifically validated 32 GiB memory layout. |
| [Installer device-tree support](vendor/README.md) | Adds the board device tree to the ISO and its GRUB boot entries so the installer starts with the correct hardware description. |

</details>

See [hardware notes and options](docs/hardware.md), [validation status](docs/validation.md), and [source provenance](docs/provenance.md) for details. The ISO build and physical boot still need validation; successful configuration evaluation alone does not establish installer compatibility.
