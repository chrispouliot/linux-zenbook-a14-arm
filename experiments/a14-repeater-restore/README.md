# A14 checked repeater-mode restore experiment v1

## Why this change

The direct port-one standby capture showed a live repeater mode change from
non-transparent (aa) to transparent (55), with the driver still retaining one
repeater and trying to train it individually. Receiver D0 and rate/lane readback
succeeded, but repeater clock recovery returned zero status and failed. DSC was
off in this test. See OPEN-ISSUES.md for evidence and the separate eDP color issue.

## Behavior

New default-off parameter `msm.a14_dp_repeater_restore_test=1`, enabled by the
included Nix module. Also requires the prior DSC-wake board/controller gate:
ASUS UX3407NA, Glymur DP, af54000.displayport-controller / laptop port one.
It is not gated on DSC actually being active, so it covers the tested direct
uncompressed connection. Other controllers, including internal eDP, are excluded.

Before rate/lane configuration and training, when a positive cached repeater
count exists, read eight live common-capability bytes. Require a valid supported
count matching the cached count, revision >=1.4 and not ff, and a recognized
mode. If mode is already aa, issue no mode write. If mode is 55, write aa to
0xf0003 and read it back. Only a complete write followed by verified aa allows
setup to continue. Update the cached mode byte only after verified restoration.
Invalid/inconsistent data, short accesses and errors stop this enable through
the existing error path. Count zero skips the check; invalid cached counts fail.

This is one checked restore sequence using normal AUX helpers and their existing
retry/locking/PM/HPD behavior. No new outer reset/retry loop is added. The old broad
LTTPR reinitialization experiment is not reinstated: there is no forced aa->55->aa
cycle, capability reprobe of the whole display, or topology reconstruction.
When the live state is already 55, only the missing transition to aa is requested.
Normal rate/lane configuration, repeater/receiver training, and stream setup are
still required. All earlier experiments and tracing remain installed.

Log markers:
- `A14-DP-repeater: live_count=1 cached_count=1 mode=55 ...`
- `A14-DP-repeater: restored 55->aa and verified; normal training follows`
- Boot normally reads mode=aa and does not need a restore.
- Failure reports `pre-training check failed=...` and the specific access error.

This addresses an observed state mismatch but still needs hardware validation.
It may not fix dock failures where mode already reads aa and rate/lane writes
fail. Existing DPU timeouts after failed enable are unresolved.

## Install

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-repeater-restore-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-repeater-restore-test.patch experiments/a14-repeater-restore

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review git diff before building. Keep screen blanking and automatic suspend off
during the build, and reboot after success. Kernel release stays unchanged.
The installer checks the latest direct-standby capture baseline and pinned source.
No backups or commits are created; unexpected edits are refused. --check is
read-only, repeated installation is idempotent, and handled write errors roll
back. Abrupt interruption is not transactional across files.

## Test the direct connection first

Keep the monitor directly connected to laptop port one, dock disconnected, lid
open, same cable/orientation and 4K144 mode. Wake/power the monitor before boot as
in the last direct boot test. Leave automatic system suspend off.

After reboot, verify both print Y:

```sh
cat /sys/module/msm/parameters/a14_dp_repeater_restore_test
cat /sys/module/msm/parameters/a14_dp_state_trace_test
```

If boot fails, capture immediately without a standby cycle:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-repeater-restore/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-repeater-restore-boot.tar.gz
```

If boot works, set screen blanking to one minute and run:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-repeater-restore/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-repeater-restore-standby.tar.gz --delay 300
```

After the five-minute countdown announcement, let the monitor fully enter standby,
wait about three minutes, then wake/unlock before capture starts. Set blanking
back to Never to avoid a second standby cycle. Leave the cable connected until
capture completes even if the external stays black. Upload the archive whether
wake succeeds or fails. The kernel journal includes this boot's before/after bpp
selection, while live debug state records the result. Mention whether the internal
screen's grey-outline appearance changed again; the eDP issue remains unmodified.
Do not combine with system suspend, lid-close, dock changes or cable-replug tests.

The recorder performs no writes or modesets. Its reads, and the retained kernel
tracing, can affect timing or trigger existing AUX recovery. Report if recording
itself changes the display behavior.

## Remove this experiment

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-repeater-restore-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Removal retains prior experiments and refuses edits to experiment-owned files.
OPEN-ISSUES.md is experiment-owned too; copy it elsewhere before removal if you
want it kept in the checkout. The downloaded installer also retains its contents.
Booting an older generation does not revert repository changes.

## Validation

ARM64 MSM objects compile/link. Actual C helper tests exercise mode/count/revision
validation, controller and parameter gates, exact restore/verify ordering, no-write
already-correct mode, short/error accesses, and cache updates only after success.
The caller's failure return precedes configuration/training, and remaining training,
stream-enable and cleanup code is unchanged. Installer tests cover baseline refusal,
exact patch application, idempotence, safe removal and handled-error rollback.
Recorder syntax is checked. Full NixOS build and hardware test run on the laptop.
