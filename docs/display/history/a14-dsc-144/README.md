> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 4K144 DSC extension v1

Requires the installed, hardware-tested A14 DSC 4K60 experiment. This is a
small additional patch to dp_panel.c; it does not replace that experiment.
The owner confirmed a usable 4K60 DSC desktop and working Ethernet, with
DSC_ENABLE=01 and FEC decode activation in the captured registers.

## What this changes

Adds the boot-only parameter `msm.a14_dp_dsc_144_test=1`. Both it and the
existing `msm.a14_dp_dsc_test=1` must be enabled. Only the captured port-one
controller on UX3407NA is eligible.

The two-slice 4K60 timing remains available. The extension also accepts the
monitor's existing EDID 3840x2160@144.050 Hz timing: 1333330 kHz;
horizontal 3840/3848/3880/4000, vertical 2160/2300/2308/2314. It requires
four-slice sink capability and uses four 960x108 slices, RGB8 source and
8 bits/pixel DSC. Two DPU hardware DSC encoders each process two slices.

At 8 bpp, the timing budget including the existing 3% margin is approximately
10.987 Gbit/s, below HBR3 x2's 12.96 Gbit/s payload. It does not fit HBR2 x2.
The DP interface clock is 666.665 MHz, below the existing 675 MHz guard.
The DPU mode check asks for about 700 MHz including its 5% factor; the
pinned Glymur device tree lists a 717 MHz operating point. Actual clock
setup remains a hardware test; no limits, OPPs or voltage settings are raised.
The existing clock/bandwidth/trained-link checks remain enabled.

USB Gen1, Ethernet, PHY settings, port-two HBR2, boot recovery v3, eDP and the
kernel release string are unchanged by this extension. No 95 Hz or custom
120 Hz timing is enabled by this patch.

## Install

Keep the dock on laptop port one and the monitor connected to the dock.
Run as your normal user:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dsc-144-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-dsc-144-test.patch experiments/a14-dsc-144

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Keep the laptop awake until you reboot after the successful build.
The installer adds a second NixOS module to the existing test module imports.
If your configuration consumes only the kernel package rather than the
repository's default NixOS module, append `msm.a14_dp_dsc_144_test=1` to your
existing boot.kernelParams list yourself.

## Hardware test

After reboot, verify both parameters:

```sh
cat /sys/module/msm/parameters/a14_dp_dsc_test
cat /sys/module/msm/parameters/a14_dp_dsc_144_test
```

Both should print Y. First verify 4K60 still works. Then open GNOME Settings
> Displays, select the external monitor, keep 3840x2160 and choose 144 Hz.
Only keep the change if the image is normal. If the screen goes blank, allow
GNOME's confirmation timeout to revert it. If the whole system freezes,
that timeout may not operate; boot the prior working NixOS generation.
GNOME may choose the EDID-preferred 144 Hz timing automatically at boot;
verify the actual rate instead of assuming it stayed at 60 Hz.

Do not test suspend in the same run. Report the actual displayed refresh
rate, image quality/flicker, internal-screen behavior and Ethernet result.
Capture after applying 144 Hz, or at the failure state if it is unavailable:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-dsc-144/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-dsc-144-test.tar.gz
```

Expected: a 144 Hz configuration log with pixel clock 1333330, four slices,
width 960 and height 108; trained HBR3 x2, DSC_ENABLE bit 0 set, and FEC decode
activation. A usable image is required to validate the path. If 144 Hz is
absent, upload the archive without forcing a modeline or bypassing limits.
The capture includes clock limits, DRM state, current/previous kernel
journals and read-only AUX status. No reset, mode change or hardware write
is performed by the recorder.

## Remove just this extension

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dsc-144-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Reboot after successful build. The working 4K60 experiment remains installed.
Remove a manually added 144-test parameter if applicable. To remove the
older 4K60 experiment too, remove this extension FIRST, then use that older
installer's --remove. No backups are created and no whole-file git restore
is used. --check makes no changes; applying again is idempotent. Modified
owned files are not silently overwritten or deleted.

## Checks and current limits

- ARM64 GCC compile and MSM driver object link passed against the captured
  kernel plus working DSC baseline. This is not a full NixOS build.
- Actual TU code exercised with the pinned fixed-point helper: HBR3 x2
  at 144 Hz yielded TU size 35, valid boundary 30, delay 20; HBR/HBR2 x2
  fail the budget guard. These calculations do not prove hardware operation.
- Exact-mode guard checked for 60 Hz retention, the separate 144 Hz gate,
  four-slice capability, incorrect timing and interlace rejection.
- Installer apply/check/idempotence/refusal/removal and exact patch application
  checked locally; only dp_panel.c changes relative to the tested kernel.
- 4K144 and switching between 4K60 DSC and 4K144 DSC remain untested on hardware.

## Earlier suspend/reboot log

The uploaded a14-pre-dsc-suspend.log belongs to the old system generation
aphg6j1avfddkhqj6f28hdd9imshh9bw. It contains no DSC test parameter or DSC
activation messages. Its recorded s2idle cycle enters near 3406.7 s and exits
near 3413.1 s. Later, near 6567.1 s, DP clock-recovery training times out
(-110); link enable fails (-104), followed by 263 vblank timeouts and frame
completion timeouts through the end of the log near 6599.3 s. There is no
recorded kernel panic or watchdog report establishing why the system reset.
This is an outstanding pre-DSC display recovery failure, not evidence that
the new DSC kernel caused that earlier incident. This extension does not
claim to fix suspend or reboot reliability.

The underlying DSC implementation's Qualcomm/JS Deck source attribution is
retained in the preceding 4K60 patch and its README.
