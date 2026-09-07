#!/usr/bin/env python3
"""Collect and validate user-supplied UX3407NA firmware; never downloads it."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile


class FirmwareError(Exception):
    pass


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def load_manifest():
    script = Path(__file__).resolve()
    for path in (script.parent / "firmware-manifest.json", script.parent.parent / "firmware-manifest.json"):
        if path.is_file():
            return json.loads(path.read_text())["files"]
    raise FirmwareError("Cannot locate firmware-manifest.json beside this tool or its parent directory.")


def validate(source, manifest, strict=False):
    errors, warnings, hashes = [], [], {}
    for item in manifest:
        path = source / item["name"]
        if not path.is_file():
            errors.append(f"Missing: {item['name']}")
        elif path.stat().st_size == 0:
            errors.append(f"Empty: {item['name']}")
        else:
            value = digest(path)
            hashes[item["name"]] = value
            if value != item["referenceSha256"]:
                message = f"Different from tested reference: {item['name']} ({value})"
                (errors if strict else warnings).append(message)
    if errors:
        raise FirmwareError("\n".join(errors))
    return hashes, warnings


def discover(sources, manifest):
    wanted = {item["name"].lower(): item for item in manifest}
    candidates = {name: [] for name in wanted}
    for source in sources:
        if not source.is_dir():
            raise FirmwareError(f"Not a directory: {source}")
        def report(error):
            print(f"Search skipped an unreadable path: {error}", file=sys.stderr)
        for parent, _, names in os.walk(source, onerror=report):
            for name in names:
                if name.lower() in wanted:
                    candidate = Path(parent) / name
                    if candidate.is_file() and candidate.stat().st_size:
                        candidates[name.lower()].append(candidate)
    # Some reference NVM filenames are byte-identical aliases. Recreate an
    # absent alias only from bytes whose hash matches that exact reference.
    known_bytes = {}
    for paths in candidates.values():
        for path in sorted(set(paths)):
            known_bytes.setdefault(digest(path), path)
    selected, errors = {}, []
    for name, item in wanted.items():
        paths = sorted(set(candidates[name]))
        by_hash = {}
        for path in paths:
            by_hash.setdefault(digest(path), []).append(path)
        if item["referenceSha256"] in by_hash:
            selected[item["name"]] = by_hash[item["referenceSha256"]][0]
        elif len(by_hash) == 1:
            selected[item["name"]] = next(iter(by_hash.values()))[0]
        elif not paths and item["referenceSha256"] in known_bytes:
            selected[item["name"]] = known_bytes[item["referenceSha256"]]
        elif not paths:
            errors.append(f"Not found: {item['name']}")
        else:
            errors.append(f"Conflicting versions of {item['name']}; search a specific driver directory or place the chosen file in a staging directory:\n  " + "\n  ".join(map(str, paths)))
    if errors:
        raise FirmwareError("\n".join(errors))
    return selected


def write_selection(selected, output, manifest, strict=False):
    # Validate a complete staged set before touching the destination.
    with tempfile.TemporaryDirectory(prefix="a14-firmware-") as temporary:
        staged = Path(temporary)
        for name, source in selected.items():
            shutil.copyfile(source, staged / name)
        hashes, warnings = validate(staged, manifest, strict)
        if output.exists() and not output.is_dir():
            raise FirmwareError(f"Destination is not a directory: {output}")
        for name, value in hashes.items():
            existing = output / name
            if existing.exists() and (not existing.is_file() or digest(existing) != value):
                raise FirmwareError(f"Refusing to replace different existing firmware: {existing}. Use a new destination.")
        sums = "".join(f"{value}  {name}\n" for name, value in sorted(hashes.items()))
        sumfile = output / "SHA256SUMS"
        if sumfile.exists() and sumfile.read_text() != sums:
            raise FirmwareError(f"Refusing to replace different {sumfile}. Use a new destination.")
        output.mkdir(parents=True, exist_ok=True)
        for name in hashes:
            target = output / name
            if not target.exists():
                with target.open("xb") as stream, (staged / name).open("rb") as original:
                    shutil.copyfileobj(original, stream)
        if not sumfile.exists():
            sumfile.write_text(sums)
        return hashes, warnings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("validate", help="Check an already extracted directory")
    check.add_argument("source", type=Path)
    check.add_argument("--strict", action="store_true", help="Require the exact tested reference hashes")
    collect = commands.add_parser("collect", help="Search mounted Windows or unpacked driver directories")
    collect.add_argument("sources", nargs="+", type=Path)
    collect.add_argument("--output", required=True, type=Path)
    collect.add_argument("--strict", action="store_true")
    copy = commands.add_parser("copy", help="Copy a validated set to the installed system's configuration")
    copy.add_argument("source", type=Path)
    copy.add_argument("output", type=Path)
    copy.add_argument("--strict", action="store_true")
    commands.add_parser("list", help="List required filenames and Linux destinations")
    args = parser.parse_args()
    try:
        manifest = load_manifest()
        if args.command == "list":
            for item in manifest:
                print(f"{item['name']} -> {item['destination']}")
            return 0
        if args.command == "validate":
            hashes, warnings = validate(args.source, manifest, args.strict)
        elif args.command == "collect":
            selected = discover(args.sources, manifest)
            hashes, warnings = write_selection(selected, args.output, manifest, args.strict)
        else:
            validate(args.source, manifest, args.strict)
            selected = {item["name"]: args.source / item["name"] for item in manifest}
            hashes, warnings = write_selection(selected, args.output, manifest, args.strict)
        for warning in warnings:
            print(f"WARNING: {warning}", file=sys.stderr)
        print(f"Validated {len(hashes)} nonempty firmware files.")
        if warnings:
            print("Names and completeness checked; differing versions still need hardware testing.")
        else:
            print("All hashes match the source machine's tested firmware set.")
        return 0
    except (FirmwareError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
