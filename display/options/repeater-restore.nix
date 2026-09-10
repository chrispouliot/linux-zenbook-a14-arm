{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_repeater_restore_test=1" ]; }
