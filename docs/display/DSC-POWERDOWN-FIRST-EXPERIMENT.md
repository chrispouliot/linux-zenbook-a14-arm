# A14 DSC blanking experiment 2: receiver power-down first

Apply this incremental repository patch ON TOP OF experiment 1. It does not
replace or remove experiment 1's source files. It modifies only that experiment's
kernel/a14-dsc-blank-test.nix integration and adds a second kernel patch and this
document. kernel.nix, the board-v2 changes, and existing display patches stay as-is.

Baseline tested: public repo c6865d3efc5b0652a994b9f4b57aff2633e987d1 plus the
updated a14-dsc-blank-experiment.patch. The kernel remains pinned to
51231839d5ef007638bd1c3500e6a76b337a66f3.

## Hypothesis and behavior

The first experiment executed but did not eliminate the flash. macOS blanks
cleanly through the same dock at 4K144. This supports testing Linux's compressed
stream shutdown order, but does not prove equivalent DSC negotiation on macOS.

The new parameter is msm.a14_dp_d3_before_dsc_test, disabled by default.
With it enabled, a qualifying A14 port-one compressed shutdown does:

1. Complete the existing PUSH_IDLE operation.
2. Request receiver D3 while host DSC/FEC remains configured.
3. After successful acknowledgement, wait 20-25 ms.
4. Disable host FEC/DSC without accessing receiver DSC/FEC registers.
5. Continue the existing link/PHY shutdown.

This tests both ordering and a short settling interval. The interval is an
experimental allowance for receiver muting, not a DisplayPort timing requirement
or a guarantee that the receiver has muted. It adds approximately 20-25 ms to
qualifying successful shutdowns (scheduler delays may increase that).

The existing wake, sink-power and sink-cleanup gates must be enabled. The stream
must be compressed, its clocks on, and PUSH_IDLE successful. Existing board/port,
DPCD revision and PHY-test guards remain. Modesets and suspend using this same
path are affected too; the change is not exclusive to GNOME lock.

A failed or short D3 transaction still forces host-only cleanup, without waiting
or probing the receiver again. The request could have taken effect even if AUX
reports an error. Host cleanup is never skipped by this experiment. Checked
receiver clearing on the next start remains unchanged, including uncompressed
starts through the existing sink-cleanup gate. Failed-link cleanup is unchanged.

## Apply

Save a14-dsc-powerdown-first-experiment.patch in ~/Downloads.
Experiment 1 must still be installed in your repository.

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-dsc-powerdown-first-experiment.patch
```

Continue only on success:

```bash
git apply --whitespace=nowarn ~/Downloads/a14-dsc-powerdown-first-experiment.patch
```

If the check fails, stop and send the error rather than forcing application.
No Git staging, commits, pushes, or flake.lock changes are made by these commands.

## Enable and build

Replace the previous experimental boot-parameter entry with these two entries
inside your existing boot.kernelParams list. Avoid duplicate entries for either
parameter. Retain all unrelated entries and the existing DSC/wake/power settings.

```nix
boot.kernelParams = [
  "msm.a14_dp_defer_sink_clear_test=0"
  "msm.a14_dp_d3_before_dsc_test=1"
];
```

The second experiment does not require the first experiment's runtime flag;
it independently defers receiver clearing in its new power-down path. Disabling
the first flag makes the result easier to interpret.

```bash
cd ~/Projects/linux-zenbook-a14-arm
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
```

This requires another kernel compilation. Reboot after the build succeeds.
The local path override includes the new files without Git staging or committing.
The override applies only to this invocation; repeat it for experiment rebuilds.
Use your actual flake input name if it differs from the repo-documented `a14`.

## Verify and test

```bash
cat /sys/module/msm/parameters/a14_dp_defer_sink_clear_test
cat /sys/module/msm/parameters/a14_dp_d3_before_dsc_test
```

Expected: N, then Y. Missing second parameter means the new kernel is not running.
The existing a14_dp_dsc_wake_test, a14_dp_sink_power_test and
a14_dp_sink_cleanup_test parameters should remain Y.

Select 4K144. Lock, let the monitor enter standby, then wake and unlock.
Report the flash and whether the image returns normally. Capture immediately:

```bash
sudo journalctl -b -k --since "5 minutes ago" --no-pager |
  rg -i 'A14-DSC-blank|A14-DSC-wake|A14-DP-power|compression:|idle_patterns|underflow|timedout'
```

Expected shutdown order:

```text
idle_patterns_sent
A14-DP-power: D3 write accepted before PHY shutdown
A14-DSC-blank2: D3 accepted; settling before source stop
A14-DSC-blank: deferring sink DSC/FEC clear until next start
compression:0x0
```

The older A14-DSC-blank log label is reused by the host-cleanup helper even with
the first flag set to 0. The A14-DSC-blank2 marker identifies experiment 2.
If D3 fails, expect the new 'D3 failed; forcing source cleanup' marker instead.
That case did not test successful receiver power-down/settling.

If the initial test works, check 4K60 lock/wake, changing to 1080p60 and back,
and one normal suspend/resume. Keep all other monitor/dock settings constant.

## Rollback

To disable experiment 2, set its boot parameter to 0, repeat the same build
command and reboot. Leave experiment 1 at 0 to return to the original runtime
behavior; set experiment 1 to 1 only to reproduce the first experiment.
Changing only these flags should reuse the cached compiled kernel.

For an unusable new boot, choose the previous NixOS generation in systemd-boot.

To remove only experiment 2's repository changes:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --reverse --check ~/Downloads/a14-dsc-powerdown-first-experiment.patch
```

Only if that succeeds:

```bash
git apply --reverse --whitespace=nowarn ~/Downloads/a14-dsc-powerdown-first-experiment.patch
```

Remove its new boot parameter and rebuild/reboot as appropriate. Experiment 1
remains installed. Reverse experiment 2 before trying to remove experiment 1.

## Validation

The second kernel patch applies to the reconstructed experiment-1 dp_ctrl.c with
zero fuzz/offsets, produces the intended source, and reverses byte-for-byte.
An extracted-function C harness compiled with warnings treated as errors tested
18 cases covering D3/settle/host order, negative and short AUX transfers,
mandatory error cleanup, no receiver accesses after the D3 attempt, experiment
off, eligibility guards, uncompressed shutdown, and unchanged D0 behavior.
The harness uses mocked hardware operations and does not validate hardware timing.
The incremental delivery patch applies/reverses cleanly over experiment 1.

No full kernel compilation, NixOS evaluation, or A14 hardware testing was possible
here. The recorded display baseline remains untouched; its existing verifier
is not a validation of these extra experimental patches.
