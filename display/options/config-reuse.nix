{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_config_reuse_test=0" ]; }
