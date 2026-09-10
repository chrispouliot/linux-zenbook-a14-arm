# A14 two-repeater reset experiment v1

Incremental experiment against a14-first-aux-direct-standby.tar.gz's captured
local repository. Upstream kernel remains linux-msm/laptops-kernel
51231839d5ef007638bd1c3500e6a76b337a66f3.

## Why this test

The first-AUX probe succeeded in dock boot but LINK_BW_SET/LANE_COUNT_SET writes
still timed out. Direct boot trained successfully. Direct 1080p60 standby then
recovered after one initial repeater-probe timeout, another FEC-read timeout and
the existing 55->aa restore. That does not establish the probe alone fixed wake.

This new behavior tests whether deliberately creating the non-transparent ->
transparent transition clears state in the two-repeater dock chain. It is a
hardware-affecting experiment, not a diagnostic-only build. No claim that dock
firmware is the sole cause, or that this will fix Ethernet or login freezing.

## Changes

### Reset (new parameter msm.a14_dp_repeater_reset_test)

Only ASUS UX3407NA, Glymur controller af54000 (laptop port one), the existing
A14 DSC-wake gate, a cached chain of exactly two repeaters and a two-lane link.
No USB vendor matching is required. Direct one-repeater connections, eDP, other
controllers and PHY compliance requests bypass the new reset.

Run once per full msm_dp_ctrl_on_link(), after main-link clocks are available,
but BEFORE normal sink preparation, FEC setup and main-link enable. Never add
this reset to link_train(): that also runs during on_stream/active maintenance.

Before AUX mode writes:
- Skip if stream clocks are on.
- Require core/link clocks on for MMIO.
- Skip if the transmitter's MAINLINK_CTRL_ENABLE bit is set.
- Read and validate live common capabilities: valid revision, two repeaters,
  mode 55 or aa. Reject unknown/mismatched live topology rather than writing.

If live mode is aa: write/verify 55, then write/verify aa.
If live mode is 55: establish/verify aa, then write/verify 55, then write/verify aa.
Read common capabilities again and require two repeaters in aa. Update only the
cached mode byte; keep existing lane/rate/capability policy and normal training.

Stop the sequence at its first error and take the existing failed-link teardown
path. Do not train while reset/verification is incomplete. No automatic
transparent-mode fallback, recovery loop, or extra outer training retry.
Normal DRM AUX helpers retain their own retries; one logical sequence can
therefore contain multiple attempts for an individual register transaction.
This is not a guaranteed fixed wall-clock-time bound.

Expected log on the captured dock:
A14-repeater-reset: begin mode=aa count=2 mainlink=... stream=0
A14-repeater-reset: aa->55 ret=0
A14-repeater-reset: 55->aa ret=0
A14-repeater-reset: verified reset; normal sink setup/training follows

A skip is not a failed reset, nor evidence the reset theory was tested. Read the
reason. Successful mode writes alone do not establish successful display output.

### Diagnostics (new parameter msm.a14_dp_aux_diag_test)

For native transactions covered by the existing A14 AUX-wake gate, measure the
msm_dp_aux_cmd_fifo_tx() call and sample REG_DP_AUX_STATUS immediately after it
returns, before this transfer path resets AUX or reads the receive FIFO.
On an error, log address, request, size, FIFO return value, elapsed_us, raw
status_return, last ISR, decoded existing driver error, TIMEOUT_COUNT and LIMITS.

The existing interrupt handler has already run when a hardware completion is
received. status_return is NOT an IRQ-latched snapshot. elapsed_us includes FIFO
setup, interrupt latency and scheduling; it is NOT wire time or GO-to-IRQ time.
Register fields remain uninterpreted. These samples alone cannot prove whether
the chain was silent or a hardware DEFER-retry budget expired. No timeout limits,
retry policy, ISR behavior or AUX reset behavior are changed.

## NixOS switches

| Option | Default | Parameter |
|---|---|---|
| hardware.a14RepeaterResetTest.enable | true | msm.a14_dp_repeater_reset_test |
| hardware.a14RepeaterResetTest.auxDiagnostics | true | msm.a14_dp_aux_diag_test |

Both C defaults are false; the module explicitly supplies 0/1 values. The earlier
firstAuxProbe remains true, boundedCleanup false and edpBppInit false on the
captured baseline. Config-reuse remains disabled. Existing DSC, HBR limits,
repeater restore, USB patches and boot-recovery v4 are retained.

Disable the new reset while keeping diagnostics by adding to your normal NixOS
configuration:

```nix
hardware.a14RepeaterResetTest.enable = false;
```

Then nixos-rebuild boot and reboot. This option-only comparison should reuse the
compiled kernel. Avoid duplicate hand-written module parameters.

## Install and build

This installer checks the latest captured recipe, all patch/module hashes and
upstream source pin. It refuses unexpected edits before writing and creates no
backup. It supports --check, repeated installation and --remove. New kernel
source files only change through an appended patch after the existing recipe.

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-repeater-reset-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-repeater-reset-test.patch experiments/a14-repeater-reset

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

After success, shut the laptop down before changing cabling. Put the Amazon dock
on laptop port one and move the monitor cable back to the dock's USB-C output.
Keep the previous dock port/cable orientation, lid open and monitor in standby.
Keep display settings as they were for the failed dock comparison. The earlier
captures initially selected 4K144 before changing to the user's 1080p60 mode;
do not describe this as a pure 1080p boot test unless logs establish that.

## Verify and capture

After boot, expected values are Y, N, N, Y, Y in this order:

```sh
for p in a14_dp_first_aux_probe_test a14_dp_bounded_cleanup_test a14_edp_bpp_init_test a14_dp_repeater_reset_test a14_dp_aux_diag_test; do
  printf '%s: ' "$p"
  cat "/sys/module/msm/parameters/$p"
done
```

Take the capture before manual replug, monitor/dock power cycling or another
suspend. If login freezes and recovery is required to run the recorder, record
what you did; the journal still preserves the earlier boot sequence.

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-repeater-reset/capture.py \
  ~/Projects/linux-zenbook-a14-arm \
  ~/a14-repeater-reset-dock-boot.tar.gz
```

Report external output, Ethernet and internal/login responsiveness separately.
No standby/hot-unplug stress test is requested before this boot is reviewed.
The recorder preserves journals before read-only AUX sampling. Reads can affect
power/state; it performs no reset or modeset. Use a new output name each time.

## Rollback

A previous boot generation remains available. To remove this experiment, first
remove any hardware.a14RepeaterResetTest assignments from your own configuration,
then run this installer with --remove, refresh a14 and rebuild boot. It removes
only its patch/module/recorder/docs and integration blocks. Earlier experiments
are retained. Modified owned files cause refusal rather than silent deletion.

## Unresolved issues and scope

- GDM-to-user-session page flips fail even with successful direct link training.
  This experiment does not claim to fix that problem.
- EDP-COLOR-01 remains: 30 bpp requested, initial 18 bpp, later 24 bpp. The optional
  eDP bpp experiment stays off. Its fallback handling needs separate revision.
- Dock USB3/Ethernet disappeared during resume in the prior dock capture. This
  code does not reset USB/UCSI or change Ethernet behavior intentionally.
- Transparent-only training remains a separate future comparison if needed.

## Verification performed

ARM64 compilation and linking of drivers/gpu/drm/msm/msm.o. Actual extracted C
helpers exercised for aa and 55 sequences, verification/short-read failures,
first-error termination, cached/live topology checks, inactive/clock guards,
one-repeater/gate exclusions and cache updates. Integration ordering checked.
Installer baseline/refusal/idempotence/rollback/removal and exact patch application
checked. No complete NixOS build/evaluation or hardware validation is available
here. GCC/installer success does not prove the reset fixes the dock.
