# NixOS on ASUS Zenbook A14 UX3407NA — Snapdragon X2 Elite

A reusable NixOS hardware module and installer builder extracted from
[Chris's A14 configuration](https://github.com/chrispouliot/nixos/tree/db6b0694d6c8d66b846bd1782edc5e268f788430/zenbook-a14-x2e-arm).

**Initial extracted release: requires a build and boot test on the A14 before
being advertised as a tested installer.** It retains the source kernel's current
limitations. This is for **UX3407NA / X2 Elite / Glymur**, not the earlier
Snapdragon X1 A14 variants. See [validation status](docs/validation.md).

## What it supplies

- Pinned `7.2.0-rc5-next-20260731` Glymur kernel, configuration, patches and
  embedded `postPatch` changes.
- UX3407NA device tree, EC overlay, early boot drivers and suspend workarounds.
- Factory firmware packaging plus the pinned QCC2072 runtime Wi-Fi firmware.
- AudioReach topology, UCM, speaker channel routing, PipeWire and HDMI hotplug.
- Overridable graphics/Bluetooth defaults and hardware power-management quirks.

It does not create users, select a desktop, configure disks, set a CPU governor,
install personal applications, or enable your personal network services.
Some display limitations and diagnostic instrumentation are still present;
see [hardware status and options](docs/hardware.md).

## Import into an existing flake

Once this project is published at the proposed GitHub location:

```nix
inputs.a14.url = "github:chrispouliot/nixos-a14";
```

Add `a14` to the outputs arguments and include these in your system's modules:

```nix
a14.nixosModules.default
{ hardware.asus.zenbookA14.firmwareSource = ./firmware; }
```

Retain your own `hardware-configuration.nix`, bootloader, users, desktop,
applications and governor module. Remove the old kernel assignment and the old
combined hardware module to avoid applying the fixes twice. The kernel and
build-time hardware dependencies use this project's pinned nixpkgs; do not add
`a14.inputs.nixpkgs.follows = "nixpkgs"` unless intentionally testing another
hardware build environment.

Before publication, use a local input such as
`a14.url = "path:/home/chris/Projects/nixos-a14";`.

`./firmware` must be included in the flake source. In a Git-backed flake, untracked
or ignored binaries are not available through this reference. For a public
configuration repository, use the [separate private firmware input](docs/firmware.md#keep-firmware-outside-your-configuration-repository).

## Build an installer ISO

From this project directory on a Linux machine with Nix and flakes enabled:

```bash
python3 scripts/firmware.py validate /absolute/path/to/firmware --strict
nix build .#iso \
  --override-input windows-firmware path:/absolute/path/to/firmware \
  --no-write-lock-file -L
```

On `aarch64-linux` this builds natively. On `x86_64-linux` it cross-compiles the
ARM64 installer, including the kernel. Cross builds can compile considerably
more userspace than native builds. The image appears under `result/iso/`.
There is no prebuilt custom-kernel binary cache configured.

The ISO includes the device tree in the EFI boot menu and carries the supplied
firmware for both the live environment and transfer to the installed system.
Build it privately: the ISO contains your supplied Windows firmware.

Read [firmware extraction and supply](docs/firmware.md), then the complete
[ISO and installation guide](docs/installation.md). A consumer flake can also
use `a14.lib.mkIso { firmwareSource = ./firmware; };`.

## Existing owner migration

The accompanying `a14-migration` directory is a prepared migration for Chris's
configuration snapshot. It retains personal software/settings and enables the
original SCMI experiment, speaker gain and 32 GiB crash diagnostic explicitly.
It contains no firmware binaries. Follow [the migration guide](docs/migration.md)
before replacing files in `/etc/nixos`.

## Repository guide

| Path | Purpose |
| --- | --- |
| `flake.nix`, `flake.lock` | Public module, pinned inputs, ISO helper and build outputs |
| `kernel.nix`, `patches/` | Original kernel logic; SCMI experiment is configurable |
| `modules/` | Hardware, audio, installer and optional ramoops configuration |
| `pkgs/windows-firmware.nix` | Exact filename-to-Linux-path packaging |
| `firmware-manifest.json` | Required names, destinations and reference checksums |
| `scripts/` | Windows and Linux firmware collection/validation |
| `examples/installed/` | Minimal personal flake and GNOME configuration |
| `vendor/` | Pinned NixOS ISO module with the device-tree boot patch |
| `docs/` | Setup, migration, options, provenance and validation |

Firmware is required by every installed system generation, not just the ISO.
Keep the extracted source backed up for future rebuilds. Updating the module
does not require re-extracting firmware unless a future release explicitly
changes its requirements.
