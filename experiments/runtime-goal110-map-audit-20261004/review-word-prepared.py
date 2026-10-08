#!/usr/bin/env python3
"""Check typed dictionary guest outcomes, callee substitutions and live images."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-dict-word-integrated-20261004'
CACHE = TREE / '.mylang-cache/goal110-dict-word-debug'
STATIC = TREE / '.mylang-cache/goal110-dict-word/static'
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/diagnostics'))
import holdouts


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def load(path):
    return json.loads(Path(path).read_text())


def main():
    manifest_path = CACHE / 'runner/manifest.json'
    manifest = load(manifest_path)
    assert manifest['identity']['source_revision'] == 'a2dfdfa994e19ac3c80373a443913c7ecdef23d7'
    holdouts.check_manifest(manifest_path, sha(manifest_path), manifest)
    counts = {}
    for name, expected_count in (('qualification.json', 720), ('holdouts.json', 516)):
        doc = load(CACHE / name)
        assert doc['manifest_sha256'] == sha(manifest_path) and doc['binary_hashes'] == manifest['binary_hashes']
        seen = set()
        for row in doc['checks']:
            key = tuple(row[k] for k in ('case', 'size', 'iterations', 'seed', 'arm'))
            assert key not in seen
            seen.add(key)
            assert row['checksum'] == row['expected_checksum'] == checksum(*key[:4])
            assert row['exit_status'] == 0 and row['clock_protocol_validated']
        assert len(seen) == expected_count
        counts[name] = len(seen)
    proof = load(STATIC / 'code-proof.json')
    assert proof['status'] == 'passed'
    bodies = {}
    for arm, row in proof['frontend'].items():
        for item in row.values():
            if isinstance(item, dict) and 'path' in item:
                assert sha(item['path']) == item['sha256']
        bodies[arm] = Path(row['body']['path']).read_text()
    generic, word = 'call $myl_native_dictionary_read(', 'call $myl_native_dictionary_read_word('
    assert bodies['after'].count(word) == 2 and bodies['before'].count(word) == 0
    assert bodies['before'].count(generic) == 5 and bodies['after'].count(generic) == 3
    assert bodies['after'].replace(word, generic) == bodies['before']
    sizes, calls = {}, {}
    for arm, row in proof['code'].items():
        path = row['binary']['path']
        assert sha(path) == row['binary']['sha256']
        nm = subprocess.check_output(['nm', '-S', '--defined-only', path], text=True)
        symbols = {p[3]: int(p[1], 16) for line in nm.splitlines() if len(p := line.split()) == 4}
        for symbol, function in row['functions'].items():
            assert symbols[symbol] == function['bytes']
            asm = subprocess.check_output(['objdump', '-d', '--no-show-raw-insn', '--disassemble=' + symbol, path], text=True)
            direct = re.findall(r'\bcall\w*\s+[^\n]*<([^>]+)>', asm)
            sizes[arm + '/' + symbol] = symbols[symbol]
            if symbol == 'myl_native_dictionary_read_word':
                assert symbols[symbol] == 426 and not direct
                assert re.search(r'\bjmp\s+[^\n]*<myl_native_dictionary_read>', asm)
            if symbol == row['batch_symbol']:
                calls[arm] = {name: direct.count(name) for name in ('myl_native_dictionary_read', 'myl_native_dictionary_read_word')}
    assert calls == {'before': {'myl_native_dictionary_read': 5, 'myl_native_dictionary_read_word': 0},
                     'after': {'myl_native_dictionary_read': 3, 'myl_native_dictionary_read_word': 2}}
    helper = ROOT / 'experiments/runtime-goal110-index-review-20261004/review-controls.py'
    spec = importlib.util.spec_from_file_location('elf_review', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    controls = []
    for row in proof['controls']:
        paths = [Path(row['artifacts'][a]['binary']['path']) for a in ('before', 'after')]
        for arm, path in zip(('before', 'after'), paths):
            assert sha(path) == row['artifacts'][arm]['binary']['sha256']
        before, after = map(module.elf, paths)
        sections = before[2] == after[2]
        headers = before[3] == after[3]
        assert sections == row['allocated_sections_identical'] and headers == row['program_headers_identical']
        equal = sections and headers and before[1][4] == after[1][4]
        if equal:
            for segment in before[3]:
                if segment[0] != 1:
                    continue
                offset, size = segment[2], segment[5]
                left, right = before[0][offset:offset+size], after[0][offset:offset+size]
                changes = {offset+i for i, pair in enumerate(zip(left, right)) if pair[0] != pair[1]}
                assert len(left) == len(right) == size
                assert not changes or (offset == 0 and not segment[1] & 1 and changes <= set(range(40, 48)))
        controls.append(dict(name=row['name'], runtime_image_equal=equal))
    assert len(controls) == 8 and sum(r['runtime_image_equal'] for r in controls) == 5
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=manifest['identity']['source_revision'], checks=counts,
                  frontend_substitutions=2, machine_call_counts=calls, function_bytes=sizes,
                  controls=controls, manifest_sha256=sha(manifest_path), static_receipt_sha256=sha(STATIC / 'code-proof.json'),
                  script_sha256=sha(__file__),
                  limitations=['Saved checksum outcomes and fresh read-only ELF/disassembly inspection; no new guest timing.',
                               'Five images match modulo nonexecuting ELF section-header offset; collections both and textQBE differ.',
                               'Native semantic/state proof is recorded separately; no goal confirmation.'])
    with Path(sys.argv[1]).open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print('PASS 1236 guest oracles, two exact substitutions, actual native calls/sizes and eight images')


if __name__ == '__main__':
    main()
