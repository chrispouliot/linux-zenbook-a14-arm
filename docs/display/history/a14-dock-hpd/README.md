> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 dock IRQ containment experiment v1

## What this changes

The 1080p60 retest failed at lane-count write 0x101 with DSC/FEC disabled.
The AUX-reset experiment ran but did not recover that transaction. Captures
also show hundreds of IRQ-tagged HPD events on Type-C port 0 during standby,
causing full DRM hotplug notifications and connector/runtime-PM activity.
The existing IRQ containment covers Type-C port 1 (the other laptop port).

This patch extends containment to Type-C port 0 on ASUS UX3407NA only, behind
the new default-off, boot-time parameter:

    pmic_glink_altmode.a14_dock_hpd_test=1

The Nix module enables it. The module is pmic_glink_altmode, not msm.
Laptop port ONE / Type-C port0 / DP-1 is the dock path in these captures.

Only an HPD-high, IRQ-tagged event on an already successfully configured DP
path is acknowledged without another mux/retimer setup or DRM hotplug notify.
Initial setup (even when tagged IRQ), HPD-low, untagged HPD-high, and changed
orientation, pin assignment, or DP mux configuration still reach the existing
handling. Failed mux/retimer setup leaves the path eligible for another setup.
The retained low-before-high queue is unchanged. The existing port1 behavior
is preserved. The experiment does not depend on a dock VID/PID; it applies to
DP Alt Mode on this A14 port, and is not a generic USB4/TB tunneling fix.

The driver logs `A14-dock-HPD: suppressing IRQ-only replay port=0` when the new
branch runs. Logs are rate-limited; their count is not the total event count.
Raw RX/WORK diagnostics remain, so incoming firmware events may still be
visible. The expected change is fewer downstream DRM notifications and PM
cycles, not necessarily fewer firmware events.

This is an experiment, not complete service-IRQ support: suppressed IRQ-only
sink requests will not be serviced through this old HPD interface. MST,
HDCP/service interrupts and generic IRQ handling are not validated. Modern
upstream work passes IRQ_HPD separately through the DRM bridge chain; a
proper backport requires more than expanding this local containment guard.
Reference: https://lore.gitlab.freedesktop.org/drm-ai-reviews/20260421-hpd-irq-events-v3-2-44d2bf40dfc2%40oss.qualcomm.com/

DSC60/144, the first DSC wake patch, AUX timeout recovery, USB/PHY settings,
boot recovery, and all link/clock limits are retained. The broken LTTPR wake
experiment stays absent. DPU frame timeout recovery is NOT changed: the
bridge enable callback cannot return a failure to its atomic commit; safely
recovering that path needs a separate DRM state/workqueue change. This patch
does not claim to fix the lane-write failure, black greeter, or replug crash.

## Install / build

The installer checks the latest captured baseline, modifies kernel.nix and
flake.nix, and adds four files. It does not modify hardware, build, reboot,
create backups or commit to git. --check is read-only; --remove removes only
this experiment, preserving unrelated edits. Modified owned files are refused.
Writes are individually atomic and rolled back on handled write failures;
an interrupted/power-lost multi-file operation is not a filesystem transaction.

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dock-hpd-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dock-hpd-test.patch experiments/a14-dock-hpd

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Keep GNOME Blank Screen set to Never and Automatic Suspend disabled during
the build. Review git diff. Reboot only after the build succeeds. No kernel
release suffix is added, preserving the existing boot-recovery version guard.

## Verify and test

```sh
cat /sys/module/pmic_glink_altmode/parameters/a14_dock_hpd_test
cat /sys/module/msm/parameters/a14_dp_aux_wake_test
```

Both should print Y. Keep the dock on laptop port one and the lid open.
First confirm boot display, Ethernet and usable internal display. If boot
fails, capture immediately and skip standby testing.

Use 1080p60 first to compare against the latest failure. Automatic Suspend
stays off. Let GNOME blank the displays, wait until the monitor has actually
entered standby, then wait two more minutes before waking/unlocking. Report
both the pre-login display and the desktop after login, and responsiveness.

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-dock-hpd/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-dock-hpd-1080p-result.tar.gz
```

Capture before changing resolution, reconnecting cables or using the monitor
power button. The recorder is read-only, but existing kernel AUX recovery
can act on timed-out reads. Report recovery during capture if it occurs.
The recorder adds the new parameter and recent GNOME Shell/display-manager
logs to the prior capture so black greeter symptoms are recorded too.

If the first test passes, repeat the same full-standby test once at 4K144 and
capture to a new filename (a14-dock-hpd-144-result.tar.gz). Stop after a failure.
Do not combine this with full system suspend, lid-close or cable-replug tests.
Return Blank Screen to Never after testing.

## Remove

Boot a previous working generation if required. To change the repo back:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dock-hpd-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Reboot after success. Remove this newest experiment before using an older
installer's removal mode. Booting an older generation alone leaves repo files
unchanged. New files are not committed automatically; git remains your history.

## Validation limits

The changed Qualcomm driver is compiled for ARM64 against the existing source
and config. A mocked C harness uses the actual event handler, DP-setup helper,
and retained-event queue to test bootstrap, duplicates, transitions, setup
failures, gate/board/port scope and one firmware ACK per handled event. The
installer is exercised for exact patch application, unchanged baseline,
idempotence, refusal without writes, rollback and safe removal. No full NixOS
build or hardware test is possible in this workspace.
