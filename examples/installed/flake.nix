{
  description = "My ASUS Zenbook A14 UX3407NA";
  inputs = {
    # The installation guide copies the shared source here from the ISO.
    # After publication, this may be replaced by github:chrispouliot/nixos-a14.
    a14.url = "path:./hardware/nixos-a14";
    nixpkgs.follows = "a14/nixpkgs";
  };
  outputs = { nixpkgs, a14, ... }: {
    nixosConfigurations.a14 = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        a14.nixosModules.default
        ./hardware-configuration.nix
        ./configuration.nix
        { hardware.asus.zenbookA14.firmwareSource = ./firmware; }
      ];
    };
    packages.aarch64-linux.iso = a14.lib.mkIso { firmwareSource = ./firmware; };
    packages.x86_64-linux.iso = a14.lib.mkIso {
      buildSystem = "x86_64-linux";
      firmwareSource = ./firmware;
    };
  };
}
