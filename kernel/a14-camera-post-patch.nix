# Camera board description. Only appended when kernel.nix is called with
# camera = true (the default). The driver and SoC device-tree backports are
# applied earlier as regular patches (see cameraPatches in kernel.nix).
''
      echo "Appending ASUS A14 camera board description"
      cat ${../patches/a14-camera.dtsi} \
        >> arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      echo
      echo "Verifying Glymur camera SoC nodes from the backported series:"
      grep -n -E 'camss: isp@acb6000|csiphy4: phy@acec000|cci1: cci@ac16000|cam_mclk4_default: ' \
        arch/arm64/boot/dts/qcom/glymur.dtsi

      echo
      echo "Verifying ASUS A14 camera board nodes:"
      grep -n -E 'compatible = "ovti,ov02c10"|compatible = "qcom,pm8010"|vdda-0p9-supply = <&vreg_l1f_e1>' \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      echo
      echo "Verifying camera driver backports:"
      grep -n -F 'qcom,glymur-camss' drivers/media/platform/qcom/camss/camss.c
      grep -n -F 'devm_phy_get_by_of_node' drivers/media/platform/qcom/camss/camss-csiphy.c
      grep -n -F '"qcom,pm8010"' drivers/mfd/qcom-pm8008.c
      test -f drivers/phy/qualcomm/phy-qcom-mipi-csi2-core.c
''
