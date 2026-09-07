inputs:
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.asus.zenbookA14;
  tools = pkgs.callPackage ../pkgs/firmware-tools.nix { };
in {
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
    ../vendor/iso-image.nix
  ];
  disabledModules = [ "installer/cd-dvd/iso-image.nix" ];
  networking.hostName = lib.mkDefault "a14-installer";
  networking.networkmanager.enable = true;
  networking.wireless.enable = lib.mkForce false;
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  isoImage.makeBiosBootable = false;
  isoImage.appendToMenuLabel = " - ASUS A14 UX3407NA X2 Elite";
  # Firmware remains accessible as source files for the target installation.
  environment.etc."a14-firmware".source = cfg.firmwareSource;
  environment.etc."nixos-a14-source".source = inputs.self.outPath;
  environment.etc."a14-installation.md".source = ../docs/installation.md;
  environment.systemPackages = [ tools pkgs.git pkgs.nano pkgs.parted pkgs.nvme-cli pkgs.pciutils pkgs.usbutils ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Avoid installer-version defaults silently changing over time.
  system.stateVersion = "26.11";
}
