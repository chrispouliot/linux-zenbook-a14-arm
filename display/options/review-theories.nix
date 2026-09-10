{ config, lib, ... }:
let
  cfg = config.hardware.a14DpReviewTest;
  flag = value: if value then "1" else "0";
in {
  options.hardware.a14DpReviewTest = {
    firstAuxProbe = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Test A14 port-one LTTPR probe before receiver access.";
    };
    boundedCleanup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Test single-transfer A14 DSC/FEC sink teardown.";
    };
    edpBppInit = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Finalize A14 eDP bpp after powered capability reads.";
    };
  };
  config.boot.kernelParams = lib.mkAfter [
    "msm.a14_dp_first_aux_probe_test=${flag cfg.firstAuxProbe}"
    "msm.a14_dp_bounded_cleanup_test=${flag cfg.boundedCleanup}"
    "msm.a14_edp_bpp_init_test=${flag cfg.edpBppInit}"
  ];
}
