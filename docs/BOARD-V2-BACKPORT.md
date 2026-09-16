# A14 board-v2 backport: first stage

Based on Bjorn Andersson's September 2026 v2 board DTS supplied in the
patch email, whose base is `68142f986ff04b2b70b31db00f719bf690f64a9a`.
Target: this repository at `755981a9c61132082aba68b07cd9b6359779aaa3`,
using kernel `51231839d5ef007638bd1c3500e6a76b337a66f3`.
This is a selective backport, not application of the complete v2 series.

## Included changes

1. `patches/board-v2/01-power-supplies.patch`: correct the USB-C,
   HDMI-path and multiport PHY supplies, supply TCSR reference generators
   3 and 4, keep the shared L15 1.8 V rail on, and describe touchpad supplies.
2. `patches/board-v2/02-usb-repeaters.patch`: add the PTN3222 redrivers at
   i2c5 addresses 0x43 and 0x4f, their supplies and multiport USB2 PHY links,
   plus the missing first USB-C repeater supplies.
3. `patches/board-v2/03-ec-reset.patch`: reserve GPIO 65 for EC reset.

The pinned tree already contains the PTN3222 driver and M31 PHY repeater
support. `PHY_NXP_PTN3222` is explicitly selected as a module and included
in the initrd module list so USB2 is not dependent on loading it after root
mount. Existing camera and video configurations remain enabled as before.

The kernel recipe applies this stage after the existing platform/display
recipe and before appending the camera and video board fragments. Regulator
labels retain their old names, avoiding broken references in the camera
fragment. With camera enabled, its existing 100 kHz setting takes precedence
over the redriver DTS's 400 kHz setting on shared i2c5.

## Deferred changes

Audio names, channel layout, UCM and topology; microphone routing/clock;
M.2 Wi-Fi/Bluetooth conversion; PCIe PHY binding changes; additional LEDs;
and CMA are separate stages. The board binding and QSEECOM allowlist entry
already exist in the pinned kernel. The cover letter's SoundWire
`pm_runtime_forbid()` workaround was not included in the supplied series.

Existing eDP limits, DP/DSC fixes, USB power retention, Bluetooth firmware
selection, EC support, audio/HDMI routing, and kernel/firmware pins remain.
Do not remove workarounds solely because this backport builds successfully.

## Apply and boot-test

Apply the supplied repository patch inside a checkout of
`chrispouliot/linux-zenbook-a14-arm`. Start with clean versions of the files
this patch modifies. It adds three kernel patches and integrates them into
the Nix build; do not apply the outer repository patch to the Linux source.

```bash
git apply --whitespace=nowarn --check ~/Downloads/a14-board-v2-stage1.patch
git apply --whitespace=nowarn --index ~/Downloads/a14-board-v2-stage1.patch
git diff --cached --stat
```

`--whitespace=nowarn` preserves the whitespace in embedded patch context lines.
`--index` stages the new files as well, so a local Git-backed Nix flake can
see them. This does not commit or push anything.

If your personal `/etc/nixos/flake.nix` imports this hardware repository as
the input `a14`, run the following from the patched hardware repository.
Use the actual input name if it differs. A GitHub input will not pick up a
local edit automatically.

```bash
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
```

This builds and installs the next boot generation; expect a kernel rebuild
despite the unchanged kernel version. Reboot to test it. Keep the known-good
boot generation available. The override is temporary; future rebuilds need
the same override until you commit/publish the hardware changes and update
your personal flake input.

Test internal display and touchpad, Wi-Fi traffic with the display active,
Bluetooth, speakers/HDMI, and the camera. Then test USB-A and both USB-C ports,
dock display/Ethernet, suspend/resume, and dock power loss in the situations
that previously failed. Start with the existing workarounds enabled.

For initial diagnostics after boot and again after reproducing a failure:

```bash
uname -r
sudo journalctl -b -k --no-pager > ~/a14-board-v2-kernel.log
ls -l /sys/bus/i2c/drivers/ptn3222/
```

Expect the redriver driver directory to contain links for the 0x43 and 0x4f
devices. Check the kernel log for probe failures, regulator errors and USB
errors. The kernel version string alone does not distinguish this build.
To recover from a boot/resume regression, select the previous generation
from systemd-boot. To undo the repository change before later edits:

```bash
git apply --whitespace=nowarn --reverse --check ~/Downloads/a14-board-v2-stage1.patch
git apply --whitespace=nowarn --reverse --index ~/Downloads/a14-board-v2-stage1.patch
```

## Validation

Validated on 2026-09-16 against the exact pinned source:

- Replayed the default initial kernel patches, all camera/video patches and
  the complete platform/display and board postPatch recipes: no failed hunks,
  fuzz or offsets. This was a direct replay of the repository recipes, not a
  Nix evaluation; inherited Nixpkgs patches and optional SCMI were not included.
- Compiled the full A14 device tree with GCC preprocessing and DTC 1.7.0,
  including the camera/video additions. All 36 compiler warnings match the
  otherwise identical pre-backport baseline; there are no new warnings.
- Compiled the board with camera/video disabled against the original pinned
  SoC description as well (35 warnings).
- Inspected the compiled DTB: corrected PHY supplies, redriver phandles,
  TCSR supply links, all EC/secure GPIO reservations, retained eDP HBR cap,
  and i2c5 at 100 kHz with camera or 400 kHz without it.
- Checked the outer repository patch against a clean checkout of `755981a`.

Nix evaluation, full kernel compilation, binding-schema validation and
hardware boot/resume testing were not performed. A device-tree build does
not validate electrical wiring or prove a suspend/resume fix. The existing
display-series verifier intentionally covers the retained pre-board-v2
recipe; it is not a verifier for this new stage.
