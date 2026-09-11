{
  lib,
  buildLinux,
  linuxPackagesFor,
  glymurSrc,
  scmiMailbox ? false,
  camera ? true,
  video ? false,
  videoFirmwareName ? "qcom/glymur/ASUSTeK/UX3407NA/qcvss8480.mbn",
  strictDevmem ? true,
  ...
}:

let
  # Front-camera support (camera = true, the default): Glymur CAMSS, CSI2 PHY,
  # CCI and PM8010 backports from linux-msm topic/glymur-laptops and the
  # September 2026 upstream Glymur camera series, rediffed against the pinned
  # snapshot. See docs/hardware.md.
  cameraPatches = map (name: ./patches/camera + "/${name}") [
    "01-phy-core-use-after-free.patch"
    "02-phy-core-phy-get-by-of-node.patch"
    "03-phy-core-devm-phy-get-by-of-node.patch"
    "04-dt-bindings-qcom-csi2-phy.patch"
    "05-phy-qcom-mipi-csi2-driver.patch"
    "06-camss-phy-api.patch"
    "07-camss-data-lanes-from-one.patch"
    "08-dt-bindings-csi2-phy-glymur.patch"
    "09-camss-glymur-compatible.patch"
    "10-mfd-pm8008-pm8010.patch"
    "11-mfd-pm8008-optional-irq.patch"
    "12-regulator-pm8008-pm8010.patch"
    "13-glymur-dts-camss-csiphy.patch"
    "14-glymur-dts-cci.patch"
    "15-glymur-dts-cam-mclk-pinctrl.patch"
  ];

  # Experimental Iris video codec support (video = true): the upstream series
  # "media: iris: Add support for glymur platform" (v10, 2026-07-26), ported
  # onto the pinned snapshot. The binding document from that series is
  # already in the tree. See docs/hardware.md.
  videoPatches = map (name: ./patches/video + "/${name}") [
    "01-iris-context-bank-hooks.patch"
    "02-iris-create-context-bank-device.patch"
    "03-iris-select-context-bank-device.patch"
    "04-iris-skip-dma-mask-without-iommu.patch"
    "05-iris-secure-pas-linux-iommu.patch"
    "06-iris-per-block-clock-power-tables.patch"
    "07-iris-glymur-power-sequence.patch"
    "08-iris-bootup-register-hook.patch"
    "09-iris-dual-core-select.patch"
    "10-iris-pixel-nonpixel-hooks.patch"
    "11-iris-glymur-platform-data.patch"
    "12-glymur-dts-iris-node.patch"
    "13-glymur-crd-dts-enable-iris.patch"
  ];

  baseKernel = buildLinux {
    pname = "linux-glymur-a14";
    version = "7.2.0-rc5-next-20260731";
    src = glymurSrc;
    buildDTBs = true;
    ignoreConfigErrors = true;

    structuredExtraConfig = with lib.kernel; {
      ARCH_QCOM = yes;

      # Temporary A14 dock/suspend reset diagnostics.
      # Built-in ramoops starts capturing before userspace runs.
      PSTORE = lib.mkForce yes;
      PSTORE_RAM = lib.mkForce yes;
      PSTORE_CONSOLE = lib.mkForce yes;
      PSTORE_PMSG = lib.mkForce yes;
      PSTORE_DEFAULT_KMSG_BYTES = lib.mkForce (freeform "262144");
      LOG_BUF_SHIFT = lib.mkForce (freeform "20");

      # This linux-next snapshot has a Rust/RCU API mismatch.
      RUST = lib.mkForce no;

      ARM_SCMI_PROTOCOL = yes;
      ARM_SCMI_TRANSPORT_MAILBOX = yes;
      ARM_SCMI_CPUFREQ = yes;

      # Temporary read-only SCMI query tool support; keep normal drivers active.
      DEBUG_FS = yes;
      ARM_SCMI_RAW_MODE_SUPPORT = yes;
      ARM_SCMI_RAW_MODE_SUPPORT_COEX = yes;

      ENERGY_MODEL = yes;
      CPU_FREQ_GOV_SCHEDUTIL = yes;
      CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = yes;

      EC_ASUS_GLYMUR = module;
    } // lib.optionalAttrs (!strictDevmem) {
      # Diagnostic only: lets acpidump read the firmware ACPI tables through
      # /dev/mem on this device-tree boot. See docs/hardware.md.
      STRICT_DEVMEM = lib.mkForce no;
    } // lib.optionalAttrs camera {
      # Camera pipeline: CAMSS, CCI, the new CSI2 PHY driver, camera clock
      # controller, PM8010 camera PMIC and the OV02C10 sensor driver.
      VIDEO_QCOM_CAMSS = module;
      I2C_QCOM_CCI = module;
      PHY_QCOM_MIPI_CSI2 = module;
      CLK_GLYMUR_CAMCC = module;
      MFD_QCOM_PM8008 = module;
      REGULATOR_QCOM_PM8008 = module;
      VIDEO_CAMERA_SENSOR = yes;
      VIDEO_OV02C10 = module;
    } // lib.optionalAttrs video {
      # Iris video codec, its clock controller and the generic PAS firmware
      # authentication interface it loads firmware through.
      VIDEO_QCOM_IRIS = module;
      CLK_GLYMUR_VIDEOCC = module;
      QCOM_PAS = yes;
      QCOM_MDT_LOADER = module;
    };
  };

  a14Kernel = baseKernel.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ./patches/a14-dp-boot-order-debug.patch
      ./patches/a14-glymur-ucsi-dp-mux-race.patch
      ./patches/a14-dp-hpd-replay.patch
    ] ++ lib.optional scmiMailbox ./patches/a14-scmi-mailbox-set-test.patch
      ++ lib.optionals camera cameraPatches
      ++ lib.optionals video videoPatches;

    postPatch = (old.postPatch or "") + (import ./kernel/a14-post-patch.nix)
      + lib.optionalString camera (import ./kernel/a14-camera-post-patch.nix)
      + lib.optionalString video ((import ./kernel/a14-video-post-patch.nix) videoFirmwareName);
  });

in
linuxPackagesFor a14Kernel
