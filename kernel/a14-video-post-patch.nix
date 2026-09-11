# Iris video codec board description. A function of the firmware path so the
# board fragment can point at the OEM image or the generic linux-firmware
# image. Only used when kernel.nix is called with video = true. The driver
# and SoC device-tree backports are applied earlier as regular patches (see
# videoPatches in kernel.nix).
videoFirmwareName: ''
      echo "Appending ASUS A14 experimental video codec board description"
      cat ${../patches/a14-iris.dtsi} \
        >> arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts
      sed -i 's|@VIDEO_FIRMWARE@|${videoFirmwareName}|' \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      echo
      echo "Verifying Glymur iris SoC node from the backported series:"
      grep -n -E 'iris: video-codec@aa00000|iris_resv: reservation-iris|compatible = "qcom,glymur-iris"' \
        arch/arm64/boot/dts/qcom/glymur.dtsi

      echo
      echo "Verifying ASUS A14 video codec board nodes:"
      grep -n -F 'firmware-name = "${videoFirmwareName}"' \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts
      ! grep -q '@VIDEO_FIRMWARE@' \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      echo
      echo "Verifying iris driver backports:"
      grep -n -F 'qcom,glymur-iris' drivers/media/platform/qcom/iris/iris_probe.c
      grep -n -F 'qcom_mdt_pas_load(core->pas_ctx' drivers/media/platform/qcom/iris/iris_firmware.c
      test -f drivers/media/platform/qcom/iris/iris_platform_glymur.c
''
