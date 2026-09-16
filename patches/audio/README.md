# A14 two-speaker UCM backport

These three new UCM files are copied without content changes from
alsa-project/alsa-ucm-conf PR #858, commit
`c9d323590229951391433ed88ae2061df897ff2b`:
https://github.com/alsa-project/alsa-ucm-conf/pull/858

The upstream BSD-3-Clause license is included as `LICENSE`.
`modules/audio.nix` overlays them on the pinned alsa-ucm-conf tree and keeps
our existing DMI card-name mapping, now pointing to the dedicated A14 config.
The topology remains in `../a14-hdmi-topology.m4` to preserve HDMI audio.
See `../../docs/BOARD-V2-BACKPORT.md` for migration and validation details.
