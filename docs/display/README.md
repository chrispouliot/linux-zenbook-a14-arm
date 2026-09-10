# A14 display stack

This packaging cleanup preserves the working A14 kernel source and runtime
settings captured in `a14-edp-depth-standby.tar.gz`. It does not claim generic
DisplayPort support or prove that every retained workaround is necessary.

## Layout

- `kernel.nix`: kernel inputs/configuration and initial platform patches.
- `kernel/a14-post-patch.nix`: existing platform source transformations, followed
  by the consolidated display patch. The older inline platform edits remain here
  verbatim; extracting those into ordinary patches is a separate cleanup.
- `patches/a14-display-stack.patch`: the final result of sixteen chronological
  display patches, including DSC and the subsequent lifecycle corrections.
- `display/default.nix`: one entry point, preserving the old option-module order.
- `display/options/`: the existing option definitions and module parameters.
  Names containing `Test` and `_test` intentionally remain compatible.
- `display/dock-recovery.py`: the unchanged v4 boot recovery implementation.
- `tools/a14-display-capture.py`: one recorder for all display investigations.
- `docs/display/HISTORY.md`: decisions, test results, and original patch order.
- `docs/display/history/`: historical experiment notes, not current instructions.

The default flake module imports `./display`. Existing application, firmware,
audio, USB, SCMI, and base hardware module integration is preserved. No firmware
input or lock-file change is part of this cleanup.

## Working configuration

The tested topology is laptop port one -> Amazon Basics TB4/USB4 dock -> USB-C to
DisplayPort cable -> 4K monitor. The external link has run 3840x2160 at 144 Hz,
HBR3 with two lanes, DSC at 8 compressed bits/pixel, FEC, and RGB 8-bit source
colour. The internal display uses 1920x1200 at 60 Hz, HBR with two lanes and
24 bits/pixel after the eDP depth correction.

The successful dock change is **transparent LTTPR mode**. This is a DisplayPort
repeater/link-training mode, not a monitor standby mode. It is selected under the
existing A14 port-one, inactive-link, two-repeater guards. The physical repeater
capability limits remain respected. The other wake/lifecycle changes remain.

Recovery v4 stays controlled by the existing
`hardware.a14DockBootRecovery.enable` option. This module still only overrides
an already-enabled service; it does not define or turn on that external option.
The service's timing, topology guards, storage check, reset policy, and boot
ordering are unchanged. The recovery script's store path changes with its move.

No runtime experiments are removed in this pass. In particular, config reuse,
the explicit repeater-reset experiment, the older eDP-bpp experiment, and bounded
sink cleanup retain their disabled settings. AUX/state diagnostics remain on.
Do not run historical experiment installers against this reorganized tree.
They expect the old file layout and baseline hashes.

## Install and review

Run the supplied `a14-cleanup-display-stack.py` installer as your normal user:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-cleanup-display-stack.py \
  ~/Projects/linux-zenbook-a14-arm --check

nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-cleanup-display-stack.py \
  ~/Projects/linux-zenbook-a14-arm

cd ~/Projects/linux-zenbook-a14-arm
git diff --stat
git status --short
```

The installer checks the exact captured integration, patches, and experiment
files before changing anything. It leaves unrelated files and the Git index
alone, creates no backup copy, and refuses a different baseline. `--check`
performs the same preflight without writing. A second install is a no-op.
`--remove` restores its exact previous file set, provided the cleanup-owned
files have not subsequently changed. Git history is also your restore point.

Stage the specific cleanup paths so the new files are included in the flake:

```sh
git add -A -- kernel.nix flake.nix kernel patches display tools docs/display experiments
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review staged changes before committing. The installer does not stage or commit.
If the old experiment directory contained additional user files, those remain.
If you directly imported an old experiment module outside this repository,
update that import to the default flake module or the appropriate module under
`display/options/`; the default flake import is already migrated.

Nix may rebuild the kernel because its recipe/patch store inputs changed, even
though the resulting patched C and DT source is identical. This cleanup is not
an ABI, frequency, pixel-depth, or suspend-behaviour change.

## Verification and the next test

The old and new default patch recipes were reconstructed against kernel commit
`51231839d5ef007638bd1c3500e6a76b337a66f3`. All 38 reconstructed source files were
byte-identical. All 27 paths touched by the consolidated display patch matched
the previously compiled source tree. The patch applied with no fuzz or offsets.
The optional SCMI patch is unchanged and passed an applicability dry run.

All seventeen option-module bodies and their ordering were checked for identity,
allowing only the relocated recovery-script reference. Its Python bytes are
identical. NixOS evaluation and hardware execution were not performed in the
packaging environment. Source hashes are recorded in `source-sha256.json`.

After rebuilding and rebooting, check normal dock boot, 4K144, Ethernet, and one
ordinary standby/wake. Capture the result with the canonical recorder:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/tools/a14-display-capture.py \
  ~/Projects/linux-zenbook-a14-arm \
  ~/a14-cleanup-boot.tar.gz
```

The optional `--delay SECONDS` argument waits before recording. The recorder
performs no resets or modesets. It saves journals before read-only AUX register
access; those reads can still wake hardware. Keep the existing connection and
use a fresh output filename. Runtime paths/parameters and recovery service state
are included along with the reorganized source files.

Once this packaging baseline is verified, the next independent experiment is
to disable recovery v4 while keeping transparent LTTPR and every kernel setting
unchanged. Do not combine that test with this cleanup. Only after it succeeds
should we consider removing its boot delay or retiring individual diagnostic
and retry paths. Upstream review will require separating generic fixes from
board/topology-specific workarounds and the experimental DSC integration.
