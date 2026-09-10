#!/usr/bin/env python3
"""Dump the firmware ACPI tables from physical memory on a device-tree boot.

On the A14 the kernel boots from the device tree, so /sys/firmware/acpi does
not exist and acpidump refuses to run (it insists on listing
/sys/firmware/acpi/tables/dynamic). The tables are still in memory: the RSDP
address is published in /sys/firmware/efi/systab, and reading it needs a kernel
built with hardware.asus.zenbookA14.diagnostics.unrestrictedDevmem = true,
because the firmware keeps the tables inside memory the kernel counts as RAM.

Run as root:

    sudo python3 tools/a14-acpi-dump.py            # writes ./acpi-tables/*.dat
    iasl -d acpi-tables/dsdt.dat                   # from nixpkgs#acpica-tools

Options let you pass the RSDP address explicitly (--rsdp 0x...), read from a
different memory file (--mem), or choose the output directory (--out).
"""

import argparse
import errno
import mmap
import os
import re
import struct
import sys

RSDP_SIG = b"RSD PTR "
HEADER_LEN = 36


def parse_args():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--rsdp", help="RSDP physical address (default: from /sys/firmware/efi/systab)")
    p.add_argument("--mem", default="/dev/mem", help="memory device or image to read (default /dev/mem)")
    p.add_argument("--out", default="acpi-tables", help="output directory (default ./acpi-tables)")
    p.add_argument("--mmap", action="store_true", help="always read through mmap() instead of read()")
    p.add_argument("--systab", default="/sys/firmware/efi/systab", help=argparse.SUPPRESS)
    return p.parse_args()


def rsdp_from_systab(path):
    try:
        text = open(path).read()
    except OSError as e:
        sys.exit(f"cannot read {path} ({e}); pass --rsdp 0x... from 'dmesg | grep efi:'")
    for key in ("ACPI20", "ACPI"):
        m = re.search(rf"^{key}=(0x[0-9a-fA-F]+)", text, re.M)
        if m:
            return int(m.group(1), 16)
    sys.exit(f"no ACPI entry in {path}")


class ReadError(Exception):
    pass


class Mem:
    """Physical memory reader.

    read() on /dev/mem only works for memory the kernel has mapped; firmware
    regions it leaves unmapped (the FACS lives in one) fail with EFAULT and are
    read through mmap() instead. EPERM on either path means STRICT_DEVMEM.
    """

    def __init__(self, path, force_mmap=False):
        try:
            self.fd = os.open(path, os.O_RDONLY)
        except OSError as e:
            sys.exit(f"cannot open {path} ({e}); run as root")
        self.path = path
        self.force_mmap = force_mmap
        self.page = mmap.PAGESIZE

    def _strict(self, addr, e):
        raise ReadError(
            f"permission denied reading {addr:#x} from {self.path} ({e}): STRICT_DEVMEM is on; "
            "rebuild with hardware.asus.zenbookA14.diagnostics.unrestrictedDevmem = true"
        )

    def _pread(self, addr, length):
        data = b""
        while len(data) < length:
            chunk = os.pread(self.fd, length - len(data), addr + len(data))
            if not chunk:
                raise ReadError(f"short read at {addr:#x} from {self.path}")
            data += chunk
        return data

    def _mmap_raw(self, addr, length):
        start = addr & ~(self.page - 1)
        skip = addr - start
        m = mmap.mmap(self.fd, skip + length, flags=mmap.MAP_SHARED, prot=mmap.PROT_READ, offset=start)
        try:
            return bytes(m[skip:skip + length])
        finally:
            m.close()

    def _mmap(self, addr, length):
        """Run the mapped read in a child: touching memory the hardware refuses
        to serve raises SIGBUS, which would otherwise kill the whole dump."""
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:  # child
            os.close(r)
            code = 0
            try:
                out = self._mmap_raw(addr, length)
            except OSError as e:
                out, code = f"{e.errno}:{e}".encode(), 2
            except BaseException:  # noqa: BLE001
                out, code = b"", 3
            with os.fdopen(w, "wb") as f:
                f.write(out)
            os._exit(code)
        os.close(w)
        with os.fdopen(r, "rb") as f:
            data = f.read()
        _, status = os.waitpid(pid, 0)
        if os.WIFSIGNALED(status):
            raise ReadError(
                f"bus error reading {length} bytes at {addr:#x}: the hardware does not allow "
                "access to this region"
            )
        code = os.WEXITSTATUS(status)
        if code == 2:
            num, _, msg = data.decode(errors="replace").partition(":")
            if num.isdigit() and int(num) == errno.EPERM:
                self._strict(addr, msg)
            raise ReadError(f"cannot map {length} bytes at {addr:#x} from {self.path} ({msg})")
        if code != 0 or len(data) != length:
            raise ReadError(f"mapped read of {length} bytes at {addr:#x} failed")
        return data

    def read(self, addr, length):
        if not self.force_mmap:
            try:
                return self._pread(addr, length)
            except OSError as e:
                if e.errno == errno.EPERM:
                    self._strict(addr, e)
                if e.errno != errno.EFAULT:
                    raise ReadError(f"cannot read {length} bytes at {addr:#x} from {self.path} ({e})")
                # EFAULT: the kernel has no linear mapping for this region; map it directly.
        return self._mmap(addr, length)


def checksum_ok(data):
    return sum(data) & 0xFF == 0


def table_name(sig, seen):
    base = sig.decode("ascii", "replace").strip().lower() or "unknown"
    n = seen.get(base, 0)
    seen[base] = n + 1
    return f"{base}.dat" if n == 0 else f"{base}{n}.dat"


def main():
    args = parse_args()
    rsdp_addr = int(args.rsdp, 16) if args.rsdp else rsdp_from_systab(args.systab)
    mem = Mem(args.mem, force_mmap=args.mmap)
    os.makedirs(args.out, exist_ok=True)
    seen = {}
    written = []

    # Hand files back to the user who invoked sudo so iasl can write next to them.
    sudo_ids = None
    if os.environ.get("SUDO_UID"):
        sudo_ids = (int(os.environ["SUDO_UID"]), int(os.environ.get("SUDO_GID", -1)))
        os.chown(args.out, *sudo_ids)

    def save(name, data):
        path = os.path.join(args.out, name)
        with open(path, "wb") as f:
            f.write(data)
        if sudo_ids:
            os.chown(path, *sudo_ids)
        written.append(path)

    try:
        rsdp = mem.read(rsdp_addr, 36)
    except ReadError as e:
        sys.exit(str(e))
    if rsdp[:8] != RSDP_SIG:
        sys.exit(f"no RSDP signature at {rsdp_addr:#x} (got {rsdp[:8]!r})")
    revision = rsdp[15]
    rsdt_addr = struct.unpack_from("<I", rsdp, 16)[0]
    if revision >= 2:
        rsdp_len, xsdt_addr = struct.unpack_from("<IQ", rsdp, 20)
        rsdp = mem.read(rsdp_addr, rsdp_len)
    else:
        rsdp_len, xsdt_addr = 20, 0
        rsdp = rsdp[:20]
    if not checksum_ok(rsdp[:20]):
        print("warning: RSDP checksum mismatch", file=sys.stderr)
    save("rsdp.dat", rsdp)
    print(f"RSDP at {rsdp_addr:#x}, revision {revision}, XSDT {xsdt_addr:#x}, RSDT {rsdt_addr:#x}")

    if xsdt_addr:
        root_addr, entry_fmt = xsdt_addr, "<Q"
    elif rsdt_addr:
        root_addr, entry_fmt = rsdt_addr, "<I"
    else:
        sys.exit("RSDP has neither XSDT nor RSDT address")

    def read_table(addr):
        header = mem.read(addr, HEADER_LEN)
        sig = header[:4]
        length = struct.unpack_from("<I", header, 4)[0]
        if length < HEADER_LEN or length > 64 * 1024 * 1024:
            raise ReadError(f"table {sig!r} at {addr:#x} has implausible length {length}")
        data = mem.read(addr, length)
        if not checksum_ok(data):
            print(f"warning: {sig.decode('ascii', 'replace')} at {addr:#x} checksum mismatch", file=sys.stderr)
        return sig, data

    try:
        root_sig, root = read_table(root_addr)
    except ReadError as e:
        sys.exit(str(e))
    save(table_name(root_sig, seen), root)
    entry_size = struct.calcsize(entry_fmt)
    entries = [struct.unpack_from(entry_fmt, root, off)[0]
               for off in range(HEADER_LEN, len(root) - entry_size + 1, entry_size)]
    print(f"{root_sig.decode()} at {root_addr:#x} lists {len(entries)} tables")

    failures = 0

    def dump(addr, what):
        nonlocal failures
        try:
            sig, data = read_table(addr)
        except ReadError as e:
            failures += 1
            print(f"  warning: skipping {what} at {addr:#x}: {e}", file=sys.stderr)
            return None, None
        save(table_name(sig, seen), data)
        print(f"  {sig.decode('ascii', 'replace')} at {addr:#x}, {len(data)} bytes")
        return sig, data

    for addr in entries:
        if not addr:
            continue
        sig, data = dump(addr, "table")
        if sig != b"FACP":
            continue
        dsdt_addr = struct.unpack_from("<Q", data, 140)[0] if len(data) >= 148 else 0
        if not dsdt_addr:
            dsdt_addr = struct.unpack_from("<I", data, 40)[0]
        if dsdt_addr:
            dump(dsdt_addr, "DSDT")
        facs_addr = struct.unpack_from("<Q", data, 132)[0] if len(data) >= 140 else 0
        if not facs_addr:
            facs_addr = struct.unpack_from("<I", data, 36)[0]
        if facs_addr:
            try:
                fhead = mem.read(facs_addr, 8)
                if fhead[:4] == b"FACS":
                    flen = struct.unpack_from("<I", fhead, 4)[0]
                    save(table_name(b"FACS", seen), mem.read(facs_addr, flen))
                    print(f"  FACS at {facs_addr:#x}, {flen} bytes")
            except ReadError as e:
                failures += 1
                print(f"  warning: skipping FACS at {facs_addr:#x}: {e}", file=sys.stderr)


    print(f"wrote {len(written)} files to {args.out}/" + (f" ({failures} skipped)" if failures else ""))
    print(f"next: iasl -d {args.out}/dsdt.dat")


if __name__ == "__main__":
    main()
