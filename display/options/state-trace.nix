{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "msm.a14_dp_state_trace_test=1" ]; }
