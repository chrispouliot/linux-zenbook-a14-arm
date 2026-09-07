# Source provenance

Initial extraction from:

- Repository: https://github.com/chrispouliot/nixos
- Commit: `db6b0694d6c8d66b846bd1782edc5e268f788430`
- Directory: `zenbook-a14-x2e-arm`

The original `kernel.nix` is retained with only two changes: an optional
`scmiMailbox` argument (default false), and conditional inclusion of its
diagnostic patch. The whole `postPatch` definition and all files in `patches/`
are preserved byte-for-byte. Their extracted checksums are recorded in
`source-file-checksums.json`.

The original `a14.nix` was separated into hardware settings, audio settings,
firmware packaging, optional ramoops diagnostics, and the personal configuration
in the accompanying owner migration. Hardware settings use defaults where
appropriate. New users get unity speaker gain and no fixed RAM reservation or
SCMI mailbox experiment. The migration explicitly restores the source owner's
values. No attempt was made to rewrite the kernel's embedded C transformations
or remove its interdependent diagnostic instrumentation.

Pinned source dependencies retained from the original lock:

| Dependency | Revision |
| --- | --- |
| Nixpkgs | `34ab99075ac4f7e40cf037eef32cb1c360bb85e9` |
| linux-msm/laptops-kernel | `51231839d5ef007638bd1c3500e6a76b337a66f3` |
| linux-msm/audioreach-topology | `e7b20b2b16cdda18eb8ae143c8d95c4815c0288e` |
| kernel-firmware/linux-firmware | `25c06030aa434817928ace452c06f095f14729d3` |

The original lock hashes are retained rather than regenerated against unrelated
versions. ISO device-tree support uses the same upstream patch as the original
flake; see `vendor/README.md` for its author, source revision and MIT notice.

The public repository contains no Windows firmware, user account configuration,
disk UUIDs, personal application inputs or Proton Bridge certificate. The
accompanying `a14-migration` is separate personal material and is not intended
for the hardware repository.

## Attribution and licensing

Retain the notices and authorship in all imported kernel patches, device-tree
files and upstream code. Kernel changes are derived from the Linux sources and
are subject to their applicable source licenses. Nixpkgs' vendored ISO module
retains its notice in `vendor/COPYING.nixpkgs`. This extraction does not assign a
new blanket license to the original project's imported material. No firmware
redistribution permission is asserted by the extraction or its checksum list.
