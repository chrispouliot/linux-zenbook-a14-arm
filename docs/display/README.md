# A14 display stack

This is the tested A14-specific display stack for kernel commit
`51231839d5ef007638bd1c3500e6a76b337a66f3`. Its latest packaging changes preserve
all 38 reconstructed kernel source files byte-for-byte. They do not establish
generic dock compatibility or prove that every retained workaround is needed.

## Layout and patch order

`kernel.nix` retains kernel configuration and the initial platform patches.
`kernel/a14-post-patch.nix` appends the existing DT fragments, applies the
[extracted platform patches](PLATFORM.md), and runs retained source checks,
followed by this display series:

| Order | Patch | Purpose |
| --- | --- | --- |
| 1 | `patches/a14-display-dsc.patch` | DSC/FEC pipeline, PPS, bandwidth/mode handling, and the 4K144 extension. |
| 2 | `patches/a14-display-lifecycle.patch` | Wake, AUX, HPD, and link teardown corrections, diagnostics, and gated alternatives. |
| 3 | `patches/a14-display-transparent-lttpr.patch` | The guarded transparent-repeater path that made the tested dock reliable. |
| 4 | `patches/a14-display-edp-depth.patch` | Native internal colour-depth finalization after powered capability setup. |

**Apply all four in order.** They are review boundaries, not independent optional
features. Earlier stages contain intermediate states corrected by later patches.
The previous `a14-display-stack.patch` is replaced by their combined result.
`series.json` records the order, hashes, affected files, and historical inputs.

- `display/default.nix`: one module entry point, preserving the original order.
- `display/options/`: existing option definitions and kernel parameters. Names
  containing `Test` or `_test` remain compatible with existing configurations.
- `display/dock-recovery.py`: retained optional userspace boot recovery v4.
- `tools/a14-display-capture.py`: canonical read-only diagnostic recorder.
- `tools/a14-verify-display-series.py`: reproducible source comparison.
- `docs/display/HISTORY.md`: investigation decisions and test results.
- `docs/display/history/`: historical notes, not current instructions.

The eighteen older Python rewrites have been extracted into ordinary patches
under `patches/platform/`. Their resulting source is unchanged. Removing
diagnostics and deleting obsolete runtime alternatives remain separate
follow-up changes. Firmware, audio,
USB, SCMI, flake inputs, and the base hardware module are unchanged by this extraction.

## Working configuration

The tested path is laptop port one -> Amazon Basics TB4/USB4 dock -> USB-C to
DisplayPort cable -> 4K monitor. It has run 3840x2160 at 144 Hz, HBR3 with two
lanes, DSC at 8 compressed bits/pixel, FEC, and RGB 8-bit source colour. The
internal panel uses 1920x1200 at 60 Hz, HBR with two lanes and 24 bits/pixel after
the eDP-depth correction. The second external controller retains an HBR2 cap.

Transparent LTTPR is a DisplayPort repeater/link-training mode, not a monitor
standby mode. It is selected only under the retained A14 port-one, inactive-link,
and two-repeater guards; physical repeater capability limits remain respected.
All the other lifecycle corrections remain present.

Repeated dock boot, display standby, full suspend, clamshell standby and replug
have passed during this investigation. The first packaging cleanup also passed
boot and suspend on the device. An overnight suspend was reported successful
before cleanup; no overnight capture was supplied. Other docks, reversed cable
orientation, and untested configurations remain outside that validation.

## Recovery v4 and the personal configuration

After the first cleanup, the owner disabled
`hardware.a14DockBootRecovery.enable` in the personal NixOS configuration.
A subsequent docked boot reportedly worked with no recovery delay and loaded in
about five seconds. This supports testing without v4; it is not a complete
matrix proving recovery unnecessary for every dock or boot condition.

The repo's v4 module remains available, unchanged. It only overrides an already
enabled personal recovery service. The original personal v3 module defines the
option; the public repo does not define or enable it. Keeping the personal
module imported with this setting disables both service definitions:

```nix
hardware.a14DockBootRecovery.enable = false;
```

Do not add this assignment to a configuration that never imported the personal
module: the option would be undefined. If removing that personal module, remove
its option assignment too. Disabling recovery does not disable DSC, transparent
LTTPR, or eDP depth. This installer does not edit `/etc/nixos` or change the
recovery setting. It does not remove the v4 override, which could otherwise
expose the older v3 service in a configuration that still enables the option.

Config reuse, explicit repeater reset, older eDP-bpp finalization, and bounded
sink cleanup retain their disabled settings. AUX/state diagnostics remain on.
Historical experiment installers target the old layout and must not be applied
to this reorganized stack.

## Install the platform-patch extraction

Run the supplied installer as your normal user:

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-extract-platform-patches.py \
  ~/Projects/linux-zenbook-a14-arm --check

nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-extract-platform-patches.py \
  ~/Projects/linux-zenbook-a14-arm

cd ~/Projects/linux-zenbook-a14-arm
git diff --stat
git status --short
```

The installer checks the tested four-patch display layout before any edits. It preserves
unrelated files and the Git index and creates no backup. `--check` is read-only;
repeating installation is a no-op. `--remove` restores the previous Python-rewrite
recipe if the affected files have not changed. Git history remains the
long-term restore point. The baseline matches the relevant files in public
commit `d65db6f`; the installer checks file
contents, not HEAD, so unrelated commits are allowed.

Stage the new files so Git-backed flakes can include them, review, then rebuild:

```sh
git add -A -- README.md kernel/a14-post-patch.nix patches/platform docs/display tools/a14-verify-display-series.py
git diff --cached --stat
git diff --cached --check
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

The installer does not stage, commit, push, rebuild, or reboot. Nix may rebuild
the kernel because its postPatch recipe and patch inputs changed even though the resulting source is
identical. After a successful build, a normal dock boot and standby/wake check
provide a practical integration check. Keep recovery disabled during that check
if it is already disabled; this is not a new recovery experiment.

## Validation

The extracted platform patches and the four display patches apply in order
with zero fuzz and no offsets. Running the full
local default patch recipe against the pinned source produces the same hashes
for all 38 reconstructed files as the tested combined stack. All option modules,
recovery code, the four display patches, and the existing recorder are unchanged. No additional kernel
compilation or hardware execution was needed for the source comparison. NixOS
evaluation was not available in the packaging environment.

For an independent source check, use a local kernel Git checkout containing the
pinned commit and a new output directory:

```sh
nix shell nixpkgs#python3 nixpkgs#git nixpkgs#patch nixpkgs#bash --command python3 \
  tools/a14-verify-display-series.py \
  --kernel-source /path/to/local/kernel-git-checkout \
  --output ~/a14-display-series-verification
```

This tool executes the trusted repository's patch recipe in a new directory,
never in the input kernel checkout. It does not build/install a kernel or
evaluate Nixpkgs-inherited patches. The optional SCMI variant is outside this
default-source comparison. Use `source-sha256.json` and the resulting log to
review the comparison; the tool rejects changed platform/display patch hashes and order.

For device diagnostics:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/tools/a14-display-capture.py \
  ~/Projects/linux-zenbook-a14-arm \
  ~/a14-display-series-boot.tar.gz
```

The recorder performs no resets or modesets. Its optional `--delay SECONDS`
argument waits before capture. Journals are saved before read-only AUX access;
those reads can still wake hardware. Use a fresh output filename.
