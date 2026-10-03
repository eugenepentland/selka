#!/usr/bin/env python3
"""Check saved assembly arithmetic and independently enumerate bounded inputs."""
import argparse
import datetime
import gzip
import hashlib
import json
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lane', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    assert not args.out.exists()
    lane = args.lane.resolve()
    work = lane / '.tmp-lox-byte-positive-20261003'
    prior = Path(__file__).with_name('review.json')
    assert audit.sha(prior) == 'd246268f8e48bbe1f40159eb9782565932f11bbb345cc49e688e0e61a82a94b2'
    qualification = audit.load(lane / 'experiments/lox-byte-positive-20261003/qualification.json')
    width = work / 'width-diag'
    first, second = audit.read(width / 'read-v1.ssa').decode(), audit.read(width / 'read-l.ssa').decode()
    assert first.count('=w culel') == 1 and first.replace('=w culel', '=l culel') == second
    counts = {}
    for name in ['v1', 'l']:
        text = audit.read(width / ('read-' + name + '.asm')).decode()
        instructions = re.findall(r'^\s*[0-9a-f]+:\s+([^\n]+)', text, re.M)
        counts[name] = len(instructions)
        assert len(instructions) == qualification['width_diagnostic']['arms'][name]['instructions'] == 70
    for arm in ['fixed', 'guarded']:
        text = audit.read(work / (arm + '-read-byte-qbe.asm')).decode()
        rows = [(int(a, 16), i.strip()) for a, i in re.findall(r'^\s*([0-9a-f]+):\s+([^\n]+)', text, re.M)]
        by_address = dict(rows)
        position = {address: i for i, (address, _) in enumerate(rows)}
        diagnostic = qualification['positive_path'][arm]
        path = diagnostic['path']
        assert len(path) == diagnostic['instructions']
        for index, row in enumerate(path):
            address = int(row['address'], 16)
            assert by_address[address] == row['instruction']
            if index + 1 == len(path):
                continue
            instruction = row['instruction']
            if instruction.startswith('j'):
                target = int(instruction.split()[1], 16)
                taken = instruction.startswith('jmp') or diagnostic['branch_choices'][hex(address)]
                expected = target if taken else rows[position[address] + 1][0]
            else:
                expected = rows[position[address] + 1][0]
            assert expected == int(path[index + 1]['address'], 16)
    root = lane.parent / 'codex-lox-parity-20261003'
    bench = root / '.tmp-lox-parity/reference/benchmarks/lox/bench'
    expected = {}
    sizes = audit.load(bench / 'sizes.json')
    for path in sorted((bench / 'scripts').glob('*.lox')):
        _, body = audit.read(path).decode().split('\n', 1)
        for engine in ['vm', 'tree']:
            expected[path.stem, 'smoke', engine] = f"var N = {sizes[path.stem]['smoke']};\n{body}"
    regressions = audit.load(lane / 'experiments/lox-byte-positive-20261003/regressions.json')
    assert len(regressions) == 17
    for case in regressions:
        for engine in ['vm', 'tree']:
            expected[case['name'], 'regression', engine] = case['source']
    for engine, name in [('tree', 'd9-lox-env-reads-runs.json.gz'), ('vm', 'd9-lox-class-method-runs.json.gz')]:
        data = json.loads(gzip.decompress(audit.read(root / 'docs/audits/evidence' / name)))
        for row in data['traces']:
            key = row['name'], 'error', engine
            if key not in expected:
                expected[key] = row['source']
        assert sum(key[1:] == ('error', engine) for key in expected) == 23
    observed = audit.load(work / 'native/observations.json')
    actual = {(row['name'], row['tier'], row['engine']) for row in observed['samples']}
    assert actual == set(expected) and len(expected) == 106
    for row in observed['samples']:
        key = row['name'], row['tier'], row['engine']
        assert audit.read(row['command'][-1]).decode() == expected[key]
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    result = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'outcome': 'saved width/common-path arithmetic and all106 independently enumerated bounded case inputs pass',
              'prior_review_sha256': audit.sha(prior), 'width_only_ssa_edit': '=w culel to =l culel, once',
              'standalone_width_instructions': counts, 'saved_common_path_connected_instruction_counts': {'fixed': 21, 'guarded': 26},
              'bounded_case_identities': {'smoke': 26, 'error': 46, 'regression': 34}, 'bounded_samples_input_bytes_verified': 1192,
              'new_guest_test_or_perf_executions': 0, 'stable_read_input_count': len(audit.READS),
              'limits': ['Static paths follow the declared nonnegative/in-bounds assumptions and recorded branch choices; they are not executed traces.',
                         'The second width object uses the same frozen QBE tool; no second compiler exists or is qualified.',
                         'Case enumeration verifies the completed bounded fixture set; omitted80 native-stress smoke cells remain unrun.']}
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest()}))


if __name__ == '__main__':
    main()
