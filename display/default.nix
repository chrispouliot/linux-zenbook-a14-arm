# Keep module ordering and legacy option names for existing user overrides.
# Consolidation changes packaging only; see ../docs/display/README.md.
{
  imports = [
    ./options/dsc-4k60.nix
    ./options/dsc-144.nix
    ./options/dsc-wake.nix
    ./options/aux-wake.nix
    ./options/dock-hpd.nix
    ./options/edp-retry.nix
    ./options/pair-config.nix
    ./options/sink-power.nix
    ./options/state-trace.nix
    ./options/config-reuse.nix
    ./options/repeater-restore.nix
    ./options/dock-recovery-v4.nix
    ./options/sink-cleanup.nix
    ./options/review-theories.nix
    ./options/repeater-reset.nix
    ./options/transparent.nix
    ./options/edp-depth.nix
  ];
}
