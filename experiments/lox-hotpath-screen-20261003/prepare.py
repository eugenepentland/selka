#!/usr/bin/env python3
"""Build a qualified hot-path candidate against immutable selected AST guests."""
import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hashes(root):
    return {str(p.relative_to(root)): sha(p)
            for p in sorted(root.rglob('*')) if p.is_file()}


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--candidate-map', type=Path, required=True)
    parser.add_argument('--qualified-llvm', type=Path, required=True)
    parser.add_argument('--qualified-qbe', type=Path, required=True)
    parser.add_argument('--qualification', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--control-work', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    work, candidate, control = args.work.resolve(), args.candidate.resolve(), args.control_work.resolve()
    compiler = args.compiler.resolve()
    expected = json.loads(args.candidate_map.read_text())
    selected = json.loads((repo / 'experiments/lox-ast-constant-20261003/sources.json').read_text())['ast']
    assert len(expected) == 37 and set(expected) == set(selected)
    assert hashes(candidate) == expected
    assert hashes(control / 'ast') == selected
    controls = json.loads((control / 'binaries.json').read_text())
    qbe = compiler.parent / 'qbe'
    assert sha(qbe) == controls['qbe_sha256']
    qualified = {'llvm': args.qualified_llvm.resolve(), 'qbe': args.qualified_qbe.resolve()}
    helper_names = ('experiments/lox-hotpath-screen-20261003/prepare.py',
                    'experiments/lox-hotpath-screen-20261003/analyze.py',
                    'experiments/lox-parity-20261003/build.py',
                    'experiments/lox-parity-20261003/run.py',
                    'experiments/lox-performance-audit-20261002/audit.py',
                    'experiments/lox-perf-improvements-20261002/analyze.py',
                    'scripts/build-slot.sh')
    originals = {str(p): sha(p) for p in (compiler, qbe, args.candidate_map.resolve(),
                                         args.qualification.resolve(), *qualified.values())}
    for name in helper_names:
        originals[str(repo / name)] = sha(repo / name)
    for arm in ('ast-llvm', 'ast-qbe', 'rust', 'go'):
        path = Path(controls['binaries'][arm])
        assert sha(path) == controls['binary_sha256'][arm]
        originals[str(path)] = sha(path)
    work.mkdir(parents=True, exist_ok=False)
    (work / 'bin').mkdir()
    (work / 'tmp').mkdir()
    shutil.copytree(control / 'ast', work / 'baseline')
    shutil.copytree(candidate, work / 'candidate')
    shutil.copytree(control / 'reference', work / 'reference')
    shutil.copy2(args.qualification, work / 'author-qualification.json')
    shutil.copy2(args.candidate_map, work / 'candidate-source37.json')
    for arm, old_arm in (('baseline-llvm', 'ast-llvm'), ('baseline-qbe', 'ast-qbe'),
                         ('rust', 'rust'), ('go', 'go')):
        old = Path(controls['binaries'][old_arm])
        shutil.copy2(old, work / 'bin' / arm)
        for suffix in ('.qbe-manifest.json', '.qbe-receipt'):
            sidecar = Path(str(old) + suffix)
            if sidecar.is_file():
                shutil.copy2(sidecar, Path(str(work / 'bin' / arm) + suffix))
    command = [sys.executable, str(repo / 'experiments/lox-parity-20261003/build.py'),
               '--work', str(work), '--source', str(work / 'candidate'),
               '--compiler', str(compiler), '--name', 'candidate', '--runtime', 'rc']
    env = {k: v for k, v in os.environ.items()
           if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
    with (work / 'prepare-build.log').open('w') as log:
        result = subprocess.run(command, cwd=repo, env=env, stdout=log, stderr=subprocess.STDOUT)
    save(work / 'prepare-command.json', {'argv': command, 'cwd': str(repo), 'status': result.returncode})
    if result.returncode:
        raise SystemExit(result.returncode)
    for backend, author in qualified.items():
        assert sha(work / 'bin' / ('candidate-' + backend)) == originals[str(author)]
    spec = importlib.util.spec_from_file_location('audit', repo / helper_names[4])
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    for tier in ('timed', 'tree', 'smoke'):
        assert len(list(audit.cases(work, tier, ['vm', 'tree'], set()))) == 26
    source_maps = {'baseline': selected, 'candidate': expected}
    manifest = {'purpose': 'qualified candidate versus selected AST, central matched hot-path screen',
                'reference_commit': controls['reference_commit'],
                'compiler': str(compiler), 'compiler_sha256': originals[str(compiler)],
                'control_compiler_sha256': controls['compiler_sha256'],
                'qbe_sha256': originals[str(qbe)],
                'qualification': str(work / 'author-qualification.json'),
                'qualification_sha256': originals[str(args.qualification.resolve())],
                'binaries': {arm: str(work / 'bin' / arm) for arm in
                             ('baseline-llvm', 'baseline-qbe', 'candidate-llvm', 'candidate-qbe', 'rust', 'go')},
                'candidate_sources': {arm: {'path': str(work / arm),
                                            'hashes': {name: value for name, value in values.items()
                                                       if '/' not in name and name.endswith('.my')}}
                                      for arm, values in source_maps.items()},
                'source37': source_maps}
    manifest['binary_sha256'] = {arm: sha(Path(path)) for arm, path in manifest['binaries'].items()}
    save(work / 'binaries.json', manifest)
    guards = dict(originals)
    for root in ('baseline', 'candidate', 'reference', 'inputs', 'bin'):
        for p in sorted((work / root).rglob('*')):
            if p.is_file():
                guards[str(p)] = sha(p)
    for name in ('candidate-source37.json', 'author-qualification.json', 'binaries.json',
                 'candidate-build.json', 'prepare-command.json', 'prepare-build.log'):
        guards[str(work / name)] = sha(work / name)
    for backend in qualified:
        meta = json.loads((work / 'bin' / ('candidate-' + backend + '.qbe-manifest.json')).read_text())
        runtime = Path(meta['runtime_object'])
        guards[str(runtime)] = sha(runtime)
    for path, digest in guards.items():
        assert sha(Path(path)) == digest, path
    for arm, values in source_maps.items():
        assert hashes(work / arm) == values
    save(work / 'guards.json', guards)
    save(work / 'prepared.json', {'prepared_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                 'guards': len(guards), 'candidate_rebuilt_byte_exact': True,
                                 'inherited_control_sidecars_keep_original_paths': True,
                                 'qualification_review_is_separate_from_preparer': True,
                                 'reference_guests_copied_not_rebuilt': True,
                                 'manifest_sha256': sha(work / 'binaries.json'),
                                 'guards_sha256': sha(work / 'guards.json')})
    print(json.dumps({'work': str(work), 'guards': len(guards), 'candidate_rebuilt_byte_exact': True}))


if __name__ == '__main__':
    main()
