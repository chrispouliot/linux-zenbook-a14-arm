# A14 DSC blanking experiment

Prepared against linux-zenbook-a14-arm commit
c6865d3efc5b0652a994b9f4b57aff2633e987d1 and its pinned kernel
51231839d5ef007638bd1c3500e6a76b337a66f3.

Observed with the WAVLINK USB 3 / DP Alt dock: 4K144 and 4K60 use DSC
and flash white at blanking; 1080p60 has dsc=0 and does not flash.
All three modes retain an 810000 link rate and two lanes. This supports a
compression-path hypothesis but does not establish the faulty component.

## What changes

The experimental patch is applied after the existing platform/display, board-v2, camera
and video postPatch stages. The recorded display patches and their source-hash
baseline remain unchanged. This experiment changes dp_ctrl.c after that baseline.

The new read-only module parameter msm.a14_dp_defer_sink_clear_test defaults to 0.
With it set to 1, the existing A14 port-one sink-power shutdown omits receiver
DSC/FEC writes only when the existing wake, sink-power and sink-cleanup gates
are enabled, the stream clocks are on, DSC is configured, and PUSH_IDLE completed.
PHY test requests keep their original path. Timeouts and failed stream starts
do not qualify. The state is cleared on a new link/stream start and before video.

Source FEC/DSC cleanup and the D3 request still happen. Checked receiver clearing
still happens before the next start, including uncompressed starts when the
existing sink-cleanup gate is enabled. Other dsc_stop callers and failed-link
cleanup retain their receiver writes. This also affects qualifying modesets or
suspend shutdowns using the same path, not only GNOME lock.

This tests receiver clearing during blanking. It does not move source DSC
shutdown or prove the monitor has muted. A remaining flash with the experiment
marker present is useful evidence for another part of the shutdown sequence.

## Apply

Download a14-dsc-blank-experiment.patch to ~/Downloads. In your existing repo:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-dsc-blank-experiment.patch
```

Continue only if that check succeeds. If it fails, send the error and your
`git rev-parse HEAD`; do not force the patch or reset your working tree.

```bash
git apply --whitespace=nowarn ~/Downloads/a14-dsc-blank-experiment.patch
git diff --check
git diff -- kernel.nix
git status --short
```

The patch changes kernel.nix and adds three files: this document,
kernel/a14-dsc-blank-test.nix, and patches/a14-dsc-defer-sink-clear-test.patch.
It does not stage, commit or push anything.

## Enable and build

Add this inside an imported NixOS module under /etc/nixos, merging with an
existing boot.kernelParams definition if it is in the same attribute set:

```nix
boot.kernelParams = [ "msm.a14_dp_defer_sink_clear_test=1" ];
```

Keep the existing DSC/wake/power/cleanup settings. Build using the modified local
repo explicitly, so a GitHub-pinned input cannot silently use the old code:

```bash
cd ~/Projects/linux-zenbook-a14-arm
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
```

The repository documentation names this input `a14`; substitute your actual input
name if different. The path override includes the new files without requiring a
Git commit or staging. It does not update flake.lock and applies only to this
build. Repeat the override for subsequent experiment builds. This changes kernel
source and requires a kernel rebuild. Reboot after a successful build.

## Test

First confirm the running kernel supports and enables the experiment:

```bash
cat /sys/module/msm/parameters/a14_dp_defer_sink_clear_test
cat /sys/module/msm/parameters/a14_dp_dsc_wake_test
cat /sys/module/msm/parameters/a14_dp_sink_power_test
cat /sys/module/msm/parameters/a14_dp_sink_cleanup_test
```

All four should print Y. A missing new parameter means the experiment kernel is
not running. Select 4K144, lock, let the monitor fully enter standby, then wake
and unlock. Note whether there is a flash and whether the image returns normally.

```bash
sudo journalctl -b -k --since "5 minutes ago" --no-pager |
  rg -i 'A14-DSC-blank|A14-DSC-wake|A14-DSC-test|A14-DP-power|compression:|idle_patterns|underflow|timedout'
```

On the qualified compressed shutdown expect:

```text
A14-DSC-blank: deferring sink DSC/FEC clear until next start
```

Source compression shutdown and D3 messages should still follow. Receiver clear
messages are expected on the next start. Without the new marker on the tested
shutdown, a change in the flash is not evidence that this experiment worked.

If 4K144 standby/wake is normal, check 4K60, changing to 1080p60 and back,
and one normal suspend/resume. The old receiver state must not break subsequent
mode changes or wake. Report the result and log before making other changes.

## Rollback

To disable the experiment while retaining the patched kernel, change its one
boot parameter to 0 (or remove it), repeat the same local-override build and
reboot. The parameter is read-only at runtime. Changing only the boot parameter
does not require another kernel compilation when the patched build is cached.

If the new boot is unusable, choose the previous NixOS generation in systemd-boot.

To remove the experiment files/integration, first check the reverse patch:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --reverse --check ~/Downloads/a14-dsc-blank-experiment.patch
```

If it succeeds, run:

```bash
git apply --reverse --whitespace=nowarn ~/Downloads/a14-dsc-blank-experiment.patch
```

Remove its boot parameter, then rebuild/reboot using your normal configuration.
A reverse-check failure means a touched file changed; do not force it. The input
lock was not modified by the supplied build command.

## Validation performed

Reconstructed dp_ctrl.c from the pinned kernel and all applicable repository
platform/display patches, with zero fuzz or offsets. Its SHA-256 matched the
repository baseline: 1bdca2b42e89ab46c7631bb41a4ae29ddfe865224ddd9494e3c9394a9e202844.
The experiment applies without fuzz or offsets, produces the intended source,
and reverses exactly to that baseline. The repository delivery patch was checked
for clean application and reversal in a separate checkout.

No NixOS evaluation, full kernel compilation, or hardware test was performed here.
The existing source-baseline verifier does not validate this extra experiment;
the application/reversal checks above do.

Updated delivery: rebased kernel.nix integration onto c6865d3; preserves the
board-v2 postPatch stage and PCIe multiphy configuration/packaging changes.
The dp_ctrl.c input and the experimental kernel diff are unchanged.
