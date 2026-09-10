{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_aux_wake_test=1" ]; }
