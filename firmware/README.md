This is an empty firmware input placeholder, not a firmware download.

Keep Windows firmware in a separate directory. To build an ISO:

    nix build .#iso --override-input windows-firmware path:/absolute/path/to/firmware

For an installed system, set hardware.asus.zenbookA14.firmwareSource instead.
See ../docs/firmware.md. Do not commit extracted binaries to this public project.
