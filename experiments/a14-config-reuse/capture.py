#!/usr/bin/env python3
"""Read-only A14 display/DSC and local-patch capture. No resets or mode changes."""
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time


def aux_read(device, edp=False):
    # Capability and current-configuration registers only. Never open for write.
    ranges = [('receiver', 0x000, 16), ('sink_power', 0x600, 1),
              ('link_config', 0x100, 3), ('link_status', 0x202, 6),
              ('dsc_caps', 0x060, 16), ('fec_caps', 0x090, 1),
              ('fec_config', 0x120, 1), ('dsc_enable', 0x160, 1),
              ('fec_status', 0x280, 1), ('extended_receiver', 0x2200, 16),
              ('repeater_caps', 0xf0000, 8)]
    if edp:
        ranges = [('receiver', 0x000, 16), ('link_config', 0x100, 3),
                  ('link_status', 0x202, 6), ('sink_power', 0x600, 1)]
    result = {}
    fd = os.open(device, os.O_RDONLY | os.O_CLOEXEC)
    try:
        for name, offset, size in ranges:
            try:
                data = os.pread(fd, size, offset)
                result[name] = dict(offset=hex(offset), requested=size,
                                    returned=len(data), hex=data.hex(' '))
            except OSError as e:
                result[name] = dict(offset=hex(offset), error=str(e))
                print(json.dumps({name: result[name]}), flush=True)
                if e.errno in (errno.ETIMEDOUT, errno.ENXIO, errno.EIO, errno.ENODEV):
                    print(json.dumps({'stopped': 'AUX unavailable; remaining reads skipped'}), flush=True)
                    break
                continue
            print(json.dumps({name: result[name]}), flush=True)
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo', type=Path, help='Current local A14 patch repository')
    parser.add_argument('output', type=Path, help='New .tar.gz capture path')
    parser.add_argument('--delay', type=int, default=0,
                        help='Wait 0–900 seconds before capture, without changing display settings')
    args = parser.parse_args()
    if not 0 <= args.delay <= 900:
        parser.error('--delay must be between 0 and 900 seconds')
    repo = args.repo.expanduser().resolve()
    output = args.output.expanduser().absolute()
    if os.geteuid() != 0:
        parser.error('Run through sudo for debugfs and AUX read access.')
    if not (repo / 'kernel.nix').is_file() or not (repo / 'patches').is_dir():
        parser.error('Expected kernel.nix and patches/ in the supplied repository.')
    if output.exists() or output.is_symlink() or not output.parent.is_dir():
        parser.error('Choose a new output filename in an existing directory.')
    print('A14 verified receiver configuration recorder v1 — read-only', flush=True)
    print('Keep the current connection, whether the display works or is blank. No reset or modeset is performed.', flush=True)
    if args.delay:
        print(f'Countdown started: capturing automatically in {args.delay} seconds. '
              'Leave this process running; wake/unlock before capture and keep the cable connected.', flush=True)
        try:
            time.sleep(args.delay)
        except KeyboardInterrupt:
            print('Cancelled before capture; no output archive created.', flush=True)
            return
    errors = []
    with tempfile.TemporaryDirectory(prefix='a14-dsc-baseline-') as tmp:
        folder = Path(tmp)

        def save(name, data):
            dest = folder / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data if isinstance(data, bytes) else data.encode())

        def copy(source, name):
            try:
                save(name, source.read_bytes())
            except OSError as e:
                errors.append(f'{source}: {e}')

        def run(name, command, timeout=20):
            try:
                p = subprocess.run(command, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=timeout)
                save(name, p.stdout)
                if p.returncode:
                    errors.append(f'{name}: exit status {p.returncode}')
            except subprocess.TimeoutExpired as e:
                save(name, e.stdout or b'')
                errors.append(f'{name}: timed out after {timeout}s')
            except OSError as e:
                errors.append(f'{name}: {e}')

        print('Capturing current local patches and build identity...', flush=True)
        manifest = []
        sources = [repo / n for n in ('kernel.nix', 'flake.nix', 'flake.lock')]
        sources += sorted((repo / 'patches').rglob('*'))
        sources += sorted((repo / 'experiments').rglob('*'))
        total = 0
        for src in sources:
            if not src.is_file():
                continue
            relative = src.relative_to(repo)
            if src.is_symlink() or not src.resolve().is_relative_to(repo):
                errors.append(f'Skipped symlink/outside-repo file: {relative}')
                continue
            size = src.stat().st_size
            if size > 16 * 1024 * 1024 or total + size > 64 * 1024 * 1024:
                errors.append(f'Skipped oversized patch file: {relative}')
                continue
            data = src.read_bytes()
            total += len(data)
            save('local-repo/' + str(relative), data)
            manifest.append(dict(path=str(relative), bytes=len(data),
                                 sha256=hashlib.sha256(data).hexdigest()))
        save('local-repo/manifest.json', json.dumps(manifest, indent=2))
        if shutil.which('git'):
            git = ['git', '-c', 'safe.directory=' + str(repo), '-C', str(repo)]
            run('local-repo/head.txt', git + ['rev-parse', 'HEAD'])
            run('local-repo/status.txt', git + ['status', '--short', '--untracked-files=all',
                                               '--', 'kernel.nix', 'flake.nix', 'flake.lock', 'patches'])
            run('local-repo/diff-from-head.patch', git + ['diff', '--no-ext-diff', '--no-textconv',
                                                        'HEAD', '--', 'kernel.nix', 'flake.nix', 'patches'])
        for path in ('/proc/version', '/proc/cmdline', '/sys/firmware/devicetree/base/model'):
            copy(Path(path), 'system/' + Path(path).name)
        save('system/paths.txt', '\n'.join(f'{p} -> {Path(p).resolve()}' for p in
             ('/run/booted-system', '/run/booted-system/kernel', '/run/current-system',
              '/run/current-system/kernel', '/run/current-system/kernel-modules')) + '\n')
        for name in ('a14_dp_dsc_test', 'a14_dp_dsc_144_test', 'a14_dp_dsc_wake_test', 'a14_dp_aux_wake_test', 'a14_edp_retry_test', 'a14_dp_pair_config_test', 'a14_dp_sink_power_test', 'a14_dp_state_trace_test', 'a14_dp_config_reuse_test'):
            copy(Path('/sys/module/msm/parameters') / name, 'system/msm-' + name)
        retired = Path('/sys/module/msm/parameters/a14_dp_lttpr_wake_test')
        save('system/retired-lttpr-parameter.txt', retired.read_text() if retired.exists() else 'absent (expected)\n')
        copy(Path('/sys/module/pmic_glink_altmode/parameters/a14_dock_hpd_test'),
             'system/pmic_glink_altmode-a14_dock_hpd_test')
        copy(Path('/proc/uptime'), 'system/uptime-before')
        copy(Path('/proc/sys/kernel/tainted'), 'system/tainted')
        # Preserve crash records without clearing firmware/pstore or changing services.
        for crash_root in (Path('/sys/fs/pstore'), Path('/var/lib/systemd/pstore')):
            if not crash_root.is_dir():
                continue
            count = total_crash = 0
            for item in sorted(crash_root.rglob('*')):
                if item.is_symlink() or not item.is_file():
                    continue
                try:
                    size = item.stat().st_size
                    if count >= 128 or size > 4 * 1024 * 1024 or total_crash + size > 32 * 1024 * 1024:
                        errors.append(f'Skipped oversized/additional crash record: {item}')
                        continue
                    copy(item, 'crash/' + str(item).lstrip('/'))
                    count += 1
                    total_crash += size
                except OSError as e:
                    errors.append(f'{item}: {e}')
        # No firmware directory or unrelated NixOS configuration is copied.
        run('system/kernel-journal.log', ['journalctl', '-b', '-k', '-o', 'short-monotonic', '--no-pager'])
        run('system/previous-kernel-journal.log', ['journalctl', '-b', '-1', '-k', '-o', 'short-monotonic', '--no-pager'])
        run('system/clock-summary.txt', ['cat', '/sys/kernel/debug/clk/clk_summary'], timeout=10)
        run('system/boot-recovery.log', ['journalctl', '-b', '-u', 'a14-dock-boot-recovery.service', '--no-pager'])
        # Restrict userspace capture to GNOME Shell/GDM diagnostics for black unlock.
        run('system/gnome-shell-journal.log', ['journalctl', '-b', '--since=-15min',
            '-o', 'short-monotonic', '--no-pager', '_COMM=gnome-shell', '_COMM=.gnome-shell-wr',
            '+', 'SYSLOG_IDENTIFIER=gnome-shell', 'SYSLOG_IDENTIFIER=.gnome-shell-wr'])
        run('system/display-manager-journal.log', ['journalctl', '-b', '--since=-15min',
            '-o', 'short-monotonic', '--no-pager', '-u', 'display-manager.service'])
        if shutil.which('nmcli'):
            run('system/network-devices.txt', ['nmcli', '-t', '-f', 'DEVICE,TYPE,STATE', 'device', 'status'])

        if shutil.which('lsusb'):
            run('system/usb-tree.txt', ['lsusb', '-t'])

        print('Capturing EDIDs, live link settings, and DRM state...', flush=True)
        connected = set()
        for connector in sorted(Path('/sys/class/drm').glob('card*-*')):
            if not (connector / 'status').is_file():
                continue
            prefix = 'drm/' + connector.name + '/'
            status = (connector / 'status').read_text().strip()
            if status == 'connected':
                connected.add(connector.name.split('-', 1)[1])
            for name in ('status', 'enabled', 'modes', 'edid'):
                copy(connector / name, prefix + name)
            edid = folder / prefix / 'edid'
            if edid.exists() and edid.stat().st_size and shutil.which('edid-decode'):
                run(prefix + 'edid-decoded.txt', ['edid-decode', str(edid)])
        debug = Path('/sys/kernel/debug/dri/ae01000.display-controller')
        for path in [debug / 'state', debug / 'debug/core_perf/max_core_clk_rate',
                     debug / 'debug/core_perf/core_clk_rate'] + sorted(debug.glob('*/dp_debug')):
            # Separate reader limits stalls without writing to DRM interfaces.
            run('debug/' + str(path.relative_to(debug)),
                [sys.executable, '-c',
                 'import pathlib,sys;sys.stdout.buffer.write(pathlib.Path(sys.argv[1]).read_bytes())',
                 str(path)], timeout=10)
        for node in ('af54000.displayport-controller', 'af5c000.displayport-controller',
                     'af6c000.displayport-controller', 'a600000.usb', 'a800000.usb'):
            base = Path('/sys/bus/platform/devices') / node / 'of_node'
            save('device-tree/' + node + '/path.txt', str(base.resolve()))
            if not base.exists():
                continue
            for prop in base.rglob('*'):
                if prop.name in ('link-frequencies', 'data-lanes', 'maximum-speed',
                                 'role-switch-default-mode', 'compatible', 'status') and prop.is_file():
                    copy(prop, 'device-tree/' + node + '/' + str(prop.relative_to(base)))

        # Match AUX by physical controller, not unstable drm_dp_aux numbering.
        aux_map = []
        controllers = {'af54000.displayport-controller': 'DP-1',
                       'af5c000.displayport-controller': 'DP-2',
                       'af6c000.displayport-controller': 'eDP-1'}
        for entry in sorted(Path('/sys/class/drm_dp_aux_dev').glob('drm_dp_aux*')):
            resolved = entry.resolve()
            aux_map.append(dict(name=entry.name, path=str(resolved)))
            connector = next((c for dev, c in controllers.items() if dev in resolved.parts), None)
            if connector not in connected:
                continue
            device = Path('/dev') / entry.name
            try:
                if not stat.S_ISCHR(device.stat().st_mode):
                    continue
            except OSError:
                continue
            print(f'Reading {connector} link/capability registers via {entry.name}...', flush=True)
            run('aux/' + connector + '-' + entry.name + '.jsonl',
                [sys.executable, str(Path(__file__).resolve()), '--aux-edp-child' if connector == 'eDP-1' else '--aux-child',
                 str(device)], timeout=15)
        save('aux/mapping.json', json.dumps(aux_map, indent=2))
        run('system/kernel-journal-after-aux.log', ['journalctl', '-b', '-k', '-o', 'short-monotonic', '--no-pager'])
        copy(Path('/proc/uptime'), 'system/uptime-after')
        save('errors.txt', '\n'.join(errors) + '\n')
        with tarfile.open(output, 'x:gz') as archive:
            for path in sorted(folder.rglob('*')):
                if path.is_file():
                    archive.add(path, arcname=str(path.relative_to(folder)))
    # Make the root-created result downloadable by the sudo caller.
    if os.environ.get('SUDO_UID', '').isdigit() and os.environ.get('SUDO_GID', '').isdigit():
        os.chown(output, int(os.environ['SUDO_UID']), int(os.environ['SUDO_GID']))
    print('Saved ' + str(output))
    if errors:
        print(f'{len(errors)} unavailable/failed items recorded in errors.txt; upload the archive anyway.')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] in ('--aux-child', '--aux-edp-child'):
        aux_read(sys.argv[2], edp=sys.argv[1] == '--aux-edp-child')
    else:
        main()
