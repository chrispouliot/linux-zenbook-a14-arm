# A14 dock boot recovery v4 experiment

## Purpose and limits

This is a boot-recovery workaround for the tested Amazon Basics dock on laptop
port one. It does not claim to fix the underlying rate/lane AUX write failure.
Earlier manual and automatic UCSI Data Reset tests recovered this dock's display
and Ethernet. The latest failure is skipped by v3 because DRM reports connected,
even though the kernel explicitly aborted external link enable. Superspeed USB
and Ethernet can be present while display setup fails.

V4 adds recognition of this failed-but-connected case. It overrides the existing
`a14-dock-boot-recovery.service` only when the existing
`hardware.a14DockBootRecovery.enable` option is true. Do not remove your existing
recovery-module import or add a second system service. The override uses the same
unit and runtime lock/state directory, and replaces its executable with v4.

Kernel.nix and all kernel patches are unchanged. The direct-connection repeater
restore stays enabled and configuration reuse stays disabled. The internal eDP
18-bpp boot / 24-bpp wake inconsistency remains tracked as EDP-COLOR-01 in
`experiments/a14-repeater-restore/OPEN-ISSUES.md` and is not altered here.

## Decision and recovery sequence

- Retain the tested A14 board/kernel, physical port, normal orientation, host
  role, USB 5 Gbps limit, dock USB hub topology and no-USB-storage restrictions.
- Retain the 30-second boot grace period and 120-second entry window. Run before
  GDM and NetworkManager. Refuse recovery unless the display manager is inactive.
- Preserve the old disconnected-DP/no-Superspeed recovery case.
- For connected DP, require `enabled`, an explicit af54000 failed-enable record
  in this boot's kernel journal, and fresh readable link registers that indicate
  training is incomplete. Resolve AUX by af54000's physical sysfs ancestry,
  not a hardcoded drm_dp_aux number. Unknown/malformed state is not accepted.
- Read 0x100..0x102 and 0x202..0x207 through a subprocess with an eight-second
  userspace timeout. Require all selected lanes' clock-recovery, equalization,
  symbol-lock bits and interlane alignment to call a link trained. A historical
  failed-enable message cannot qualify a currently trained link for reset.
- Wait for stable USB/connector state, verify UCSI 2.1 through the same temporary
  scoped GET_CAPABILITY probe used by v3, then recheck current link state and
  display-manager state. Abort if the topology changed or recovery no longer
  qualifies.
- Mark the attempt before issuing ONE `0x810003` UCSI Data Reset, then observe
  for 20 seconds. No automatic retries or session-time reset service is added.
- Check actual link training plus Ethernet USB enumeration at 5 Gbps afterward.
  A trained link is not proof of a visible picture; the user's observation is
  still required. The service logs incomplete recovery and stops if necessary.

The reset briefly disconnects this port's USB devices, including Ethernet and
keyboard/mouse. It occurs during boot, before the graphical login service starts.
It is deliberately not a generic dock/port workaround. Existing AUX recovery can
run on diagnostic reads. Service timeout is 90 seconds; it does not retry after
errors, restarts, or timeouts within the same boot.

## Install

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dock-recovery-v4.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  experiments/a14-dock-recovery-v4

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review git diff before the rebuild. This should reuse the compiled kernel; only
service/configuration output changes. Keep automatic suspend and blanking off
while rebuilding. No backups, commits, resets or service restarts are performed
by the installer. It validates the latest captured recipe, patches/modules and
pinned kernel source. --check is read-only; unexpected changes are refused.
Handled write errors roll back; abrupt interruption is not transactional across
files. Installation is idempotent.

## One boot test

Keep the Amazon dock on port one in the same orientation as the failed capture.
Keep the monitor connected through the dock and wake/power it before boot. Remove
dock storage for this test, as required by the existing recovery restrictions.
Reboot after the configuration build succeeds. Expect the existing boot grace
period and, when recovery qualifies, another 20-second observation period.
Do not unplug/replug during this boot test.

After login, inspect the service and capture without a standby cycle:

```sh
systemctl show a14-dock-boot-recovery.service --property=Description --value
journalctl -b -u a14-dock-boot-recovery.service --no-pager

sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-dock-recovery-v4/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-dock-recovery-v4-boot.tar.gz
```

Description must say v4. Upload the archive and report external display, Ethernet,
and desktop responsiveness. Leave the cable connected until capture completes.
If recovery skips or fails, its before/recheck/after JSON and kernel logs are in
the archive, alongside the exact installed unit. Do not manually clear its runtime
markers or restart it to force another reset. Further work should use the reason
recorded in this first test.

## Remove only this service override

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dock-recovery-v4.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

After reboot the previously imported recovery module supplies the service again.
Kernel patches remain unchanged. Removal refuses modified experiment-owned files
and preserves unrelated repository edits.

## Validation

Python syntax and actual service decision/control-flow tests pass. Tests cover the
latest failed capture, already-trained link, invalid/short evidence, topology and
orientation scope, storage guard, early/late state changes, inactive display-manager
requirement, one-reset limit and attempted marker surviving command failure/restart.
Installer tests cover baseline refusal, idempotence, preservation of every existing
file except flake.nix, handled-error rollback and safe removal. NixOS evaluation,
unit merging and actual dock recovery still require testing on the laptop.
