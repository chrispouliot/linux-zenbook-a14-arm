# PCIe driver patch 04 runs earlier through buildLinux.kernelPatches so
# Nixpkgs can configure it. Board patches run after the platform/display recipe
# and before the camera/video DT appends. See docs/BOARD-V2-BACKPORT.md.
''
      echo "Applying ASUS A14 v2 board power, PCIe, M.2, LED and audio changes"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/01-power-supplies.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/02-usb-repeaters.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/03-ec-reset.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/05-board-completion.patch}
      cp ${../patches/a14-pcie-multiphy.dtsi} arch/arm64/boot/dts/qcom/a14-pcie-multiphy.dtsi
      sed -i '/#include "glymur.dtsi"/a #include "a14-pcie-multiphy.dtsi"' \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

''
