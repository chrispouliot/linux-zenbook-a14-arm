inputs: hardwarePkgs:
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.asus.zenbookA14;
  # Qualcomm's generic, Qualcomm-signed Glymur VPU image from linux-firmware.
  # The retail laptop's firmware is expected to require the OEM-signed
  # qcvss8480.mbn instead (see firmware-manifest.json), but the generic image
  # is installed too so that video.firmwareName can select it for a test
  # without changing the firmware directory.
  genericVpuFirmware = hardwarePkgs.runCommand "glymur-vpu36-firmware" { } ''
    install -Dm644 \
      ${inputs.linux-firmware-qcc2072}/qcom/vpu/vpu36_p4_s7.mbn \
      $out/lib/firmware/qcom/vpu/vpu36_p4_s7.mbn
  '';
in {
  config = lib.mkIf cfg.video.enable {
    hardware.firmware = lib.mkBefore [ genericVpuFirmware ];

    # v4l2-ctl for enumerating the decoder/encoder nodes; GStreamer players use
    # the stateful V4L2 decoder elements (v4l2h264dec, v4l2h265dec) from
    # gst-plugins-good automatically, and ffmpeg has h264_v4l2m2m and friends.
    environment.systemPackages = [ pkgs.v4l-utils ];
  };
}
