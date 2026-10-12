#!/usr/bin/env python3
"""Qualify reserved component sources, preserving the installed wire protocols.

Run inside one outer build admission. --scope-free-check removes only the known
filesystem acquisition from a disposable source copy to expose subsequent
ownership refusals; it is source-check evidence, never component qualification.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
BASE = 'fbfcaa7a923186a8e773c3760f81c10aa345a432'
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'experiments/zero-rc-20261011'))
import audit


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--compiler-revision', required=True)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scope-free-check', action='store_true')
    parser.add_argument('--legacy-seed', action='store_true')
    parser.add_argument('--default-zero', action='store_true')
    parser.add_argument('--counted', action='store_true')
    parser.add_argument('--components', nargs='+', choices=('test_index', 'cache_plan'), default=['test_index', 'cache_plan'])
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.work = args.work.resolve()
    args.output = args.output.resolve()
    if args.output.exists():
        raise ValueError('Choose an unused evidence output path')
    args.work.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.counted and (args.legacy_seed or args.scope_free_check):
        parser.error('--counted requires a zero-RC component build')
    rows = []
    for state in (('before', 'after') if args.scope_free_check else ('after',)):
        for component in args.components:
            source = ROOT / 'selfhost/components' / component
            sources = {}
            project = args.work / state / component
            project.mkdir(parents=True, exist_ok=True)
            for path in source.glob('*.my'):
                text = subprocess.check_output(['git', 'show', f'{BASE}:{path.relative_to(ROOT)}'], cwd=ROOT).decode() if state == 'before' else path.read_text()
                sources[path.name] = hashlib.sha256(text.encode()).hexdigest()
                if args.scope_free_check and path.name == 'main.my':
                    text = text.replace('func exchange(fs: Filesystem, path: str)', 'func exchange(data: bytes)')
                    lines = text.splitlines(keepends=True)
                    text = ''.join(line for line in lines if not any(part in line for part in ('    mut data = b""', '    with try fs.open', '        data = file.read')))
                    text = text.replace('exchange(fs, args[1])', 'exchange(b"")')
                    text = text.replace('args: str[], fs: Filesystem, out: Stream', 'args: str[], out: Stream')
                (project / path.name).write_text(text)
            command = [str(args.compiler), 'check' if args.scope_free_check else 'build', str(project / 'main.my')]
            if not args.legacy_seed and not args.default_zero:
                command += ['--experimental-zero-rc']
            binary = project / component
            if args.scope_free_check:
                command += ['--no-cache']
            else:
                command += ['--release', '--zig', str(args.zig), '-o', str(binary), '--cache-dir', str(project / 'cache')]
                if not args.legacy_seed: command += ['--emit-llvm', str(project / (component + '.ll'))]
                if args.counted: command += ['--counters']
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=300)
            row = dict(state=state, component=component, sources=sources, command=command, status=result.returncode, stdout=result.stdout, stderr=result.stderr, passed=result.returncode == 0)
            if result.returncode == 0 and not args.scope_free_check:
                row['binary_sha256'] = sha(binary)
                selected = binary
                counts = args.output.parent / (args.output.stem + '-counts') / component
                if args.counted:
                    counts.mkdir(parents=True)
                    selected = project / 'counted-launcher'
                    selected.write_text('#!/usr/bin/env python3\n' +
                        'import hashlib, json, os, subprocess, sys\nfrom pathlib import Path\n' +
                        f'root=Path({str(counts)!r})\nbinary={str(binary)!r}\n' +
                        'path=root/(str(os.getpid())+".json")\n' +
                        'env=dict(os.environ,MYLANG_COUNTERS=str(path),MYL_CORE_LEAKCHECK="1")\n' +
                        'request=Path(sys.argv[2]) if len(sys.argv)==3 else None\n' +
                        'info={"arguments":sys.argv[1:],"request_sha256":hashlib.sha256(request.read_bytes()).hexdigest() if request and request.is_file() else None}\n' +
                        'run=subprocess.run([binary,*sys.argv[1:]],env=env,stderr=subprocess.PIPE)\ninfo["status"]=run.returncode\n' +
                        'info["stderr"]=run.stderr.decode(errors="replace")\nsys.stderr.buffer.write(run.stderr)\n' +
                        'path.with_suffix(".status.json").write_text(json.dumps(info)+"\\n")\n' +
                        'sys.exit(run.returncode if run.returncode>=0 else 128-run.returncode)\n')
                    selected.chmod(0o755)
                oracle_source = ROOT / 'selfhost/tests' / f'run_{component}_component.py'
                oracle = ['python3', '-B', str(oracle_source), '--component', str(selected)]
                run = subprocess.run(oracle, cwd=ROOT, env=dict(os.environ, MYL_CORE_LEAKCHECK='1'), capture_output=True, text=True, timeout=300)
                row.update(oracle=oracle, oracle_status=run.returncode, oracle_stdout=run.stdout, oracle_stderr=run.stderr)
                row['oracle_source_sha256'] = sha(oracle_source)
                row['passed'] &= run.returncode == 0
                if args.counted:
                    import gzip
                    audits = []
                    for status_file in sorted(counts.glob('*.status.json')):
                        status = json.loads(status_file.read_text())
                        counter_file = status_file.with_name(status_file.name.removesuffix('.status.json')+'.json')
                        observed = audit.audit(counter_file) if counter_file.exists() else None
                        audits.append(dict(status=status, audit=observed))
                        if observed:
                            archive = counter_file.with_suffix('.json.gz')
                            with gzip.open(archive, 'wb') as compressed:
                                compressed.write(counter_file.read_bytes())
                            observed['counter_file'] = str(archive)
                            observed['counter_encoding'] = 'gzip; counter_sha256 hashes uncompressed JSON'
                            counter_file.unlink()
                    row['counted_runs'] = audits
                    # Controlled guest error returns also clean up. Hard runtime
                    # termination is retained separately and cannot imply cleanup.
                    row['all_observed_rc_free'] = bool(audits) and all(item['audit'] and item['audit']['observed_rc_free'] for item in audits)
                    row['returned_runs_leak_free'] = all(item['audit'] and item['audit']['managed_leak_free'] and 'myl-core leakcheck:' not in item['status']['stderr'] for item in audits if item['status']['status'] in (0, 2))
                    row['passed'] &= row['all_observed_rc_free'] and row['returned_runs_leak_free']
                if not args.legacy_seed:
                    llvm = (project / (component + '.ll')).read_text()
                    row['llvm_rc_clean'] = not any(token in llvm for token in ('@myl_core_retain', '@myl_core_release', '@myl_core_share(', 'load atomic i32'))
                    row['passed'] &= row['llvm_rc_clean']
                    symbols = subprocess.check_output(['nm', str(binary)], text=True)
                    row['symbols_rc_clean'] = not any(token in symbols for token in ('myl_core_retain', 'myl_core_release', 'myl_core_share'))
                    row['passed'] &= row['symbols_rc_clean']
            rows.append(row)
            args.output.write_text(json.dumps(dict(compiler=str(args.compiler), compiler_sha256=sha(args.compiler), compiler_revision=args.compiler_revision, harness_sha256=sha(Path(__file__)), source_base=BASE, transformed_source_check=args.scope_free_check, seed_compatibility_only=args.legacy_seed, counted=args.counted, rows=rows, all_passed=all(row['passed'] for row in rows)), indent=2)+'\n')
            print(json.dumps(row), flush=True)
    raise SystemExit(0 if all(row['passed'] for row in rows) else 1)


if __name__ == '__main__':
    main()
