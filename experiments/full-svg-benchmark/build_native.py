#!/usr/bin/env python3
"""Build the native Rust, Go and Zig schematic arms and record their provenance.

Rust and Zig are compiled at -O3 (`rustc -C opt-level=3`, `zig -O ReleaseFast`);
Go is compiled by its default optimizing toolchain, which has no -O knob. Each
binary is installed next to the netlisp and mylang arms as
`.tmp/full-svg-benchmark-20260921/<arm>`, where measure.py looks for it, and is
then checked against the mylang O3 SVG bytes.

Writes `native-provenance.json` and `native-check.txt`.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
PORTS = OUT / 'ports'
WORK = ROOT / '.tmp/full-svg-benchmark-20260921'
RUSTC = os.environ.get('RUSTC', str(Path.home() / '.cargo/bin/rustc'))
GO = os.environ.get('GO', shutil.which('go') or 'go')
CHECK = PORTS / 'check_native.sh'

SOURCES = {'rust-o3': PORTS / 'rust/main.rs', 'go-fast': PORTS / 'go/main.go',
           'zig-o3': PORTS / 'zig/main.zig'}


def commands():
    yield 'rust-o3', [RUSTC, '-C', 'opt-level=3', '-C', 'codegen-units=1',
                      '-C', 'debug-assertions=off',
                      '-o', str(WORK / 'rust-o3'), str(SOURCES['rust-o3'])], {}
    yield 'go-fast', [GO, 'build', '-o', str(WORK / 'go-fast'),
                      str(SOURCES['go-fast'])], {
        'GOCACHE': str(WORK / 'gocache'), 'GOPATH': str(WORK / 'gopath')}
    yield 'zig-o3', [str(ROOT / 'zigw'), 'build-exe', str(SOURCES['zig-o3']),
                     '-O', 'ReleaseFast', '-fllvm',
                     '--cache-dir', str(WORK / 'zig-cache'),
                     f'-femit-bin={WORK / "zig-o3"}'], {}


def toolchains():
    versions = {}
    for name, command in (('rustc', [RUSTC, '--version']), ('go', [GO, 'version']),
                          ('zig', [str(ROOT / 'zigw'), 'version'])):
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        versions[name] = result.stdout.strip()
    return versions


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    (WORK / 'ports').mkdir(parents=True, exist_ok=True)
    records = []
    for name, command, extra_environment in commands():
        environment = dict(os.environ)
        environment.update(extra_environment)
        print('==', name, ' '.join(command))
        subprocess.run(command, env=environment, check=True, cwd=ROOT)
        records.append({'name': name, 'argv': command,
                        'source': str(SOURCES[name].relative_to(ROOT)),
                        'source_sha256': digest(SOURCES[name]),
                        'binary': str((WORK / name).relative_to(ROOT)),
                        'binary_bytes': (WORK / name).stat().st_size,
                        'binary_sha256': digest(WORK / name)})
    lines = []
    passed = True
    for record in records:
        result = subprocess.run([str(CHECK), str(WORK / record['name'])],
                                capture_output=True, text=True)
        record['check_passed'] = result.returncode == 0
        record['check_output'] = result.stdout.strip().splitlines()
        passed = passed and result.returncode == 0
        lines.extend(f"{record['name']} {line}"
                     for line in result.stdout.strip().splitlines())
        lines.extend(f"{record['name']} {line}"
                     for line in result.stderr.strip().splitlines())
    (OUT / 'native-check.txt').write_text('\n'.join(lines) + '\n')
    evidence = {
        'schema': 'full-svg-native-ports-v1',
        'passed': passed,
        'toolchains': toolchains(),
        'flags': {
            'rust-o3': '-C opt-level=3 -C codegen-units=1 -C debug-assertions=off',
            'go-fast': 'go build (default optimization; no -O level exists)',
            'zig-o3': 'build-exe -O ReleaseFast -fllvm',
        },
        'expectation': ('each binary reproduces the mylang O3 SVG bytes exactly on '
                        'fixture, changed-net and changed-value'),
        'builds': records,
    }
    (OUT / 'native-provenance.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print('\n'.join(lines))
    print('native ports:', 'all three match the mylang SVG bytes' if passed else 'MISMATCH')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
