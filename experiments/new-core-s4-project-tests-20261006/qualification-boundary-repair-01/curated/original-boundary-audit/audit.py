#!/usr/bin/env python3
"""Pure qualification reducers. Never launch a compiler or native executable."""
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
AREA = Path(__file__).resolve().parent
M = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests')
E = M.parent / 'codex-new-core-s4-emission'
S = M / 'experiments/new-core-s4-project-tests-20261006'
sys.path.insert(0, str(S))
import qualification_support as support
import conformance_checked as conform
import fuzz_matrix as fuzz


def saved(name, value):
    (AREA / name).write_text(json.dumps(value, indent=2) + '\n')


def report(status='passed'):
    value = {'version': 'native-tests-v1', 'tests': [{'name': 'app::test_one', 'status': status}]}
    value.update({key: int(key == status) for key in ('passed', 'cached', 'failed', 'skipped', 'unsupported')})
    return value


def main():
    sources = [S / name for name in ('qualification_support.py', 'conformance_checked.py',
        'project_matrix.py', 'fuzz_matrix.py', 'qualification_selftest.py')]
    strict_path = M / 'experiments/new-core-s3-20261006/wave-x/integration/fuzz_qualification.py'
    sources.append(strict_path)
    before = [support.identity(path) for path in sources]
    head_before = support.git(M, 'rev-parse', 'HEAD')
    fixture = AREA / 'fixtures'
    fixture.mkdir(exist_ok=False)
    known = json.loads((E / 'experiments/new-core-s4-emission-20261006/conformance-private-02/manifest.json').read_text())
    origin_path = M / 'experiments/new-core-s3-20261006/wave-b/s3-c/resume-context-corrected-oracle.json'
    origin = json.loads(origin_path.read_text())
    old, core = known['oracles']['old']['path'], known['oracles']['core']['path']
    args = argparse.Namespace(old_source='a16a324e629c1c68e0180017f6d2faf20364b13d',
        core_source=known['compiler_sources']['core'], zig=Path(known['tools']['zig']['path']),
        qbe=Path(known['tools']['qbe']['path']))
    environment = {key: os.environ.get(key) for key in ('MYLANG_ZIG', 'MYLANG_QBE', 'TMPDIR', 'ZIG_LOCAL_CACHE_DIR')}
    try:
        wrong = support.manifest(M, old, core, args, sources)
        wrongly_unchanged = support.unchanged(M, wrong)
        args.old_source = origin['source_commit']
        corrected = support.manifest(M, old, core, args, sources)
        assert wrong['oracles'] == corrected['oracles']
        assert wrong['compiler_sources']['old'] != corrected['compiler_sources']['old']
        assert origin['files'][0]['sha256'] == wrong['oracles']['old']['sha256']
        saved('source-label-red.json', {'fixture_kind': 'actual recorded artifact, metadata-only reducer',
            'compiler_processes': 0, 'wrong_label_accepted': True, 'wrong_label_unchanged': wrongly_unchanged,
            'wrong': wrong, 'correct_label_control': corrected,
            'original_source_receipt': support.identity(origin_path), 'original_source': origin['source_commit']})

        # Retaining copied input bytes does not guard the live paths used by commands.
        project = fixture / 'project'
        project.mkdir()
        leaf = project / 'leaf.my'
        leaf.write_text('module leaf\n\npublic def value() -> int:\n    return 7\n')
        snapshot = support.snapshot(project, AREA / 'project-before')
        live_before = support.identity(leaf)
        leaf.write_text('module leaf\n\npublic def value() -> int:\n    return 8\n')
        (project / 'app.cases.json').write_text('{}\n')
        live_after = support.identity(leaf)
        phase_unchanged = support.unchanged(M, corrected)
        assert live_before['sha256'] != live_after['sha256']
        saved('project-live-input-red.json', {'fixture_kind': 'owned synthetic input; no compiler processes',
            'snapshot': snapshot, 'live_before': live_before, 'live_after': live_after,
            'new_uninventoried_input': support.identity(project / 'app.cases.json'),
            'final_manifest_unchanged': phase_unchanged,
            'conclusion': 'snapshot path/hash describes retained copy; final guard excludes live project paths'})

        # Actual inherited strict Monitor uses source-path identity across old/Core builds.
        strict = fuzz.strict_wrapper()
        evidence, cache = fixture / 'fuzz-evidence', fixture / 'fuzz-cache'
        (evidence / 'sources').mkdir(parents=True)
        cache.mkdir()
        source = fixture / 'case.my'
        source.write_text('module case\n\ndef main() -> int:\n    for i in range(3):\n        pass\n    return 0\n')
        source_before = support.identity(source)
        synthetic_args = argparse.Namespace(kind='s0', cases=1, seed=1, old=Path(old).resolve(),
            new=Path(core).resolve(), evidence=evidence, cache_root=cache)
        simulated_calls = []

        def simulated_run(argv, *positional, **options):
            simulated_calls.append({'argv': argv, 'source_identity_at_call': support.identity(source)})
            return subprocess.CompletedProcess(argv, 0, b'0\n', b'')

        monitor = strict.Monitor(synthetic_args, simulated_run)
        modes = [('old', old, []), ('debug', core, []), ('release', core, ['--release']),
                 ('verify', core, ['--release', '--verify-facts'])]
        for role, executable, flags in modes:
            if role == 'debug':
                source.write_text('module case\n\ndef main() -> int:\n    return 0\n')
            output = fixture / ('guest-' + role)
            monitor.run([executable, 'build', str(source), '-o', str(output), *flags], capture_output=True)
            for arg in range(5):
                monitor.run([str(output), str(arg)], capture_output=True)
        monitor.journal.close()
        os.environ.update(TMPDIR=str(cache), ZIG_LOCAL_CACHE_DIR=str(cache))
        value = strict.s2.qualify(synthetic_args, monitor, 0, 'cases=1 compared=15 mismatch=0\n', None)
        arguments_per_case = 5
        native_complete = all(sum(item == case for item, _ in monitor.outcomes) == arguments_per_case
                              for case in monitor.cases) and all(
            set(outcomes) == {'old', *strict.MODES} for outcomes in monitor.outcomes.values())
        value.update(oracles={'old': corrected['oracles']['old'], 'new': corrected['oracles']['core']},
            oracle_unchanged=True, native_comparisons=monitor.comparisons, native_complete=native_complete)
        value['qualified'] = value['qualified'] and native_complete and monitor.comparisons == value['comparisons_expected']
        accepted = fuzz.qualified_kind(0, value, 's0', 1, value['oracles'])
        assert accepted
        assert support.identity(source) != source_before
        saved('fuzz-source-mutation-red.json', {'fixture_kind': 'synthetic CompletedProcess results; NO compiler/native processes',
            'before': source_before, 'after': support.identity(source),
            'retained_first_source': support.identity(next(iter(monitor.retained.values()))),
            'simulated_calls': simulated_calls, 'strict_report': value, 'matrix_predicate_accepts': accepted})

        # Report producer defines executed = passed + failed, dropped/unloaded imply nonzero setup status.
        for field, value in (('executed', 0), ('dropped', 1), ('unloaded', 1)):
            inconsistent = {**report(), field: value}
            counts = conform.validate_report(inconsistent, 0, allow_cached=False)
            saved('report-' + field + '-red.json', {'fixture_kind': 'pure synthetic report',
                'report': inconsistent, 'status': 0, 'validator_accepts': True, 'counts': dict(counts)})

        # Full selection checks coverage/modes but does not require leak/verification options.
        baseline = conform.baseline_table(conform.BASELINE.read_text())
        sweep = conform.imported('audit_sweep', M / 'experiments/new-core-s1-20261005/conformance.py')
        opts = argparse.Namespace(set='all', include_arena=False, files=[], modes='debug,release',
            leakcheck=False, verify=False)
        expected, total = conform.selection(sweep, opts, baseline['counts'], None)
        rows = [{'file': name, 'tests': count, 'problems': [], 'modes': {
            mode: {'match': count, 'mismatch': 0, 'unsupported': 0} for mode in ('debug', 'release')}}
            for name, count in expected.items()]
        conform.coverage(rows, expected, ['debug', 'release'], total)
        saved('full-mode-flags-red.json', {'fixture_kind': 'pure selection and synthetic coverage rows',
            'set': 'all', 'modes': ['debug', 'release'], 'tests_per_mode': total,
            'leakcheck': False, 'verify': False, 'selection_and_coverage_accept': True,
            'limit': 'generic qualified currently also describes diagnostic selections; caller may enforce final flags'})
    finally:
        for key, value in environment.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
    after = [support.identity(path) for path in sources]
    head_after = support.git(M, 'rev-parse', 'HEAD')
    saved('summary.json', {'schema': 's4-qualification-boundary-audit-v1', 'compiler_processes': 0,
        'native_processes': 0, 'sources': before, 'source_bytes_unchanged': before == after,
        'head_before': head_before, 'head_after': head_after, 'head_unchanged': head_before == head_after,
        'tracked_status': support.git(M, 'status', '--porcelain', '--untracked-files=no'),
        'reductions': ['source-label', 'project-live-input', 'fuzz-source-mutation', 'report-executed',
                       'report-dropped', 'report-unloaded', 'full-mode-flags']})
    assert before == after
    print('Pure reductions complete; no compiler/native process launched.')


if __name__ == '__main__':
    main()
