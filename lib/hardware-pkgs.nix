nixpkgs: buildSystem:
import nixpkgs ({
  localSystem.system = buildSystem;
  config.allowUnfree = true;
} // nixpkgs.lib.optionalAttrs (buildSystem != "aarch64-linux") {
  crossSystem.system = "aarch64-linux";
})
