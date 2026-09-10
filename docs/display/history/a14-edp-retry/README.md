> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 native eDP training retry experiment v1

The latest long-standby test was 4K144 on the external monitor and succeeded.
The internal panel failed two-lane channel equalization and fell back to one
lane at 2.7 Gbit/s. That link trained, but its 2.16 Gbit/s payload cannot carry
1920x1200@60 RGB24 (154260 kHz x 24 = 3.70224 Gbit/s). Disabling and re-enabling
the built-in display restored two lanes and a visible desktop.

This experiment is gated by `msm.a14_edp_retry_test=1` (default off in C,
enabled by the included Nix module). It targets only ASUS UX3407NA's
`af6c000.displayport-controller`, native 1920x1200 / 154260 kHz / RGB24,
uncompressed, with advertised 270000 kHz and two lanes. PHY compliance tests
are excluded. It does not raise the internal link-frequency cap.

For this mode, try training at the existing two-lane rate up to three times.
Clear the sink training pattern and reset training voltage/pre-emphasis
between attempts. On initial enable, use the existing mainlink/PHY reinit
(including its 20 ms delay) when pixel clocks are off. Retraining and link
maintenance use a 20 ms pause without cycling clocks that may be live.
Stop after disconnect, setup failure before training, reinit failure, or the
third failed attempt. No rate/lane fallback is attempted for this mode.

Check capacity using the full mode pixel clock before retraining and before
stream startup. Wide-bus interface-clock halving does not reduce payload.
An inadequate link returns ENOSPC. On link-enable failure, include this
controller in the existing PM/PHY cleanup and aborted-enable handling.
Other modes/controllers and all existing DSC/AUX/dock-HPD patches are retained.
The kernel release string stays unchanged for the boot-recovery version guard.

This is a targeted experiment, not a proven fix for why lane-one EQ fails.
It does not implement DPU atomic-commit failure recovery, alter PSR handling,
or resolve all external AUX, cable-replug or suspend failures. If every retry
fails the internal panel can still remain unavailable; capture before recovery.

## Install and build

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-edp-retry-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-edp-retry-test.patch experiments/a14-edp-retry

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review `git diff` before rebuilding. Keep Automatic Suspend disabled and Blank
Screen set to Never during the build. Reboot only after a successful build.
Installer checks the captured recipe, patch files, Nix modules and kernel pin;
refuses unexpected changes; makes no backups, commits or hardware writes.
`--check` validates without edits; `--remove` removes this experiment only.
Handled write errors roll back writes; abrupt interruption is not transactional.

## Test

```sh
cat /sys/module/msm/parameters/a14_edp_retry_test
```

Must print Y. Keep the lid open and the existing dock/cable arrangement and
4K144 setting. First check whether the internal login screen and both desktops
appear at boot, and Ethernet works. If the internal display fails at boot,
capture immediately and do not proceed to standby.

With Automatic Suspend still disabled, set GNOME's screen timeout to one
minute. Let the external monitor enter full standby, wait another 2–3 minutes,
then wake/unlock. Check both displays before and after login. Return Blank
Screen to Never afterward. Do not combine this test with lid-close, system
suspend, cable unplugging or a resolution change.

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-edp-retry/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-edp-retry-result.tar.gz
```

Capture while any black screen remains, before disabling/re-enabling the
panel. Upload the archive with what each screen showed. Recorder adds eDP
receiver/config/status/power reads and the new module flag, and fixes GNOME
Shell journal matching for NixOS. It makes no resets, modesets or AUX writes;
existing kernel recovery may run on timed-out reads. Report if capture itself
changes the display. Use a new filename for each capture.

Success evidence: native internal link stays at two lanes / 270000 kHz, both
screens are visible, no new training/frame-timeout cascade. Retry diagnostics
begin `A14-eDP-retry:`. First-attempt success establishes a baseline but does
not demonstrate recovery from the intermittent EQ failure; a logged failed
attempt followed by success provides that evidence.

## Remove

If needed, boot a previous working generation. That does not revert repo files.

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-edp-retry-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Reboot after success. Removal preserves unrelated edits and refuses modified
experiment-owned files. Remove the newest experiment before older installers.

## Validation

Changed MSM objects compile and link for ARM64 against the captured source
and config. A C harness runs the actual new scope, capacity and retry functions
with injected training/reinit/disconnect outcomes. Installer checks exercise
baseline refusal, idempotence, rollback, safe removal and exact patch application.
A full NixOS build and hardware validation must be performed on the laptop.
