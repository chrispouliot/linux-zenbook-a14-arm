# A14 receiver state trace experiment v1

This is a diagnostic, not a new wake fix. The latest failed retest verified
receiver D3 -> D0 and cleared DSC/FEC successfully, then both combined rate/lane
configuration attempts timed out. Later userspace capture ran after AUX PHY
cleanup and could not show receiver state during the failed configuration.

The new default-off parameter `msm.a14_dp_state_trace_test=1` adds snapshots in
dp_ctrl.c before paired receiver configuration and after each failed attempt,
before cleanup. It also requires the existing paired-configuration and DSC-wake
gates: ASUS UX3407NA, Glymur DP, af54000.displayport-controller / dock DP-1.
All prior patches, including sink power sequencing, remain installed.

Each snapshot logs software clock state, link rate/lane count, cached repeater
capabilities, then native AUX reads of:

| Address | Bytes | State |
| --- | --- | --- |
| 0x600 | 1 | Receiver power |
| 0x000 | 16 | Receiver capabilities |
| 0x100 | 3 | Rate, lanes, training pattern |
| 0x120 | 1 | FEC configuration |
| 0x160 | 1 | DSC enable |
| 0x202 | 6 | Link status |
| 0xf0000 | 8 | Repeater capabilities and mode |

Look for `A14-DP-state` with phase `before-config` or `config-failed`.
The adjacent `A14-DP-pair` message distinguishes write/readback/mismatch errors.
Every read logs its return value and AUX reply; data is printed only for a
complete acknowledged read. These sequential reads are not an atomic snapshot.

The helper makes one native transfer per range, with no implicit probe and no
retry on DEFER. It uses the AUX hardware mutex and normal driver transfer
callback, retaining powered-down, initialization, HPD and runtime-PM checks.
Remote AUX is rejected. Reported detach or powered-down errors end a snapshot.
Other failures are logged and the next range is tried. A normal driver access
may succeed with retries where this diagnostic reports DEFER or timeout.

There are no diagnostic writes and diagnostic return values do not replace the
configuration result. Reads still affect timing and can invoke the existing AUX
reset/calibration on failure. Therefore success with tracing does not prove a
fix. Slow reads can add delay; the single-attempt rule avoids an additional
32-retry loop per register but is not a hard wall-clock deadline. The existing
DPU timeout cascade after failed enable is not fixed here.

## Install

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-state-trace-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-state-trace-test.patch experiments/a14-state-trace

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review git diff before rebuilding. Disable automatic suspend and screen blanking
during the build; reboot after success. Kernel release is unchanged for boot
recovery's version guard. No backups or commits are created. The installer
checks the latest captured recipe, source revision, patches and Nix modules;
unexpected edits are refused. `--check` is read-only, handled write errors roll
back, and repeated installation is idempotent. Abrupt interruption is not
transactional across files.

## One standby test

After reboot verify:

```sh
cat /sys/module/msm/parameters/a14_dp_state_trace_test
```

It should print Y. Keep the lid open, dock on port one, 4K144, and automatic
system suspend off. Confirm displays and Ethernet at boot. If boot display
fails, capture immediately using the command below without `--delay 300` and
do not add a standby cycle.

If boot works, set GNOME screen blanking to one minute, then run:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-state-trace/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-state-trace-standby.tar.gz --delay 300
```

The five-minute countdown starts after the recorder's announcement. Let the
monitor fully enter standby, wait about three minutes, then wake/unlock before
the capture begins. Set blanking back to Never immediately after unlocking to
avoid a second cycle. Leave the cable connected until capture finishes, even if
the external remains black. The delayed capture runs without needing a visible
terminal. Upload the archive whether wake succeeds or fails. Report if the
capture itself changes display behavior. Do not combine with system suspend,
lid-close, mode changes or unplugging during this test.

The userspace recorder issues no writes, resets or modesets; its reads can also
trigger the existing kernel AUX recovery. Kernel snapshots are the key addition:
they run before failed-enable cleanup, independently of this later recorder.

## Remove only this diagnostic

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-state-trace-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Removal preserves unrelated edits and refuses modified experiment-owned files.
Booting a previous generation does not revert the repository. A full NixOS
build and hardware validation must run on the laptop.
