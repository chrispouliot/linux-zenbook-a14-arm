# A14 native eDP depth experiment v1

Baseline: the uploaded a14-transparent-dock-144-replug capture, with the working
transparent-mode dock patch and kernel source revision
51231839d5ef007638bd1c3500e6a76b337a66f3. A git commit of the same file contents is
compatible with the installer. This is a focused hardware experiment.

## Reason

The internal panel reported 1920x1200@60, HBR (270000) x2, 18 bpp after boot, but
24 bpp after display standby/resume. At the 154260 kHz pixel clock the HBR x2
payload is 4.32 Gbit/s: 24 bpp needs 3.70224 Gbit/s; 30 bpp needs 4.6278 Gbit/s.
Thus the link cap requires dropping a 30-bpp request to 24, not necessarily 18.

The current panel depth selector returns its minimum of 18 bpp when link_info
is still empty at mode_set. The previous experimental code already saved the
original EDID-derived request, but its correction was disabled and could abort
the internal display on a failure. This patch replaces that correction with a
local calculation and enables it through a new, separate parameter.

## Scope and behaviour

* `msm.a14_edp_depth_test`: default false in C, enabled by this NixOS module.
* A14 UX3407NA/Glymur eDP controller af6c000 only. No changes to the external
  DisplayPort controller's depth calculation or transparent-mode implementation.
* Only the captured native 1920x1200 timing at 154260 kHz, HBR x2, uncompressed
  RGB, powered/initialized AUX and PHY, inactive stream. Skip video/PHY tests,
  DSC/FEC, YUV420, missing/invalid capabilities, and unsupported timing/link state.
* After successful powered HPD setup and before on_link/on_stream, calculate the
  depth from the saved request with the existing panel selector. Validate that
  it is standard RGB depth, within the request and full-pixel-clock bandwidth.
* Commit only mode.bpp and timing.bpp after all validation. No full panel
  reinitialization, partial timing/compression update, or new AUX access is used.
* On failed HPD setup, skip the calculation. On any skipped/failed calculation,
  leave the old mode unchanged and preserve the pre-experiment enable/PM flow.
  The depth experiment no longer unplugs the internal panel or aborts enable.
  This does not repair a genuine HPD/power/capability failure; such failures
  remain subject to the existing driver behaviour and are logged for review.
* Keep the earlier `a14_edp_bpp_init_test` parameter OFF. Its internal helper is
  updated too, but this test is controlled by the new parameter. The transparent
  experiment's existing forced-OFF setting for the old parameter is preserved.

The HBR device-tree limit, eDP retry patch, working dock settings, DSC arithmetic,
USB behaviour, gamma/ICC settings, and DPU dithering configuration are not changed.
The test targets consistent stream depth, not proof of the reported near-black
UI difference or a fix for black wallpaper/delayed redraw.

## Install and rebuild

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-edp-depth-test.py \
  ~/Projects/linux-zenbook-a14-arm

cd ~/Projects/linux-zenbook-a14-arm
git add -N patches/a14-edp-depth-test.patch experiments/a14-edp-depth
git diff --stat
git diff -- kernel.nix flake.nix experiments/a14-edp-depth/nixos.nix

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

No backups, builds, commits, reboots, or hardware writes are performed by the
installer itself. It validates the captured recipe, modules, patches and source
revision, and refuses unexpected edits. `--check` validates without edits;
`--remove` removes only this experiment and refuses modified owned files.

## First test: boot with internal display enabled

After a successful build, reboot with the laptop lid open, internal display
enabled, and your current dock/monitor connection unchanged. Keep the working
external 4K144 setting. Do not intentionally suspend or blank the screens before
the first capture; that would obscure the boot-depth result.

```sh
for p in a14_edp_depth_test a14_dp_transparent_test a14_edp_bpp_init_test; do
  printf '%s: ' "$p"
  cat "/sys/module/msm/parameters/$p"
done
```

Expected Y, Y, N. Check internal depth:

```sh
sudo cat /sys/kernel/debug/dri/ae01000.display-controller/eDP-1/dp_debug
```

Expected active=1920x1200, refresh=60, rate=270000, num_lanes=2, bpp=24.
Then capture even if the result is unexpected:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-edp-depth/capture.py \
  ~/Projects/linux-zenbook-a14-arm \
  ~/a14-edp-depth-boot.tar.gz
```

Expected log sequence, if early mode_set has empty capabilities:

```
A14-eDP-depth: phase=mode_set requested=30 selected=18 rate=0 lanes=0
A14-eDP-depth: phase=enable requested=30 before=18 selected=24 rate=270000 lanes=2
```

A request of 24 instead of 30 is also valid and should select 24. If capabilities
were already available, mode_set may already select 24. A "setup/finalize
skipped" message means the correction was not applied; include it in the report.

Report whether login and both displays work, whether Ethernet works, and whether
the internal near-black appearance differs from the known post-wake appearance.
Avoid changing brightness, Night Light, or colour settings during the comparison.
If login requires a recovery suspend, say so and capture afterward: the journal
still records the earlier mode selection, but the live state is then post-wake.

After reviewing the boot result, the next check is one display-only standby
cycle: it should return at the same 24 bpp rather than changing from 18 to 24.

## Rollback

The existing working generation remains selectable in systemd-boot.
To keep the compiled patch but disable the correction, add to an imported module:

```nix
hardware.a14EdpDepthTest.enable = false;
```

Rebuild boot and reboot. The old depth parameter stays off, so both depth
experiments are then disabled. No kernel source change is required for this
parameter-only comparison if the same compiled kernel is retained.

For full removal:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-edp-depth-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
```

Remove any `hardware.a14EdpDepthTest` setting you added, refresh a14, rebuild boot
and reboot. The previous transparent-mode dock integration is retained.

## Validation

The modified driver was compiled and linked as ARM64 msm.o against the complete
local patch stack. Tests compile the actual C depth helper and the existing
bandwidth-selection loop, checking 30->24 selection, stable repeat calls,
request caps, bandwidth rejection, invalid/missing/powered/active/compression
states, no partial mode mutation, and the eDP-only gate. Call-site checks verify
successful HPD precedes correction and no experiment-specific unplug/abort/PM
operation remains. Installer tests cover exact baseline matching, mismatch
refusal without writes, idempotence, removal, transaction rollback and recorder
syntax. The patch applies with fuzz=0 and no offsets to the reconstructed
captured stack and reproduces the compiled source.

No full NixOS evaluation/build or physical hardware validation was available here.
