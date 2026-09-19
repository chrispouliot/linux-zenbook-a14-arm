# A14 DSC blanking experiment 3: D3 before PUSH_IDLE

Apply this incremental repository patch on top of experiments 1 and 2, with the
corrected kernel/a14-dsc-blank-test.nix string from experiment 2. Keep all three
kernel patches installed. Only the third runtime experiment should be enabled.

Prepared against repo c6865d3 plus the two delivered experiments. The pinned
kernel remains 51231839d5ef007638bd1c3500e6a76b337a66f3. This addition does not
edit kernel.nix, existing display patches, or board-v2 integration.

## Why another location

Experiment 2 executed but the flash remained. Its D3 request occurs in bridge
post-disable, after PUSH_IDLE and DPU encoder shutdown. The compression:0x0 log
covers DP-controller configuration, not every source-side DSC block. Experiment 3
moves the receiver power request to the earlier bridge atomic_disable callback,
just before PUSH_IDLE and before DPU disable. The rest of the pipeline still
follows its normal shutdown callbacks. The hypothesis remains unconfirmed.

## Behavior and scope

New read-only parameter: msm.a14_dp_early_d3_test, default 0.

For a connected A14 port-one stream, the helper checks the existing board/port,
wake, sink-power, sink-cleanup, DPCD revision, and PHY-test guards. It also requires
configured DSC and enabled stream/link clocks. The bridge's aborted-enable guard
remains in front of the new helper.

On a qualifying shutdown:

1. Read receiver power and request D3 while the compressed source is intact.
2. After acknowledgement, wait 20-25 ms, then perform the existing PUSH_IDLE.
3. Let the existing DPU timing/DSC cleanup run.
4. Perform late host-side DP DSC/FEC cleanup without another receiver D3 request
   or receiver DSC/FEC writes. Host link/PHY shutdown still runs.

The settling interval is experimental, not a protocol-mandated delay or proof
that the monitor has muted. It adds roughly 20-25 ms on qualifying success;
scheduling can add more. Modesets and suspend using this same callback are also
affected. No new AUX accesses are made for disconnected/aborted enables.

If the initial power read fails, no early write happened: log the failure and
continue with the old shutdown path. If the D3 write fails or is short, remember
that it may have reached the receiver, skip the settling delay, and still run
PUSH_IDLE and later host cleanup. In that case suppress duplicate power-down and
receiver compression accesses in these cleanup paths. A disconnect between early
and late callbacks is also covered by the host-cleanup and off_link_stream guards.
Unrelated asynchronous HPD/AUX handling is not globally disabled by this patch.

Checked D0 and receiver DSC/FEC clearing on the next start remain. Early-write
state is reset for the new power-up/link lifecycle. Experiments 1/2 retain their
previous behavior when the third flag is off.

## Apply

Save a14-dsc-early-powerdown-experiment.patch to ~/Downloads. Then:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-dsc-early-powerdown-experiment.patch
```

Only if that succeeds:

```bash
git apply --whitespace=nowarn ~/Downloads/a14-dsc-early-powerdown-experiment.patch
nix-instantiate --parse kernel/a14-dsc-blank-test.nix >/dev/null
```

If either check fails, send the error; do not force application. The patch adds
one kernel patch, this document, and one line inside the Nix integration string.
It does not stage, commit, push, or edit your system configuration.

## Enable and build

Manually replace the previous experimental entries in your existing
boot.kernelParams list with these three entries. Keep unrelated parameters.
Do not duplicate the same parameter with conflicting values.

```nix
"msm.a14_dp_defer_sink_clear_test=0"
"msm.a14_dp_d3_before_dsc_test=0"
"msm.a14_dp_early_d3_test=1"
```

The existing a14_dp_dsc_wake_test, a14_dp_sink_power_test and
a14_dp_sink_cleanup_test flags must remain enabled; leave those settings alone.

```bash
cd ~/Projects/linux-zenbook-a14-arm
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
```

Another kernel build and reboot are required. The explicit path override includes
new files without Git staging/committing and does not update flake.lock. It is
only for this invocation: repeat it for subsequent experiment builds. Substitute
your actual input name if it differs from the repository-documented `a14`.

## Check and capture

After reboot:

```bash
cat /sys/module/msm/parameters/a14_dp_defer_sink_clear_test
cat /sys/module/msm/parameters/a14_dp_d3_before_dsc_test
cat /sys/module/msm/parameters/a14_dp_early_d3_test
```

Expected: N, N, Y. A missing third parameter means the new kernel is not running.

Test 4K144 lock -> complete monitor standby -> wake. Capture immediately:

```bash
sudo journalctl -b -k --since "5 minutes ago" -o short-monotonic --no-pager |
  rg -i 'A14-DSC-blank|A14-DSC-wake|A14-DP-power|compression:|idle_patterns|underflow|timedout|wait disable|timeout|failed'
```

Expected external shutdown sequence:

```text
A14-DSC-blank3: D3 accepted before PUSH_IDLE; settling with source intact
idle_patterns_sent
A14-DSC-blank3: late host-only cleanup; no second D3 request
A14-DSC-blank: deferring sink DSC/FEC clear until next start
compression:0x0
```

The old A14-DSC-blank label is shared host-cleanup logging; it can appear while
experiment 1 is disabled. The blank3 marker proves the early request ran. An
initial-read or early-write failure is separately logged and is not a successful
test of the early-D3/settling hypothesis. Idle messages alone may also come from
other outputs, so retain the timestamps and nearby markers.

Report whether the flash changed, whether wake worked, and the log. If normal,
then test 4K60 blank/wake, 1080p60 and back, and one suspend/resume. Watch for new
wait-disable/idle timeouts as well as display recovery; do not treat absence of a
flash alone as proof the shutdown is correct.

## Rollback

Set msm.a14_dp_early_d3_test=0, leave the other experiment flags at 0, repeat the
same build and reboot. A flag-only change can reuse the cached compiled kernel.
For an unusable boot, select the preceding NixOS generation in systemd-boot.

To remove experiment 3's repository changes:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --reverse --check ~/Downloads/a14-dsc-early-powerdown-experiment.patch
```

Only if that succeeds:

```bash
git apply --reverse --whitespace=nowarn ~/Downloads/a14-dsc-early-powerdown-experiment.patch
```

Remove its new boot parameter and rebuild/reboot. Experiments 1/2 remain
installed. Remove in reverse order if removing the whole experiment stack.

## Verification performed

The kernel patch applies to the reconstructed experiment-2 source with zero fuzz
or offsets, matches the intended three source files, and reverses to its inputs.
The original dp_ctrl.h and dp_display.c were checked against the repository's
source-hash manifest. The incremental repository delivery applies/reverses on
top of both earlier corrected deliveries.

Nix tree-sitter grammar parsing passed for the integration file and kernel.nix;
this is syntax checking, not Nix evaluation. The parser also rejected the malformed
string pattern from the previous packaging error.

A C harness compiled actual extracted bridge-disable, early-powerdown, DSC-stop
and sink-power functions with mocked hardware operations and warnings as errors.
It passed 28 event-sequence assertions covering early order, retention of source
DSC until late cleanup, negative/short transfers, duplicate suppression, direct
host cleanup, wake D0, guards, and the previous two runtime modes. The harness
does not validate kernel concurrency or real hardware behavior.

No full kernel compilation, NixOS evaluation, or A14 hardware test was performed
here. Existing baseline source verifiers do not cover these added experiments.
