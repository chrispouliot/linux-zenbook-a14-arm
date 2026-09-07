{
  description = "ASUS Zenbook A14 UX3407NA / Snapdragon X2 Elite NixOS hardware support and installer";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    glymur-kernel = {
      url = "github:linux-msm/laptops-kernel/51231839d5ef007638bd1c3500e6a76b337a66f3";
      flake = false;
    };
    audioreach-topology = {
      url = "github:linux-msm/audioreach-topology";
      flake = false;
    };
    linux-firmware-qcc2072 = {
      url = "git+https://gitlab.com/kernel-firmware/linux-firmware.git?rev=25c06030aa434817928ace452c06f095f14729d3";
      flake = false;
    };
    # Empty placeholder. Supply private firmware with --override-input when
    # building an ISO. Importing nixosModules.default uses firmwareSource instead.
    windows-firmware = {
      url = "path:./firmware";
      flake = false;
    };
  };

  outputs = inputs@{ self, nixpkgs, windows-firmware, ... }:
    let
      systems = [ "aarch64-linux" "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      hardwarePkgsFor = import ./lib/hardware-pkgs.nix nixpkgs;
      mkInstaller = {
        firmwareSource,
        buildSystem ? "aarch64-linux",
        extraModules ? [ ],
      }: nixpkgs.lib.nixosSystem {
        modules = [
          self.nixosModules.default
          self.nixosModules.installer
          {
            nixpkgs.pkgs = hardwarePkgsFor buildSystem;
            hardware.asus.zenbookA14.firmwareSource = firmwareSource;
          }
        ] ++ extraModules;
      };
    in {
      nixosModules.default = import ./modules inputs;
      nixosModules.asus-zenbook-a14-ux3407na = self.nixosModules.default;
      nixosModules.installer = import ./modules/installer.nix inputs;
      lib = {
        inherit mkInstaller;
        mkIso = args: (mkInstaller args).config.system.build.isoImage;
      };
      nixosConfigurations.installer = mkInstaller {
        firmwareSource = windows-firmware.outPath;
      };
      packages = forAllSystems (system: let
        pkgs = nixpkgs.legacyPackages.${system};
        kernelPackages = (hardwarePkgsFor system).callPackage ./kernel.nix {
          glymurSrc = inputs.glymur-kernel;
        };
      in {
        kernel = kernelPackages.kernel;
        firmware-tools = pkgs.callPackage ./pkgs/firmware-tools.nix { };
        default = self.packages.${system}.firmware-tools;
        iso = self.lib.mkIso {
          buildSystem = system;
          firmwareSource = windows-firmware.outPath;
        };
      });
      apps = forAllSystems (system: {
        firmware = {
          type = "app";
          program = "${self.packages.${system}.firmware-tools}/bin/a14-firmware";
        };
      });
      checks = forAllSystems (system: let pkgs = nixpkgs.legacyPackages.${system}; in {
        firmware-tools = pkgs.runCommand "a14-firmware-tests" {
          nativeBuildInputs = [ pkgs.python3 ];
        } ''
          cp -r ${./scripts} scripts
          cp -r ${./tests} tests
          cp ${./firmware-manifest.json} firmware-manifest.json
          python3 -m unittest discover -s tests -v
          touch $out
        '';
      });
    };
}
