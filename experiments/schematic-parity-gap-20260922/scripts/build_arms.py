#!/usr/bin/env python3
"""Build schematic guest arms with a frozen compiler.

usage: build_arms.py --compiler /path/mylang --work /path/work --arms spec.json
spec.json: {"name": {"backend": "llvm"|"qbe", "opt": "3", "lto": true, "bounded": false,
                     "strip": "overflow,cast" (optional, applied to the emitted manifest),
                     "guest": "gc"|"arena" (optional; arena wraps main in `with arena():`),
                     "manifest_from": "other-arm" (optional: reuse that arm's emitted manifest before stripping)}}
Writes <work>/<name> (binary), <name>.declared, <name>-emitted.json, <name>.qbe-manifest.json (receipt), builds.json.
"""
import argparse, hashlib, json, os, shutil, subprocess, sys, time
from pathlib import Path

ROOT = Path(os.environ.get('AUDIT_ROOT', '/home/epentland/ai/canopy/mylang'))
# AUDIT_TREE: the source tree whose src/schematic/guest and provider are built (a lane's worktree)
TREE = Path(os.environ.get('AUDIT_TREE', str(ROOT / '.tmp/perf-audit-20260922/tree')))
STRIP = Path(__file__).resolve().parent / 'strip_il.py'
ZIG = os.environ.get('MYLANG_ZIG', '/home/epentland/.local/bin/zig')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def environment():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('MYLANG_') or key == 'LD_PRELOAD':
            del env[key]
    env['MYLANG_MEMORY_LIMIT'] = '268435456'
    return env


def prepare_guest(work, policy):
    guest = work / f'guest-{policy}'
    if guest.exists():
        shutil.rmtree(guest)
    guest.mkdir(parents=True)
    for source in (TREE / 'src/schematic/guest').glob('*.my'):
        shutil.copy2(source, guest / source.name)
    if policy == 'arena':
        entry = guest / 'main.my'
        text = entry.read_text()
        head, body = text.split('def main(host: Host) -> Result[None, int]:\n', 1)
        entry.write_text(head + 'def main(host: Host) -> Result[None, int]:\n    with arena():\n' + ''.join('    ' + line if line.strip() else line for line in body.splitlines(True)))
    return guest


def run(command, **kw):
    result = subprocess.run([str(c) for c in command], cwd=TREE, env=environment(), capture_output=True, timeout=1800, **kw)
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode()[-4000:])
        raise SystemExit(f'failed: {" ".join(str(c) for c in command)}')
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', required=True); ap.add_argument('--work', required=True); ap.add_argument('--arms', required=True)
    ap.add_argument('--only', default=None)
    a = ap.parse_args()
    compiler = Path(a.compiler).resolve(); work = Path(a.work).resolve(); work.mkdir(parents=True, exist_ok=True)
    spec = json.loads(Path(a.arms).read_text())
    records = json.loads((work / 'builds.json').read_text()) if (work / 'builds.json').exists() else {}
    guests = {}
    for name, arm in spec.items():
        if a.only and name not in a.only.split(','):
            continue
        policy = arm.get('guest', 'gc')
        if policy not in guests:
            guests[policy] = prepare_guest(work, policy)
        entry = guests[policy] / 'main.my'
        manifest = work / f'{name}-emitted.json'
        if arm.get('manifest_from'):
            source_manifest = work / f"{arm['manifest_from']}-emitted.json"
        else:
            emit = [compiler, 'emit-project-qbe', entry, '--drop-debug', '--no-cache']
            if not arm.get('bounded'):
                emit += ['--drop-step-checks', '--drop-frame-checks']
            result = run(emit)
            source_manifest = work / f'{name}-raw.json'
            source_manifest.write_bytes(result.stdout)
        if arm.get('strip'):
            result = subprocess.run([sys.executable, str(STRIP), str(source_manifest), str(manifest), arm['strip']], capture_output=True, text=True)
            print(result.stdout.strip(), result.stderr.strip())
            assert result.returncode == 0
        else:
            shutil.copy2(source_manifest, manifest)
        names = ','.join(d['name'] for d in json.loads(manifest.read_text())['host']['declarations'])
        (work / f'{name}.declared').write_text(names)
        command = [compiler, 'build', entry, '--project', '--provider', TREE / 'src/schematic/native_schematic.c',
                   '--zig', ZIG, '--keep-symbols', f'--manifest-file={manifest}', '--cache-dir', work / f'cache-{name}', '--report', '-o', work / name]
        if arm.get('backend', 'llvm') == 'llvm':
            command += ['--backend', 'llvm', '--llvm-opt', arm.get('opt', '3')]
            if arm.get('lto', True):
                command += ['--lto']
        else:
            command += ['--backend', 'qbe']
        start = time.perf_counter()
        result = run(command)
        (work / f'{name}-build.stderr').write_bytes(result.stderr)
        (work / f'{name}-build.stdout').write_bytes(result.stdout)
        records[name] = {'spec': arm, 'build_argv': [str(c) for c in command], 'elapsed_seconds': time.perf_counter() - start,
                         'binary_sha256': sha(work / name), 'manifest_sha256': sha(manifest), 'declarations': names,
                         'compiler_sha256': sha(compiler)}
        print('built', name, f'{records[name]["elapsed_seconds"]:.1f}s', flush=True)
        (work / 'builds.json').write_text(json.dumps(records, indent=1) + '\n')


if __name__ == '__main__':
    main()
