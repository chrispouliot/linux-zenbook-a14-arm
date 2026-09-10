#!/usr/bin/env python3
"""Reconstruct the default local A14 patch recipe and check its source hashes.

Requires Python 3.12+, git, patch, bash, and a local Git checkout containing the
pinned kernel commit. Never changes the input checkout or builds/installs a kernel.
Executes this repository's postPatch shell/Python code in a new output directory;
use only with a trusted repository. Does not evaluate Nix or inherited Nixpkgs
patches. The optional SCMI patch is outside this default-source comparison.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shlex
import subprocess
import tarfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--kernel-source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New, nonexistent output directory')
    args = parser.parse_args()
    repo = args.repo.expanduser().resolve()
    source = args.kernel_source.expanduser().resolve()
    out = args.output.expanduser().absolute()
    if out.exists() or out.is_symlink():
        parser.error('Output already exists; choose a new path')
    manifest = json.loads((repo / 'docs/display/series.json').read_text())
    expected = json.loads((repo / 'docs/display/source-sha256.json').read_text())
    rev = manifest['source_revision']
    git = ['git', '-C', str(source)]
    subprocess.run(git + ['cat-file', '-e', rev + '^{commit}'], check=True)
    kernel_nix = (repo / 'kernel.nix').read_text()
    required = 'postPatch = (old.postPatch or "") + (import ./kernel/a14-post-patch.nix);'
    if kernel_nix.count(required) != 1:
        parser.error('Unexpected kernel recipe integration')
    initial = re.findall(r'\./patches/([^\s;]+\.patch)', kernel_nix)
    if initial != ['a14-dp-boot-order-debug.patch', 'a14-glymur-ucsi-dp-mux-race.patch',
                   'a14-dp-hpd-replay.patch', 'a14-scmi-mailbox-set-test.patch']:
        parser.error('Initial patch list changed; update this verifier deliberately')
    expression = (repo / 'kernel/a14-post-patch.nix').read_text()
    if expression.count("''\n") != 2 or not expression.endswith("\n''\n"):
        parser.error('Unexpected postPatch expression delimiters')
    body = expression.split("''\n", 1)[1].rsplit("\n''\n", 1)[0]
    marker = '      # Display series: all four patches are required, in this order.\n'
    if body.count(marker) != 1:
        parser.error('Display series boundary missing or duplicated')
    platform = json.loads((repo / 'docs/display/platform-series.json').read_text())
    if platform['source_revision'] != rev:
        parser.error('Platform and display series target different kernel revisions')
    platform_order = re.findall(r'\$\{\.\./(patches/[^}]+\.patch)\}', body.split(marker)[0])
    if platform_order != [entry['path'] for entry in platform['post_patch_order']]:
        parser.error('Platform recipe order differs from its recorded series')
    for entry in platform['post_patch_order']:
        data = (repo / entry['path']).read_bytes()
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            parser.error('Platform patch differs from recorded series: ' + entry['path'])
    order = re.findall(r'\$\{\.\./(patches/[^}]+\.patch)\}', body.split(marker)[1])
    if order != [entry['path'] for entry in manifest['patches']]:
        parser.error('Recipe order does not match the recorded series')
    for entry in manifest['patches']:
        data = (repo / entry['path']).read_bytes()
        if hashlib.sha256(data).hexdigest() != entry['sha256']:
            parser.error('Patch differs from recorded series: ' + entry['path'])
    # Only the local patch/DT paths used by this expression need substitution.
    body = re.sub(r'\$\{\.\./patches/([^}]+)\}',
                  lambda m: shlex.quote(str(repo / 'patches' / m[1])), body)
    if '${' in body:
        parser.error('Unexpected unresolved Nix interpolation')
    paths = []
    for name in sorted(expected):
        if Path(name).is_absolute() or '..' in Path(name).parts:
            parser.error('Invalid source manifest path')
        if subprocess.run(git + ['cat-file', '-e', rev + ':' + name],
                          capture_output=True).returncode == 0:
            paths.append(name)
    if not paths:
        parser.error('No manifest source paths found at the pinned commit')
    archive = subprocess.check_output(git + ['archive', rev, '--', *paths])
    out.mkdir(parents=True, exist_ok=False)
    with tarfile.open(fileobj=io.BytesIO(archive)) as stream:
        stream.extractall(out, filter='data')
    commands = ['set -eu', 'set -o pipefail']
    for name in initial[:-1]:
        commands.append('patch --batch --forward --fuzz=0 -p1 < ' +
                        shlex.quote(str(repo / 'patches' / name)))
    script = '\n'.join(commands) + '\n' + body + '\n'
    (out / 'RECONSTRUCTION.sh').write_text(script)
    log = out / 'RECONSTRUCTION.log'
    with log.open('w') as stream:
        result = subprocess.run(['bash', 'RECONSTRUCTION.sh'], cwd=out,
                                stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode or re.search(r'with fuzz|offset [0-9-]+ lines?|FAILED', log.read_text()):
        raise SystemExit('Patch recipe failed or needed offsets; inspect ' + str(log))
    actual = {name: hashlib.sha256((out / name).read_bytes()).hexdigest()
              if (out / name).is_file() else 'missing' for name in expected}
    (out / 'actual-source-sha256.json').write_text(json.dumps(actual, indent=2) + '\n')
    mismatches = [name for name in expected if actual[name] != expected[name]]
    # Detect source files created outside the expected manifest too.
    metadata = {'RECONSTRUCTION.sh', 'RECONSTRUCTION.log', 'actual-source-sha256.json'}
    extras = [str(p.relative_to(out)) for p in out.rglob('*') if p.is_file()
              and str(p.relative_to(out)) not in expected and p.name not in metadata]
    if mismatches or extras:
        raise SystemExit('Source comparison failed: ' + ', '.join(mismatches + extras))
    print(f'PASS: all {len(expected)} reconstructed source files match the tested baseline.')
    print('PASS: platform and display patches applied in order without fuzz or offsets.')
    print('No NixOS evaluation, kernel compilation, or hardware test performed.')
    print('Reconstruction and hashes:', out)


if __name__ == '__main__':
    main()
