{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_sink_cleanup_test=1" ]; }
