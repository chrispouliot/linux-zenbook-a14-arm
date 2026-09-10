{ config, lib, pkgs, ... }:
let
  enabled = lib.attrByPath [ "hardware" "a14DockBootRecovery" "enable" ] false config;
in {
  # Override the existing service only when the existing user option is enabled.
  # Removing this experiment returns to the previously imported recovery module.
  config = lib.mkIf enabled {
    systemd.services.a14-dock-boot-recovery = {
      description = lib.mkForce "A14 port-one dock boot recovery v4 (experimental)";
      wantedBy = lib.mkForce [ "multi-user.target" ];
      wants = lib.mkForce [ "sys-kernel-debug.mount" "sys-kernel-tracing.mount" ];
      after = lib.mkForce [ "systemd-udev-trigger.service" "sys-kernel-debug.mount" "sys-kernel-tracing.mount" ];
      before = lib.mkForce [ "display-manager.service" "NetworkManager.service" ];
      path = [ pkgs.systemd ];
      restartIfChanged = false;
      stopIfChanged = false;
      serviceConfig = {
        Type = lib.mkForce "oneshot";
        ExecStart = lib.mkForce "${pkgs.python3}/bin/python3 -u ${./recovery.py}";
        RemainAfterExit = lib.mkForce true;
        Restart = lib.mkForce "no";
        TimeoutStartSec = lib.mkForce "90s";
        TimeoutStopSec = lib.mkForce "5s";
        UMask = lib.mkForce "0077";
      };
    };
  };
}
