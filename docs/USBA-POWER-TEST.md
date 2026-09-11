# A14 USB-A power-domain retention experiment

## Evidence

The same boot passed pm_test=devices (device resume 482 ms), then failed
pm_test=platform. The failing test ran late/noirq callbacks, waited five
seconds, and resumed without entering s2idle. It logged a write translation
fault at IOVA 0x30f840e260, stream 0xda0, followed by Host System Error on
xhci-hcd.0.auto (a400000.usb). This narrows the trigger to the additional
stages, subject to the limitation that the tests were sequential.

The prior full xHCI reset experiment ran but returned -110, with watchdog
and RCU stalls. This installer removes it when its exact contents match.

## Candidate and scope

The A14 USB-A controller uses GCC_USB30_MP_GDSC. Existing USB-C retention
patches do not retain this domain. Generic PM domain code can power domains
off during noirq. The candidate keeps only the MP controller domain on,
only on asus,zenbook-a14-ux3407na. It does not retain its separate PHY domains,
keep device clocks on, change SMMU mappings, or introduce a retry loop.

This is a diagnostic workaround with possible idle and suspend power cost.
Success would support a power-domain transition/retention issue, not identify
the exact lost state. Further work would be needed for correct power gating.

## Install and test

The installer accepts the captured display-series baseline or that baseline
with the exact previous USB-A reset experiment. Preflight validates all edits
before changing files. No backup is created. Git is the backup.

Stage new files AND the two removed reset-experiment files if tracked. Refresh
the NixOS a14 input, rebuild and reboot. A previous-generation boot alone does
not remove source changes; this installer handles that source cleanup.

First use only the USB-A mouse and confirm it works after boot. Check:

    cat /sys/module/gcc_glymur/parameters/a14_usba_keep_power
    sudo journalctl -k -b --no-pager | rg A14-USBA

Expect Y and the A14-USBA-power banner, with no A14-USBA-reset banner.
Run pm_test=platform once, with an EXIT trap restoring pm_test=none. It should
return automatically after the five-second test delay plus driver time.
Capture the complete kernel journal and lsusb -t before resetting/replugging.
Report mouse function. Only after this passes, try a 10-20 second real suspend.

If it fails, stop repeated tests and recover with a reboot. If it passes,
repeat real suspend before drawing conclusions and measure power later.

## Disable / remove

Boot parameter gcc_glymur.a14_usba_keep_power=0 disables this experiment for
that boot; it is read-only after probe. Installer --remove removes the power
experiment and restores the pre-USB-A-test baseline; it does NOT reinstall
the failed xHCI reset experiment. Refresh the input and rebuild afterward.

Source verification covers the ordered platform/display series, not optional
camera/video/SCMI or inherited Nixpkgs patches. ARM64 object compilation does
not substitute for a full NixOS build or hardware validation.
