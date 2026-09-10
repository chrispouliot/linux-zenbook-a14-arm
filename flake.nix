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
      # BEGIN A14 DSC 4K60 experiment v1
      nixosModules.default = {
        imports = [
          (import ./modules inputs)
          ./experiments/a14-dsc-4k60/nixos.nix
          # BEGIN A14 DSC 144Hz extension v1
          ./experiments/a14-dsc-144/nixos.nix
          # BEGIN A14 DSC wake experiment v1
          ./experiments/a14-dsc-wake/nixos.nix
          # BEGIN A14 AUX wake experiment v1
          ./experiments/a14-aux-wake/nixos.nix
          # BEGIN A14 dock HPD experiment v1
          ./experiments/a14-dock-hpd/nixos.nix
          # END A14 dock HPD experiment v1
          # BEGIN A14 eDP retry experiment v1
          ./experiments/a14-edp-retry/nixos.nix
          # END A14 eDP retry experiment v1
          # BEGIN A14 paired config experiment v1
          ./experiments/a14-pair-config/nixos.nix
          # END A14 paired config experiment v1
          # BEGIN A14 sink power experiment v1
          ./experiments/a14-sink-power/nixos.nix
          # END A14 sink power experiment v1
          # BEGIN A14 state trace experiment v1
          ./experiments/a14-state-trace/nixos.nix
          # END A14 state trace experiment v1
          # BEGIN A14 config reuse experiment v1
          ./experiments/a14-config-reuse/nixos.nix
          # END A14 config reuse experiment v1
          # BEGIN A14 repeater restore experiment v1
          ./experiments/a14-repeater-restore/nixos.nix
          # END A14 repeater restore experiment v1
          # BEGIN A14 dock recovery v4 experiment v1
          ./experiments/a14-dock-recovery-v4/nixos.nix
          # END A14 dock recovery v4 experiment v1
          # BEGIN A14 sink cleanup experiment v1
          ./experiments/a14-sink-cleanup/nixos.nix
          # END A14 sink cleanup experiment v1
          # BEGIN A14 review theories experiment v1
          ./experiments/a14-review-theories/nixos.nix
          # END A14 review theories experiment v1
          # BEGIN A14 repeater reset experiment v1
          ./experiments/a14-repeater-reset/nixos.nix
          # END A14 repeater reset experiment v1
          # BEGIN A14 transparent experiment v1
          ./experiments/a14-transparent/nixos.nix
          # END A14 transparent experiment v1
          # BEGIN A14 eDP depth experiment v1
          ./experiments/a14-edp-depth/nixos.nix
          # END A14 eDP depth experiment v1
          # END A14 AUX wake experiment v1
          # END A14 DSC wake experiment v1
          # END A14 DSC 144Hz extension v1
        ];
      };
      # END A14 DSC 4K60 experiment v1
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
