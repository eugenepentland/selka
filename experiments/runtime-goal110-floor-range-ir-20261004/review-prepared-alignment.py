#!/usr/bin/env python3
"""Review prepared alignment guests and saved checks before any timing."""
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-natural-loop-align-20261004'
CACHE = TREE / '.mylang-cache/goal110-natural-loop-align'
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
    assert manifest['identity']['source_revision'] == '5818cee8e679c1f30fd5966963210511fcf69919'
    holdouts.check_manifest(manifest_path, sha(manifest_path), manifest)
    counts = {}
    for name, count in (('qualification.json', 720), ('holdouts.json', 516)):
        doc = load(CACHE / name)
        assert doc['manifest_sha256'] == sha(manifest_path)
        assert doc['binary_hashes'] == manifest['binary_hashes']
        seen = set()
        for row in doc['checks']:
            key = tuple(row[k] for k in ('case', 'size', 'iterations', 'seed', 'arm'))
            assert key not in seen
            seen.add(key)
            assert row['checksum'] == row['expected_checksum'] == checksum(*key[:4])
            assert row['exit_status'] == 0 and row['clock_protocol_validated']
        assert len(seen) == count
        counts[name] = count
    text = load(CACHE / 'text-checks.json')
    assert text['status'] == 'passed' and len(text['records']) == text['execution_count'] == 200
    for item in text['binaries'].values():
        assert sha(item['path']) == item['sha256']
    for row in text['records']:
        args = [row[k] for k in ('case', 'size', 'iterations', 'seed')]
        assert row['command'] == [text['binaries'][row['arm']]['path'], *map(str, args)]
        assert row['status'] == 0 and row['stderr'] == ''
        actual, clock = map(int, row['stdout'].split())
        assert actual == row['oracle'] == checksum(*args) and clock > 0
    helper = ROOT / 'experiments/runtime-goal110-index-review-20261004/review-controls.py'
    spec = importlib.util.spec_from_file_location('elf_review', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    images = load(CACHE / 'runtime-image-comparison.json')
    image_rows = []
    for row in images['rows']:
        paths = [Path(row[side + '_path']) for side in ('before', 'after')]
        assert all(sha(path) == row[side + '_sha256'] for side, path in zip(('before', 'after'), paths))
        before, after = map(module.elf, paths)
        equal = before[1][4] == after[1][4] and before[2] == after[2] and before[3] == after[3]
        if equal:
            for segment in before[3]:
                if segment[0] == 1:
                    start, size = segment[2], segment[5]
                    equal = equal and before[0][start:start+size] == after[0][start:start+size]
        assert equal == row['runtime_image_equal'] == (row['backend'] == 'qbe')
        image_rows.append([row['group'], row['backend'], equal])
    assert len(image_rows) == 8
    code = load(CACHE / 'code/code-proof.json')
    sizes = {}
    for group, row in code['groups'].items():
        sizes[group] = []
        for arm in ('before', 'after'):
            recorded = row['arms'][arm]
            item = recorded['binary']
            assert sha(item['path']) == item['sha256']
            actual = module.elf(Path(item['path']))[2]['.text'][0][4]
            assert actual == recorded['text_bytes']
            sizes[group].append(actual)
        assert sizes[group][1] - sizes[group][0] == row['text_delta_bytes']
    for row in code['native_ir']:
        for name in ('il', 'ir'):
            assert sha(row[name]['path']) == row[name]['sha256']
        il, ir = Path(row['il']['path']).read_text(), Path(row['ir']['path']).read_text()
        assert il.count('# myl-floor-result') == ir.count('call void @llvm.assume') == row['markers']
        assert ir.count('!"llvm.loop.align", i32 32') == row['align32_payloads']
    commands = load(CACHE / 'commands.json')
    for item in [commands['bindings'], commands['sentinel_control_screen'], *commands['helpers'].values()]:
        assert sha(item['path']) == item['sha256']
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  source_revision=manifest['identity']['source_revision'], checks=counts, text_checks=200,
                  runtime_images=image_rows, llvm_text_sizes=sizes,
                  manifest_sha256=sha(manifest_path), commands_sha256=sha(CACHE / 'commands.json'),
                  script_sha256=sha(__file__),
                  limitations=['Saved outcomes and static images; no new timing or target confirmation.',
                               'Static review verifies section size/image identity and bound metadata; machine backedge classification remains the code-proof helper analysis.'])
    with Path(sys.argv[1]).open('x') as out:
        out.write(json.dumps(result, indent=2) + '\n')
    print('PASS 1236 qualification/holdout outcomes, 200 text outcomes, eight images and command bindings')


if __name__ == '__main__':
    main()
