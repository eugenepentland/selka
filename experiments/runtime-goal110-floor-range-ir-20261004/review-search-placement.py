#!/usr/bin/env python3
"""Read-only replay of the diagnostic search placement counterfactual."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TREE = ROOT.parent / 'goal110-floor-result-range-20261004'
CACHE = TREE / '.mylang-cache/goal110-search-placement'
sys.path.insert(0, str(ROOT / 'benchmarks/runtime/expanded'))
from registry import checksum


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def check(binding):
    path = Path(binding['path'])
    assert sha(path) == binding['sha256']
    if 'bytes' in binding:
        assert path.stat().st_size == binding['bytes']
    return path


def main():
    proof = json.loads((CACHE / 'proof/placement-proof.json').read_text())
    commands = json.loads((CACHE / 'commands.json').read_text())
    helpers = TREE / 'experiments/runtime-goal110-search-placement-20261004'
    for name, digest in commands['helpers'].items():
        assert sha(helpers / name) == digest
    assert proof['status'] == 'passed'
    check(proof['driver'])
    fill = b'\t.fill 32, 1, 0x90 # diagnostic placement counterfactual only\n'
    for kind in ('raw', 'annotated'):
        left, right = [check(proof['assembly_identity'][arm][kind]).read_bytes()
                       for arm in ('capture', 'fill32')]
        assert right.count(fill) == 1 and right.replace(fill, b'') == left
    for arm, variant in proof['variants'].items():
        binary = check(variant['binary'])
        build = json.loads(check(variant['build']).read_text())
        assert build['exit_status'] == 0 and build['guest'] == variant['binary']
        for kind in ('compiler', 'compiler_receipt', 'guest_manifest', 'wrapper', 'config', 'driver'):
            check(build[kind])
        for name, function in variant['functions'].items():
            assert function['command'][-1] == str(binary)
            assert function['command'][:3] == ['objdump', '-d', '--no-show-raw-insn']
            assert function['command'][3] == '--disassemble=' + name
            actual = subprocess.check_output(function['command'])
            assert actual == check(function['assembly']).read_bytes()
            check(function['normalized'])
    for name, comparison in proof['comparisons'].items():
        assert comparison['normalized_equal']
        left, right = [proof['variants'][arm]['functions'][name]['normalized']['sha256']
                       for arm in ('capture', 'fill32')]
        assert left == right
    doc = json.loads((CACHE / 'text-checks.json').read_text())
    assert doc['status'] == 'passed' and doc['execution_count'] == len(doc['records']) == 200
    for row in doc['records']:
        expected = checksum(row['case'], row['size'], row['iterations'], row['seed'])
        parsed = re.fullmatch(r'([0-9]+) ([0-9]+)\n', row['stdout'])
        assert row['oracle'] == expected and parsed and int(parsed[1]) == expected and int(parsed[2]) > 0
        assert row['status'] == 0 and row['stderr'] == ''
        binary = check(doc['binaries'][row['arm']])
        assert row['command'] == [str(binary), row['case'], str(row['size']), str(row['iterations']), str(row['seed'])]
    result = dict(status='pass', reviewed_utc=datetime.now(timezone.utc).isoformat(),
                  proof_sha256=sha(CACHE / 'proof/placement-proof.json'),
                  checks_sha256=sha(CACHE / 'text-checks.json'), commands_sha256=sha(CACHE / 'commands.json'),
                  outcomes=200, disassemblies=8, script_sha256=sha(__file__),
                  limitations=['Read-only disassembly and saved oracle replay; no timing.',
                               'The sole assembly delta inserts 32 NOP bytes before the search loop label.',
                               'Later symbol placements also move; this diagnoses placement sensitivity only.',
                               'Normalization was reviewed in the candidate helper; whole raw and annotated assembly identity is checked independently.'])
    with Path(sys.argv[1]).open('x') as output:
        output.write(json.dumps(result, indent=2) + '\n')
    print('PASS complete assembly delta, eight live disassemblies, tool/artifact bindings and 200 oracles')


if __name__ == '__main__':
    main()
