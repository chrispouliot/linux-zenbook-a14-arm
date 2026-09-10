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
| `camera.enable` | `true` | Camera drivers, board description, libcamera and the udmabuf rule; turning it off rebuilds the kernel |
| `diagnostics.unrestrictedDevmem` | `false` | Builds without STRICT_DEVMEM so acpidump can read the firmware ACPI tables; rebuilds kernel |
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

## Camera

The front camera is enabled by default; `camera.enable = false` removes the
drivers, the board description and the userspace pieces. The older
`experimental.camera.enable` name is still accepted. It works on the UX3407NA: 1920x1092 at 30 fps through the software ISP on the
GPU, tested with `cam` and GNOME Snapshot, and the privacy LED lights while
the sensor streams.
Three parts are involved:

- **Driver backports** (`patches/camera/`): fifteen commits taken from
  linux-msm `topic/glymur-laptops` and the September 2026 upstream Glymur
  camera series, rediffed against the pinned snapshot. They add the generic
  Qualcomm CSI2 PHY driver and the PHY core helpers it needs, teach CAMSS to
  drive PHYs through the PHY API and accept the Glymur compatible, add PM8010
  support to the PM8008 MFD and regulator drivers, and add the Glymur CAMSS,
  CSIPHY, CCI and MCLK nodes to the SoC device tree. Glymur's camera block is
  a subset of the X1E80100 one, so the CAMSS driver change is small.
- **Board description** (`patches/a14-camera.dtsi`): the OV02C10 sensor at
  0x36 on CCI1 bus 1, MCLK4, reset on GPIO 239, CSIPHY4 with two lanes, a
  PM8010 camera PMIC at 0x08 on i2c5 with reset on GPIO 106, and the camera
  privacy LED on GPIO 111, which the V4L2 core lights while the sensor
  streams. This is the Zenbook A16 and CRD wiring. The A14's own firmware
  tables confirm the PMIC address and bus (device PML0 on the controller at
  0xb94000), the LED GPIO (device CAMP), and the CSIPHY set (device MPCS); the
  PMIC and sensor both probed on hardware. The firmware does not describe the
  PMIC reset GPIO or the sensor's LDO mapping, so those remain the A16 values.
  The firmware also enables a second sensor device, CAMI, presumably the IR
  camera for Windows Hello; it is not wired up.
- **Userspace** (`modules/camera.nix`): libcamera and v4l-utils, with PipeWire
  and WirePlumber kept on. CAMSS produces raw Bayer frames; libcamera's simple
  pipeline handler and software ISP convert them, and applications use the
  camera through PipeWire. Firefox needs `media.webrtc.camera.allow-pipewire`.
  The module also gives the `video` group access to `/dev/udmabuf`, which the
  software ISP needs for its buffers. Without it WirePlumber, which enumerates
  the camera at login, can run before logind's seat ACL exists, the ISP setup
  fails and the PipeWire camera offers no formats, so applications report no
  camera. Your user must be in the `video` group. If that happens anyway,
  `systemctl --user restart wireplumber` recreates the node.

Kernel configuration: the pinned kernel already builds CAMSS, CCI, the camera
clock controller, the PM8008 drivers and the OV02C10 driver as modules; the
option adds the new `PHY_QCOM_MIPI_CSI2` module and pins the rest explicitly.

### First test on the device

1. `dmesg | grep -i -E 'camss|csiphy|csi2|cci|pm8010|ov02c10'` for probe
   messages.
2. `i2cdetect -y <i2c5 bus number>` should show 0x08 (the bus number appears in
   `ls -l /sys/bus/i2c/devices | grep b94000`). Nothing there means the PMIC
   bus or its reset GPIO is wrong.
3. A sensor chip-ID error means power is present but a rail or the reset GPIO
   is wrong. A CCI transfer timeout means the sensor is unpowered or on the
   other bus.
4. `media-ctl -p`, then `cam -l` and `cam -c1 -C10`. Afterwards `wpctl status`
   should list an `ov02c10` libcamera source, and `pw-cli enum-params <id>
   EnumFormat` on that source should print RGB formats. An empty format list
   means the software ISP did not start inside WirePlumber; check
   `journalctl --user -b -u wireplumber` for SoftwareIsp or DmaBufAllocator
   errors.

### If it does not probe: dump the ACPI tables

The Windows firmware describes the camera PMIC (I2C address, controller and
reset GPIO), the camera GPIOs including the privacy LED, and the CSIPHY in the
DSDT. On this device-tree boot the tables are only reachable through
`/dev/mem`: `acpidump` cannot be used because it insists on the missing
`/sys/firmware/acpi` directory, and `STRICT_DEVMEM` blocks the read because
the firmware places the tables inside memory the kernel counts as RAM. Build
once with `diagnostics.unrestrictedDevmem = true`, boot it, then:

```bash
sudo python3 tools/a14-acpi-dump.py      # RSDP from /sys/firmware/efi/systab, writes ./acpi-tables/
nix shell nixpkgs#acpica-tools -c iasl -d acpi-tables/dsdt.dat
```

Turn the option off again afterwards. In `dsdt.dsl`, look for the camera
platform device (CCI register windows at `0x0AC15000`/`0x0AC16000` and GpioIo
pins), the I2C camera PMIC device (`I2cSerialBusV2` entries at `0x0008` and
`0x0009`, its controller name, and reset GpioIo pins) and the CSIPHY device.
Map the ACPI I2C controller to a device-tree bus by its register address.
The sensor's own power sequence is not in the DSDT; it lives in the Qualcomm
camera driver's `com.qti.sensormodule.*.bin` and `CAMF_RES_*.bin` files,
which ASUS ships in its downloadable Qualcomm board support package.
