# A14 combined receiver-configuration experiment v1

## Evidence and hypothesis

The eDP retest capture shows the external DP-1 receiver accepting D0, DSC
clear and FEC writes, then timing out 64 times while writing lane count at
DPCD 0x101. The two checked setup attempts fail before clock recovery starts.
DPU subsequently waits for frames on the failed output until disconnect.
The internal eDP link trains on two lanes on attempt 1 and stays usable.

The current Qualcomm helper writes lane count (0x101) first, then link rate
(0x100). This experiment writes both as a two-byte native AUX transaction
starting at 0x100, then reads back both bytes. At HBR3 x2 the data is 1e 82.
This is a transaction/order hypothesis, not proof that the dock requires it.

The combined LINK_BW_SET programming form is present in the same pinned
kernel's i915 `intel_dp_link_training_set_bw()` implementation:
`drivers/gpu/drm/i915/display/intel_dp_link_training.c`.
Upstream source reference:
https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/i915/display/intel_dp_link_training.c

## Scope and behavior

New default-off boot-time parameter: `msm.a14_dp_pair_config_test=1`.
The included Nix module enables it. The branch also requires the existing
`msm.a14_dp_dsc_wake_test=1` gate, which scopes the checked helper to ASUS
UX3407NA and af54000.displayport-controller (laptop port one / dock DP-1).
It applies to both compressed and uncompressed streams on that path.
The eDP rate-table method is rejected, just as by the prior checked helper.

Each attempt writes exactly two bytes, requires full success, then reads and
verifies exactly two bytes. A short transfer or mismatched readback fails.
Keep the existing two-attempt maximum and 20 ms inter-attempt pause; a returned
ENODEV/ENXIO ends the attempt sequence. There is no lane-first fallback after
failure, and no extra reset sequence. The normal DRM/AUX locking, low-level
32-retry helper, software HPD disconnect checks and existing AUX recovery stay
in use. Gate-off behavior is the previous checked helper.

DSC/FEC sequencing, link rates, lane counts, LTTPR mode, USB settings, boot
recovery and the internal eDP retry patch remain in place. The kernel release
string does not change, preserving the boot-recovery version guard.

This patch targets the failed configuration transaction. It does not repair
DPU atomic-commit recovery: if setup still fails, the external display can
stay logically active and frame timeouts can recur. A proper recovery change
must coordinate a committed DRM state and connector lifetime; emitting a
hotplug notification directly from atomic_enable would not safely solve it.

## Install and build

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-pair-config-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-pair-config-test.patch experiments/a14-pair-config

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review git diff before rebuilding. Leave screen blanking and Automatic
Suspend disabled during the build; reboot only after success. Installer checks
the last captured recipe, patches, experiment Nix modules and source pin. It
refuses unexpected changes and creates no backups or commits. `--check` makes
no edits. Handled write failures roll back; abrupt interruption is not a
multi-file filesystem transaction.

## Verify and test

```sh
cat /sys/module/msm/parameters/a14_dp_pair_config_test
cat /sys/module/msm/parameters/a14_dp_dsc_wake_test
cat /sys/module/msm/parameters/a14_edp_retry_test
```

All three should print Y. Keep the same dock arrangement on laptop port one,
the lid open, and the external monitor at 4K144. Check both displays and Ethernet
at boot. If boot display fails, capture immediately, without another standby:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-pair-config/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-pair-config-boot.tar.gz
```

If boot works, leave Automatic Suspend disabled, set the GNOME screen timeout
to one minute, and start this delayed recorder before the standby test:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-pair-config/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-pair-config-standby.tar.gz --delay 300
```

The recorder prints when its five-minute countdown actually starts (after
Nix setup/sudo). Let the external monitor fully enter standby, wait another
two minutes, then wake/unlock before the countdown ends. Leave the terminal
process running. The capture starts automatically after five minutes even if
the terminal is stranded on a black external display. Wait for the archive to
finish (allow another minute) before unplugging or changing display settings.
AUX reads may trigger the existing kernel recovery: report if the screen wakes
only when capture starts. If the monitor has not completed two minutes of full
standby before capture starts, report the shorter test duration.

Use a fresh output filename per run. The recorder performs no resets, modesets
or AUX writes, and includes current/previous kernel journals, local patches,
DP/eDP state/registers and recent GNOME logs. Unplug after capture if necessary
to regain usable windows. Return Blank Screen to Never afterward. Do not mix
this test with system suspend, lid-close, cable-replug or resolution changes.

Upload the archive and report boot behavior, which displays returned, whether
Ethernet remained connected, and any lingering black login background.

Expected diagnostics: `A14-DP-pair: verified rate=1e lanes=82` and a successful
external training/stream start. On failure, logs distinguish write failure,
read failure and readback mismatch. One successful wake is not proof that the
intermittent failure is fixed.

## Remove

Boot an older working generation if needed. To remove only this experiment:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-pair-config-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Reboot after success. Unrelated edits and prior experiments are preserved;
modified experiment-owned files are refused. Booting an old generation alone
does not revert repo files. Remove this newest experiment before older ones.

## Validation

The changed MSM driver compiles and links for ARM64 against the pinned source
and captured config. A C harness tests the actual new helper and dispatch:
transaction address/size/order, readback, partial transfers, retries, errors,
disconnect results, scope and gate-off behavior. Installer checks cover exact
patch application, baseline refusal, no-write checks, rollback, idempotence
and safe removal. The recorder's delay validation and syntax are checked.
A full NixOS build and hardware testing remain for the laptop.
