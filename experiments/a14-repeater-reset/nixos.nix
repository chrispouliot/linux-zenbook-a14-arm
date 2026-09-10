{ config, lib, ... }:
let
  cfg = config.hardware.a14RepeaterResetTest;
  flag = value: if value then "1" else "0";
in {
  options.hardware.a14RepeaterResetTest = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Test verified LTTPR reset on inactive A14 two-repeater dock links.";
    };
    auxDiagnostics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Log raw A14 native AUX status and FIFO-call time on errors.";
    };
  };
  config.boot.kernelParams = lib.mkAfter [
    "msm.a14_dp_repeater_reset_test=${flag cfg.enable}"
    "msm.a14_dp_aux_diag_test=${flag cfg.auxDiagnostics}"
  ];
}
