# A14 board-v2 combined backport

Based on Bjorn Andersson's supplied v2 A14 UX3407NA board series, posted
base `68142f986ff04b2b70b31db00f719bf690f64a9a`. The kernel stays pinned at
`51231839d5ef007638bd1c3500e6a76b337a66f3`. The initial repository baseline
was `755981a9c61132082aba68b07cd9b6359779aaa3`.

Stage 1 supplied power, USB repeater and EC reset changes. The incremental
`a14-board-v2-stage2.patch` adds the remaining board changes and their
PCIe/audio dependencies together, for one rebuild and reboot. Apply stage 2
on top of stage 1. This is an adapted backport, not a verbatim cherry-pick.

## Included changes

| Area | Combined result |
| --- | --- |
| PHY and reference supplies | Correct USB-C, HDMI-path and multiport PHY supplies; TCSR reference-generator 3/4 supplies; always-on shared L15; touchpad supplies. |
| USB repeaters | Two PTN3222 devices at i2c5 addresses 0x43/0x4f, their supplies and multiport USB2 PHY links, plus first USB-C repeater supplies. |
| EC | Reserve GPIO 65 for EC reset. |
| PCIe/NVMe | Backport the Glymur multiphy driver and binding from the posted base, switch the A14 to port B of `pcie3_phy`, and add both reference-generator supplies. Include the driver in the initrd. |
| Wi-Fi/Bluetooth | Replace the fictitious WCN7850 PMU/regulators with the M.2 connector and PCIe/UART power-sequencing graph. Keep QCC2072 firmware selection. |
| Speakers | Describe only the two real swr0 codecs as `SpkrLeft`/`SpkrRight`; remove the nonexistent swr3 speakers. Adopt a two-channel frontend, matching UCM and PipeWire mapping. |
| Microphones | Two DMIC routes, DMIC0/1 pins, 2.4 MHz mic clock, and the upstream two-channel/S32_LE VA backend configuration. |
| LEDs | Describe keyboard camera/microphone indicators and camera privacy LED. Keep the V4L2 sensor connected to the privacy LED. |
| Memory | Describe a 256 MiB default CMA pool and enable CMA support. |
| Cleanup | Remove empty `chosen` and the touchscreen reset pin's forced `output-high`. |

The board compatible binding and QSEECOM allowlist entry already exist in
our pinned kernel, so there is nothing to apply for the other two emails.
The eDP dependency is already represented by the pinned/local display stack.

## Backport adaptations

- `patches/board-v2/01` through `03` are retained from stage 1. `04` adds the
  PCIe driver/binding; `05` completes the board description. The recipe
  runs after the existing platform/display recipe and before camera/video
  board fragments.
- `a14-pcie-multiphy.dtsi` carries the needed SoC node, GCC clock inputs and
  PCIe3b PHY reference **only for the A14**. The old PCIe3b PHY is disabled
  on this board; other Glymur boards retain their existing provider. The
  unused PCIe3a controller is not added. The driver itself comes unchanged
  from the posted base.
- The pinned M.2 driver's automatic Bluetooth-ID table lacks this QCC2072
  card. Keep an explicit `qcom,qcc2072-bt` UART child and 3.2 Mbaud setting;
  the existing HCI driver obtains power through the new UART graph. Do not
  remove that identification just because upstream's board omits it.
- Regulator labels keep their old names for compatibility with the camera
  fragment. Camera support still selects 100 kHz on shared i2c5; without
  camera support the board uses 400 kHz. Privacy LED and pinctrl definitions
  now live in the base board so the camera fragment does not duplicate them.
- UCM files are from [alsa-ucm-conf PR 858](https://github.com/alsa-project/alsa-ucm-conf/pull/858),
  commit `c9d323590229951391433ed88ae2061df897ff2b`, over our pinned
  alsa-ucm-conf 1.2.16.1. The existing working card-name symlink selects the
  dedicated A14 configuration instead of modifying generic four-speaker files.
- The topology adopts [audioreach-topology PR 78](https://github.com/linux-msm/audioreach-topology/pull/78),
  commit `54304cb2630f65d57dec57bd9cd72d263e896e72`, while retaining our
  MultiMedia5/DisplayPort2 HDMI backend. It stays installed at the firmware
  path expected by our pinned driver. The speaker backend's existing
  two-channel fix remains. PipeWire now uses `[ FL FR ]`, not four slots.
- The upstream UCM's microphone `Format S32_LE` and topology's S16_LE
  capture frontend/S32_LE VA backend are retained as posted. Recording
  still needs hardware verification with this DSP/userspace combination.

## Existing workarounds and remaining uncertainty

USB-A power retention, display retries, eDP HBR limit, external DP1 rate
limit, DP/DSC fixes, SCMI polling, camera/video support and HDMI hotplug
handling remain. The user's configured speaker gain also remains.

Keep `gcc_glymur.a14_usba_keep_power` at its normal enabled default. The
submitted resume log with `gcc_glymur.a14_usba_keep_power=0` showed USB-A
xHCI/SMMU failures and coincided with internal-display blinking. This
backport is not evidence that the blinking or that USB failure is fixed.

The cover letter says Bjorn needed `pm_runtime_forbid()` on swr0 on his
linux-next tree. That implementation is **not in the supplied series** and
is not added here. It is not established that our pinned kernel needs it.
Playback start/stop, idle, and resume testing will determine whether our
new audio configuration exposes the same problem. Existing retries do not
make unconditional changes such as USB power retention automatically stop.

## Apply and boot-test

Run inside the hardware repository after applying stage 1. Start with no
uncommitted edits to the files stage 2 changes other than the stage 1 patch.
The outer patch updates this Nix repository; do not apply it to Linux itself.

```bash
git apply --whitespace=nowarn --check ~/Downloads/a14-board-v2-stage2.patch
git apply --whitespace=nowarn --index ~/Downloads/a14-board-v2-stage2.patch
git diff --cached --stat
```

`--index` also stages new files for Git-backed Nix flakes. No commit or push
is performed. `--whitespace=nowarn` preserves embedded patch context lines.

For a personal NixOS flake whose hardware input is named `a14` and whose
host output is also `a14`, run from this patched hardware checkout:

```bash
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
```

Use your actual input name, host output and configuration path if different.
A remote GitHub input does not automatically use local edits. Expect a full
kernel rebuild despite the unchanged kernel version. Reboot into the new
boot generation, leaving the previous working generation available. Future
rebuilds need the override until these changes are published and your input
is updated.

Test cold boot/NVMe, Wi-Fi with the internal screen active, Bluetooth,
touchpad and keyboard indicators. Test speakers at a modest volume, confirm
left/right output, stop playback, wait for idle and start again; test mic
recording and camera/privacy LED. Then test suspend/resume, repeat audio and
wireless tests, and test USB-A, both USB-C ports and HDMI audio/display.
LED nodes alone do not guarantee desktop mute-key integration.

Capture a log after a failure, before rebooting:

```bash
sudo journalctl -b -k --no-pager > ~/a14-board-v2-stage2-kernel.log
```

For a boot/resume regression, select the previous generation in systemd-boot.
To undo just stage 2 before making later repository edits:

```bash
git apply --whitespace=nowarn --reverse --check ~/Downloads/a14-board-v2-stage2.patch
git apply --whitespace=nowarn --reverse --index ~/Downloads/a14-board-v2-stage2.patch
```

## Validation

Checked on 2026-09-16 against the pinned source:

- Replayed the default initial kernel patches, camera/video patches, and
  platform/display/board/camera/video recipes with zero fuzz and no failed
  hunks or offsets. This does not include inherited Nixpkgs patches or the
  optional SCMI mailbox patch.
- Compiled the A14 DT with camera/video enabled and with both disabled.
  DTC 1.7.0 reports 38/37 warnings respectively: the prior 36/35 plus two
  `graph_child_address` warnings for the upstream M.2 endpoint numbering.
- Inspected the DTB for multiphy port B and supplies, disabled legacy PHY,
  M.2 graph links, QCC2072 identity, two speaker names, disabled swr3,
  mic clock, CMA, LED pinctrl/camera linkage, retained HDMI and eDP limits,
  and shared-bus clock settings.
- Compiled the new PCIe driver object using host x86_64 COMPILE_TEST against
  the pinned kernel headers. This is an API/build check, not an ARM64 build.
- Built the combined AudioReach topology with m4 and alsatplg. Parsed the
  A14 UCM and 13 included files with ALSA's config parser against the pinned
  UCM tree; checked static include resolution. This cannot verify hardware
  mixer controls or actual audio operation.
- Parsed changed Nix files for syntax. Checked the incremental repository
  patch against an exact stage 1 snapshot.

Full Nix evaluation, a complete ARM64 kernel build, binding-schema validation
and stage 2 hardware testing have not been performed. The legacy display
verifier still covers its original recipe, not this board/audio backport.
