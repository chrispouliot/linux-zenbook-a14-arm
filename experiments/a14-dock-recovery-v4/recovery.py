import errno
import fcntl
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time

ROOT = Path('/sys/bus/platform/devices/a600000.usb')
PORT = Path('/sys/class/typec/port0')
COMMAND = Path('/sys/kernel/debug/usb/ucsi/pmic_glink.ucsi.0/command')
STATE = Path('/run/a14-dock-boot-recovery')
KERNEL = '7.2.0-rc5-next-20260731'

def log(message):
    print(message, flush=True)

def read(path):
    try:
        return path.read_text().strip().rstrip('\0')
    except OSError:
        return None

def under(path, parent):
    return path.resolve().is_relative_to(parent.resolve())

def write(path, value, append=False):
    flags = os.O_WRONLY | os.O_CLOEXEC | (os.O_APPEND if append else 0)
    fd = os.open(path, flags)
    try:
        data = (value + '\n').encode()
        if os.write(fd, data) != len(data):
            raise OSError(errno.EIO, 'short command write')
    finally:
        os.close(fd)

def snapshot():
    usb = []
    storage = False
    for dev in Path('/sys/bus/usb/devices').iterdir():
        if not under(dev, ROOT):
            continue
        if read(dev / 'bInterfaceClass') == '08':
            storage = True
        vendor = read(dev / 'idVendor')
        if vendor:
            usb.append(dict(name=dev.name, vendor=vendor,
                            product=read(dev / 'idProduct'),
                            speed=read(dev / 'speed')))
    connectors = [p for p in Path('/sys/class/drm').glob('card*-DP-1')
                  if 'ae01000.display-controller' in p.resolve().parts]
    return dict(
        usb=sorted(usb, key=lambda x: x['name']), storage=storage,
        dp=read(connectors[0] / 'status') if len(connectors) == 1 else None,
        enabled=read(connectors[0] / 'enabled') if len(connectors) == 1 else None,
        role=read(PORT / 'data_role'), orientation=read(PORT / 'orientation'),
        maximum_speed=read(ROOT / 'of_node/maximum-speed'),
        driver=(ROOT / 'driver').resolve().name,
        ucsi_port='pmic_glink.ucsi.0' in PORT.resolve().parts,
    )

def topology_reason(s):
    # Retain v3's board/port/topology/storage restrictions.
    if s['maximum_speed'] != 'super-speed':
        return 'the tested USB 5 Gbps limit is absent'
    if s['driver'] != 'dwc3-qcom' or not s['ucsi_port']:
        return 'controller or UCSI mapping differs'
    if s['role'] != '[host] device' or s['orientation'] != 'normal':
        return 'port role/orientation differs from the confirmed tests'
    roots = [d for d in s['usb'] if re.fullmatch(r'[0-9]+-1', d['name'])
             and (d['vendor'], d['product'], d['speed']) ==
             ('1d5c', '5801', '480')]
    if len(roots) != 1:
        return 'the expected dock USB2 root hub is absent'
    root = roots[0]['name']
    if not any(d['name'] == root + '.4' and
               (d['vendor'], d['product']) == ('2109', '2822')
               for d in s['usb']):
        return 'the expected downstream VIA hub is absent'
    if s['storage']:
        return 'USB storage is attached to this controller'
    return None


def failure_reason(s, evidence):
    reason = topology_reason(s)
    if reason:
        return reason
    if s['dp'] == 'disconnected':
        # Original v3 recovery signature; do not broaden unknown states.
        if any('-' in d['name'] and d['speed'] not in ('1.5', '12', '480')
               for d in s['usb']):
            return 'disconnected DP with SuperSpeed present or unknown USB speed'
        return None
    if s['dp'] != 'connected' or s['enabled'] != 'enabled':
        return 'DP-1 state is unknown or it is not enabled'
    if not evidence or not evidence.get('failed_enable'):
        return 'no explicit port-one failed-enable record this boot'
    link = evidence.get('link', {})
    if link.get('error') or not link.get('valid'):
        return 'live DP link state is unavailable or invalid'
    if link['trained']:
        return 'live DP link is already trained'
    # New case: positive failed-enable evidence AND a currently untrained link.
    # Ethernet enumeration or SuperSpeed USB does not mean display output works.
    return None


def decode_link(config, status):
    if len(config) != 3 or len(status) != 6:
        raise ValueError('short DPCD read')
    lanes = config[1] & 0x1f
    valid = config[0] in (0x06, 0x0a, 0x14, 0x1e) and lanes in (1, 2, 4)
    trained = valid and bool(status[2] & 1) and all(
        ((status[i // 2] >> (4 * (i % 2))) & 7) == 7 for i in range(lanes))
    return dict(valid=valid, trained=trained, lanes=lanes,
                config=config.hex(), status=status.hex())


def aux_child():
    # Dynamic AUX index, but fixed physical DP controller. No AUX writes.
    matches = [p for p in Path('/sys/class/drm_dp_aux_dev').glob('drm_dp_aux*')
               if 'af54000.displayport-controller' in p.resolve().parts]
    if len(matches) != 1:
        raise RuntimeError('port-one AUX mapping is unavailable or ambiguous')
    fd = os.open('/dev/' + matches[0].name, os.O_RDONLY | os.O_CLOEXEC)
    try:
        config = os.pread(fd, 3, 0x100)
        status = os.pread(fd, 6, 0x202)
        print(json.dumps(decode_link(config, status)), flush=True)
    finally:
        os.close(fd)


def read_link():
    try:
        p = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--aux-child'],
                           capture_output=True, text=True, timeout=8, check=True)
        return json.loads(p.stdout)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        return dict(error=str(e))


def has_failed_enable(journal):
    return ('msm-dp-display af54000.displayport-controller: '
            'A14-DP: failed enable resources released') in journal


def collect_evidence(name):
    journal = subprocess.run(['journalctl', '-k', '-b', '--no-pager', '-o', 'cat'],
                             capture_output=True, text=True, timeout=8, check=True).stdout
    (STATE / (name + '-kernel.log')).write_text(journal)
    e = dict(failed_enable=has_failed_enable(journal), link=read_link())
    (STATE / (name + '-link.json')).write_text(json.dumps(e, indent=2) + '\n')
    return e


def display_manager_inactive():
    p = subprocess.run(['systemctl', 'show', 'display-manager.service',
                        '--property=ActiveState', '--value'],
                       capture_output=True, text=True, timeout=5, check=True)
    return p.stdout.strip() == 'inactive'


def uptime_seconds():
    return float(Path('/proc/uptime').read_text().split()[0])

def wait_for_boot_state():
    # Early DP status can be provisional while the dock hubs enumerate.
    # Always retain the grace period used by the successful v1 boot reset.
    log('Waiting until 30 seconds after boot for normal dock enumeration')
    time.sleep(max(0, 30 - uptime_seconds()))
    return snapshot()

def ucsi_version():
    # Same temporary ARM64 probe as the twice-successful manual recorder.
    # Never reinterpret USB-PD revision as UCSI interface version.
    tracefs = next((Path(p) for p in ('/sys/kernel/tracing',
                      '/sys/kernel/debug/tracing')
                    if (Path(p) / 'kprobe_events').is_file()), None)
    if tracefs is None:
        raise RuntimeError('tracefs/kprobes unavailable; no reset')
    rows = [line.split() for line in Path('/proc/kallsyms').read_text().splitlines()
            if len(line.split()) >= 3 and line.split()[2] == 'ucsi_send_command'
            and line.split()[1].lower() == 't']
    if len(rows) != 1:
        raise RuntimeError('ucsi_send_command symbol is ambiguous; no reset')
    row = rows[0]
    if len(row) == 3:
        target = 'ucsi_send_command'
    elif len(row) == 4 and row[3] == '[typec_ucsi]':
        target = 'typec_ucsi:ucsi_send_command'
    else:
        raise RuntimeError('unexpected UCSI module; no reset')
    group = 'a14_boot_ucsi_' + str(os.getpid())
    instance = tracefs / 'instances' / group
    created = installed = False
    try:
        instance.mkdir()
        created = True
        write(instance / 'tracing_on', '0')
        write(tracefs / 'kprobe_events',
              f'p:{group}/version {target} version=+0(%x0):x16 command=%x1:x64', True)
        installed = True
        event = instance / 'events' / group / 'version'
        write(event / 'filter', 'command == 6')
        write(event / 'enable', '1')
        write(instance / 'tracing_on', '1')
        write(COMMAND, '0x6')
        write(instance / 'tracing_on', '0')
        write(event / 'enable', '0')
        trace = (instance / 'trace').read_text()
        (STATE / 'ucsi-version.trace').write_text(trace)
        versions = {int(v, 16) for v, c in re.findall(
            r'\bversion=(0x[0-9a-fA-F]+)\s+command=(0x[0-9a-fA-F]+)', trace)
            if int(c, 16) == 6}
        if versions != {0x0210}:
            raise RuntimeError(f'UCSI version differs from tested 2.1: {versions}; no reset')
        log('Verified UCSI 2.1 using GET_CAPABILITY')
    finally:
        # A cleanup failure aborts recovery rather than hiding a tracing error.
        problems = []
        if created:
            for name in ('tracing_on', 'events/enable'):
                try:
                    write(instance / name, '0')
                except OSError as e:
                    problems.append(str(e))
            try:
                instance.rmdir()
            except OSError as e:
                problems.append(str(e))
        if installed:
            try:
                write(tracefs / 'kprobe_events', f'-:{group}/version', True)
            except OSError as e:
                problems.append(str(e))
        if problems:
            raise RuntimeError('Probe cleanup failed: ' + '; '.join(problems))

def capture(name):
    s = snapshot()
    (STATE / name).write_text(json.dumps(s, indent=2) + '\n')
    return s

def main():
    log('A14 dock boot recovery v4')
    if os.geteuid() != 0:
        raise RuntimeError('root is required')
    if platform.machine() != 'aarch64' or platform.release() != KERNEL:
        log('SKIP: this workaround is restricted to the tested A14 kernel')
        return
    if read(Path('/sys/firmware/devicetree/base/model')) != 'ASUS Zenbook A14 (UX3407NA)':
        log('SKIP: device model differs')
        return
    STATE.mkdir(mode=0o700, exist_ok=True)
    with (STATE / 'lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if (STATE / 'checked').exists():
            log('SKIP: boot recovery has already been checked this boot')
            return
        if uptime_seconds() > 120:
            log('SKIP: outside the boot window; reboot to test')
            return
        before = wait_for_boot_state()
        (STATE / 'checked').write_text('One check per boot; no automatic retries.\n')
        (STATE / 'before.json').write_text(json.dumps(before, indent=2) + '\n')
        reason = topology_reason(before)
        if reason:
            log('SKIP: ' + reason)
            return
        if not display_manager_inactive():
            log('SKIP: display manager is not inactive; no session-time reset')
            return
        evidence = collect_evidence('before') if before['dp'] == 'connected' else None
        reason = failure_reason(before, evidence)
        if reason:
            log('SKIP: ' + reason)
            return
        if not COMMAND.is_file():
            raise RuntimeError('UCSI command interface unavailable; no reset')
        time.sleep(2)
        if snapshot() != before:
            log('SKIP: dock state is still changing')
            return
        ucsi_version()
        # Recheck after version probing; never reset a link that recovered meanwhile.
        final = snapshot()
        final_evidence = collect_evidence('recheck') if final['dp'] == 'connected' else None
        reason = failure_reason(final, final_evidence)
        if final != before or reason or not display_manager_inactive():
            log('SKIP: final state changed or recovery no longer qualifies: ' + str(reason))
            return
        (STATE / 'attempted').write_text('connector 1: UCSI Data Reset 0x810003\n')
        log('Issuing ONE port-one UCSI Data Reset (0x810003); reason=' +
            ('explicit failed enable with untrained link' if final['dp'] == 'connected'
             else 'original missing-DP/USB3 signature'))
        write(COMMAND, '0x810003')
        time.sleep(20)
        after = capture('after.json')
        result = collect_evidence('after')
        nic = next((d for d in after['usb'] if
                    (d['vendor'], d['product']) == ('0bda', '8156')), None)
        trained = result['link'].get('valid') and result['link'].get('trained')
        log('RESULT: DP-1=' + str(after['dp']) + '; link_trained=' + str(bool(trained)) +
            '; Ethernet USB speed=' + (str(nic['speed']) + ' Mb/s' if nic else 'absent'))
        if after['dp'] != 'connected' or not trained or not nic or nic['speed'] != '5000':
            raise RuntimeError('recovery incomplete; no retry will be attempted')
        log('Link training and Ethernet enumeration recovered; confirm the monitor picture')


def terminated(signum, frame):
    raise RuntimeError('service terminated')

if __name__ == '__main__':
    if sys.argv[1:] == ['--aux-child']:
        aux_child()
        sys.exit(0)
    if sys.argv[1:]:
        raise SystemExit('This program runs only as the boot service')
    signal.signal(signal.SIGTERM, terminated)
    try:
        main()
    except Exception as e:
        log('ERROR: ' + str(e))
        sys.exit(1)