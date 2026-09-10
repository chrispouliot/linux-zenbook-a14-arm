# Display investigation history

## Scope and confidence

This is a condensed record from the A14 investigation through 2026-09-10.
Repeated local success is evidence for this hardware/topology, not universal
validation. The user reported a successful overnight suspend after the latest
eDP-depth change; no overnight capture was supplied.

## Main stages

1. **Bandwidth and USB bring-up.** Direct DP initially negotiated restricted link
   rates/lane counts. HBR2 x4 produced 4K60; the dock later demonstrated HBR3 x2
   at 4K60. The retained USB/DT changes include the port-one host-default and
   USB 5 Gbps restriction. The second external controller retains its HBR2 cap.
   Some old diagnostic comments still say HBR-only; the effective frequency
   array includes 5.4 Gbps. These old comments are preserved in the legacy
   source transformation for source-parity purposes.
2. **Suspend and dock boot.** Unbinding the USB controller isolated early suspend
   hangs. Dock enumeration varied between boot, replug, and power cycles.
   Userspace recovery progressed through v1-v4. USB/Ethernet recovery alone did
   not guarantee a working DP link. V4 remains present and conditionally active.
3. **DSC.** A controlled 4K60 experiment established DSC, then the 144 Hz extension
   enabled 4K144. Subsequent patches addressed source/sink lifecycle sequencing,
   disable/wake handling, AUX, HPD, and eDP failures. Hot-unplug had previously
   triggered a full reboot. Successful replug was later recorded.
4. **Intermittent wake failures.** Short standby sometimes succeeded while longer
   standby failed. Failure also occurred at 1080p, so it was not explained only
   by 4K144 bandwidth. Direct cable and multiple docks were compared. Config
   reuse regressed boot and was disabled. Repeater restoration helped direct
   standby but did not solve the Amazon dock consistently.
5. **External review and discriminating tests.** First-AUX probing, bounded
   cleanup, eDP-bpp finalization, explicit repeater reset, and AUX diagnostics
   were evaluated as separate hypotheses. Probe/reset tests did not establish a
   reliable dock solution. Some generations also froze the login screen.
6. **Transparent LTTPR.** Selecting/retaining transparent mode for the guarded
   two-repeater port-one topology produced repeated successful dock boots,
   standby, 4K144 suspend, clamshell standby, and replug. The old non-transparent
   reset experiment remains disabled. Direct one-repeater handling retains its
   separate restoration path.
7. **Internal colour depth.** An early eDP mode calculation selected 18 bpp while
   link caps were zero. The final eDP-depth patch recomputes the native mode's
   depth after powered setup and selects 24 bpp within the HBR x2 link budget.
   Logs showed requested=30, early selected=18, final selected=24 at boot and
   24 -> 24 on wake. User-visible colour improved; not every earlier GNOME black
   background or browser UI change has been proved to have this cause.
8. **Packaging cleanup.** The sixteen display patches are consolidated without
   changing their resulting source. Platform transformations and option names
   remain compatible. Recorders are consolidated. No workaround is retired.

## Successful observations before cleanup

- Two dock boots: external picture, internal login without freeze, Ethernet.
- Two 4K60 display-standby cycles; 4K144 standby.
- Full system suspend, including a recorded ~197-second interval, then recovery.
- Clamshell display standby and upstream cable replug at 4K144.
- eDP-depth boot and standby captures, with 24-bpp internal output.
- User-reported overnight suspend with everything still working.

Some earlier wakes initially showed a black background or needed pointer motion
before repaint. Recent reports were good. Early suspend wakeups were considered
consistent with mouse movement; no wake-source policy change was made.

## Known limits and remaining work

- Transparent-mode selection is deliberately scoped; this is not a general TB4
  or USB4 validation matrix. Reversed orientation and other dock topologies are
  not certified by these results.
- Early receiver capability reads can still time out before transparent mode is
  selected. Do not confuse successful recovery with absence of all AUX errors.
- The original eDP BPP gate and the newer eDP-depth correction are different
  experiments. The former stays off; the latter is on.
- Recovery v4's necessity after transparent mode is not yet established. Test
  disabling it independently before deleting it.
- Retry/trace code and disabled alternatives remain in the consolidated patch.
  Removing them changes code or behavior and deserves a separate review/test.
- Full kernel build and real hardware checks remain the device owner's part of
  the cleanup validation. The packaging check establishes exact patched-source
  equality, not an independent proof that the underlying driver is correct.

## Original display patch order

These patches were applied after all older platform transformations. Their net
result is now `patches/a14-display-stack.patch`. Original files and intermediate
states remain available in the user's Git history. Hashes identify the captured
inputs; they do not pin or modify the user's Git commit.

| Order | Original patch | SHA-256 |
| --- | --- | --- |
| 1 | `a14-dp-dsc-4k60-test.patch` | `d71a986448546627c1c8678a595e091a716cd16080615d98ce8e7a64abde24ad` |
| 2 | `a14-dp-dsc-144-test.patch` | `3c9f57dd173b6fd846c10a6c7650f827c0a2ca019af7ce0a8ee3c03d57c711ea` |
| 3 | `a14-dp-dsc-wake-test.patch` | `f6a25a73be2e19dbe9a87cb598e8a3fed40d116a21db6bef8a1be70ec862190c` |
| 4 | `a14-dp-aux-wake-test.patch` | `ed78dc83ff75f128e6b1f95266ac94f7f6df073816222f8618e051f67f197aa0` |
| 5 | `a14-dock-hpd-test.patch` | `c41e92c9dd221c101e601c413e3c473aa1505995832f5027d7f08c76b51c4642` |
| 6 | `a14-edp-retry-test.patch` | `b67c5ecf49a11e62e287796c1ebedaaab2364d7219602a3e081233f4b4daa60d` |
| 7 | `a14-dp-pair-config-test.patch` | `c92b805dc48c1d1befb36349784923132944c48a005b84785e817f1a78ef0459` |
| 8 | `a14-dp-sink-power-test.patch` | `4dee06d859e5ac0938acfb57abf1e049298e946ff8f82fff4b4258a9a80430d9` |
| 9 | `a14-dp-state-trace-test.patch` | `e07e22ccec03321b94db5eac889621cb1d341f37ffe374e33fdada569c5217cc` |
| 10 | `a14-dp-config-reuse-test.patch` | `1184d92db39ef508687168d2286e7ccd92ea533c0bf22570b09e532f3c734dcb` |
| 11 | `a14-dp-repeater-restore-test.patch` | `362f154d3ba6b15e6c3a8e2a46806bab73e8dc4fa0078fe2c5d1c16764910b0b` |
| 12 | `a14-dp-sink-cleanup-test.patch` | `b41880e7aab069e1bfab0fb277acc6f94f3f42f3eca8141f405acd39d0e25fe4` |
| 13 | `a14-dp-review-theories-test.patch` | `5d994e574f3e7488c7f59dd3a05ad4ff21c6c7376e307f01041ef69c723dc8c1` |
| 14 | `a14-dp-repeater-reset-test.patch` | `2d3dd04be502c5923ba8d92d4bdd2f745ec67a8a42ed7a1edd7fd4878045e041` |
| 15 | `a14-dp-transparent-test.patch` | `46435e2271e3139f3f6c1e723c0127b88a128e441d4295c3a51c07b5cf22515a` |
| 16 | `a14-edp-depth-test.patch` | `29730a67505556cf4494ae7aaa084ec8afb3401e8e058878de23325c6631d61d` |

## Module migration

Module order is unchanged. Each `experiments/a14-NAME/nixos.nix` moved to
`display/options/NAME.nix`. Recovery references `display/dock-recovery.py`.
All recorder callers should now use `tools/a14-display-capture.py`.
Historical notes below `history/` may reference removed paths or superseded
experiments and should not be followed as current installation instructions.
