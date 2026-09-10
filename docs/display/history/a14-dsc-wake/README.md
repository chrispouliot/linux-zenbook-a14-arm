> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 DSC display-wake experiment v1

This is an additive test on the hardware-confirmed 4K60 and 4K144 DSC patches.
It targets the UX3407NA af54000 DP controller (dock on laptop port one), using
`msm.a14_dp_dsc_wake_test=1`, default off in the kernel. Both earlier DSC
parameters remain enabled. No USB/PHY/device-tree/clock/bandwidth changes.

## Evidence and hypothesis

In a14-dsc-suspend-test.tar.gz, an earlier s2idle cycle exits around 652 s and
DSC/FEC activation follows. The later blanking event stops the stream at
829.8 s. Re-enable at 854.9 s encounters AUX write timeouts at DP_LANE_COUNT_SET
and DP_DOWNSPREAD_CTRL, then clock recovery fails at 858.7 s. Repeated DPU
frame/vblank timeouts follow. The captured receiver lane count is one, whereas
the driver retains two. FEC status is 02 instead of the working 05.

The current teardown checks native HPD before clearing sink DSC/FEC. The
Type-C/PMIC GLINK connection can report native HPD=0 even while connected;
there were no sink DSC/FEC disable writes in the blanking sequence. The patch
tests whether explicitly clearing and verifying receiver state prevents that
bad re-enable. It also stops ignoring AUX setup failure. This does not prove
the initial timeout's cause or guarantee a cure for it.

## Changes

- With the test gate enabled on the exact controller, teardown attempts and
  verifies DSC/FEC disable, independent of native HPD. Host teardown continues
  even if AUX fails. The existing AUX initted/enable_xfers/runtime-PM guards
  remain intact; the patch does not force access after disconnect.
- Before a new DSC link is started, request and verify receiver power D0,
  then clear and verify sink DSC/FEC. No global or dock power reset is used.
- Verify receiver lane count and rate before training. Make at most two
  configuration attempts, with 20 ms between them. AUX's existing transaction
  timeouts still apply. Fail setup on short transfers, mismatches or errors;
  also check the downspread/coding write.
- Balance the enable PM reference and newly acquired PHY initialization when
  link enable fails, and use the existing aborted-enable marker.
  This is resource cleanup, not a complete DPU commit-timeout recovery fix.
- Logs use `A14-DSC-wake:` for clear results, verified settings and failures.

## Newly reported unplug/replug reboot

The owner reported a full-system reboot on cable unplug/replug while this
patch was being prepared. Its cause is not established by the blanking log.
This experiment does not claim to fix that reboot. Do not use hotplug as the
first test or reproduce the crash deliberately. Preserve the previous kernel
journal and pstore using the recorder below before changing kernels.
The recorder is read-only and never resets, unbinds, changes modes or clears
crash records. It also captures current link status and sink power.
Missing pstore records do not prove there was no kernel/firmware crash.

## Install and capture the existing crash before rebuilding

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dsc-wake-test.py \
  ~/Projects/linux-zenbook-a14-arm

sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-dsc-wake/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-dsc-replug-crash.tar.gz
```

The first command edits the repository only; the running kernel is unchanged.
A missing a14_dp_dsc_wake_test parameter in this pre-rebuild capture is expected.
Upload the crash archive. No intentional cable replug is needed.

```sh
git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-dsc-wake-test.patch experiments/a14-dsc-wake
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Keep the machine awake until the build finishes; reboot only after success.
The kernel release is retained for boot recovery v3. The new parameter is
imported through nixosModules.default, like the two earlier experiments.
If consuming only the kernel package, add msm.a14_dp_dsc_wake_test=1 yourself.

## First hardware test: screen blanking, lid open

After reboot, `cat /sys/module/msm/parameters/a14_dp_dsc_wake_test` must print Y.
Verify the desktop at 4K144 and Ethernet first. Save work, keep the dock and
lid unchanged, and temporarily set automatic suspend off. Allow GNOME's
one-minute screen blanking once, then wake/unlock. Do not test lid-close,
full suspend and cable hotplug in the same run. If successful, a later test
can isolate the lid-closed blanking case that originally failed.

Capture success or failure from the internal screen before resetting anything:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-dsc-wake/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-dsc-wake-result.tar.gz
```

Expected: sink clear DSC=0 FEC=0; receiver verified rate=1e lanes=82;
DSC/FEC enable messages on wake; usable 4K144 image without the timeout loop.
If the system resets, run the recorder after reboot before another test.
Use a fresh output filename for subsequent captures.

## Rollback

Boot the prior NixOS generation if the new one is unusable. To remove only
this experiment from the repo, run the installer with `--remove`, refresh
input a14, rebuild boot and reboot. It retains both earlier DSC patches and
all existing unrelated patches. Remove this experiment before removing the
144 Hz or 4K60 experiments. No backup is created; no whole-file git restore
is used. --check validates without changes. Modified owned files are refused.

## Local validation and limitations

ARM64 MSM objects compile and link against the user's pinned source plus
captured patch baseline; this is not a full NixOS build or hardware result.
Mocked AUX tests cover successful configuration, mismatched readback, short
transfers, failed writes, two-attempt bound, teardown errors, and D0 failure.
Installer checks cover baseline refusal, idempotence, exact patch application,
removal and preservation of unrelated edits. Hardware verification is pending.
