# Direct 4K144 DSC, v1

The captured DP-1 direct connection selected 3840x2160 at 144.050 Hz,
1333330 kHz, HBR3 x4 and 18 source bits/pixel without DSC. At 4K60 it selected
30 bits/pixel and the reported grey UI border disappeared. This implicates the
mode-dependent color path; it does not prove monitor calibration or gamma.

The existing DSC selection admitted only two lanes. Patch 5 adds four-lane HBR3
to the existing exact 4K144 whitelist and updates the trained-link guard.
Target: RGB8 (24 source bits/pixel), DSC8 (8 compressed bits/pixel), four
960-pixel slices and FEC. The existing DSC and DSC144 parameters must be enabled.
This does not add RGB10 DSC, HDR support, or color calibration.

Scope remains the UX3407NA af54000 controller (the tested DP-1 / port-one path).
Two-lane dock DSC, four-lane uncompressed 4K60, eDP depth, repeater modes,
USB/USB4 negotiation and userspace dock recovery are unchanged.
This does not solve the separate BIOS315 USB4 dock regression.

## Validation and test

Before distribution: reconstruct the recorded source with the repository verifier,
compile the changed MSM driver for ARM64, and exercise DSC selection and
four-lane transfer-unit calculations. Hardware validation remains pending.

Keep the monitor directly on laptop port one. Start at the working 4K60 mode,
update the a14 flake input, rebuild and reboot. Select 3840x2160 at 144 Hz in GNOME.
Capture with tools/a14-display-capture.py. Expected: DP-1 HBR3 x4, 24 bpp,
and A14-DSC-test configured RGB8 DSC8 plus successful DSC/FEC enable in the journal.
dp_debug bpp is source depth; it is not the compressed DSC bitrate.
Compare the grey border and dark gradients with 4K60. A changed bpp alone does
not demonstrate correct gamma or range. Test standby only after stable output.

If output fails, select 4K60 on the internal display, or boot the previous NixOS
generation. The installer --remove reverses only its exact edits and refuses
ambiguous or modified patch contents. Git history remains the source backup.
