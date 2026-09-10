# A14 sink-state cleanup experiment v1

The current 1080p60 capture shows a real fresh uncompressed modeset (30 bpp),
but the driver still chooses HBR3 x2. It fails writing the same rate/lane pair.
The receiver's FEC_CONFIGURATION remains 01 from the earlier failed DSC enable;
DSC_ENABLE is 00. This test therefore did not start with clean FEC state.

The local source explains the leak: DSC preparation sets FEC_READY before link
training, but training failure tears down the host without clearing sink FEC.
The regular DSC-stop helper returns early if dsc_configured is false, and the
next uncompressed enable skips the DSC-only sink preparation.

This patch fixes those two gaps behind msm.a14_dp_sink_cleanup_test=1:
- On a full port-one start, perform existing checked D0/DSC/FEC preparation for
  uncompressed modes as well as compressed modes.
- After failed link training, clear and verify sink DSC/FEC before PHY teardown.
  A sink access error is logged; host teardown continues.

Scope remains A14 af54000 and the existing a14_dp_dsc_wake_test gate. PHY compliance
requests receive no new preparation or cleanup. The new preparation does not run
while stream clocks are on. When the new parameter is off, previous behavior is
preserved. There are no additional link-training retries, rate changes, repeater
mode cycles, or UCSI resets. Existing AUX helper retries still apply to accesses.
The original FEC_READY-before-training order is unchanged.

This addresses an observed cleanup defect, not a proven cause of the initial
boot rate/lane write timeout. Initial 4K144 boot can still fail. Both earlier
awake and standby boots failed identically. A failed attempt followed by a clean
1080p modeset is the useful next comparison.

Keep the direct-connection repeater restore enabled, config reuse disabled, and
v4 boot recovery as installed. EDP-COLOR-01 remains separately tracked in
experiments/a14-repeater-restore/OPEN-ISSUES.md. This patch does not affect eDP.

## Install

Run the downloaded installer as your normal user, not sudo:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-sink-cleanup-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-sink-cleanup-test.patch experiments/a14-sink-cleanup

git -C ~/Projects/linux-zenbook-a14-arm diff --stat
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

This requires a kernel build. Keep automatic blanking and suspend off during
build. The installer creates no backups or commits, validates the captured local
patch baseline and pinned source revision, and preserves existing patches. Use
--check for read-only validation or --remove to remove only this experiment.
Handled write failures roll back; abrupt termination is not an atomic multi-file
transaction. Removal refuses modified experiment-owned files.

## First test

Reboot after the build succeeds. Keep the Amazon dock on port one in normal
orientation, with no dock storage and no replugging during capture.

Verify:

```sh
cat /sys/module/msm/parameters/a14_dp_sink_cleanup_test
```

It must print Y. Capture the initial boot whether the display works or not:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-sink-cleanup/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-sink-cleanup-boot.tar.gz
```

If the external display remains black, set it to 1920x1080 at 60 Hz in GNOME,
Apply, keep the internal screen enabled, and capture again without rebooting:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-sink-cleanup/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-sink-cleanup-1080p.tar.gz
```

If GNOME reverts the mode, capture anyway. If 1080p was already selected, disable
only the external monitor and Apply, then enable it at 1080p60 and Apply to get a
fresh start. Keep the internal monitor enabled. Do not add a standby test yet.
Upload the captures and report visible output, Ethernet, and desktop responsiveness.

The logs should contain A14-DP-cleanup preparation/failure markers. On an
uncompressed before-config snapshot FEC should be 00; on a failed compressed
attempt it can be 01 before configuration but should be cleared on failure.
A successful compressed link legitimately has FEC=01. A failed clear will report
its error and is not treated as success.

## Validation

Actual changed C helper tests cover compressed/uncompressed starts, active stream
exclusion, experiment gate, PHY-test exclusion, preparation errors, cleanup errors,
and unchanged gate-off DSC behavior. Call-site checks verify cleanup occurs before
mainlink teardown. ARM64 msm.o compilation and installer/patch application tests
are performed locally. Full NixOS build and hardware behavior require the laptop.
