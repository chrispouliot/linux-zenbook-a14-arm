# A14 display issues to retain across experiments

Updated 2026-09-09. These are open issues, not confirmed fixes.

## EDP-COLOR-01: internal OLED changes from 6 to 8 bits per color after standby

User observation: the ChatGPT textbox intermittently has a grey outline on the
internal OLED, not the external display. It was visible before this standby
cycle and disappeared after wake. A causal connection to color depth is plausible
but not established; browser/compositor rendering and display processing have
not been isolated.

Evidence from the same kernel boot:

| Internal eDP-1 | Working boot / before standby | After standby wake |
| --- | --- | --- |
| Controller | af6c000.displayport-controller | same |
| Mode | 1920x1200 @ 60 Hz, 154260 kHz | same |
| Link | HBR 270000 x two lanes | same |
| Configured bpp | 18 (6 bits per RGB component) | 24 (8 bits per RGB component) |
| Link levels in dp_debug | voltage 2, pre-emphasis 1 | same |

The boot log selects internal `updated bpp = 18` at 5.232768 seconds.
After standby it selects `updated bpp = 24` at 495.198659 seconds. The before/after
eDP dp_debug snapshots independently agree. External remains 3840x2160@144,
uncompressed 18 bpp across this cycle. Do not confuse its separate bandwidth
limitation with the internal display's color-depth change.

At 154260 kHz, RGB24 requires 3.70224 Gbit/s; HBR x2 provides 4.32 Gbit/s of
8b/10b payload capacity. The observed internal 24-bpp mode fits this link.
The driver's bpp selection uses mode/EDID data, link capability information and
a separate compliance-video-test path. We have not yet identified which input
caused the first boot selection to differ. Investigate initialization ordering,
validity of the link information used for bpp selection, and compliance-test
state rather than simply forcing a value without checking the selection path.

The existing eDP retry helper is gated on native 24-bpp mode. It does not select
color depth and did not run for the initial 18-bpp mode in this capture; it did
run successfully after the 24-bpp wake. Preserve this distinction when assessing
internal display recovery.

Next work: diagnose the bpp selection inputs at boot and wake, then make selection
consistent for the native internal mode. If the outline recurs, a screenshot
plus a photo of the screen can help investigate its relationship to rendering
and physical output. Do not infer a changed ICC profile/gamma curve solely from
bpp, and do not claim this is a ChatGPT server-side UI change.

Source captures:
- `a14-config-reuse-boot-two.tar.gz`, library_file_id
  `libfile_8a811e1cddf481919fc55594bf784173`
  SHA256 `9c1276bbb837563a788eba074c82856b3a1ab7dc924d12fb9bf99ec51816f8d6`
- `a14-config-reuse-direct-standby.tar.gz`, library_file_id
  `libfile_f930cb001b948191bf5bc12fa41f8d88`
  SHA256 `240283f37b4eb640710648962168d906393f67b47ee3c06baf0c30ad9386c373`

## DP-WAKE-02: direct connection repeater mode reverts during standby

Direct cable on laptop port one, one detected repeater, HBR3 x4, no DSC.
At boot live LTTPR mode is aa and training succeeds. At 111.236238 seconds it
still reads aa. Standby D3 is accepted at 306.929816 seconds; D0 is verified at
495.448627 seconds. Before wake training the live mode reads 55, while the driver
retains count=1. It proceeds to train LTTPR1 individually, gets zero status and
fails clock recovery. The record contains no intervening driver mode write.
Mode reversion is observed; whether monitor sleep, D3 or some other event causes
it is not yet established.

The repeater-restore experiment addresses this specific state mismatch. It does
not establish a fix for the dock's configuration-write timeouts, where live mode
was already aa. Test the direct path first.

## DP-FAIL-03: failed external enable leaves display-controller timeouts

The display pipeline can keep waiting for frame/vblank completion after DP link
enable fails. Desktop lag varies. This needs proper driver failure recovery;
successful AUX/repeater recovery does not by itself fix this failure handling.

## DP-COLOR-04: direct four-lane 4K144 currently uses 6-bit uncompressed output

The experimental DSC selection requires two lanes. Direct HBR3 x4 therefore
selects uncompressed RGB18 for the 1333330-kHz mode. Full-color DSC over four
lanes remains separate follow-up work after wake behavior is understood.
