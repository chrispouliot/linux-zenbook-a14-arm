> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 DSC 4K60 experiment v1

This is the first implementation test toward 4K144. It does NOT enable
4K144 yet. Its purpose is to establish a working compressed stream using
the already-working 4K60 timing, then extend the tested path to higher rates.

## Exact scope

- Kernel source: linux-msm/laptops-kernel revision
  `51231839d5ef007638bd1c3500e6a76b337a66f3` plus the captured local A14 patches.
- Board: ASUS Zenbook A14 UX3407NA, Glymur.
- Output: physical port one, `af54000.displayport-controller` (captured as DP-1).
- Two DP lanes at HBR2 or HBR3; the captured dock runs HBR3 x2.
- Exact RGB 3840x2160 timing: 533250 kHz; horizontal 3840/3888/3920/4000;
  vertical 2160/2163/2168/2222 (approximately 60 Hz).
- RGB 8 bits/component, DSC 8 bits/pixel; two 1920x108 slices.
- Check DSC decoding, RGB8, two-slice support, maximum slice width, throughput,
  line-buffer depth and FEC capability. Check AUX results for enabling FEC/DSC.
- Other modes use the captured uncompressed TU algorithm. Existing bandwidth
  rejection still filters modes that cannot fit; no 4K144 mode is forced.
- The direct port-two HBR2 cap, PHY fixes, USB Gen1 cap, HPD changes,
  boot recovery v3 and kernel release string are retained.

The experimental kernel parameter `msm.a14_dp_dsc_test` defaults off in C.
The companion NixOS module enables it through `boot.kernelParams` when the
repository's `nixosModules.default` is imported, including its named alias.
If you only consume this repository's kernel package, add
`boot.kernelParams = [ "msm.a14_dp_dsc_test=1" ];` to your existing NixOS
configuration (append to an existing list). The running value must be `Y`.

## Apply and build

Run the downloaded installer as your normal user with Python 3:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dsc-4k60-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-dsc-4k60-test.patch experiments/a14-dsc-4k60

git -C ~/Projects/linux-zenbook-a14-arm diff --stat
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

The installer validates the captured kernel.nix, flake.nix, source revision
and existing patch hashes. It inserts the DSC patch at the END of postPatch,
after the existing A14 source transformations, and wraps the default NixOS
module with the experiment module. Existing inputs are not changed by the
installer. No backups are created; existing git history and the previous
NixOS generation remain the recovery route.

Reboot only after a successful build. This should rebuild the kernel.
The release string intentionally stays `7.2.0-rc5-next-20260731` because the
working boot-recovery service checks it. Thus `uname -r` alone cannot prove
that the experiment was built or booted.

## First hardware test

Keep the monitor on the dock and the dock on laptop port one. Start at 4K60.
Allow the existing boot-recovery v3 service to complete. First assess both
screens and Ethernet while awake; leave suspend and 144 Hz for later.

```sh
cat /sys/module/msm/parameters/a14_dp_dsc_test
sudo journalctl -b -k --no-pager | rg 'A14-DSC-test|A14-DP: stream enable failed'

sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-dsc-4k60/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-dsc-4k60-test.tar.gz
```

Upload the archive and state whether the external desktop is usable at 4K60,
whether the internal screen is normal, and whether Ethernet works. The
recorder performs reads only, with bounded readers for AUX/debugfs. It also
records the actual booted system, module parameter, local source changes,
EDID, connector state, boot-recovery journal and DSC/FEC registers.

Expected evidence: parameter `Y`; configuration log says RGB8 DSC8, two
slices of width 1920 and height 108; FEC decode detected; DSC_ENABLE bit 0
set in the AUX capture. The debug display of `bpp=24` is the SOURCE depth
and does not by itself establish compression. An image or a 4K60 mode alone
also does not prove DSC is active. Missing capability or failed activation
messages are useful results; do not keep resetting the dock to hide them.

## Rollback

If the display experiment prevents use of the machine, select the previous
NixOS generation in the boot menu. No firmware update is involved.

To remove only this experiment from the local repository:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-dsc-4k60-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Then reboot after the successful build. Removal checks owned file contents
before deleting them and preserves edits outside its exact integration blocks.
It does not restore kernel.nix from old git HEAD, which would discard the
working local changes. If you added the parameter manually, remove it too.
`--check` validates without writing, and rerunning apply is idempotent.

## Validation and limits

- Built all enabled MSM driver objects and linked `drivers/gpu/drm/msm/msm.o`
  with the captured ARM64 configuration, GNU GCC 13.2 and binutils 2.42.
  DP, DPU and DSI were enabled. Build-only changes disabled BTF/GCC plugins
  and certificate paths for the local toolchain; these are not delivered.
- Exercised the actual DSC TU calculation on the host using the pinned
  drm_fixed.h implementation and simple userspace compatibility definitions.
  HBR2 x2 and HBR3 x2 produce bounded valid TU parameters for the test timing.
  HBR x2 is rejected by the mode/stream bandwidth and test-scope checks.
- Checked preservation of the original uncompressed TU implementation and
  unrelated PHY/USB files, clean patch application after captured postPatch,
  and installer apply/idempotence/refusal/removal on temporary repo copies.
- This is NOT a full NixOS build, a hardware validation, or an upstream-ready
  driver implementation. The user's NixOS build and hardware test are next.
  Shared DPU/DSI structures are touched; the boot parameter does not erase
  those source changes. The previous generation is the full rollback.
- Successful 4K60 DSC would validate the compression path, not 4K144. The
  latter needs another scoped change, four slices (960 pixels each), its
  1333330 kHz timing, and testing of clocks, transport and dock behavior.

## Provenance

Adapted from JS Deck's May 2026 DSC candidate, commit
`fac6d5b9dfb715a2d849365f62ddc9b8310992bf`:
https://gist.github.com/xzn/028a18f78f6fa6f08a8a0d6a3d29c232

That candidate was based on Kuogee Hsieh's Qualcomm DP DSC series:
https://lore.kernel.org/lkml/1674498274-6010-1-git-send-email-quic_khsieh@quicinc.com/

Original source notices are retained. This adaptation removes unrelated
candidate CRTC/CWB/command-mode changes, retains the baseline uncompressed
TU code, corrects capability checks and encoder initialization, uses the
actual DSC slice count, and avoids overwriting DP DTO counts during DPU setup.
