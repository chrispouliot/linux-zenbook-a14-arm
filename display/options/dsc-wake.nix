{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_dsc_wake_test=1" ]; }
