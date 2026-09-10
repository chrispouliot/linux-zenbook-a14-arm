> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 transparent LTTPR experiment v1

Experimental patch for the captured 2026-09-09 repeater-reset tree, on upstream
51231839d5ef007638bd1c3500e6a76b337a66f3. This is a hardware test, not a confirmed fix.

## Question

The last capture verified aa -> 55 -> aa transitions, but the two-byte write at
DPCD 0x100 still timed out on all four full link starts. It also failed at
1080p60 without DSC. Test whether staying in transparent mode changes that result.

## Changes

* Add `msm.a14_dp_transparent_test`, default off in the driver, enabled by this
  experiment's NixOS module.
* Select only A14 UX3407NA/Glymur port one (af54000), with exactly two physical
  repeaters advertising a two-lane limit. The direct one-repeater connection,
  port two, and eDP are not selected for transparent-mode training. Selection
  skips PHY and video compliance requests.
* During inactive HPD setup, verify live repeater caps, set mode 55 if necessary,
  and verify readback. Do not run normal 55 -> aa initialization afterward.
* Preserve the physical common capabilities (count/rate/lane limits). Set the
  software training count to zero so the existing training loop addresses DPRX
  only; it does not attempt separate non-transparent repeater training.
* Read receiver/DSC/FEC capabilities after selection. Clear the experiment's
  cached link_info before that read so an old nonzero rate cannot bypass the
  new capability limits. Existing source, receiver and repeater limits remain.
* Before each inactive full enable, verify/re-establish 55, then read DPRX caps
  and require them to match the capabilities used for mode setup. Changed
  capabilities fail with -ESTALE rather than silently changing an already
  checked mode. This version does not automatically trigger new detection.
* Before every training entry, verify 55 without changing modes. Active-link
  maintenance never switches modes. Stream/core/link-clock and transmitter
  guards protect mode changes. On active port-one notifications the experiment
  retains existing LTTPR state instead of reinitializing it; the older caps
  recovery helper is also prevented from changing modes while power_on is true.
* Skip both earlier repeater-reset and repeater-restore helpers on a selected
  transparent connection. The NixOS module separately disables the failed reset
  experiment, retaining its raw AUX diagnostics.

No additional outer retry loop, UCSI reset, USB controller reset, new timeout,
DSC algorithm, or eDP colour/depth change is added. Standard DRM AUX helpers keep
 their existing internal retries. Extra capability reads can add boot time if
AUX is unavailable. A mode write ACK/readback does not prove every repeater's
internal state; the result must be checked in the logs and on the monitor.

The existing boot recovery service is retained. This experiment does not fix
failed-enable/KMS handling or the separate Ethernet loss after suspend. A failed
link can still cause the already observed login freeze. Do not use suspend as
the first test of this patch.

## Installation

Run the downloaded installer as your normal user:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-transparent-test.py \
  ~/Projects/linux-zenbook-a14-arm

cd ~/Projects/linux-zenbook-a14-arm
git add -N patches/a14-dp-transparent-test.patch experiments/a14-transparent
git diff --stat
git diff -- kernel.nix flake.nix experiments/a14-transparent/nixos.nix

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

The installer checks the recipe, flake, patches and Nix modules against the
latest uploaded capture, plus the upstream source revision. It does not require
a clean git tree or create backups. It refuses mismatched files before edits,
is idempotent, and supports `--check` and `--remove`. It does not build or reboot.
If a hash check fails, share the current diff; do not bypass the check.

## First test: dock boot only

1. Keep the Amazon dock on laptop port one and the USB-C-to-DP monitor cable
   connected to the dock. Keep the laptop lid open. Use a saved 1080p60 desktop
   mode for this comparison if available; GDM may have a separate saved layout.
2. After the build succeeds, reboot with the topology unchanged. Leave the
   monitor in its normal standby state; no pre-emptive power button or cable
   reset. Let the existing boot recovery service finish once.
3. Record whether the greeter is responsive, which screens work, and whether
   Ethernet works. Do not start a standby/suspend test or replug before capture.
4. Check the actual booted settings:

```sh
for p in a14_dp_transparent_test a14_dp_repeater_reset_test a14_dp_aux_diag_test \
         a14_dp_first_aux_probe_test a14_edp_bpp_init_test a14_dp_bounded_cleanup_test; do
  printf '%s: ' "$p"
  cat "/sys/module/msm/parameters/$p"
done
```

Expected: Y, N, Y, Y, N, N in that order.

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-transparent/capture.py \
  ~/Projects/linux-zenbook-a14-arm \
  ~/a14-transparent-dock-boot.tar.gz
```

The recorder performs no resets or modesets; it saves journals before AUX reads.
AUX reads can wake hardware, so report what you saw before running it. If the
login freezes and suspend/resume is necessary to reach a terminal, say so with
the capture; the earlier boot journal is still useful. If recovery is impossible,
boot the previous generation rather than repeating forced failures.

Expected diagnostic progression (each line is evidence to inspect, not a promise):

* `A14-transparent: phase=hpd verified mode=55 physical_repeaters=2 ...`
* `A14-transparent: phase=enable verified mode=55 ...`
* `A14-transparent: DPRX caps unchanged; train_count=0 ...`
* `A14-transparent: training verified mode=55; DPRX only`
* A successful link-config write and mainlink READY, or the first reported error.

A physically working display at boot is the first outcome. Investigate standby,
4K144/DSC, and Ethernet retention separately after reviewing this capture. The
patch does not force a resolution or refresh rate; logs establish the actual mode.

## Disable / remove

Fastest recovery is the previous NixOS generation in systemd-boot.
To retain the compiled diagnostics but disable transparent selection, add to
an imported NixOS module:

```nix
hardware.a14TransparentTest.enable = false;
```

Rebuild boot and reboot. This module keeps the unsuccessful repeater-reset
experiment disabled even when transparent selection is disabled. AUX diagnostic,
first-probe and disabled eDP-bpp/bounded-cleanup settings remain pinned for this
comparison. No kernel source rebuild should be needed for a parameter-only edit
if the same compiled kernel is retained, but Nix evaluation decides that.

To remove only this experiment using the installer:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-transparent-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
```

Remove any `hardware.a14TransparentTest` setting you added, refresh a14, rebuild
boot, and reboot. Removing the module also removes its override disabling the
previous repeater-reset test, so that previous module's default becomes active
again unless you explicitly set `hardware.a14RepeaterResetTest.enable = false`.

## Validation performed before delivery

* ARM64 GCC compilation and link of `drivers/gpu/drm/msm/msm.o` against the local
  reconstructed kernel with the full previous patch stack.
* Actual C helpers tested with mocked hardware: AA/55 selection, no AA writes,
  active transmitter/clock guards, topology/cap preservation, short reads,
  failed ACK/readback, retained-state validation, and active training checks.
* Actual HPD initializer tested for no fallback to normal non-transparent init
  on selected/failed selection paths and no active-link mode reinitialization.
* Installer baseline checks, refusal without edits, idempotence, removal, failure
  rollback, and recorder syntax; patch stack applies at fuzz=0 with no offsets
  and reproduces the compiled source.

No full NixOS evaluation/build or physical hardware test was available here.
