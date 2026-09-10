> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 AUX timeout recovery experiment v1

This installer atomically removes the failed LTTPR wake experiment and adds
an AUX timeout recovery experiment. It accepts either the captured repo with
the LTTPR experiment still installed, or that same baseline after its exact
removal. Earlier 4K60/144 DSC and first DSC wake patches remain. Rebooting an
older NixOS generation does not change the repository; the installer handles
that expected state. No backup or whole-file git restore is used.

## Evidence and scope

Full-standby wake still timed out on lane configuration after verified D0 and
DSC/FEC cleanup. The LTTPR experiment completed its mode reset, then produced
the same lane-write timeouts during boot. It is removed, not merely disabled.

The AUX driver currently resets after a completion timeout only when native
HPD reports connected. This dock uses Type-C/PMIC GLINK HPD and repeatedly
reports native HPD zero while AUX operations are otherwise working. Also,
the IRQ-reported timeout branch returns -ETIMEDOUT without that reset.

This experiment changes only dp_aux.c relative to the earlier DSC wake
baseline, gated by the new default-off parameter `msm.a14_dp_aux_wake_test=1`
on UX3407NA af54000. After a native AUX timeout, while software enable_xfers
and initted remain true, it stops the transaction and uses the existing AUX
reset and interrupt-clear functions. The transfer mutex and runtime-PM
reference are held. It returns the error so the existing caller controls
retries. No new retry loop, PHY calibration, USB reset, repeater-mode reset,
DSC timing change, or bandwidth/clock increase is introduced.

Diagnostic messages `A14-AUX-wake:` include address, request, last ISR,
AUX error code and whether the software completion wait expired. The original
connection/init guards are not bypassed. A disconnected transfer must still
fail without new AUX reset writes. The older built-in timeout calibration
behavior is unchanged. A reset can still fail to recover a sleeping receiver;
this is not a guarantee of wake or hotplug reliability. DPU commit timeout
recovery and the unplug/replug-triggered reboot remain unresolved.

## Install, build, reboot

Run on your previous working generation with the repository in its current
state. The script checks everything before committing its file changes.

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-aux-wake-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-aux-wake-test.patch experiments/a14-aux-wake

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Keep the machine awake with Blank Screen set to Never during the build.
Reboot only after it succeeds. The default NixOS module imports the new
parameter and removes the LTTPR module import. If you added the old parameter
manually elsewhere, remove it there; kernel-only consumers must manually add
msm.a14_dp_aux_wake_test=1. The release string remains unchanged for boot
recovery v3, so verify the parameter/build identity instead of uname alone.

```sh
cat /sys/module/msm/parameters/a14_dp_aux_wake_test
test ! -e /sys/module/msm/parameters/a14_dp_lttpr_wake_test && echo 'Old repeater experiment absent'
```

The first prints Y and the second prints the absence message. If either is
wrong, capture the current state before testing further.

## One hardware test

Keep the dock on laptop port one, lid open, Automatic Suspend off. Verify
4K144 and Ethernet after boot. If the initial display is blank, capture and
stop. Otherwise save work, use GNOME's one-minute blank-screen timeout,
wait for actual monitor standby and another 30 seconds, then wake/unlock.
Do not combine this with lid-close, system suspend or USB-C replug.

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-aux-wake/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-aux-wake-result.tar.gz
```

Upload success or failure with display/Ethernet/responsiveness observations.
If the screen stays blank, capture before its power button, cable changes or
reboot. The recorder is read-only, retains previous-boot/pstore data, stops
AUX reads after failure, and records kernel journals before and after probes.
With this kernel's new recovery gate, any native AUX timeout, including a
recorder read timeout, can trigger driver-side AUX recovery. The recorder
does not explicitly request a reset, and the before/after journals retain
that distinction. Report if output returns during capture.
Return Blank Screen to Never after this one test.

## Rollback

Boot the previous working generation if needed. Run this installer with
--remove, refresh a14, rebuild boot, then reboot to remove this AUX experiment.
Removal retains earlier DSC/wake patches and does NOT restore the broken
LTTPR experiment. Remove this experiment first before removing older ones.
--check does not write; repeat install is idempotent. Unexpected or modified
owned files are refused, without deleting them. Inspect git diff after install.

## Validation

ARM64 MSM objects compile/link against the captured patch chain. Exact patch
application and installer migration from both supported repository states
are tested, including refusal of modified retired files and no-write checks.
Mocked source tests exercise completion timeouts, IRQ timeouts, native HPD
zero, disabled gate, disconnect/init guards, and successful transfers.
This is not a full NixOS build or hardware proof.
