{ config, lib, ... }:
let
  cfg = config.hardware.a14EdpDepthTest;
  flag = value: if value then "1" else "0";
in {
  options.hardware.a14EdpDepthTest.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Finalize native A14 eDP RGB depth after powered panel setup.";
  };
  config.boot.kernelParams = lib.mkAfter [
    "msm.a14_edp_depth_test=${flag cfg.enable}"
  ];
}
