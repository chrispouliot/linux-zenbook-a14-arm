{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_dsc_144_test=1" ]; }
