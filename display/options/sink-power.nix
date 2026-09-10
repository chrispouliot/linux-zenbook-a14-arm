{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_sink_power_test=1" ]; }
