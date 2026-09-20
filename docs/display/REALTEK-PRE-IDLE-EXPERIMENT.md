# Realtek pre-idle timing diagnostic

The corrected post-idle test ran: idle completed at 1177.164066, the hold began
at 1177.164482 and ended at 1178.176108, compression stopped at 1178.178794,
and D3 followed at 1178.179520. The user still saw the flash immediately.
That places it at the idle transition or earlier, before the later cleanup.

This experiment adds a separate pause immediately before the bridge requests
PUSH_IDLE. It is a timing diagnostic, not a proposed permanent fix.

## Implementation and scope

`msm.a14_dp_realtek_pre_idle_hold_ms` is an unsigned, root-writable runtime
parameter. Zero is the default and bypasses all diagnostic work. Nonzero
values are capped at 1000 ms for the actual pause and sampled once per call.
The earlier `msm.a14_dp_realtek_idle_hold_ms` parameter controls the post-idle
pause independently. For this experiment, set the post-idle parameter to zero.

Both phases share the same narrow board/port, exact Realtek branch identity,
DSC, enabled-clock and two-lane HBR3 checks. The pre-idle phase requires idle
not to have completed; the post-idle phase requires successful idle completion.
The software `plugged` and normal AUX transfer disconnect checks remain in
place. Native HPD zero is allowed, as required for this A14 USB-C connection.

Only the connected bridge atomic-disable callback invokes these holds. The
new pre-idle call is before the old early-D3 hook and before PUSH_IDLE; the
three old shutdown experiments must still be disabled. A successful pre-idle
hold performs one checked branch-identity read, logs BEGIN, sleeps, then logs
END. It sends no video-stop, compression-disable or power-down command. The
ordinary shutdown sequence follows the hold.

The display engine remains configured at this point in the verified atomic
helper sequence. The experiment does not guarantee that a desktop image is
still visible: earlier compositor or display work could already have changed
the picture, and observing that is part of the test.

## Install

Apply this incremental patch over the installed Realtek post-idle experiment
and its native-HPD correction. All earlier experiment patches remain installed.

Save `a14-realtek-pre-idle-experiment.patch` in `~/Downloads`:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --check ~/Downloads/a14-realtek-pre-idle-experiment.patch
git apply --whitespace=nowarn ~/Downloads/a14-realtek-pre-idle-experiment.patch
```

Set these entries in the existing `boot.kernelParams` list. Keep unrelated
settings, including the original DSC and DSC-wake enablement flags.

```nix
"msm.a14_dp_defer_sink_clear_test=0"
"msm.a14_dp_d3_before_dsc_test=0"
"msm.a14_dp_early_d3_test=0"
"msm.a14_dp_direct_two_lane_test=0"
"msm.a14_dp_realtek_idle_hold_ms=0"
"msm.a14_dp_realtek_pre_idle_hold_ms=1000"
```

Build the boot generation using the local repository, including new files:

```bash
cd ~/Projects/linux-zenbook-a14-arm
sudo nixos-rebuild boot --flake /etc/nixos#a14 \
  --override-input a14 "path:$PWD" --no-write-lock-file
sudo reboot
```

## Run the comparison

Connect through WAVLINK at 3840x2160@144, with the internal display disabled.

```bash
for p in \
  a14_dp_defer_sink_clear_test \
  a14_dp_d3_before_dsc_test \
  a14_dp_early_d3_test \
  a14_dp_direct_two_lane_test \
  a14_dp_realtek_idle_hold_ms \
  a14_dp_realtek_pre_idle_hold_ms
do
  printf '%s: ' "$p"
  cat "/sys/module/msm/parameters/$p"
done
```

Expected: N, N, N, N, 0, 1000.

Use the direct blank command, watching from the moment you submit it:

```bash
(
  gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
    --object-path /org/gnome/Mutter/DisplayConfig \
    --method org.freedesktop.DBus.Properties.Set \
    org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 3>' &&
  {
    sleep 8
    gdbus call --session --dest org.gnome.Mutter.DisplayConfig \
      --object-path /org/gnome/Mutter/DisplayConfig \
      --method org.freedesktop.DBus.Properties.Set \
      org.gnome.Mutter.DisplayConfig PowerSaveMode '<int32 0>'
  }
)
```

Report whether the picture stays normal for roughly one second before flashing,
whether it flashes immediately, or whether another sequence occurs. If it
turns black before the flash, mention that too. Timing is relative to command
submission, not just to disappearance of the desktop.

Collect the log after wake:

```bash
sudo journalctl -b -k --since "2 minutes ago" \
  -o short-monotonic --no-pager |
  rg 'A14-Realtek|idle_patterns_sent|compression:|A14-DP-power'
```

The expected relevant order is:

1. `A14-Realtek-pre-idle: BEGIN 1000 ms hold before PUSH_IDLE`;
2. About one second later, `A14-Realtek-pre-idle: END hold; PUSH_IDLE follows`;
3. `idle_patterns_sent`, then normal cleanup and D3.

There should be no post-idle BEGIN/END while its parameter is zero. The logs
must show the pre-idle BEGIN/END before the result can be interpreted. SKIP,
identity mismatch or AUX read failure means that the new hold did not run.

- Normal picture through the pause, flash at its end: stronger evidence that
  the source idle transition interacting with the branch triggers the flash.
- Flash immediately, while the confirmed pre-idle pause is still running:
  investigate earlier compositor/atomic-disable work and the read before BEGIN.
- Flash absent: the added delay changes the outcome, requiring a comparison
  with the timer set to zero before concluding anything further.

This remains an observation-based localization. It does not capture DP symbols
or establish whether the source or Realtek firmware violates the protocol.

## Runtime control and rollback

Disable only the new pause, with no rebuild or reboot:

```bash
echo 0 | sudo tee /sys/module/msm/parameters/a14_dp_realtek_pre_idle_hold_ms
```

Re-enable it:

```bash
echo 1000 | sudo tee /sys/module/msm/parameters/a14_dp_realtek_pre_idle_hold_ms
```

Changes apply on the next matching disable, not to a sleep already underway.
The diagnostic also affects matching modesets, so leave it at zero when not
testing. For persistence, remove its boot parameter or set it to zero on the
next rebuild. An older boot generation remains available if needed.

To remove this incremental patch, first remove its boot parameter, then:

```bash
cd ~/Projects/linux-zenbook-a14-arm
git apply --reverse --check ~/Downloads/a14-realtek-pre-idle-experiment.patch
git apply --reverse ~/Downloads/a14-realtek-pre-idle-experiment.patch
```

Rebuild and reboot. The corrected post-idle diagnostic remains installed.

## Validation

- Kernel patch applies and reverses byte-for-byte without fuzz or offsets on
  the corrected post-idle source used for the successful hardware hold.
- The shared helper, board/port predicate and both wrappers compile in a
  stubbed C harness with `-Wall -Wextra -Werror`, including printf-format checks.
- 114 cases cover both phases, their opposite idle-state requirements,
  independent timers, native HPD zero, software AUX disconnect, read failures,
  exact identity, conflicting experiments, delay bounds, one-time sampling,
  correct phase messages and unchanged controller state.
- Callback ordering checked: pre-idle hold, old early-D3 hook, PUSH_IDLE,
  post-idle hold, then DPU disable in the pinned atomic-helper sequence.
- Modified Nix integration parses using the tree-sitter Nix grammar and all
  six referenced patch files exist.
- Delivery patch applies and reverses exactly on the installed corrected
  post-idle repository baseline.

No full Nix evaluation, kernel build or A14 hardware test was performed here.
