# Extracted platform patches

The eighteen Python search-and-replace blocks formerly embedded in
`kernel/a14-post-patch.nix` are now ordinary unified-diff patches under
`patches/platform/`. The postPatch recipe is 170 lines instead of 2,046 and
contains no Python source rewrites. It still appends the three existing DT
fragments, applies patches, and performs the retained grep/sed checks.

This is a mechanical extraction. All resulting kernel source, diagnostics,
experimental gates, link limits and runtime defaults are unchanged. Patch
application requires exact context (`--fuzz=0`); local validation found no offsets.
The original rewrite input checks are replaced by patch context checks, while
the separate shell source-verification checks remain in their original order.

## Required order

After the initial patches from `kernel.nix`, append `a14-usb-fix.dtsi`,
`a14-audio-left-only.dtsi` and `a14-edp-hbr.dtsi`. Follow the order below, then
apply the complete four-patch display series. The existing bank0 patch stays
between platform patches 09 and 10. None of these boundaries makes an
intermediate driver state suitable for independent deployment.

| Rewrite | Patch | Existing behavior preserved |
| --- | --- | --- |
| 01 | [01-external-dp-hbr2.patch](../../patches/platform/01-external-dp-hbr2.patch) | Applies the second external controller HBR2 cap after the existing DT appends. |
| 02 | [02-audio-stereo.patch](../../patches/platform/02-audio-stereo.patch) | Constrains the WSA backend to stereo while preserving the frontend. |
| 03 | [03-hid-fn-lock.patch](../../patches/platform/03-hid-fn-lock.patch) | Enables the tested Zenbook keyboard Fn-lock behavior. |
| 04 | [04-glink-diagnostics.patch](../../patches/platform/04-glink-diagnostics.patch) | Retains PMIC GLINK USB-C/DP event diagnostics. |
| 05 | [05-hpd-irq-containment.patch](../../patches/platform/05-hpd-irq-containment.patch) | Retains suppression of repeated IRQ-only HPD notifications. |
| 06 | [06-dp-hpd-state.patch](../../patches/platform/06-dp-hpd-state.patch) | Retains DP hotplug-state stabilization and resume reinitialization. |
| 07 | [07-dp-link-bandwidth.patch](../../patches/platform/07-dp-link-bandwidth.patch) | Validates modes against physical DP payload capacity. |
| 08 | [08-aux-wrong-data-count.patch](../../patches/platform/08-aux-wrong-data-count.patch) | Completes AUX wrong-data-count interrupts with an error. |
| 09 | [09-phy-startup.patch](../../patches/platform/09-phy-startup.patch) | Retains orientation-aware PHY programming, AUX setup and startup error propagation. |
| Existing | [a14-dp-usb-preserve-bank0.patch](../../patches/a14-dp-usb-preserve-bank0.patch) | Preserves USB-sensitive bank0 controls; unchanged and still applied here. |
| 10 | [10-usb-domain-retention.patch](../../patches/platform/10-usb-domain-retention.patch) | Keeps the affected USB/PHY power domains on through suspend. |
| 11 | [11-hpd-disconnect-retention.patch](../../patches/platform/11-hpd-disconnect-retention.patch) | Retains disconnect events and the corresponding bridge replay handling. |
| 12 | [12-phy-safe-detach.patch](../../patches/platform/12-phy-safe-detach.patch) | Defers shared-PHY SAFE-mode reinitialization to the retained teardown path. |
| 13 | [13-dp-live-sink-check.patch](../../patches/platform/13-dp-live-sink-check.patch) | Retains the live-sink check before restoring an external link. |
| 14 | [14-hpd-bootstrap.patch](../../patches/platform/14-hpd-bootstrap.patch) | Preserves initial IRQ-tagged HPD during DP setup. |
| 15 | [15-usb-dp-lifecycle.patch](../../patches/platform/15-usb-dp-lifecycle.patch) | Retains the USB/DP lifecycle correction for the shared PHY. |
| 16 | [16-phy-boot-mode.patch](../../patches/platform/16-phy-boot-mode.patch) | Retains the experimental dock boot-mode programming behavior. |
| 17 | [17-dpcd-probe.patch](../../patches/platform/17-dpcd-probe.patch) | Retains the preliminary DPCD-probe override on af54000. |
| 18 | [18-repeater-caps-recovery.patch](../../patches/platform/18-repeater-caps-recovery.patch) | Retains the guarded repeater-capability recovery helper before the later display patches. |

## Verification and remaining work

The original recipe and the extracted recipe were each run against the pinned
kernel source. Every one of the 38 reconstructed source files has the same
SHA-256 as the previously hardware-tested stack. `platform-series.json` records
the new patch hashes/order; `source-sha256.json` remains unchanged. The existing
source verifier now checks both platform and display order and patch hashes.

The four display patches, all Nix option modules, recovery v4, the recorder,
DT fragments, initial patches, kernel configuration and flake inputs are
unchanged. Recovery remains disabled through the owner's personal setting.
NixOS evaluation and hardware execution were not performed during extraction;
this source comparison is not a fresh hardware certification.

The next code cleanup should be a separate change: review remaining diagnostic
and dormant experiment paths, remove only those shown unnecessary, and test
that change. Splitting these diffs further for upstream review may also be
useful, but do not equate this packaging change with an upstream-ready series.
