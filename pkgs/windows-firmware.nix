{ lib, runCommand, firmwareSource }:
let
  # Optional files: installed only when present in the firmware directory.
  optional = name: destination:
    lib.optionalString (builtins.pathExists (firmwareSource + "/${name}")) ''
      install -Dm644 ${firmwareSource}/${name} $out/lib/firmware/${destination}
    '';
  firmware = runCommand "asus-a14-glymur-firmware" { } ''
    # ------------------------------------------------------------
    # ADSP / CDSP
    # ------------------------------------------------------------

    install -Dm644 ${firmwareSource}/qcadsp8480.mbn \
      $out/lib/firmware/qcom/glymur/ASUSTeK/UX3407NA/qcadsp8480.mbn

    install -Dm644 ${firmwareSource}/qccdsp8480.mbn \
      $out/lib/firmware/qcom/glymur/ASUSTeK/UX3407NA/qccdsp8480.mbn

    install -Dm644 ${firmwareSource}/adsp_dtbs.elf \
      $out/lib/firmware/qcom/glymur/ASUSTeK/UX3407NA/adsp_dtbs.elf

    install -Dm644 ${firmwareSource}/cdsp_dtbs.elf \
      $out/lib/firmware/qcom/glymur/ASUSTeK/UX3407NA/cdsp_dtbs.elf


    # ------------------------------------------------------------
    # Iris video codec (optional, experimental.video.enable)
    # ------------------------------------------------------------

    ${optional "qcvss8480.mbn" "qcom/glymur/ASUSTeK/UX3407NA/qcvss8480.mbn"}


    # ------------------------------------------------------------
    # Wi-Fi
    # ------------------------------------------------------------

    # Factory ASUS/NCM820A QCC2072 board data.
    #
    # linux-firmware supplies generic QCC2072 board-2.bin, but it does
    # not contain the ASUS 105b:e14f board entry. Provide the exact
    # factory Qualcomm BDF ELF as ath12k's board.bin fallback.
    #
    # Note that this is board/calibration data and is separate from
    # firmware-2.bin above.
    install -Dm644 ${firmwareSource}/bdwlan_qcc2072_1p0_ncm820A.elf \
      $out/lib/firmware/ath12k/QCC2072/hw1.0/board.bin


    # ------------------------------------------------------------
    # Bluetooth
    # ------------------------------------------------------------

    # Factory FastConnect C7700/NCM820A Bluetooth rampatch.
    install -Dm644 ${firmwareSource}/hmtbtfw20.tlv \
      $out/lib/firmware/qca/hmtbtfw20.tlv

    # Generic fallback NVM.
    install -Dm644 ${firmwareSource}/hmtnv20.bin \
      $out/lib/firmware/qca/hmtnv20.bin

    # Factory board-ID-specific NVM variants.
    install -Dm644 ${firmwareSource}/hmtnv20.b3b \
      $out/lib/firmware/qca/hmtnv20.b3b

    install -Dm644 ${firmwareSource}/hmtnv20.b105 \
      $out/lib/firmware/qca/hmtnv20.b105

    install -Dm644 ${firmwareSource}/hmtnv20.b107 \
      $out/lib/firmware/qca/hmtnv20.b107

    install -Dm644 ${firmwareSource}/hmtnv20.b108 \
      $out/lib/firmware/qca/hmtnv20.b108

    install -Dm644 ${firmwareSource}/hmtnv20.b10f \
      $out/lib/firmware/qca/hmtnv20.b10f

    install -Dm644 ${firmwareSource}/hmtnv20.b112 \
      $out/lib/firmware/qca/hmtnv20.b112
  '';
in firmware
