# Hardware scope and options

This is an extraction of the current working configuration, not a claim that
all X2 Elite hardware features are complete. Only the UX3407NA board is targeted.

## Retained baseline

The kernel is `linux-msm/laptops-kernel` revision
`51231839d5ef007638bd1c3500e6a76b337a66f3`, version
`7.2.0-rc5-next-20260731`, with the source project's complete `postPatch` body.
It retains USB bring-up, the populated speaker-codec mapping, internal eDP HBR
limit, external DP1 HBR limit, Fn-lock changes, DP/PHY fixes, and suspend handling.

The default module enables corrected audio routing with unity gain. The source
file named `a14-audio-left-only.dtsi` is retained literally; the accompanying
audio configuration explains that the two populated codecs map to the physical
left and right speakers despite their DT names. Do not rename/remove it based
on the filename alone.

For the initial extraction, kernel instrumentation and diagnostic-capable
configuration (pstore, DEBUG_FS, SCMI raw support) remain compiled in. Turning
off verbose boot settings does not remove every `dev_info` added by the source
patches. Converting these to a quieter patch series is a separate cleanup after
hardware validation. The fixed-address ramoops DT reservation and its userspace
helper are fully opt-in.

## Options under `hardware.asus.zenbookA14`

| Option | Default | Effect |
| --- | --- | --- |
| `firmwareSource` | `null` (must be supplied) | Directory of the 13 required firmware files |
| `audio.enable` | `true` | Topology, UCM, PipeWire, speaker routing and HDMI hotplug |
| `audio.speakerGain` | `1.0` | Gain multiplier; source owner used `1.50` |
| `experimental.scmiMailbox` | `false` | Adds the original diagnostic SCMI mailbox-write patch; rebuilds kernel |
| `diagnostics.verbose` | `false` | Adds `drm.debug=0x100`; defaults console verbosity to 7 |
| `diagnostics.ramoops32GiB.enable` | `false` | Original reserved memory and pstore helper, only for the verified memory layout |
| `usb.viaHubWorkaround` | `true` | Original VIA `2109:0817/2817` suspend/power workarounds |

The ramoops option is not a generic "all 32 GiB A14s are safe" switch. It reserves
`0xb80000000..0xb803fffff`, previously checked against the source machine's DT
and `/proc/iomem`. Enabling it on another memory layout requires validating that
reservation first. It is preserved in Chris's migration configuration only.

The source SCMI patch is an experiment, not a demonstrated performance
improvement. The migration enables it to keep Chris's kernel behavior. New
users start without it. CPU governor selection and boost preference stay in
the user's configuration.

## Integration boundaries

- The hardware module sets `boot.kernelPackages` to the pinned custom package
  set. Remove competing kernel assignments when importing it.
- `nixpkgs.hostPlatform` defaults to `aarch64-linux`. Evaluation asserts ARM64,
  but cannot probe the destination laptop model on the build machine.
- No bootloader is selected by the core module. The example selects
  systemd-boot and explicitly enables `installDeviceTree`.
- `boot.loader.efi.canTouchEfiVariables` defaults to `false` because the source
  machine rejects those writes. This does not create a new named firmware boot
  entry; the firmware must be able to boot the installed loader.
- TPM2 userspace/initrd integration defaults off, matching the source.
- The supported filesystem set preserves the original ext4/vfat/btrfs/xfs
  restriction with `mkForce`, avoiding unsupported ZFS against this kernel.
  An intentional custom set needs a stronger priority such as `mkOverride 40`
  and testing of the requested filesystem against the kernel.
- PipeWire defaults on with the audio module. Disable `audio.enable` if using a
  different audio stack; the supplied userspace routing then does not apply.
- NetworkManager is enabled in the installer/example, not by the core module.
  When used, Wi-Fi power saving defaults off as in the source configuration.
- The original HDMI helper currently uses ALSA card index 0, PCM 4. USB audio
  changing card numbering is a known integration assumption to test; it was
  retained to avoid changing audio behavior during extraction.
- Userland comes from the consuming system's nixpkgs. Hardware build-time
  dependencies use this flake's pin. An arbitrary older NixOS/PipeWire version
  is not promised compatible; start with the included pinned example.

## Updates

Update the `a14` input deliberately; its lock pins the shared module and hardware
dependencies. Avoid making this flake's nixpkgs follow a changing personal
nixpkgs input until tested. A new kernel source requires checking every patch
and every exact-match replacement in `postPatch`, building, and validating
hardware. Keeping the patch body intact is deliberate for this initial release.
