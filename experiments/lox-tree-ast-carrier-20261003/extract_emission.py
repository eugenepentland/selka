#!/usr/bin/env python3
"""Read frozen SSA/ELFs and save static AST carrier evidence; never run guests."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--arms', type=Path, required=True,
                        help='JSON arm -> {qbe_cache, llvm_binary, qbe_binary}')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists(), 'refuse to overwrite frozen emission evidence'
    args.out.mkdir(parents=True)
    result = {'arms_manifest_sha256': sha(args.arms),
              'evidence_scope': 'QBE physical SSA plus exact LLVM LTO/QBE linked assembly. Static sites and byte sizes are not timing or dynamic counters.',
              'arms': {}}
    names = ['evaluate', 'execute', 'call_expr', 'class_declaration',
             'call_node', 'class_node', 'run_block', 'run_body']
    for arm, config in json.loads(args.arms.read_text()).items():
        cache = Path(config['qbe_cache'])
        manifests = list(cache.rglob('interpreter.manifest.json'))
        assert len(manifests) == 1, manifests
        manifest = manifests[0]
        doc = json.loads(manifest.read_text())
        before = {p: sha(p) for p in [config['llvm_binary'], config['qbe_binary']]}
        functions = {}
        for name in names:
            f = next(row for row in doc['functions'] if row['name'] == 'interpreter::' + name)
            paths = list((cache / 'frontend/fragments').rglob(f['il_digest']))
            assert paths and len({sha(p) for p in paths}) == 1, paths
            il = paths[0].read_text()
            (args.out / (arm + '-' + name + '.ssa')).write_text(il)
            row = {'name': f['name'], 'symbol': f['symbol'],
                   'ssa_source': str(paths[0]), 'ssa_sha256': sha(paths[0]),
                   'ssa_lines': len(il.splitlines()),
                   'managed_ops': {x: len(re.findall('_rcg_' + x + r'\b', il))
                                   for x in ['take', 'drop', 'loan', 'unloan', 'copy']},
                   'normalized_index_bounds': il.count('$myl_qbe_fail_normalized_index_bounds'),
                   'assembly': {}}
            for backend in ['llvm', 'qbe']:
                binary = config[backend + '_binary']
                argv = ['objdump', '-d', '--disassemble=' + f['symbol'], binary]
                assembly = subprocess.run(argv, capture_output=True, text=True, check=True).stdout
                path = args.out / (arm + '-' + name + '.' + backend + '.asm')
                path.write_text(assembly)
                calls = Counter(re.findall(r'call\s+[0-9a-f]+\s+<([^>]+)>', assembly))
                nm_argv = ['nm', '-S', '--defined-only', binary]
                nm = subprocess.run(nm_argv, capture_output=True, text=True, check=True).stdout
                definition = next((line for line in nm.splitlines() if line.endswith(' ' + f['symbol'])), None)
                row['assembly'][backend] = {
                    'binary': binary, 'binary_sha256': before[binary],
                    'command': argv, 'nm_command': nm_argv,
                    'assembly_sha256': sha(path), 'calls': dict(sorted(calls.items())),
                    'size_bytes': int(definition.split()[1], 16) if definition else None,
                    'symbol_status': 'present' if definition else 'no standalone symbol: inlined or unreferenced'}
            functions[name] = row
        assert {p: sha(p) for p in before} == before
        result['arms'][arm] = {'manifest': str(manifest), 'manifest_sha256': sha(manifest),
                               'binary_hashes_verified_after': True, 'functions': functions}
    (args.out / 'emission.json').write_text(json.dumps(result, indent=2) + '\n')


if __name__ == '__main__':
    main()
