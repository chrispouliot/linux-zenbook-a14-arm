{
  lib,
  buildLinux,
  linuxPackagesFor,
  glymurSrc,
  scmiMailbox ? false,
  ...
}:

let
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
    };
  };

  a14Kernel = baseKernel.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ./patches/a14-dp-boot-order-debug.patch
      ./patches/a14-glymur-ucsi-dp-mux-race.patch
      ./patches/a14-dp-hpd-replay.patch
    ] ++ lib.optional scmiMailbox ./patches/a14-scmi-mailbox-set-test.patch;

    postPatch = (old.postPatch or "") + (import ./kernel/a14-post-patch.nix);
  });

in
linuxPackagesFor a14Kernel
