#!/usr/bin/env python3
"""Check source-pinned default and LLVM-policy IL, including the QBE consumer."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--after', type=Path, required=True)
parser.add_argument('--qbe', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
fixture = Path(__file__).with_name('native-fixture.my')
report = {'status': 'running', 'records': [], 'runner_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
texts = {}
try:
    for policy in ('qbe', 'llvm-v1'):
        for label, host in (('before', args.before), ('after', args.after)):
            command = [str(host.resolve()), 'emit-qbe', str(fixture), '--native-scalars=' + policy]
            done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
            path = out / (label + '-' + policy + '.json')
            path.write_text(done.stdout)
            report['records'].append({'command': command, 'status': done.returncode, 'stdout_file': str(path),
                                      'stdout_sha256': hashlib.sha256(done.stdout.encode()).hexdigest(), 'stderr': done.stderr})
            assert done.returncode == 0, report['records'][-1]
            texts[label, policy] = done.stdout
        assert ('# myl-floor-result' in texts['after', policy]) == (policy == 'llvm-v1')
        if policy == 'qbe':
            assert texts['before', policy] == texts['after', policy]
        else:
            stripped = json.loads(texts['after', policy])
            baseline = json.loads(texts['before', policy])
            dependency_hashes = []
            for function, original in zip(stripped['functions'], baseline['functions']):
                function['il'] = ''.join(line for line in function['il'].splitlines(keepends=True)
                                         if '# myl-floor-result' not in line)
                before_hash = original['test_dependencies']['implementation_hash']
                after_hash = function['test_dependencies']['implementation_hash']
                if before_hash != after_hash:
                    dependency_hashes.append({'name': function['name'], 'before': before_hash, 'after': after_hash})
                function['test_dependencies']['implementation_hash'] = before_hash
            assert baseline == stripped
            report['changed_llvm_test_implementation_hashes'] = dependency_hashes
    unit = next(function for function in json.loads(texts['after', 'llvm-v1'])['functions']
                if function['name'] == 'zero_bool')['il']
    il_path = out / 'after-llvm-zero-bool.ssa'
    il_path.write_text(unit)
    assert '# myl-floor-result' in unit
    command = [str(ROOT / 'scripts/build-slot.sh'), 'build', str(args.qbe.resolve()),
               '-o', str(out / 'llvm-policy-qbe.s'), str(il_path)]
    done = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120)
    report['records'].append({'command': command, 'status': done.returncode, 'stdout': done.stdout, 'stderr': done.stderr})
    assert done.returncode == 0, report['records'][-1]
    report.update(status='passed', qbe_policy_byte_identical=True, llvm_policy_il_only_comment_delta=True)
finally:
    (out / 'emission-checks.json').write_text(json.dumps(report, indent=2) + '\n')
print('PASS exact default QBE IL; LLVM-policy only typed comments; QBE accepts annotated IL')
