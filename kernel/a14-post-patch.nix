# Ordered platform patches, source checks, and the complete display series.
''
      echo "Applying ASUS A14 Glymur USB bring-up DT overrides"
      cat ${../patches/a14-usb-fix.dtsi} \
        >> arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      cat ${../patches/a14-audio-left-only.dtsi} >> \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      cat ${../patches/a14-edp-hbr.dtsi} \
        >> arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts

      echo "Applying ASUS A14 second external controller HBR2 cap"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/01-external-dp-hbr2.patch}

      echo "Forcing ASUS A14 WSA backend to stereo"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/02-audio-stereo.patch}

      echo "Enabling ASUS Zenbook A14 HID Fn Lock support"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/03-hid-fn-lock.patch}

      echo "Adding ASUS A14 PMIC GLINK Alt Mode diagnostics"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/04-glink-diagnostics.patch}

      echo "Suppressing ASUS A14 port 1 IRQ-only HPD storm"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/05-hpd-irq-containment.patch}

      echo "Applying ASUS A14 MSM DP HPD-state stabilization"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/06-dp-hpd-state.patch}

      grep -n -E -C 5 \
        'A14: repeated HPD-high|A14: HPD handling|A14: force a real' \
        drivers/gpu/drm/msm/dp/dp_display.c

      echo "Correcting ASUS A14 DP physical-link payload validation"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/07-dp-link-bandwidth.patch}

      echo
      echo "Verifying ASUS A14 DP physical-link payload validation:"
      grep -n -E -C 7 \
        'A14-DP: rejecting .*payload' \
        drivers/gpu/drm/msm/dp/dp_display.c

      echo "Handling ASUS A14 DP AUX wrong-data-count interrupts"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/08-aux-wrong-data-count.patch}

      grep -n -B3 -A7 \
        'A14-DP: AUX wrong data count' \
        drivers/gpu/drm/msm/dp/dp_aux.c

      echo "Applying reviewed Glymur DP PHY corrections and error propagation"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/09-phy-startup.patch}

      echo
      echo "Verifying reviewed Glymur DP PHY corrections:"
      sed -n \
        '/static int qmp_v8_helper_configure_dp_phy/,/static void qmp_v8_dp_aux_init/p' \
        drivers/phy/qualcomm/phy-qcom-qmp-combo.c | \
        grep -E \
          'qmp_combo_configure_dp_mode\(qmp\)|writel\(0x06, .*QSERDES_DP_PHY_AUX_CFG2'
      ! grep -q 'qmp_v8_combo_configure_dp_mode' \
        drivers/phy/qualcomm/phy-qcom-qmp-combo.c

      echo
      echo "Verifying ASUS A14 external-DP PHY/link-clock error propagation:"
      grep -n -E -C 3 \
        'A14-DP: QMP (power-on|pre-start|C_READY)|A14-DP: QMP v8 (helper|DP PHY|final|clock)' \
        drivers/phy/qualcomm/phy-qcom-qmp-combo.c
      grep -n -F \
        'status & BIT(0), 500, 50000' \
        drivers/phy/qualcomm/phy-qcom-qmp-combo.c
      grep -n -B5 -A16 \
        'A14-DP: DP PHY configuration failed' \
        drivers/phy/qualcomm/phy-qcom-qmp-combo.c
      grep -n -B8 -A30 \
        'A14-DP: failed to power on DP PHY' \
        drivers/gpu/drm/msm/dp/dp_ctrl.c

      # Preserve bank0 USB-sensitive controls during matching Glymur DP startup.
      patch --batch --fuzz=0 -p1 < ${../patches/a14-dp-usb-preserve-bank0.patch}

      echo "Keeping ASUS A14 USB-C power domains on across suspend"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/10-usb-domain-retention.patch}

      echo
      echo "Verifying ASUS A14 second external controller HBR2 cap:"
      sed -n '/ASUS A14 external DP1 HBR diagnostic limit/,/};/p' \
        arch/arm64/boot/dts/qcom/glymur-asus-zenbook-a14-ux3407na.dts | \
        grep -F 'link-frequencies = /bits/ 64 <1620000000 2700000000 5400000000>'

      echo
      echo "Verifying ASUS A14 stereo WSA backend:"
      grep -n -B4 -A12 \
        'channels->min = channels->max = 2' \
        sound/soc/qcom/x1e80100.c

      echo
      echo "Verifying ASUS A14 Fn-lock patch:"
      grep -n -B2 -A6 \
        'hdev->product != USB_DEVICE_ID_ASUSTEK_I2C_ZENBOOK_KEYBOARD' \
        drivers/hid/hid-asus.c

      echo
      echo "Verifying ASUS A14 PMIC GLINK diagnostics:"
      grep -n -E \
        'A14-DP: (WORK|RX8180|RX8280|RX8280-DP|queue_work returned false)' \
        drivers/soc/qcom/pmic_glink_altmode.c

      echo
      echo "Verifying ASUS A14 IRQ-only HPD containment:"
      grep -n -B7 -A5 \
        'A14-DP: suppressing port 1 IRQ-only HPD notification' \
        drivers/soc/qcom/pmic_glink_altmode.c

      echo
      echo "Verifying ASUS A14 USB-C suspend workaround:"
      for gdsc in \
        gcc_usb30_prim_gdsc \
        gcc_usb_0_phy_gdsc \
        gcc_usb30_sec_gdsc \
        gcc_usb_1_phy_gdsc
      do
        sed -n "/static struct gdsc $gdsc = {/,/};/p" \
          drivers/clk/qcom/gcc-glymur.c | \
          grep -F 'POLL_CFG_GDSCR | RETAIN_FF_ENABLE | ALWAYS_ON'
      done

      echo
      echo "Applying ASUS A14 retained HPD disconnect test"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/11-hpd-disconnect-retention.patch}

      echo "Applying ASUS A14 SAFE detach reinitialization test"

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/12-phy-safe-detach.patch}

      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/13-dp-live-sink-check.patch}

      echo "Preserving initial IRQ-tagged HPD during DP setup"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/14-hpd-bootstrap.patch}

      echo "Correcting Glymur DP-only USB lifecycle"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/15-usb-dp-lifecycle.patch}

      echo "Applying A14 dock boot-mode experiment"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/16-phy-boot-mode.patch}

      echo "Applying A14 external DPCD probe experiment"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/17-dpcd-probe.patch}

      echo "Applying A14 dock repeater recovery experiment"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/18-repeater-caps-recovery.patch}

      # A14 USB-A domain retention experiment; see docs/USBA-POWER-TEST.md.
      patch --batch --forward --fuzz=0 -p1 < ${../patches/platform/19-usba-power-retention.patch}

      # Display series: all five patches are required, in this order.
      patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-display-dsc.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-display-lifecycle.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-display-transparent-lttpr.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-display-edp-depth.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-display-direct-dsc.patch}

      echo "All ASUS A14 kernel patches applied successfully"
''
