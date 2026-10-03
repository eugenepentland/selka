#!/usr/bin/env python3
"""Read frozen byte-index proof and qualification evidence without guest execution."""
from collections import Counter
import argparse
import datetime
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).parent.parent / 'lox-next-measurement-independent-review-20261003'))
import audit

COMMIT = 'ee1f99f0aacb842872527c28652b129f0da55b03'
F89 = 'f89c339c1be3bb21fadf34b69b394fffa87e7248f3f5feeab49b62fc761a9520'
QBE = '99ad919d70ad582dee6202b045bd53e1ab18fec356de98849610f49983756d63'


def function(source, name):
    return re.search(r'^(?:pub )?fn ' + name + r'\(.*?(?=^(?:pub )?fn |\Z)', source, re.M | re.S)[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lane', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    assert not args.out.exists()
    lane = args.lane.resolve()
    exp = lane / 'experiments/lox-byte-positive-20261003'
    work = lane / '.tmp-lox-byte-positive-20261003'
    qualification = audit.load(exp / 'qualification.json')
    changed = subprocess.run(['git', 'diff-tree', '--no-commit-id', '--name-only', '-r', COMMIT], cwd=lane,
                             capture_output=True, text=True, check=True).stdout.splitlines()
    assert [n for n in changed if not n.startswith('experiments/')] == ['SPEC.md', 'src/qbe_managed.zig', 'src/qbe_positive_index.zig', 'src/qbe_positive_index_test.zig']
    committed = {}
    for name in changed:
        data = subprocess.run(['git', 'show', COMMIT + ':' + name], cwd=lane, capture_output=True, check=True).stdout
        assert data == audit.read(lane / name)
        committed[name] = audit.sha(lane / name)
    for name, digest in qualification['proof_source']['source_sha256'].items():
        assert audit.sha(lane / name) == digest
    old = subprocess.run(['git', 'show', qualification['proof_source']['base'] + ':src/qbe_positive_index.zig'],
                         cwd=lane, capture_output=True, text=True, check=True).stdout
    new = audit.read(lane / 'src/qbe_positive_index.zig').decode()
    for name in ['normalizer', 'extraEntry', 'loads', 'quiet']:
        assert function(old, name) == function(new, name)
    original_cert = function(old, 'certify')
    current_cert = function(new, 'certify').replace('var proof = normalizer', 'const proof = normalizer')
    current_cert = current_cert.replace('    proof.byte_length_guard = code[proof.read].op.buffer_operation.output == .u8;\n', '')
    assert original_cert == current_cert
    assert 'record.collection.kind != .list or record.collection.box' in new
    assert 'layout.size < 2 and element != .u8' in new
    managed = audit.read(lane / 'src/qbe_managed.zig').decode()
    positive = re.search(r'pub fn positiveRead\(.*?\n        }', managed, re.S)[0]
    assert positive.index(' culel ') < positive.index('unsigned_below') < positive.index('indexPayload(')
    assert '9223372036854775807' in positive and 'self.labelPrefix(proof.start)' in positive
    assert 'require(' not in positive and 'fail_' not in positive
    assert 'if (!self.checks or self.step_checks) return;' in new
    assert 'if (self.version != null or self.original != null) return;' in new
    assert 'qbe_rc_ops.zig' in new and '.after(E, self,' in new
    # Independent admission algebra, not a runtime allocation or fallback-trap model.
    lengths = [0, 1, (1 << 63) - 1, 1 << 63, (1 << 63) + 1, (1 << 64) - 1]
    indices = [-(1 << 63), -1, 0, 1, (1 << 63) - 1]
    for length, index in itertools.product(lengths, indices):
        guard = length <= (1 << 63) - 1 and (index & ((1 << 64) - 1)) < length
        assert guard == (length <= (1 << 63) - 1 and 0 <= index < length)
    assert not (1 << 63 <= (1 << 63) - 1) and 0 < 1 << 63

    compressed = audit.read(exp / 'receipts.json.gz')
    raw = gzip.decompress(compressed)
    assert hashlib.sha256(compressed).hexdigest() == qualification['archive']['sha256']
    assert hashlib.sha256(raw).hexdigest() == qualification['archive']['raw_json_sha256']
    packet = json.loads(raw)['files']
    assert len(packet) == qualification['archive']['raw_files'] == 41
    for name, item in packet.items():
        assert hashlib.sha256(item['text'].encode()).hexdigest() == item['sha256']
        assert audit.read(work / name) == item['text'].encode()
    saved = lambda name: json.loads(packet[name]['text'])
    builds = saved('guest-builds.json')
    assert builds == qualification['builds'] and builds['verified_after']
    assert audit.sha(builds['compiler']) == builds['compiler_sha256'] == qualification['compiler_sha256'] == F89
    assert audit.sha(Path(builds['compiler']).parent / 'qbe') == builds['qbe_sha256'] == qualification['qbe_sha256'] == QBE
    source = Path(builds['source'])
    source_report = audit.sources({'path': str(source), 'all_files': builds['source37'],
                                  'hashes': {n: d for n, d in builds['source37'].items() if n.endswith('.my')}})
    guests = {}
    for row in builds['runs']:
        assert row['status'] == 0 and audit.sha(row['stdout']) == row['stdout_sha256'] and audit.sha(row['stderr']) == row['stderr_sha256']
        if 'binary' not in row:
            assert 'emit-project-qbe' in row['argv'] and '--drop-step-checks' in row['argv']
            continue
        argv = row['argv']
        assert not any(arg.startswith('--drop-') for arg in argv)
        backend = audit.option(argv, '--backend')
        runtime = 'rc' if '--rc-runtime' in argv else 'gc'
        assert '--' + runtime + '-runtime' in argv
        assert audit.sha(row['binary']) == row['binary_sha256'] and audit.sha(row['manifest']) == row['manifest_sha256']
        assert audit.sha(row['binary'] + '.qbe-receipt') == row['receipt_sha256']
        audit.codegen(row['binary'], row['manifest_sha256'], row['runtime_object'], row['runtime_object_sha256'], backend)
        guests[runtime + '-' + backend] = row['binary_sha256']
    assert set(guests) == {'rc-llvm', 'rc-qbe', 'gc-llvm', 'gc-qbe'}
    public = saved('byte-guard-qualification.json')
    assert public['verified_after'] and public['source_sha256'] == builds['source37']
    assert public['compiler_sha256'] == F89 and public['qbe_sha256'] == QBE
    names = sorted(p.stem + '::' + name for p in source.glob('*.my')
                   for name in re.findall(r'^public def (test_\w+)\(', audit.read(p).decode(), re.M))
    assert len(names) == 88 and names == qualification['public_names'] and len(public['runs']) == 4
    for run in public['runs']:
        assert run['status'] == 0 and '--cases' not in run['argv']
        assert audit.option(run['argv'], '--max-steps') == '1000000000'
        text = audit.read(run['log']).decode()
        assert audit.sha(run['log']) == run['log_sha256']
        assert sorted(re.findall(r'^passed (\S+)$', text, re.M)) == names
        assert run['summaries'] == ['88 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 10 programs']
    native = saved('native/completed.json')
    assert native['verified_after'] and native['helper_status'] == 0
    assert native['before']['candidate37'] == native['after']['candidate37'] == builds['source37']
    assert native['before']['artifacts_sha256'] == native['after']['artifacts_sha256']
    for path, digest in native['after']['artifacts_sha256'].items():
        assert audit.sha(path) == digest
    for name, digest in native['receipt_sha256'].items():
        assert audit.sha(work / 'native' / name) == digest
    binaries = saved('native/binaries.json')['binaries']
    for backend in ['llvm', 'qbe']:
        for mode, runtime in [('rc', 'rc'), ('ordinary', 'gc'), ('gc', 'gc')]:
            assert audit.sha(binaries['octets-' + mode + '-' + backend]) == guests[runtime + '-' + backend]
    observed = saved('native/observations.json')
    rows, omitted = observed['samples'], observed['unrun']
    key = lambda row: tuple(row[n] for n in ['name', 'tier', 'engine', 'arm', 'lox_gc_stress'])
    done, unrun = {key(r) for r in rows}, {key(r) for r in omitted}
    cases = {(r['name'], r['tier'], r['engine']) for r in rows}
    expected = {(n, t, e, a, stress) for n, t, e in cases for a in binaries if not a.startswith('control-') for stress in [False, True]}
    assert len(cases) == 106 and len(rows) == len(done) == 1192 and len(omitted) == len(unrun) == 80
    assert done.isdisjoint(unrun) and done | unrun == expected
    counts = Counter('native_gc_stress' if r['native_gc_stress'] else 'rc' if '-rc-' in r['arm'] else 'ordinary_gc' for r in rows)
    assert counts == qualification['native_mode_counts'] == {'rc': 424, 'ordinary_gc': 424, 'native_gc_stress': 344}
    for row in rows:
        assert row['actual'] == row['expected'] and row['command'][0] == binaries[row['arm']]
        assert audit.sha(row['command'][-1]) == row['source_sha256']
    for filename, field, count in [('native/constant-255-boundary.json', 'samples', 12), ('native/argument-limits.json', 'pairs', 192), ('native/rc-native-stress-refusals.json', 'pairs', 8)]:
        pairs = saved(filename)[field]
        assert len(pairs) == count
        for row in pairs:
            assert row['actual'] == row['expected']
            assert audit.sha(row['argv'][0]) in guests.values()
            if filename.endswith('refusals.json'):
                assert row['actual']['status'] == 2 and row['actual']['stdout'] == '' and '--gc-runtime' in row['actual']['stderr']
            else:
                assert audit.sha(row['argv'][-1]) == row['source_sha256']
    # Preserve the original failed broad command and its narrower corrected replay.
    commands = audit.load(exp / 'commands.json')
    statuses = {r['name']: r['status'] for r in commands['runs']}
    assert statuses['broad-initial'] == 1 and statuses['affected-replay'] == 0 and statuses['focused-qualified'] == 0
    broad, replay = packet['units.log']['text'], packet['units-replay.log']['text']
    failed = re.findall(r"^error: '([^']+)' failed:", broad, re.M)
    assert len(failed) == 24 and failed == qualification['broad_initial']['failed_names']
    assert 'RESULT {"passed":2461,"failed":24,"skipped":0}' in broad and '1 leaked' in broad
    assert 'RESULT {"passed":60,"failed":0,"skipped":0}' in replay and '1 leaked' not in replay
    assert 'RESULT {"passed":22,"failed":0,"skipped":0}' in packet['focused-qualified.log']['text']
    modules = {name.split('.test.')[0] for name in failed}
    declared = {m + '.test.' + name for m in modules
                for name in re.findall(r'^test "([^"]+)"', audit.read(lane / 'src' / (m + '.zig')).decode(), re.M)}
    assert len(declared) == 48 and set(failed) <= declared == set(qualification['affected_replay']['named_tests'])
    assert Path(lane / 'zig-out').resolve() == Path(commands['layout_fix']['link']).resolve()
    pin = commands['qbe_pin']
    assert audit.sha(pin['built_qbe']) == pin['built_sha256']
    assert audit.sha(pin['guest_qbe']) == audit.sha(pin['frozen_qbe']) == QBE
    width = qualification['width_diagnostic']
    assert width['selected_qbe_sha256'] == QBE
    for arm in width['arms'].values():
        for name, digest in arm['files_sha256'].items():
            assert audit.sha(lane / name) == digest
        assert arm['instructions'] == 70 and arm['setbe'] == 1 and arm['boolean_zero_compares'] == 1
    assert qualification['positive_path']['fixed']['instructions'] == 21 and qualification['positive_path']['guarded']['instructions'] == 26
    for arm in ['fixed', 'guarded']:
        assert audit.sha(work / (arm + '-read-byte-qbe.asm')) == qualification['positive_path'][arm]['assembly_sha256']
    for path, digest in list(audit.READS.items()):
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
    result = {'recorded_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'candidate_commit': COMMIT,
              'outcome': 'proof passes with stated qualification limits; no actionable compiler defect; compiler remains unselected',
              'committed_files_sha256': committed, 'source_v3': source_report, 'compiler_sha256': F89, 'guest_qbe_sha256': QBE,
              'actual_four_guest_sha256': guests, 'certificate_refusals_and_original_normalizer_unchanged': True,
              'unsigned_byte_guard_admission_cases_checked': 30, 'huge_length_is_fallback_not_new_trap': True,
              'payload_address_and_load_follow_both_guards': True, 'original_result_slot_clearing_preserved': True,
              'focused_tests': 22, 'accounted_public_passes': 352, 'native_exact_pairs': 1396,
              'native_mode_counts_bounded': dict(counts), 'rc_native_stress_checked_refusals': 8, 'native_smoke_unrun': 80,
              'broad_initial': qualification['broad_initial'], 'affected_replay': qualification['affected_replay'],
              'archive_raw_files_verified': 41, 'static_qbe_common_path': {'fixed': 21, 'guarded': 26},
              'standalone_width_variants_total_instructions': {'w': 70, 'l': 70}, 'new_compiler_or_performance_runs': 0,
              'source_root_main_or_feedback_mutations': 0, 'stable_read_input_count': len(audit.READS),
              'limits': ['Huge-length cases are guard-admission algebra only; no huge runtime object was allocated and no fallback trap is assumed.',
                         'Focused/broad units use the separate built focus tool; actual frozen F89 guest builds use adjacent QBE99ad. The preserved installed QBE4f650 tool is not silently relabeled.',
                         '352 provider-free directory public passes retain step accounting, so they refuse this guard; focused and1396 unaccounted native pairs exercise separate guard behavior.',
                         'The original broad run failed24 tests and leaked once; corrected60 replay covers the five affected modules, not a single full-suite green rerun.',
                         '1192 native bounded rows plus12 operand255 and192 argument/recovery pairs total1396; eight RC stress refusals and80 unrun cells are separate.',
                         'Static common-path and standalone width diagnostics are not dynamic instruction counts or timings; no v2 compiler or speed acceptance is claimed.',
                         'Whole-function native assembly counts are author diagnostic receipts; this review reads saved common-path/width assembly without new disassembly.',
                         'Source-v3 qualification is isolated from the selected AST-only canonical source and does not establish combined-source acceptance or Rust/Go parity.']}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'out': str(args.out), 'sha256': hashlib.sha256(args.out.read_bytes()).hexdigest(), 'inputs': len(audit.READS)}))


if __name__ == '__main__':
    main()
