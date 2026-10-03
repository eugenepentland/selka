#!/usr/bin/env python3
"""Dump unchanged LLVM guests and inventory forced inlining restrictions."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def inspect(work, compiler, source, command, reference):
    modules = sorted((work / 'dump').glob('*.ll'))
    assert modules, 'LLVM diagnostic dump is empty'
    counts = Counter({name: 0 for name in ['exported_definitions', 'nonexported_definitions',
                                         'function_noinline', 'callsite_noinline',
                                         'rc_glue_callsite_noinline']})
    calls = Counter()
    examples = {}
    inputs = {}
    maximum = {'position': 0, 'module': ''}
    for path in modules:
        text = path.read_text()
        ssa = path.with_suffix('.ssa')
        il = ssa.read_text()
        header = next(line for line in il.splitlines()
                      if line.startswith(('export function ', 'function ')))
        counts['exported_definitions' if header.startswith('export ') else
               'nonexported_definitions'] += 1
        counts['function_noinline'] += sum('noinline' in line
                                          for line in text.splitlines()
                                          if line.startswith('attributes #'))
        for line in text.splitlines():
            if re.search(r'\bcall\b', line) and 'noinline' in line:
                counts['callsite_noinline'] += 1
            match = re.search(r'\bcall\b.*@myl_t_[0-9a-f]{64}_rcg_([a-z_]+)\(', line)
            if match:
                operation = match[1]
                calls[operation] += 1
                counts['rc_glue_callsite_noinline'] += int('noinline' in line)
                examples.setdefault(operation, {'module': path.name, 'call': line.strip()})
        for line in il.splitlines():
            match = re.match(r'\s*dbgloc (\d+)', line)
            if match and int(match[1]) > maximum['position']:
                maximum = {'position': int(match[1]), 'module': path.name}
        inputs[path.name] = {'llvm_sha256': sha(path), 'il_sha256': sha(ssa),
                             'signatures_sha256': sha(path.with_suffix('.sigs.json'))}
    binary = work / 'bin/unchanged-dump'
    manifest = binary.with_name(binary.name + '.qbe-manifest.json')
    return {'source': str(source),
            'source_sha256': {p.name: sha(p) for p in sorted(source.glob('*.my'))},
            'compiler': str(compiler), 'compiler_sha256': sha(compiler),
            'command': command,
            'environment': {'TMPDIR': str(work / 'tmp'),
                            'MYLANG_LLVM_DUMP': str(work / 'dump')},
            'binary': str(binary), 'binary_sha256': sha(binary),
            'manifest_sha256': sha(manifest),
            'reference_binary': str(reference) if reference else None,
            'reference_binary_sha256': sha(reference) if reference else None,
            'reference_binary_identical': sha(binary) == sha(reference) if reference else None,
            'llvm_units': len(modules), 'restriction_counts': dict(counts),
            'rc_glue_static_calls': dict(sorted(calls.items())),
            'maximum_dbgloc': maximum, 'representative_calls': examples,
            'input_hashes': inputs}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--reference', type=Path)
    p.add_argument('--inspect-only', action='store_true')
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    work, compiler, source = a.work.resolve(), a.compiler.resolve(), a.source.resolve()
    repo = Path(__file__).resolve().parents[2]
    for directory in ['tmp', 'dump', 'bin']:
        (work / directory).mkdir(parents=True, exist_ok=True)
    command = [str(repo / 'scripts/build-slot.sh'), 'build', str(compiler), 'build',
               str(source / 'main.my'), '--project', '--backend', 'llvm',
               '--llvm-opt', '3', '--lto', '--rc-runtime', '--keep-symbols',
               '--cache-dir', str(work / 'cache-dump'),
               '-o', str(work / 'bin/unchanged-dump')]
    if not a.inspect_only:
        assert not (work / 'bin/unchanged-dump').exists(), 'refusing to overwrite binary'
        assert not list((work / 'dump').glob('*.ll')), 'fresh dump directory required'
        before = {f.name: sha(f) for f in source.glob('*.my')}
        compiler_hash = sha(compiler)
        env = {k: v for k, v in os.environ.items()
               if not k.startswith('MYLANG_') and k != 'LD_PRELOAD'}
        env['TMPDIR'], env['MYLANG_LLVM_DUMP'] = str(work / 'tmp'), str(work / 'dump')
        with (work / 'dump-build.log').open('w') as log:
            result = subprocess.run(command, cwd=repo, env=env, stdout=log,
                                    stderr=subprocess.STDOUT)
        assert result.returncode == 0
        assert before == {f.name: sha(f) for f in source.glob('*.my')}
        assert compiler_hash == sha(compiler)
    receipt = inspect(work, compiler, source, command, a.reference)
    a.out.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in ['llvm_units', 'restriction_counts',
                                                  'rc_glue_static_calls',
                                                  'reference_binary_identical']}, indent=2))


if __name__ == '__main__':
    main()
