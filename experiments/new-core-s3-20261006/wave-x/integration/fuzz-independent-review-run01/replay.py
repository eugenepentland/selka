#!/usr/bin/env python3
"""Read-only replay of completed pre-failure S3 fuzz command journals.

No compiler, native guest, generator, build, or gate is executed. The completed
S0/S1/RC/split checks are historical after rebinding failed on source case81.
Default stdout is a JSON receipt; --output requires a fresh filename.
"""
import argparse
import base64
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re


AREA = Path(__file__).resolve().parent
INTEGRATION = AREA.parent
ROLES = {'old', 'debug', 'release', 'verify'}
S0_ARGS = [('5', '3', '7'), ('0', '2', '1'), ('37', '4', '999983'),
           ('1', '1', '-12'), ('64', '2', '42')]
EXPECTED_ARGS = {'s0': S0_ARGS, 's1': S0_ARGS,
                 'rc': [(), ('x',), ('x', 'y', 'z')],
                 'split': [('0',), ('1',), ('3',), ('7',), ('23',)]}
SOURCE = '5ee5b8d2e1d1c697a98dfa590cbeda704ed7ae55'
OLD = 'd36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79'
NEW = '05e5206c53b853ff8855d547784cec0ae8c0587da3dbd5b0e02eb0eb2744721c'


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def load(path):
    return json.loads(path.read_text())


def decode(value):
    require(isinstance(value, str), 'Non-string base64 outcome')
    return base64.b64decode(value, validate=True)


def trap(stderr):
    match = re.search(rb'\bR_[A-Z_0-9]+\b', stderr)
    return match.group().decode('ascii') if match else ''


def outcome(record):
    return record['status'], decode(record['stdout_b64']), trap(decode(record['stderr_b64']))


def authority():
    freeze = load(AREA / 'authority/source-freeze.json')
    manifest = load(AREA / 'authority/matrix-manifest.json')
    require(freeze['qualified_source_commit'] == SOURCE, 'Unexpected frozen source')
    require(manifest['source_commit'] == manifest['qualified_head_requested'] == SOURCE,
            'Matrix source authority differs')
    expected = {name: freeze['oracles'][name] for name in ('old', 'new')}
    require(expected == manifest['oracles'], 'Matrix/freeze oracle identity differs')
    require(expected['old']['sha256'] == OLD and expected['new']['sha256'] == NEW,
            'Unexpected oracle SHA authority')
    require(manifest['cases_per_kind'] == 200, 'Matrix count authority differs')
    return freeze, manifest, expected


def replay(kind):
    freeze, manifest, oracles = authority()
    inputs = load(AREA / 'authority/inputs.json')
    binding = inputs[kind]
    evidence = INTEGRATION / binding['evidence_relative_to_integration']
    summary_path = evidence / 'summary.json'
    summary = load(summary_path)
    journal_path = evidence / 'commands.jsonl'
    journal_bytes = journal_path.read_bytes()
    records = [json.loads(line) for line in journal_bytes.decode().splitlines()]
    require([row['command_id'] for row in records] == list(range(1, len(records) + 1)),
            'Command IDs are not contiguous and unique: ' + kind)
    require(summary['command_count'] == len(records), 'Summary command count differs')
    require(summary['kind'] == ('text' if kind == 'split' else kind), 'Kind mismatch')
    require(summary['cases_requested'] == summary['cases_seen'] == summary['accepted'] == 200,
            'Not exactly 200 accepted cases: ' + kind)
    for key in ('qualified', 'complete', 'oracle_unchanged', 'native_complete'):
        require(summary[key] is True, 'Unqualified completion flag: ' + key)
    require(summary['harness_status'] == 0 and summary['error'] is None and not summary['failures'],
            'Recorded harness failure')
    for key in ('old_rejected', 'core_refused', 'core_build_failed'):
        require(summary[key] == 0, 'Nonzero refusal/build failure count: ' + key)
    require(summary['oracles'] == oracles, 'Summary oracle binding differs')
    captured_harness = AREA / binding['harness_capture']
    require(sha(captured_harness.read_bytes()) == binding['harness_sha256'] == summary['harness_sha256'],
            'Captured original harness SHA differs')
    require(not (evidence / 'failures').exists(), 'Unexpected retained failure directory')
    expected_args = EXPECTED_ARGS[kind]
    expected_compared = 200 * len(expected_args) * 3
    require(summary['comparisons_expected'] == summary['native_comparisons'] == expected_compared,
            'Incomplete summary comparison total')
    text_bytes = (evidence / 'harness.txt').read_bytes()
    stats_lines = []
    for line in text_bytes.decode().splitlines():
        stats = {key: int(value) for key, value in re.findall(r'\b(\w+)=(\d+)\b', line)}
        if {'cases', 'compared', 'mismatch'} <= stats.keys():
            stats_lines.append(stats)
    require(len(stats_lines) == 1 and stats_lines[0] == summary['harness'],
            'Original harness summary is not complete/exact')
    stats = stats_lines[0]
    require(stats['cases'] == 200 and stats['compared'] == expected_compared,
            'Original harness totals differ')
    for key in ('mismatch', 'fact', 'caught', 'old_rejected', 'rejected', 'new_refused', 'refused'):
        require(stats.get(key, 0) == 0, 'Original harness recorded failures: ' + key)

    sources = {}
    for path in (evidence / 'sources').iterdir():
        require(path.is_file() and path.suffix == '.my', 'Unexpected saved-source artifact')
        match = re.fullmatch(r'(.+)-([0-9a-f]{12})\.my', path.name)
        require(match is not None, 'Saved-source SHA reference is malformed')
        digest = sha(path.read_bytes())
        require(digest.startswith(match[2]), 'Saved-source SHA reference does not match bytes')
        index_match = re.search(r'(\d+)$', match[1])
        require(index_match is not None, 'Saved-source lacks original case index')
        sources[path.name] = dict(name=path.name, original_stem=match[1],
                                  case_index=int(index_match[1]), sha256=digest,
                                  builds={}, groups={})
    require(len(sources) == 200, 'Not exactly 200 unique saved sources')
    require(len({item['sha256'] for item in sources.values()}) == 200,
            'Duplicate complete source contents')
    require({item['case_index'] for item in sources.values()} == set(range(200)),
            'Original source case indices are not complete/unique')
    require(Path(summary['saved_sources']).name == 'sources', 'Saved-source directory differs')

    executables = {}
    original_paths = {}
    build_count = native_count = compared = stderr_same = stderr_different = trap_compared = 0
    build_max = native_max = 0.0
    role_counts = Counter()
    for row in records:
        argv = row['command']
        role = row['role']
        require(isinstance(argv, list) and argv and all(isinstance(a, str) for a in argv),
                'Invalid recorded argv')
        require(role in ROLES, 'Unexpected build/native role')
        source = Path(row['source'])
        require(str(source.parent) == summary['saved_sources'] and source.name in sources,
                'Command references an unknown saved source')
        case = sources[source.name]
        require(type(row['status']) is int, 'Invalid native status')
        elapsed = row['elapsed_seconds']
        require(isinstance(elapsed, (int, float)) and math.isfinite(elapsed) and elapsed >= 0,
                'Invalid recorded command time')
        stdout, stderr = decode(row['stdout_b64']), decode(row['stderr_b64'])
        building = len(argv) > 2 and argv[1] == 'build'
        require(type(row['building']) is bool and building == row['building'],
                'Recorded command kind differs from argv')
        if building:
            build_count += 1
            build_max = max(build_max, elapsed)
            require(row['status'] == 0, 'Nonzero compiler status')
            require(role not in case['builds'], 'Duplicate build role for one source')
            expected_compiler = oracles['old' if role == 'old' else 'new']['path']
            require(argv[0] == expected_compiler, 'Compiler/oracle path binding differs')
            require(Path(argv[2]).stem == case['original_stem'], 'Build source name differs')
            prior = original_paths.setdefault(source.name, argv[2])
            require(prior == argv[2], 'One saved case names multiple original sources')
            require(argv.count('-o') == 1 and argv.count('--cache-dir') == 1,
                    'Incomplete output/private frontend cache flags')
            expected_flags = {'old': (True, False), 'debug': (False, False),
                              'release': (True, False), 'verify': (True, True)}[role]
            require(('--release' in argv, '--verify-facts' in argv) == expected_flags,
                    'Recorded build flags do not establish the role')
            output = argv[argv.index('-o') + 1]
            executables[output] = (source.name, role)
            case['builds'][role] = row['command_id']
            continue
        native_count += 1
        role_counts[role] += 1
        native_max = max(native_max, elapsed)
        require(executables.get(argv[0]) == (source.name, role),
                'Native executable is not bound to its most recent build')
        require(0 <= row['status'] <= 6, 'Crash/signal or unexpected native exit')
        require(b'leakcheck' not in stderr and re.search(rb'leak: \d+ blocks live', stderr) is None,
                'Native leak marker')
        require(b'R_CORE_FACT' not in stderr, 'Native fact failure')
        arguments = tuple(argv[1:])
        require(arguments in expected_args, 'Original harness argument set changed')
        group = case['groups'].setdefault(arguments, {})
        entries = group.setdefault(role, [])
        if role == 'old':
            require(not entries or outcome(entries[0]) == outcome(row),
                    'Repeated old native oracle is nondeterministic')
        else:
            require('old' in group and group['old'], 'Native oracle was not executed first')
            old = group['old'][0]
            require(outcome(old) == outcome(row), 'Raw status/stdout/primary trap mismatch')
            compared += 1
            trap_compared += bool(trap(stderr))
            if decode(old['stderr_b64']) == stderr:
                stderr_same += 1
            else:
                stderr_different += 1
            if kind == 'split':
                require(decode(old['stderr_b64']) == stderr,
                        'Strict text-transport raw stderr mismatch')
        entries.append(row)

    inventory = []
    old_repetitions = 3 if kind == 'rc' else 1
    for case in sorted(sources.values(), key=lambda item: item['case_index']):
        require(set(case['builds']) == ROLES, 'Not exactly four complete build roles')
        require(set(case['groups']) == set(expected_args), 'Incomplete original argument sets')
        argument_groups = []
        for arguments in expected_args:
            group = case['groups'][arguments]
            require(set(group) == ROLES, 'Incomplete native role coverage')
            require(len(group['old']) == old_repetitions and
                    all(len(group[role]) == 1 for role in ROLES - {'old'}),
                    'Native role repetitions differ from original harness')
            argument_groups.append(dict(
                arguments=list(arguments),
                command_ids={role: [row['command_id'] for row in group[role]] for role in sorted(ROLES)},
                status=group['old'][0]['status'], trap=outcome(group['old'][0])[2],
                stdout_sha256=sha(decode(group['old'][0]['stdout_b64'])),
                stderr_sha256_by_role={role: [sha(decode(row['stderr_b64'])) for row in group[role]]
                                       for role in sorted(ROLES)}))
        inventory.append(dict(source='sources/' + case['name'], sha256=case['sha256'],
                              original_case_index=case['case_index'],
                              build_command_ids=case['builds'], native_argument_groups=argument_groups))
    require(build_count == 800, 'Unexpected complete build count')
    expected_native = 200 * len(expected_args) * (old_repetitions + 3)
    require(native_count == summary['native_runs'] == expected_native,
            'Native event count does not match every role/argument')
    require(compared == expected_compared == summary['native_comparisons'],
            'Raw native comparison count differs')
    require(len(records) == build_count + native_count, 'Unaccounted command record')
    return dict(
        schema='s3-independent-fuzz-journal-replay-v1', historical_only=True,
        final_s3_x_qualified=False, completed_evidence_replay_qualified=True,
        qualified_source_at_execution=SOURCE, kind=kind,
        evidence_relative_to_integration=binding['evidence_relative_to_integration'],
        summary_sha256=sha(summary_path.read_bytes()), journal_sha256=sha(journal_bytes),
        harness_output_sha256=sha(text_bytes), captured_harness_sha256=binding['harness_sha256'],
        oracle_authority=oracles, saved_complete_sources=200, distinct_source_sha256s=200,
        original_case_indices=list(range(200)), source_filename_digest_reference_bits=48,
        build_roles_per_case=sorted(ROLES), builds=build_count, native_events=native_count,
        native_role_event_counts=dict(role_counts), original_argument_sets=[list(a) for a in expected_args],
        exact_raw_outcome_comparisons=compared, primary_trap_comparisons=trap_compared,
        raw_stderr_equal_comparisons=stderr_same, raw_stderr_different_comparisons=stderr_different,
        all_raw_stderr_equal_required=(kind == 'split'),
        contiguous_command_ids=True, command_records=len(records),
        original_harness_summary_exact=True, original_harness_stats=stats,
        refusals_build_failures_leaks_facts_crashes_timeouts=0,
        maximum_recorded_build_seconds=build_max, maximum_recorded_native_seconds=native_max,
        scope='Read-only replay of persisted complete sources, command IDs/roles/argv, base64 raw outcomes and original harness accounting; no native execution.',
        limitations=[
            'Historical only after final rebinding source case81 mismatched. This is not complete nine-kind matrix or S3 exit qualification.',
            'Native status, stdout bytes and first R_* trap code are exact. Full stderr is preserved by the hashed original journal; only split/text transport requires raw stderr byte equality here.',
            'Retained filenames carry a 48-bit SHA-256 prefix. Replay verifies it and records full current source SHA-256; it does not invent an execution-time full-hash field absent from the journal.',
            'Timeouts/crashes/leaks/facts are checked through complete recorded outcomes, no failure records and retained strict wrapper authority. Individual child environments are not journaled.',
            'Original transient guest/build paths need not remain available. Replay reads retained evidence, never volatile frontend/native caches.'],
        case_inventory=inventory)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', required=True, choices=tuple(EXPECTED_ARGS))
    parser.add_argument('--output', type=Path, help='Fresh receipt output; existing paths are refused')
    args = parser.parse_args()
    require(args.output is None or not args.output.exists(), 'Refusing existing output')
    receipt = replay(args.kind)
    rendered = json.dumps(receipt, indent=2) + '\n'
    if args.output is None:
        print(rendered, end='')
    else:
        with args.output.open('x') as stream:
            stream.write(rendered)
        print(f"{args.kind}: historical complete replay, 200 sources, "
              f"{receipt['exact_raw_outcome_comparisons']} comparisons, "
              f"{receipt['command_records']} contiguous commands")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
