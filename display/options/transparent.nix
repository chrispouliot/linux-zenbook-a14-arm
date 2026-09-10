{ config, lib, ... }:
let
  cfg = config.hardware.a14TransparentTest;
  flag = value: if value then "1" else "0";
in {
  options.hardware.a14TransparentTest.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Test transparent LTTPR training on A14 port-one two-repeater dock links.";
  };
  config = {
    # Keep one behaviour change in this comparison and retain raw diagnostics.
    hardware.a14RepeaterResetTest.enable = lib.mkForce false;
    hardware.a14RepeaterResetTest.auxDiagnostics = lib.mkForce true;
    hardware.a14DpReviewTest = {
      firstAuxProbe = lib.mkForce true;
      boundedCleanup = lib.mkForce false;
      edpBppInit = lib.mkForce false;
    };
    boot.kernelParams = lib.mkAfter [
      "msm.a14_dp_transparent_test=${flag cfg.enable}"
    ];
  };
}
