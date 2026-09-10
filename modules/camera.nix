{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.asus.zenbookA14;
in {
  config = lib.mkIf cfg.experimental.camera.enable {
    # CAMSS delivers raw Bayer frames only. libcamera's simple pipeline handler
    # (built with the qcom-camss entry in nixpkgs' libcamera) and its software
    # ISP turn them into usable video. nixpkgs' PipeWire is built with
    # libcamera and WirePlumber loads the libcamera monitor as part of its
    # default video-capture feature, so applications see the camera through
    # PipeWire once both run. Firefox still needs
    # media.webrtc.camera.allow-pipewire enabled in about:config.
    services.pipewire.enable = lib.mkDefault true;
    services.pipewire.wireplumber.enable = lib.mkDefault true;

    # `cam -l` / `cam -c1 -C10` for libcamera checks, media-ctl and v4l2-ctl
    # for the raw CAMSS graph.
    environment.systemPackages = [ pkgs.libcamera pkgs.v4l-utils ];

    # The software ISP allocates its frame buffers through a dma-buf provider.
    # This kernel has no /dev/dma_heap, so libcamera uses /dev/udmabuf, which
    # systemd leaves root:kvm and only opens to the seat user through a logind
    # ACL at session activation. WirePlumber enumerates the camera at login,
    # which can happen before that ACL exists; the ISP then fails to set up,
    # the PipeWire node ends up with no formats and applications see no
    # camera. Give the video group permanent access instead (rules in
    # 99-local.rules override the group set by 50-udev-default.rules).
    # Users must be in the video group.
    services.udev.extraRules = ''
      KERNEL=="udmabuf", GROUP="video", MODE="0660"
    '';
  };
}
