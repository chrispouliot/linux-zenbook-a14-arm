# Validation of the initial extraction

Validated with Nix 2.31.2 on an x86_64 Linux build environment, using the original
source/lock pins. No access to the physical A14 was available.

| Check | Result |
| --- | --- |
| Parse shared project and owner migration Nix files | Passed |
| Native ARM64 ISO derivation evaluation | Passed |
| x86_64-to-ARM64 ISO derivation evaluation | Passed |
| Installed GNOME example with default hardware profile | Full toplevel derivation evaluation passed |
| Installed GNOME example with owner diagnostic hardware profile | Full toplevel derivation evaluation passed |
| Core module's CPU governor selection | Remains unset; personal policy is not imposed |
| Default device-tree overlays | EC overlay only; no fixed RAM reservation |
| Owner diagnostic device-tree overlays | EC plus the original ramoops overlay |
| ISO without Windows firmware | Rejected during evaluation with the 13 missing filenames |
| Linux firmware tool | Built with Nix; packaged `nix run .#firmware` command tested |
| Firmware discovery/copy unit checks | Seven passed, directly and as the Nix check derivation |
| Existing source firmware | All 13 required reference hashes matched |
| Windows firmware package | Built locally; all 13 installed Linux paths and bytes verified |
| Kernel patch applicability | All initial patches and the complete embedded postPatch apply without fuzz in both SCMI modes |
| Embedded kernel postPatch preservation | Byte-for-byte unchanged from the original definition |
| Vendored ISO device-tree patch | Applies without fuzz to the pinned module |

The patch-application check used the actual Nix-evaluated patch list and custom
postPatch body against the pinned kernel's affected files. It included the
Nixpkgs randstruct patch and all 15 affected source files. This confirms patch
applicability, not that the resulting kernel compiles or runs correctly.

Still required on the A14 or an appropriate builder:

- Full custom kernel compilation and full ISO build.
- USB/UEFI boot of the new ISO, partition visibility and installation.
- First boot of the installed system and device-tree/firmware loading.
- Audio, display, USB/dock, suspend/resume, networking and Bluetooth checks.
- Running the PowerShell collector on Windows. Its logic was reviewed; no
  Windows/PowerShell runtime was available for an execution test.
- Evaluation/build of Chris's complete personal migration on his machine. The
  local Vireo/Decibels inputs are not available here; only the extracted hardware
  profiles and unchanged personal-file preservation were checked locally.

No claim of a full kernel build, boot-tested ISO, or universally working X2 Elite
support is made. Keep a known-good boot generation during migration.

## Reproduce the quick checks

```bash
python3 -m unittest discover -s tests -v
python3 scripts/firmware.py validate /absolute/path/to/firmware --strict
nix build .#checks.x86_64-linux.firmware-tools
nix eval .#packages.x86_64-linux.iso.drvPath --raw \
  --override-input windows-firmware path:/absolute/path/to/firmware \
  --no-write-lock-file
```

Use `packages.aarch64-linux.iso` for the native ISO derivation. Follow the
installation/migration guides for the subsequent full build and hardware tests.
Evaluating a derivation does not build it.
