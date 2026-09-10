inputs:
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.asus.zenbookA14;
  hardwarePkgs = import ../lib/hardware-pkgs.nix inputs.nixpkgs pkgs.stdenv.buildPlatform.system;
  manifest = builtins.fromJSON (builtins.readFile ../firmware-manifest.json);
  missing = if cfg.firmwareSource == null then [ ] else
    builtins.filter (file: !(builtins.pathExists (cfg.firmwareSource + "/${file.name}"))) manifest.files;
  windowsFirmware = hardwarePkgs.callPackage ../pkgs/windows-firmware.nix {
    firmwareSource = cfg.firmwareSource;
  };
  wifiFirmware = hardwarePkgs.runCommand "qcc2072-firmware-00228" { } ''
    install -Dm644 \
      ${inputs.linux-firmware-qcc2072}/ath12k/QCC2072/hw1.0/firmware-2.bin \
      $out/lib/firmware/ath12k/QCC2072/hw1.0/firmware-2.bin
  '';
  earlyModules = [
    "tcsrcc-glymur" "phy_qcom_qmp_pcie"
    "phy_qcom_m31_eusb2" "phy_qcom_eusb2_repeater"
    "phy_qcom_qmp_usb" "phy_qcom_qmp_usbc"
    "gpi" "i2c_qcom_geni" "i2c_hid_of"
  ];
in {
  imports = [
    (lib.mkRenamedOptionModule
      [ "hardware" "asus" "zenbookA14" "experimental" "camera" "enable" ]
      [ "hardware" "asus" "zenbookA14" "camera" "enable" ])
    (import ./audio.nix inputs hardwarePkgs)
    ./ramoops.nix
    ./camera.nix
  ];

  options.hardware.asus.zenbookA14 = {
    firmwareSource = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Directory containing the factory Windows firmware files listed in firmware-manifest.json. Required for the installer and installed system.";
    };
    audio.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the A14 audio topology, UCM, speaker routing, PipeWire and HDMI hotplug helper.";
    };
    audio.speakerGain = lib.mkOption {
      type = lib.types.numbers.between 0.0 2.0;
      default = 1.0;
      description = "Speaker gain multiplier. 1.0 is unity; the source configuration used 1.50.";
    };
    camera.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the front camera: backported Glymur CAMSS, CSI2 PHY, CCI and PM8010 drivers, the UX3407NA camera board description, libcamera and the udmabuf access rule. Changing it rebuilds the kernel; see docs/hardware.md.";
    };
    experimental.scmiMailbox = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the source configuration's experimental SCMI mailbox performance writes. Changes the kernel build; not a proven performance fix.";
    };
    diagnostics.unrestrictedDevmem = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Build the kernel without STRICT_DEVMEM so acpidump can read the firmware ACPI tables through /dev/mem on this device-tree boot. Diagnostic only; rebuilds the kernel.";
    };
    diagnostics.verbose = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable drm.debug=0x100 and verbose console output. Existing instrumentation remains compiled into the baseline kernel.";
    };
    diagnostics.ramoops32GiB.enable = lib.mkEnableOption "the fixed-address ramoops reservation validated only against the original 32 GiB machine's memory map";
    usb.viaHubWorkaround = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Apply the source configuration's 2109:0817/2817 VIA hub suspend workarounds.";
    };
  };

  config = {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.system == "aarch64-linux";
        message = "nixos-a14 supports aarch64-linux on ASUS UX3407NA (X2 Elite/Glymur).";
      }
      {
        assertion = cfg.firmwareSource != null;
        message = "Set hardware.asus.zenbookA14.firmwareSource to your extracted firmware directory. See docs/firmware.md.";
      }
      {
        assertion = missing == [ ];
        message = "A14 firmware directory is incomplete. Missing: ${lib.concatMapStringsSep ", " (file: file.name) missing}. Run a14-firmware validate DIRECTORY; see docs/firmware.md.";
      }
    ];
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    boot.kernelPackages = hardwarePkgs.callPackage ../kernel.nix {
      glymurSrc = inputs.glymur-kernel;
      scmiMailbox = cfg.experimental.scmiMailbox;
      camera = cfg.camera.enable;
      strictDevmem = !cfg.diagnostics.unrestrictedDevmem;
    };

    hardware.deviceTree = {
      enable = true;
      name = "qcom/glymur-asus-zenbook-a14-ux3407na.dtb";
      filter = "glymur-asus-zenbook-a14-ux3407na.dtb";
      overlays = [ {
        name = "asus-a14-ec";
        filter = "glymur-asus-zenbook-a14-ux3407na.dtb";
        dtsFile = ../patches/a14-ec-overlay.dts;
      } ];
    };
    boot.initrd.availableKernelModules = earlyModules ++ [ "nvme" "usb_storage" "uas" ];
    boot.initrd.kernelModules = earlyModules;
    boot.kernelModules = [ "asus-glymur-ec" ];
    hardware.enableRedistributableFirmware = lib.mkDefault true;
    hardware.firmware = lib.mkBefore (
      [ wifiFirmware ] ++ lib.optional (cfg.firmwareSource != null) windowsFirmware
    );
    hardware.firmwareCompression = lib.mkDefault "none";
    hardware.graphics.enable = lib.mkDefault true;
    hardware.bluetooth.enable = lib.mkDefault true;
    hardware.bluetooth.powerOnBoot = lib.mkDefault true;

    boot.initrd.systemd.tpm2.enable = lib.mkDefault false;
    systemd.tpm2.enable = lib.mkDefault false;
    # Explicitly exclude ZFS from this experimental kernel's filesystem set.
    # This retains the source baseline; intentional overrides need priority < 50.
    boot.supportedFilesystems = lib.mkForce [ "ext4" "vfat" "btrfs" "xfs" ];
    boot.kernelParams = [ "console=tty1" "consoleblank=0" "pm_async=off" "mem_sleep_default=s2idle" ]
      ++ lib.optional cfg.usb.viaHubWorkaround "usbcore.quirks=2109:0817:k"
      ++ lib.optional cfg.diagnostics.verbose "drm.debug=0x100";
    boot.consoleLogLevel = lib.mkDefault (if cfg.diagnostics.verbose then 7 else 3);
    # Avoid firmware-variable write failures seen on the original machine.
    # No bootloader is enabled here; the installed-system example selects one.
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault false;

    networking.networkmanager.wifi.powersave = lib.mkDefault false;
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="platform", KERNEL=="6c80000.soundwire", ATTR{power/control}="on"
    '' + lib.optionalString cfg.usb.viaHubWorkaround ''
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2109", ATTR{idProduct}=="2817", TEST=="power/control", ATTR{power/control}="on"
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="2109", ATTR{idProduct}=="0817", TEST=="power/control", ATTR{power/control}="on"
    '';
  };
}
