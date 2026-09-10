# A14 receiver D3/D0 sequencing experiment v1

## Evidence

Both successful and failed screen-standby shutdowns take msm_dp_ctrl_off()
with sink_count=1 and the dock still connected. That path clears DSC/FEC,
resets the controller, disables the link clocks and exits the host PHY, but
never writes DP_SET_POWER_D3 to the receiver. Only the other sink_count=0
shutdown branch calls the driver's existing power-saving helper.

In the failed wake, register 0x600 reads D0 already set. The driver writes D0
again, clears DSC/FEC, then rate/lane configuration times out. Separate writes
and the combined write both fail intermittently. This is a new power-state
sequencing hypothesis; the logs do not prove that missing D3 is the cause.

The pinned kernel's Intel driver explicitly powers down the sink before
port disable; its comment explains avoiding sink link-loss interrupts:
https://github.com/linux-msm/laptops-kernel/blob/51231839d5ef007638bd1c3500e6a76b337a66f3/drivers/gpu/drm/i915/display/intel_ddi.c
Qualcomm's existing DP sink power helpers are in dp_link.c in the same tree.

## Change

New parameter `msm.a14_dp_sink_power_test=1` (default off in C; enabled by the
included Nix module). Also requires the existing DSC-wake gate, which selects
ASUS UX3407NA and af54000.displayport-controller (port one / dock DP-1).
DP revisions below 1.1, invalid revision ff, and PHY compliance tests are skipped.

When a previously active stream is disabled with sink_count>0 and software
plugged=true, clear host/sink DSC/FEC using the existing cleanup, then read
0x600 and request D3, preserving unrelated bits. Require a complete AUX write.
Do not read back after D3 because the receiver may go to sleep. Regardless of
D3 success/failure, continue the normal controller/clock/PHY shutdown. This
also applies to connected modesets and system display teardown, not only idle.

On a fresh external enable, after AUX PHY init and before the existing sink
capability preflight, request D0, wait 1–2 ms and verify its power-state bits.
A failed/short D0 access or readback mismatch uses the existing aborted-enable
PM/PHY cleanup. The existing later D0/DSC/FEC preparation remains unchanged.
There are no extra outer retries and no override of AUX disconnect gating.

eDP retry, DSC144, AUX recovery, HPD containment, paired receiver setup, USB
settings and boot recovery remain installed. This experiment neither changes
LTTPR transparency nor retains extra PHY power references during standby.
The kernel release is unchanged for boot recovery's version guard.

A D3 ACK confirms the command was accepted, not the dock's complete internal
power state. If receiver setup still fails, the DPU timeout cascade can recur;
this experiment does not implement atomic-commit recovery. USB/Ethernet and
monitor behavior still need hardware validation.

## Install

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-sink-power-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-sink-power-test.patch experiments/a14-sink-power

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review git diff first. Leave screen blanking and Automatic Suspend disabled
during the build and reboot only after success. No backups or commits are
created. The installer checks the latest captured recipe, patches, Nix modules
and pinned source; unexpected changes are refused. --check is read-only.
Handled write failures roll back; abrupt interruption is not transactional.

## Test

```sh
cat /sys/module/msm/parameters/a14_dp_sink_power_test
cat /sys/module/msm/parameters/a14_dp_dsc_wake_test
```

Both should print Y. Keep the dock on laptop port one, lid open, and 4K144.
Confirm both displays and Ethernet at boot. If boot fails, capture immediately
with the command below but omit --delay 300; do not add another standby test.

For a working boot, leave Automatic Suspend disabled, set GNOME blanking to
one minute, then start the delayed recorder:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-sink-power/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-sink-power-standby.tar.gz --delay 300
```

The countdown begins after Nix/sudo setup and its printed announcement. Let
the monitor fully enter standby, wait another two minutes, then wake/unlock
before the five-minute capture starts. Set blanking back to Never immediately
after unlocking to avoid a second standby, keeping the capture running. Leave
the cable connected until capture completes (allow another minute). If the
external is black, allow the automatic capture to finish before unplugging.
Use a new output filename each time. Do not combine this with system suspend,
lid-close, mode changes or cable-replug testing.

Expected logs: A14-DP-power D3 write accepted on blanking, D0 verified before
sink check on wake, then successful receiver setup, training and DSC/FEC start.
Report boot behavior, both displays before/after login, external lock-screen
background and Ethernet. A successful cycle is a test result, not proof of
stability; we will assess the logs before another test.

The recorder is read-only (no AUX writes, resets or modesets). Existing kernel
AUX recovery may still run on reads; report if capture itself wakes the monitor.
Basic receiver/power/link registers are now captured before repeater registers,
so a failed repeater read will no longer hide those earlier observations.

## Remove

If needed boot a previous working generation, then remove this newest layer:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-sink-power-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Reboot after success. Removal preserves unrelated edits and refuses modified
experiment-owned files. Booting an older generation does not revert the repo.

## Validation

MSM objects compile and link for ARM64 with the pinned source/config. Actual
C helper tests cover power bits/order, D3 without readback, D0 verification,
short/error accesses and gate/controller/revision scope. The actual display
shutdown function is exercised to check connected/disconnected paths and host
cleanup after a failed D3 request. Installer checks cover baseline refusal,
exact application, idempotence, handled-error rollback and safe removal.
Recorder syntax and reordered AUX ranges are checked. Full NixOS build and
hardware validation must run on the laptop.
