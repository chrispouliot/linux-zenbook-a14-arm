# Migrate Chris's existing configuration

The sibling `a14-migration` directory is prepared from
`chrispouliot/nixos` commit `db6b0694d6c8d66b846bd1782edc5e268f788430`.
It is specific to Chris's system and must not be presented as a generic example.
Its disk UUIDs, user and application paths are retained from that snapshot.
No files on the actual laptop have been modified by preparing this bundle.

## What changed

- `flake.nix` imports `a14.nixosModules.default` and `./personal.nix` instead of
  the combined `./a14.nix` and local kernel package assignment.
- The shared flake owns kernel, topology and QCC2072 firmware source inputs.
  Personal flake inputs, including local Vireo/Decibels projects, remain.
- `personal.nix` retains applications/services, Flatpaks, swap/zram, NetworkManager
  and power governor imports. It explicitly retains speaker gain `1.50`, the
  SCMI mailbox experiment and the original verbose/ramoops diagnostic profile.
- `installed.nix`, `hardware-configuration.nix`, governor, Steam/Hytale and
  other personal files are copied unchanged.
- ISO outputs now use `a14.lib.mkIso`. They intentionally use the generic
  installer defaults, without personal applications or the fixed RAM reservation.
- No Windows firmware binaries are in the bundle. Copy your existing directory.

The shared default has unity speaker gain, SCMI experiment off and ramoops off.
The migration explicitly opts into your current values so the initial hardware
comparison does not accidentally drop them.

## Test from a staging directory first

Unpack the bundle so `nixos-a14/` and `a14-migration/` are siblings, for example
under `~/Projects/a14-sharing/`. The migration's local `a14` input points to
`/home/chris/Projects/a14-sharing/nixos-a14`. If you unpack elsewhere, edit
`a14.url` in the staged `flake.nix` to that shared project's actual **absolute**
path before locking/building. Relative inputs outside a flake's source directory
are not reliable in pure evaluation.

Copy the firmware from your actual configuration into the staging migration:

```bash
cd ~/Projects/a14-sharing
cp -a /etc/nixos/firmware a14-migration/firmware
python3 nixos-a14/scripts/firmware.py validate a14-migration/firmware --strict
```

If your current `/etc/nixos` differs from the GitHub snapshot, merge those
differences into the staged migration before building. In particular preserve
newer patches and current disk configuration; this bundle cannot see local
changes that were never pushed to GitHub.

The migration retains local app inputs such as `/home/chris/Projects/vireo`
and `/home/chris/Projects/decibels`. They must exist on your A14, as before.
The supplied lock preserves their original entries. Adding the new `a14` input
will update the lock without intentionally upgrading the other inputs:

```bash
cd a14-migration
nix flake lock
nix build .#nixosConfigurations.a14.config.system.build.toplevel -L
```

Do not run a blanket `nix flake update` for the first migration. The first build
may rebuild the kernel because its derivation changed during packaging. A
matching version string does not mean Nix will reuse the old kernel build.

After the build succeeds, test the next boot while leaving the running system
alone:

```bash
sudo nixos-rebuild boot --flake .#a14
sudo reboot
```

This writes a new boot generation. Keep the earlier generation in the boot
menu. Check display/dock, Ethernet across suspend, internal/HDMI audio,
Wi-Fi/Bluetooth and the AC/battery governor switching. If anything regresses,
boot the previous generation before changing additional variables.

## Make the migration your normal configuration

After testing, back up `/etc/nixos` and merge the new `flake.nix` and
`personal.nix` into it. Keep your actual firmware, generated hardware file and
personal app files. Remove the old hardware import and kernel assignment;
the old `a14.nix`, `kernel.nix` and `patches/` can remain as unused backups until
you are satisfied with the migration.

When moving the flake to `/etc/nixos`, change the local input to the actual
stable absolute project path, for example:

```nix
a14.url = "path:/home/chris/Projects/a14-sharing/nixos-a14";
```

Or, after you publish the shared project:

```nix
a14.url = "github:chrispouliot/nixos-a14";
```

Run `nix flake lock` to record the changed input. If `/etc/nixos` is Git-backed,
track the new Nix files before rebuilding. Your existing tracked firmware
directory works with `firmwareSource = ./firmware`; the private local input
method is also available in [firmware.md](firmware.md).

Only the `nixos-a14/` directory belongs in the proposed public hardware repo.
`a14-migration/` is your personal configuration, not part of the hardware module.
