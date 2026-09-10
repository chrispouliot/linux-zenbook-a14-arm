{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_edp_retry_test=1" ]; }
