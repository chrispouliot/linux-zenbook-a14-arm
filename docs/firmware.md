# Supply the Windows firmware

The public project does not contain the factory Windows firmware. Supply files
from your own UX3407NA installation or its matching unpacked driver packages.
Do not substitute firmware from an X1 A14 or a different board.

Your already extracted A14 `firmware/` directory can be reused as-is. The tool
checks 13 files. `hmtbtfw20.ver` is not required by the Linux packaging.

| Purpose | Required filenames |
| --- | --- |
| Audio/compute DSP images | `qcadsp8480.mbn`, `qccdsp8480.mbn` |
| Board DSP device trees | `adsp_dtbs.elf`, `cdsp_dtbs.elf` |
| Wi-Fi board data | `bdwlan_qcc2072_1p0_ncm820A.elf` |
| Bluetooth patch and NVM | `hmtbtfw20.tlv`, `hmtnv20.bin`, `hmtnv20.b3b`, `hmtnv20.b105`, `hmtnv20.b107`, `hmtnv20.b108`, `hmtnv20.b10f`, `hmtnv20.b112` |
| Video codec image (optional) | `qcvss8480.mbn`, only for `experimental.video.enable`; collected when present, skipped with a warning otherwise |

The generic QCC2072 `firmware-2.bin` is fetched separately from the pinned
linux-firmware source. You do not need to find that file in Windows.
The AudioReach topology is built from source automatically.

## Collect while running Windows

Download/unpack this project on Windows. In an elevated PowerShell terminal,
from its directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-A14Firmware.ps1 -Destination "$env:USERPROFILE\Desktop\a14-firmware"
```

This searches `C:\Windows\System32\DriverStore\FileRepository` by default.
It reads files and copies only the required set; it does not modify installed
drivers. If required files are absent from DriverStore, search all of System32:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Collect-A14Firmware.ps1 -Source "$env:windir\System32" -Destination "$env:USERPROFILE\Desktop\a14-firmware"
```

You may instead pass the directory of an already unpacked, matching ASUS driver
package. These tools search by filename; they do not unpack installers, decrypt
BitLocker volumes, or manufacture missing board files. If files remain absent,
retain Windows and obtain the matching driver package before continuing.

When multiple versions exist, a file matching the tested reference is preferred.
If none matches and conflicting versions remain, collection fails and asks you
to narrow the source directory. One unique non-reference version is accepted
with a warning, or rejected when `-Strict` is supplied. Reference hashes identify
the original tested set, not all firmware versions that could work.

Several reference Bluetooth NVM names have identical bytes. If one such name
is absent, the collectors can recreate it from another listed file only when
that file's hash exactly matches the missing file's reference hash. They never
guess equivalent aliases for unfamiliar firmware versions.

Copy the resulting `a14-firmware` directory to the Linux build machine or a
separate USB drive. Keep an additional backup before repartitioning or removing
Windows. The PowerShell collector has not been run on Windows in this packaging
environment; use the Linux validator below before building.

## Collect from Linux

With a Windows volume already mounted read-only, or unpacked driver files:

```bash
python3 scripts/firmware.py collect /mnt/windows/Windows/System32 \
  --output "$HOME/a14-firmware"
```

Multiple source directories can be supplied. Discovery is case-insensitive and
the output is normalized to Linux's required filenames. A conflicting existing
destination file is never overwritten; use a new output directory instead.
If Windows is encrypted, collect from within Windows or unlock it using your
normal recovery procedure first.

## Validate files you already have

```bash
python3 scripts/firmware.py validate "$HOME/a14-firmware" --strict
```

Without `--strict`, differences from the reference generate warnings while
missing/empty files still fail. Validation cannot prove that an unfamiliar
firmware version works on hardware. Do not silence a differing hash by editing
the reference manifest.

The standalone tool requires Python 3.11 or newer. If it is not installed, Nix
can run the same tool:

```bash
nix run .#firmware -- validate "$HOME/a14-firmware" --strict
```

## Supply an installed configuration

With a firmware directory inside the flake source:

```nix
hardware.asus.zenbookA14.firmwareSource = ./firmware;
```

The module installs the DSP files under
`qcom/glymur/ASUSTeK/UX3407NA/`, the Wi-Fi board file as
`ath12k/QCC2072/hw1.0/board.bin`, and Bluetooth files under `qca/`, using NixOS's
firmware mechanism. No manual copying into `/lib/firmware` is required.

In a Git-backed flake, local path references only see tracked files. Tracking a
file locally does not require publishing it, but do not push the firmware to a
public repository. The following input method is preferable for public configs.

## Keep firmware outside your configuration repository

Place the directory somewhere durable on the local machine and add a non-flake
input, using the actual absolute path on that machine:

```nix
inputs.a14-firmware = {
  url = "path:/home/chris/Firmware/a14";
  flake = false;
};
```

Add `a14-firmware` to the outputs arguments, then use:

```nix
{
  hardware.asus.zenbookA14.firmwareSource = a14-firmware.outPath;
}
```

The lock records a local path and content hash, not the binaries themselves.
Another machine must supply its own path or use
`--override-input a14-firmware path:/its/firmware/directory`. Keep the path stable
and available for evaluation. Root also needs to be able to read it during
`nixos-rebuild` and `nixos-install`.

The module import stays identical with either firmware method. Both methods
copy firmware into the Nix store and include it in system closures; do not
publish those closures or an ISO containing the files just because the source
repository is public. The original source marks these factory files as not for
redistribution.

## Supply an ISO build

The shared project's ISO outputs use the separate `windows-firmware` input:

```bash
nix build .#iso \
  --override-input windows-firmware path:/absolute/path/to/a14-firmware \
  --no-write-lock-file -L
```

This override is needed for ISO builds, not for importing the hardware module
into a system that already sets `firmwareSource`. The placeholder input contains
only a README; attempting an ISO without supplying firmware fails early with
the missing filenames.

The ISO exposes its supplied source at `/etc/a14-firmware`. During installation:

```bash
sudo a14-firmware copy /etc/a14-firmware /mnt/etc/nixos/firmware
```

The copy command validates the full set and refuses to overwrite different
existing files. This supplies the target flake for its initial installation and
future rebuilds; it is not a one-time hardware flash.
