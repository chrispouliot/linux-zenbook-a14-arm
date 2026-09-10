> Historical experiment instructions, preserved for review. Use docs/display/README.md for the current workflow.

# A14 verified receiver configuration reuse experiment v1

## Evidence and hypothesis

The OWC dock boot failure in a14-state-trace-standby.tar.gz showed receiver
D0 (0x600=01), responsive AUX reads and link configuration 0x100=1e 82 before
and after both rate/lane writes timed out. DSC was disabled, FEC ready was set,
and link training had not completed. Reads did not establish a working link.
The cached repeater mode 55 versus live aa followed an explicit boot-time mode
switch and does not by itself indicate a mode mismatch.

This experiment tests whether a redundant rate/lane write blocks an otherwise
trainable link. Retained DPCD values may still be insufficient: success is not
assumed from register contents alone.

## Change and scope

New default-off C parameter `msm.a14_dp_config_reuse_test=1`, enabled by the
included Nix module. Requires the prior paired-configuration and DSC-wake gates,
which select ASUS UX3407NA, Glymur DP, af54000.displayport-controller / port one.
The eDP rate-table path is excluded by the existing guard.

After the existing before-config diagnostic snapshot, make a fresh normal
DPCD read of both bytes starting at 0x100. Only a complete read exactly matching
the requested rate and lane byte (including enhanced framing) skips the paired
configuration write. Neither cached values nor the diagnostic buffer is used.
A short/failed read or mismatch falls through to the unchanged checked-write,
verification and retry path. Normal AUX locking, retry and disconnect gates
remain in force. This check runs at each invocation of paired configuration,
not only boot or standby.

Returning success here completes only the rate/lane configuration step. The
caller still programs downspread/coding, trains each repeater and the receiver,
and performs the remaining stream/DSC/FEC setup. Training and stream-enable
functions are unchanged. No failed write is retroactively treated as success.

Expected new log:
`A14-DP-reuse: fresh match rate=1e lanes=82; skipping rate/lane write, training still required`

Other outcomes log `mismatch` or `pre-read returned` and use the checked-write
path. Existing A14-DP-state and training logs remain available. A later failure
can still cause the existing display-controller timeout cascade; this patch
does not implement recovery of a failed atomic enable. There is no new LTTPR
mode reset, rate cap change or USB/dock recovery change.

## Install and build

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-config-reuse-test.py \
  ~/Projects/linux-zenbook-a14-arm

git -C ~/Projects/linux-zenbook-a14-arm add -N -- \
  patches/a14-dp-config-reuse-test.patch experiments/a14-config-reuse

sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Review git diff before building. Keep blanking and automatic suspend disabled
during the build. Reboot after success. Kernel release and all previous patches
are preserved. No backups or commits are created. The installer validates the
latest captured recipe, patch/module hashes and pinned kernel source. It refuses
unexpected edits, supports read-only --check and is idempotent. Handled write
failures roll back; abrupt interruption is not transactional across files.

## Test boot first

Keep the OWC dock on the same laptop port, same cable and monitor, lid open,
4K144 and automatic system suspend off. After reboot:

```sh
cat /sys/module/msm/parameters/a14_dp_config_reuse_test
cat /sys/module/msm/parameters/a14_dp_state_trace_test
```

Both should print Y. Capture the boot result whether the display works or fails:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-config-reuse/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-config-reuse-boot.tar.gz
```

Leave cables connected until capture finishes. Upload that archive and report
both displays and desktop responsiveness. If boot fails, do not add a standby
cycle. If boot works, assess the capture before further testing so a later
standby failure does not obscure the first result.

## Subsequent standby test

Once ready to test standby, set blanking to one minute and start:

```sh
sudo nix shell nixpkgs#python3 --command python3 \
  ~/Projects/linux-zenbook-a14-arm/experiments/a14-config-reuse/capture.py \
  ~/Projects/linux-zenbook-a14-arm ~/a14-config-reuse-standby.tar.gz --delay 300
```

Wait for the five-minute countdown announcement. Let the external fully enter
standby, wait about three minutes, then wake/unlock before capture starts. Set
blanking back to Never to avoid a second cycle. Let capture finish before
unplugging even if external stays black. Keep system suspend disabled. Existing
diagnostic reads can influence timing or invoke existing AUX recovery; report
if capture itself changes the display behavior.

## Remove only this experiment

```sh
nix shell nixpkgs#python3 --command python3 \
  ~/Downloads/a14-install-config-reuse-test.py \
  ~/Projects/linux-zenbook-a14-arm --remove
sudo nix flake update a14 --flake /etc/nixos
sudo nixos-rebuild boot --flake /etc/nixos#a14
```

Removal retains all prior experiments including tracing and refuses modified
experiment-owned files. Booting an older generation does not revert the repo.

## Validation

ARM64 MSM objects compile and link against the pinned patched kernel. Actual C
function tests cover exact matches, rate/lane/framing mismatches, short/error
reads, scope/gates, fallback retries and error propagation. Training and stream
enable functions are checked unchanged. Installer tests cover exact baseline
application, refusal without writes, idempotence, removal preserving unrelated
edits and rollback of handled write failures. Recorder syntax is checked. Full
NixOS build and hardware testing must run on the laptop.
