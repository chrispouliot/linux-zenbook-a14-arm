# A14 review theories — experiment v1

Baseline: the captured sink-cleanup v1 kernel recipe and dock boot-recovery v4,
from a14-sink-cleanup-boot.tar.gz. Pinned upstream source:
linux-msm/laptops-kernel 51231839d5ef007638bd1c3500e6a76b337a66f3.
This is an experimental local patch, not an upstream fix or hardware-validated release.

## What this installs

One incremental patch with three independent, boot-time module parameters.
Default installation enables ONLY the first-AUX probe. Existing experiments,
link frequencies, DSC settings and recovery service remain as captured.

| NixOS option under hardware.a14DpReviewTest | msm parameter | Default |
|---|---|---|
| firstAuxProbe | a14_dp_first_aux_probe_test | true |
| boundedCleanup | a14_dp_bounded_cleanup_test | false |
| edpBppInit | a14_edp_bpp_init_test | false |

All three code defaults are false. The imported NixOS module supplies explicit
0/1 values. Parameters are read-only after load. Enable another experiment in
your own NixOS configuration, rebuild the boot configuration and reboot. That
parameter-only change should reuse the compiled kernel.

### First AUX probe

On the UX3407NA Glymur external controller af54000 (laptop port one), while
power_on is false, call drm_dp_dpcd_probe(aux, 0xf0000) before the receiver reads
in HPD and detect, and before D0/preflight in full atomic enable. Runtime power,
PHY initialization and existing AUX transfer gates remain in force. Excludes
eDP, other controllers, other boards and a running stream.

This is based on the LTTPR-before-DPRX ordering in the pinned tree's
intel_dp_read_dprx_caps(). It does not write repeater mode or reset USB/UCSI.
The probe is best-effort: its negative return is logged and existing detection
continues. It uses the normal DRM helper, including its retry budget; it is not
a one-hardware-transaction or fixed-wall-clock-time guarantee. Multiple setup
phases can each probe. Existing independent AUX clients/HPD requests are not
serialized into a new global state machine by this experiment.

Expected log: A14-first-AUX: phase=hpd|detect|enable probe=0xf0000 ret=0 ...
A successful probe alone does NOT prove subsequent link training succeeded.

### Bounded cleanup (off initially)

DSC stop and failed-link sink cleanup can use one native write and one verifying
read per register (DSC_ENABLE, FEC_CONFIGURATION), stopping at the first error,
DEFER, short ACK or mismatched readback. All transfers use the AUX mutex,
powered-down guard and existing driver callback. Host teardown continues on
failure. Normal sink preparation retains its existing retries.

This bounds the added DSC/FEC cleanup to at most four driver transfers; it does
not bound mutex acquisition, driver-internal waits, the earlier training-pattern
clear, the rest of teardown or the system's overall latency. PHY compliance
requests retain the old path. Gate also requires the existing A14 DSC-wake gate.

### eDP bpp initialization (off initially)

Tracks EDP-COLOR-01: boot showed 18 bpp, wake 24 bpp on the same panel/timing.
Save the requested mode bpp before mode_set's initial bandwidth reduction.
After the powered eDP capability read succeeds, recompute panel information
from that saved request before on_link/on_stream. Do not try to power the panel
early or fabricate capability values. Reject a zero/insufficient capacity or
failed setup instead of programming an unverified stream. Scope is A14 internal
controller af6c000, non-test, uncompressed eDP. This is still experimental and
needs its own boot/wake comparison; it does not alter ICC profiles or gamma.

Expected log for the captured native panel:
A14-eDP-bpp: requested=24 before=18 selected=24 rate=270000 lanes=2 fits=1
On later wakes before may already be 24. Inspect dp_debug for actual live bpp.

The early mode-validation diagnostic can still mention capacity=0: this change
finalizes the depth after capabilities become available, not during mode probing.

## Install

Run as your normal user; no backup is created. The installer checks the exact
captured recipe, patch/module hashes and pinned upstream revision before writing.
It refuses unexpected local edits, is idempotent, and supports --check/--remove.

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-review-theories-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-review-theories-test.patch experiments/a14-review-theories

git -C ~/Projects/linux-zenbook-a14-arm diff --stat
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Reboot after a successful build. Do not identify this build by uname alone: the
release string remains unchanged. Verify parameters and booted kernel path.

```sh
for p in a14_dp_first_aux_probe_test a14_dp_bounded_cleanup_test a14_edp_bpp_init_test; do
  printf '%s: ' "$p"
  cat "/sys/module/msm/parameters/$p"
done
readlink -f /run/booted-system/kernel
```

Expected first test: Y, N, N.

## First test: boot detection only

Keep the Amazon dock, laptop port one and current plug orientation. Keep the
same saved external mode (prefer the existing 1080p60 diagnostic setting).
Leave the monitor in standby at reboot; do not manually wake it to mask the
initialization problem. Keep the lid open and run the recorder using the
internal display. Existing boot recovery v4 remains part of the baseline.

After boot, record whether external display, Ethernet and internal login work.
Capture BEFORE manual unplug/replug, disabling/re-enabling displays, suspend,
or monitor/dock power cycling. No standby or hot-unplug stress test is needed
until we review this boot result.

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-review-theories/capture.py \
  ~/Projects/linux-zenbook-a14-arm \
  ~/a14-first-aux-boot.tar.gz
```

The recorder takes journals/DRM state before its read-only AUX register sampling;
AUX reads can still affect device power/state. It performs no reset or modeset.
Choose a new output name for each capture. If manual recovery is needed before
you can run it, say exactly what you did; do not describe it as a clean boot.

## Later comparisons (do not enable all at once)

To test cleanup in a subsequent boot, add to your normal NixOS configuration:

```nix
hardware.a14DpReviewTest.boundedCleanup = true;
```

To test colour depth separately, in a later boot:

```nix
hardware.a14DpReviewTest.edpBppInit = true;
```

Use false to disable either. To compare the new probe against the captured
baseline without recompiling the kernel:

```nix
hardware.a14DpReviewTest.firstAuxProbe = false;
```

For these local NixOS option changes run nixos-rebuild boot and reboot; the a14
input only needs updating when the a14 repository itself changes. Do not set
duplicate msm parameters manually alongside these options.

## Remove / rollback

Boot your previous generation if needed. To remove this experiment from the
repo, first remove any hardware.a14DpReviewTest assignments from your own config,
then run the same installer with --remove, refresh the a14 input and rebuild.
No earlier experiment is removed. The installer refuses removal if its owned
files were edited; restore those particular edits before removal.

## Deliberately deferred theories

No forced aa->55->aa reset; no transparent-mode fallback; no hardware timeout
register changes; no FEC/DSC sequencing rewrite; no failed-link hotplug worker.
Those need separate evidence and active-link/lifetime handling. The current
failed-enable/GNOME freeze issue is not claimed fixed by any of these changes.

## Validation and limits

ARM64 compilation/linking of drivers/gpu/drm/msm/msm.o against the reconstructed
patched tree. Host C tests exercise the actual extracted helpers' AUX reply/error
handling, guards, cleanup limits, first-probe scope and eDP capacity selection.
Installer tests cover exact baseline/refusal, idempotence, rollback and clean
removal; patch application checked with zero fuzz and no offsets.
No full NixOS evaluation/build or hardware execution is available here. Hardware
boot, standby, suspend and 4K144 reliability remain unverified for this patch.
