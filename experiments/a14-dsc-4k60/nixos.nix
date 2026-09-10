# A14 DSC 4K60 experiment v1. Imported only by this test installation.
{ lib, ... }:
{
  boot.kernelParams = lib.mkAfter [ "msm.a14_dp_dsc_test=1" ];
}
