# Direct DisplayPort two-lane comparison

This diagnostic compares direct 3840x2160@144 DSC over two HBR3 lanes with
WAVLINK's two-lane DSC path. The original direct test used four lanes and
blanked cleanly; WAVLINK flashed. Keep all three shutdown experiments off.

## Baseline and scope

Prepared from the source recipes in the user's capture, reporting repository
HEAD 595cc572ff69e01079493dc3f86cae212c4558c8. The public repository was still
at c6865d3, so the captured files are the integration baseline.

This incremental patch expects the three previous experiments to be installed,
including the corrected `kernel/a14-dsc-blank-test.nix`. It adds a fourth patch
to that recipe but does not enable any of the old experiments.

The new module parameter is `msm.a14_dp_direct_two_lane_test`, default false,
read-only after module load. It changes the effective lane count from four to
two only when all these conditions match:

- ASUS Zenbook A14 UX3407NA board;
- `qcom,glymur-dp` controller named `af54000.displayport-controller`;
- receiver does not advertise a DisplayPort branch;
- ordinary HBR3 link rate (810000), without the eDP rate table;
- four effective lanes after receiver, endpoint and LTTPR capability limits.

The cap is applied before mode selection, DSC bandwidth calculations and link
training. It does not alter raw receiver capabilities, the negotiated USB-C
pin assignment, or the blanking sequence. It does not increase a lower lane
limit. With this parameter enabled, other modes on the eligible direct link
also use the two-lane limit; select 4K144 explicitly for the comparison.

## Install

Save `a14-dp-direct-two-lane-experiment.patch` in `~/Downloads`, then:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-dp-direct-two-lane-experiment.patch
git apply --whitespace=nowarn ~/Downloads/a14-dp-direct-two-lane-experiment.patch
```

Set these entries in the existing `boot.kernelParams` list in `/etc/nixos`.
Replace previous values for the same names; retain unrelated parameters,
including the existing DSC enablement parameters.

```nix
"msm.a14_dp_defer_sink_clear_test=0"
"msm.a14_dp_d3_before_dsc_test=0"
"msm.a14_dp_early_d3_test=0"
"msm.a14_dp_direct_two_lane_test=1"
```

Build the boot generation from the local repository, including the newly
created files:

```bash
cd ~/Projects/linux-zenbook-a14-arm
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
sudo reboot
```

The path override applies to this invocation; it does not update the flake lock.

## Verify and test

Connect the monitor directly to the same laptop port previously used for the
clean 4K144 test. Keep the internal display disabled and use 3840x2160@144.

```bash
cat /sys/module/msm/parameters/a14_dp_defer_sink_clear_test
cat /sys/module/msm/parameters/a14_dp_d3_before_dsc_test
cat /sys/module/msm/parameters/a14_dp_early_d3_test
cat /sys/module/msm/parameters/a14_dp_direct_two_lane_test
```

Expected: `N`, `N`, `N`, `Y`.

```bash
sudo journalctl -b -k -o short-monotonic --no-pager |
  rg -i 'A14-DP-lanes|A14-DSC|num_lanes|compression:|underflow|timedout|timeout|failed' |
  tail -n 80
```

A valid comparison requires all three:

1. `A14-DP-lanes: direct HBR3 test limiting 4 -> 2 lanes before mode selection`;
2. successful active-stream log with `rate=810000, num_lanes=2`;
3. `configured 3840x2160@144 RGB8 DSC8` (four slices), and a stable image.

`Y` alone does not prove that the lane limit applied. A missing 144 Hz mode,
failed training, or fallback to another mode makes the comparison inconclusive.
Keep the external display connected for the timed blank/wake test:

```bash
(
  gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
    --object-path /org/gnome/Mutter/DisplayConfig \
    --method org.freedesktop.DBus.Properties.Set \
    org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 3>' &&
  {
    sleep 8
    gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
      --object-path /org/gnome/Mutter/DisplayConfig \
      --method org.freedesktop.DBus.Properties.Set \
      org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 0>'
  }
)
```

Afterward, collect the same filtered journal output and report whether the
white flash occurred and whether the picture returned normally.

- Clean direct two-lane DSC strengthens the case for a dock/driver interaction.
- A flash appearing on direct two-lane DSC points toward the A14's two-lane
  transmission path or the monitor's response to it.

This does not reproduce the dock's USB3 pin assignment, electrical path or
receiver firmware. It isolates active DP lane count more closely, without
proving which component is at fault.

## Disable or remove

To disable, set `msm.a14_dp_direct_two_lane_test=0`, rebuild with the same local
path override and reboot. The earlier boot generation is also available if
this experimental generation cannot drive the monitor normally.

To remove this incremental patch, first remove its boot parameter, then:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --reverse --check ~/Downloads/a14-dp-direct-two-lane-experiment.patch
git apply --reverse ~/Downloads/a14-dp-direct-two-lane-experiment.patch
```

Rebuild and reboot. This leaves the three earlier experiment patches installed.

## Validation performed before delivery

- Reconstructed `dp_panel.c` from the pinned kernel and recorded patch series;
  SHA-256 matched the captured source manifest:
  `9342273bbbdb3550b127a850290a534da56994bb33587a0ea63971b16026c406`.
- Kernel patch applies and reverses byte-for-byte without fuzz or offsets.
- Compiled the actual lane-limit and mode-selection functions in a stubbed C
  harness with `-Wall -Wextra -Werror`: 384 guard combinations passed, the
  captured 4K144 timing retained RGB8/DSC on four and two lanes, and a one-lane
  connection was not promoted.
- Parsed the modified Nix integration using the tree-sitter Nix grammar and
  checked that all referenced patches exist.
- Checked application and reversal of the delivery patch against the captured
  repository baseline.

No full Nix evaluation, kernel build, or A14 hardware test was performed here.
