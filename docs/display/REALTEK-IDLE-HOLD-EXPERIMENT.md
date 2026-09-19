# Realtek post-idle diagnostic hold

The direct A14 connection blanks cleanly at 4K144 DSC with both four and two
HBR3 lanes. WAVLINK's Realtek `00:e0:4c` / `Dp1.4\0` branch flashes with the
two-lane stream. macOS through the same dock also blanks cleanly at 4K144.
The earlier three shutdown-order experiments did not remove the flash.

This diagnostic separates source idle from subsequent DPU/DSC/FEC and power
teardown by an adjustable pause. It is not a confirmed fix.

## Native-HPD correction

The initial diagnostic incorrectly required `msm_dp_aux_is_link_connected()`
to return nonzero. This function reads the controller's native HPD status,
which the earlier A14 captures show as zero even with working USB-C video.
The installed parameter could therefore show 1000 while the pause was skipped.
The failed run had idle at 155.544085 and source cleanup at 155.552974, about
9 ms later, with no BEGIN/END messages. It did not test the proposed hold.

The correction removes that inappropriate native-HPD predicate. The bridge
still checks software `plugged` before calling the helper, and the normal AUX
transfer function retains its disconnect gate. The exact Realtek identity must
still be read successfully. Other skip conditions now produce explicit logs.

If the original patch is already installed, save the incremental
`a14-realtek-idle-hpd-fix.patch` in `~/Downloads` and apply:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-realtek-idle-hpd-fix.patch
git apply --whitespace=nowarn ~/Downloads/a14-realtek-idle-hpd-fix.patch
```

Keep the same boot flags: four older experiments off and
`msm.a14_dp_realtek_idle_hold_ms=1000`. Rebuild using the local path override
below, reboot, and repeat the WAVLINK blank test. This correction changes the
existing inner kernel patch, so it adds no new Nix recipe entry or parameter.

## What changes

The connected bridge's atomic-disable callback already calls PUSH_IDLE and
waits for its completion interrupt. The new helper runs immediately afterward,
before the callback returns. In the pinned DRM atomic-helper sequence, the DPU
encoder's atomic-disable runs after bridge atomic-disable; receiver and source
DSC/FEC cleanup and D3 happen later, in bridge post-disable.

With the diagnostic enabled, the helper reads nine bytes at DP_BRANCH_OUI
(0x500) and requires the exact captured Realtek identity. It logs BEGIN, sleeps
for the requested interval, logs END, then allows the existing sequence to
continue. It makes no new AUX writes or controller-register writes. An idle
interrupt is a source-side event; it does not prove the branch has already
blanked its downstream output.

Parameter: `msm.a14_dp_realtek_idle_hold_ms`, unsigned milliseconds, default 0,
root-writable at runtime. Values greater than 1000 are capped at 1000 for the
actual pause. The parameter is sampled once per invocation. Zero bypasses the
helper without even performing the branch-identity read.

Additional guards require:

- Existing A14 DSC-wake board/port check (UX3407NA, Glymur DP, af54000);
- Software-connected link, successful PUSH_IDLE completion, configured DSC, and enabled
  core/link/stream clocks;
- A branch receiver, HBR3 link rate 810000, two active lanes;
- No PHY compliance test or recorded early D3;
- All three older shutdown-order experiments disabled.

Direct sinks, uncompressed streams and link-training PUSH_IDLE calls do not
receive this pause. Matching compressed modesets can pause too, so disable the
diagnostic after testing. This test leaves the source DPU/DSC/FEC configured
during the pause, but video transmission has already transitioned to idle.

## Install

This incremental delivery expects the previous direct-two-lane experiment and
all three shutdown experiments to be installed. It adds a fifth patch to
`kernel/a14-dsc-blank-test.nix`. Its kernel source baseline was reconstructed
from the recorded source manifest and those three shutdown patches.

Save `a14-realtek-idle-hold-experiment.patch` in `~/Downloads`, then:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-realtek-idle-hold-experiment.patch
git apply --whitespace=nowarn ~/Downloads/a14-realtek-idle-hold-experiment.patch
```

Update the following entries in your existing `boot.kernelParams` list. Keep
unrelated flags, including the original DSC/wake enablement flags, intact.

```nix
"msm.a14_dp_defer_sink_clear_test=0"
"msm.a14_dp_d3_before_dsc_test=0"
"msm.a14_dp_early_d3_test=0"
"msm.a14_dp_direct_two_lane_test=0"
"msm.a14_dp_realtek_idle_hold_ms=1000"
```

Build from the local repository and reboot:

```bash
cd ~/Projects/linux-zenbook-a14-arm
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
sudo reboot
```

## Test on WAVLINK

Use the dock at 3840x2160@144 with the internal display disabled. Confirm:

```bash
cat /sys/module/msm/parameters/a14_dp_defer_sink_clear_test
cat /sys/module/msm/parameters/a14_dp_d3_before_dsc_test
cat /sys/module/msm/parameters/a14_dp_early_d3_test
cat /sys/module/msm/parameters/a14_dp_direct_two_lane_test
cat /sys/module/msm/parameters/a14_dp_realtek_idle_hold_ms
```

Expected: N, N, N, N, 1000.

Run the same timed direct blank/wake command:

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

Observe whether the flash occurs immediately with picture disappearance, about
a second after picture disappearance, or does not occur. Also note if the
picture stays visible through the pause; the monitor's visual transition may
not coincide with the source entering idle.

Collect logs after blanking and waking:

```bash
sudo journalctl -b -k --since "3 minutes ago" -o short-monotonic --no-pager |
  rg -i 'A14-Realtek-idle|A14-DSC-blank|A14-DP-power|compression:|idle_patterns|underflow|timedout'
```

A valid enabled test must include both `A14-Realtek-idle: BEGIN 1000 ms hold`
and `A14-Realtek-idle: END hold`, separated by about one second. The expected
order is idle completion, BEGIN, END, then the usual cleanup/power messages.
A parameter value of 1000 without BEGIN/END is not evidence the hold ran.
Identity read failure, mismatch, or enabled older experiments skips the hold.

For a same-kernel comparison, set zero and repeat the blank command once:

```bash
echo 0 | sudo tee /sys/module/msm/parameters/a14_dp_realtek_idle_hold_ms
```

This change takes effect on the next matching disable and needs no rebuild or
reboot. It does not interrupt a pause already underway. Re-enable if needed:

```bash
echo 1000 | sudo tee /sys/module/msm/parameters/a14_dp_realtek_idle_hold_ms
```

Interpretation is provisional:

- Immediate flash despite a confirmed hold: later DPU/DSC/FEC/D3 cleanup is
  unlikely to be the trigger; focus on the transition to idle or earlier work.
- Flash delayed until the end of the hold: focus on later cleanup/link removal.
- Clean with hold, flash with zero: allowing the idle state time to propagate
  changes the outcome; a shorter interval can then be tested without rebuilding.

## Disable / rollback

Set the runtime value to zero to remove the diagnostic pause immediately for
future blanking operations. Set the boot parameter to zero or remove it on the
next rebuild to make that persistent. Keep the earlier boot generation if the
experimental kernel cannot drive the display normally.

To remove just this patch, remove its boot parameter, then:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --reverse --check ~/Downloads/a14-realtek-idle-hold-experiment.patch
git apply --reverse ~/Downloads/a14-realtek-idle-hold-experiment.patch
```

Rebuild with the local path override and reboot. Earlier experiment patches
remain installed but can stay disabled.

## Validation

The controller, header and bridge baseline was checked by reversing the three
older experiments and matching the resulting files against the captured
`docs/display/source-sha256.json`, then reapplying those experiments.

The new kernel patch applies and reverses exactly without fuzz or offsets. The
Nix integration parses with the tree-sitter Nix grammar and all five referenced
patch files exist. The actual new helper and its board/port predicate compile
in a stubbed C harness with `-Wall -Wextra -Werror`. The corrected harness covers guard
failures, conflicting experiments, AUX errors and short reads, every identity
byte, bounded delay, one-time parameter sampling, and unchanged controller
state. Regression cases separate native HPD from software AUX availability:
native HPD zero with a successful identity read must pause, while a software
disconnect must fail the read and skip the pause. Callback placement was checked against the pinned DRM atomic helper.
The delivery patch was checked for exact application and reversal on the
four-experiment repository baseline.

No full Nix evaluation, kernel build, or A14 hardware test was performed here.

Relevant source reviewed:

- https://github.com/linux-msm/laptops-kernel/blob/51231839d5ef007638bd1c3500e6a76b337a66f3/drivers/gpu/drm/drm_atomic_helper.c
- https://github.com/LineageOS/android_kernel_qcom_sm8250/blob/lineage-20/techpack/display/msm/dp/dp_ctrl.c

The Qualcomm-derived SST shutdown path also uses PUSH_IDLE; this research did
not establish a separate supported no-video/mute register for this hardware.

The incremental native-HPD fix was also checked for application and reversal
against the installed v1 repository files. No full kernel build was performed.
