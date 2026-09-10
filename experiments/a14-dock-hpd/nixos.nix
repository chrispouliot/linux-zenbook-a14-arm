{ lib, ... }: { boot.kernelParams = lib.mkAfter [ "pmic_glink_altmode.a14_dock_hpd_test=1" ]; }
