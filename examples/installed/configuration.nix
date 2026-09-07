{ ... }:
{
  networking.hostName = "a14";
  networking.networkmanager.enable = true;
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 5;
    installDeviceTree = true;
  };
  boot.loader.efi.efiSysMountPoint = "/boot";
  # The shared module defaults canTouchEfiVariables to false for this firmware.

  # Desktop choice belongs to the owner. This example uses GNOME.
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  users.users.owner = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "render" ];
  };
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  # Keep this at the initial installation version during future upgrades.
  system.stateVersion = "26.11";
}
