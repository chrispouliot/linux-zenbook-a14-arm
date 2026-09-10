{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_pair_config_test=1" ]; }
