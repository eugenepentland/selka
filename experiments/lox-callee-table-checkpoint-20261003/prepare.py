#!/usr/bin/env python3
"""Build the checked 80/84-test Lox pair and pinned Rust/Go references."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile


REFERENCE = '4e48a09220c2e018eba8c4b1eb3fe1137a3dae73'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(root):
    return {str(p.relative_to(root)): sha(p)
            for p in sorted(root.rglob('*')) if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--cargo', type=Path, default=os.environ.get('LOX_BENCH_CARGO')
                        or shutil.which('cargo') or Path.home() / '.cargo/bin/cargo')
    parser.add_argument('--go', type=Path, default=os.environ.get('LOX_BENCH_GO')
                        or shutil.which('go') or Path.home() / '.local/bin/go')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    preparer = Path(__file__).resolve()
    preparer_hash = sha(preparer)
    work, compiler = args.work.resolve(), args.compiler.resolve()
    compiler_hash = sha(compiler)
    qbe = compiler.parent / 'qbe'
    qbe_hash = sha(qbe) if qbe.is_file() else None
    cargo, go = args.cargo.absolute(), args.go.absolute()
    rustc = Path(os.environ.get('RUSTC', str(cargo.parent / 'rustc'))).absolute()
    for tool in (cargo, go, rustc):
        if not tool.is_file():
            raise ValueError(f'missing reference toolchain: {tool}')
    work.mkdir(parents=True, exist_ok=False)
    for name in ('bin', 'tmp', 'reference'):
        (work / name).mkdir()
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    env.update(TMPDIR=str(work / 'tmp'), GOTMPDIR=str(work / 'tmp'))
    env['PATH'] = str(cargo.parent) + os.pathsep + env.get('PATH', '')
    env['RUSTC'] = str(rustc)
    commands = []

    def run(argv, cwd=repo, extra_env=None):
        index = len(commands)
        log = work / f'prepare-{index:02d}.log'
        command_env = dict(env)
        command_env.update(extra_env or {})
        record = {'argv': [str(a) for a in argv], 'cwd': str(cwd),
                  'environment': {k: command_env[k] for k in
                                  ('TMPDIR', 'GOTMPDIR', 'PATH', 'RUSTC', *(extra_env or {}))},
                  'log': str(log),
                  'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
        with log.open('w') as out:
            result = subprocess.run(record['argv'], cwd=cwd, env=command_env,
                                    stdout=out, stderr=subprocess.STDOUT)
        record.update(status=result.returncode, log_sha256=sha(log),
                      finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
        commands.append(record)
        (work / 'prepare-commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        if result.returncode:
            raise SystemExit(result.returncode)

    migration = repo / 'docs/audits/d9-stage3d-migrations'
    run(['bash', migration / 'apply-lox.sh', work / 'migration', '--optimized'])
    source = work / 'migration/lox/benchmarks/lox/ports/mylang'
    shutil.copytree(source, work / 'combined')
    shutil.copytree(source, work / 'baseline')
    patch = migration / 'lox-runtime-perf-20261003-callee-table.patch'
    run(['patch', '--batch', '--fuzz=0', '-R', '-p1', '-i', patch], cwd=work / 'baseline')
    expected = json.loads((Path(__file__).parent / 'sources.json').read_text())
    sources = {}
    for name in ('baseline', 'combined'):
        root = work / name
        all_files = hashes(root)
        if all_files != expected[name]:
            raise ValueError(f'{name} differs from the measured source')
        sources[name] = {'path': str(root), 'all_files': all_files,
                         'hashes': {k: v for k, v in all_files.items() if k.endswith('.my')}}
        run([sys.executable, repo / 'experiments/lox-parity-20261003/build.py',
             '--work', work, '--source', root, '--compiler', compiler, '--name', name])

    archive = work / 'reference.tar'
    run(['git', 'archive', '--format=tar', '--output=' + str(archive), REFERENCE,
         'benchmarks/lox/bench', 'benchmarks/lox/ports/rust', 'benchmarks/lox/ports/go'])
    with tarfile.open(archive) as data:
        data.extractall(work / 'reference', filter='data')
    reference_hashes = hashes(work / 'reference')
    ref = work / 'reference/benchmarks/lox/ports'
    slot = repo / 'scripts/build-slot.sh'
    run([slot, 'build', cargo, 'build', '--release', '--locked'], cwd=ref / 'rust',
        extra_env={'CARGO_TARGET_DIR': str(work / 'rust-target')})
    shutil.copy2(work / 'rust-target/release/lox', work / 'bin/rust')
    run([slot, 'build', go, 'build', '-buildvcs=false', '-o', work / 'bin/go', './cmd/lox'], cwd=ref / 'go',
        extra_env={'GOCACHE': str(work / 'go-build'), 'GOMODCACHE': str(work / 'go-mod'),
                   'GOTOOLCHAIN': 'local'})
    binaries = {name: str(work / 'bin' / name) for name in
                ('baseline-llvm', 'baseline-qbe', 'combined-llvm', 'combined-qbe', 'rust', 'go')}
    for name, src in sources.items():
        assert hashes(Path(src['path'])) == expected[name]
    assert hashes(work / 'reference') == reference_hashes
    assert sha(compiler) == compiler_hash
    assert (sha(qbe) if qbe.is_file() else None) == qbe_hash
    toolchains = {}
    for tool, path, argv in [('cargo', cargo, ['--version']),
                             ('rustc', rustc, ['--version']), ('go', go, ['version'])]:
        version = subprocess.check_output([str(path), *argv], env=env, text=True).strip()
        toolchains[tool] = {'path': str(path), 'sha256': sha(path), 'version': version}
    sysroot = Path(subprocess.check_output([str(rustc), '--print', 'sysroot'],
                                          env=env, text=True).strip())
    for tool in ('cargo', 'rustc'):
        executable = sysroot / 'bin' / tool
        if executable.is_file():
            toolchains[tool]['sysroot_executable'] = str(executable)
            toolchains[tool]['sysroot_executable_sha256'] = sha(executable)
    assert sha(preparer) == preparer_hash
    manifest = {'compiler': str(compiler), 'compiler_sha256': compiler_hash,
                'adjacent_qbe_sha256': qbe_hash, 'reference_toolchains': toolchains,
                'reference_commit': REFERENCE, 'candidate_sources': sources,
                'reference_source_hashes': reference_hashes,
                'binaries': binaries,
                'binary_sha256': {name: sha(Path(p)) for name, p in binaries.items()},
                'prepare_commands_sha256': sha(work / 'prepare-commands.json'),
                'preparer': str(preparer), 'preparer_sha256': preparer_hash}
    (work / 'binaries.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'manifest': str(work / 'binaries.json'),
                      'sha256': sha(work / 'binaries.json')}), flush=True)


if __name__ == '__main__':
    main()
