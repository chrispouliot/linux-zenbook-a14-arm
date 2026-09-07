# Vendored NixOS ISO module

`iso-image.nix` is from Nixpkgs revision
`34ab99075ac4f7e40cf037eef32cb1c360bb85e9`, under the Nixpkgs MIT license
in `COPYING.nixpkgs`.

Applied upstream patch:
https://github.com/NixOS/nixpkgs/commit/de1fdb6310af8f70c98746ba4550dc2799a03621
("nixos/iso-image: add devicetree support", György Kurucz).

The patch applies without fuzz (one hunk has a line offset). The module's
`file-options.nix` and `make-iso9660-image.nix` imports are rewritten relative to
`modulesPath` so the vendored file can live here. No other behavior is changed.
The installer disables the original `installer/cd-dvd/iso-image.nix` module and
imports this file. This avoids import-from-derivation and patching the consumer's
entire nixpkgs during evaluation.

Use this module with the pinned Nixpkgs through `lib.mkInstaller` / `lib.mkIso`.
When updating the pin, check whether native device-tree ISO support has landed
and remove this copy if it is no longer necessary.
