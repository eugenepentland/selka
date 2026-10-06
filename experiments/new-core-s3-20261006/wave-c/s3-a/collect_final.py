#!/usr/bin/env python3
"""Check final A receipts and record the source, compiler and input provenance."""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import subprocess

from review_word35 import imported

ROOT = Path(__file__).resolve().parents[4]
AREA = Path(__file__).resolve().parent
SOURCE = '203c0ca6100344304cbd9fd20d22cc7f9448a145'
BASE = 'f1319a774d638c664de9f02bb27098650a13249b'


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name):
    return json.loads((AREA / name).read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), 'retain prior receipts'
    gate = imported(ROOT / 'experiments/new-core-s2-20261005/wave-b/integration/full_old_gate.py')
    rows = imported(AREA / 'measure_all40.py')
    receipt = dict(qualified=False, source=SOURCE, base=BASE, error=None)
    try:
        gate.source_unchanged(ROOT, SOURCE)
        assert not git('diff', BASE, '--', 'src/core/ir.zig', 'src/core/own.zig', 'tests/lang')
        receipt['protected_paths_unchanged'] = ['src/core/ir.zig', 'src/core/own.zig', 'tests/lang']
        inputs = git('diff', '--name-only', BASE, SOURCE, '--', '.', ':!experiments').splitlines()
        receipt['source_inputs_sha256'] = {name: digest(ROOT / name) for name in inputs}
        receipt['compiler_sha256'] = digest(ROOT / 'zig-out/bin/mylang-core')
        receipt['oracle_sha256'] = {name: digest(ROOT / '.mylang-cache/s3-a/oracle' / name) for name in ('mylang', 'qbe')}
        assert receipt['oracle_sha256'] == dict(mylang='d36658dbfb78d29213224532a13fd5ad8b7c0e290dbfb87613d9815678305c79',
                                              qbe='b6139650a99b39131cd791fa1fdc84c09472dc303930bbadd3f8a5348487af4c')
        receipt['formats'] = dict(module_interface='module-interface-v5', check_summaries='check-summaries-v6', mutation='mutation-v2')
        for name, expected in [('module_interface.zig', 'module-interface-v5'), ('semantic_summary.zig', 'check-summaries-v6'), ('semantic_cache.zig', 'mutation-v2')]:
            assert expected in (ROOT / 'src' / name).read_text()
        receipt['exclusive_core_seconds'] = float((AREA / 'logs/core-trace-combined-11.time').read_text())
        assert receipt['exclusive_core_seconds'] <= 10
        core = load('trace-combined-core64-review-04.json')
        assert core['qualified'] and core['source'] == SOURCE and core['verdicts'] == 64
        assert core['tests'] == dict(passed=276, failed=0, skipped=0)
        assert core['seconds'] <= 300 and core['max_shard_seconds'] <= 90 and not core['build_inspection']['errors']
        receipt['core64'] = core
        conformance = (AREA / 'logs/trace-combined-full-conformance-06.txt').read_text()
        modes = re.findall(r'(debug|release)\s+matching (\d+), mismatching (\d+), unsupported (\d+)', conformance)
        assert modes == [('debug', '1518', '0', '0'), ('release', '1518', '0', '0')]
        receipt['strict_conformance'] = dict(modes=modes, leakcheck=True, verify=True,
            seconds=float((AREA / 'logs/trace-combined-full-conformance-06.time').read_text()))
        measure = load('all40-combined-final-03.json')
        assert measure['valid'] and measure['cpu'] == 10 and measure['rounds'] == 7
        assert set(measure['rows']) == set(rows.UNITS) and measure['all_within_both_limits']
        assert not measure['speed_gate_misses'] and not measure['old_gate_misses'] and not measure['zig_gate_misses']
        receipt['performance'] = {}
        for name, row in measure['rows'].items():
            assert set(row['sizes']) == {'4096', '64'}
            receipt['performance'][name] = {}
            for size, cell in row['sizes'].items():
                assert cell['within_both_limits'] and cell['within_old_limit'] and cell['within_zig_limit']
                assert all(math.isfinite(cell[field]) and 0 < cell[field] <= 1.10 for field in ('new_over_old', 'new_over_zig'))
                receipt['performance'][name][size] = {key:cell[key] for key in ('new_over_old', 'new_over_zig', 'within_both_limits')}
        receipt['measurement_seconds'] = float((AREA / 'logs/all40-combined-final-03.time').read_text())
        binaries = ROOT / '.mylang-cache/s3-a/all40-combined-final-03'
        receipt['measured_binaries_sha256'] = {f'{rows.stem(row)}_{kind}':digest(binaries / f'{rows.stem(row)}_{kind}') for row in rows.UNITS for kind in ('old', 'new')}
        receipt['measured_llvm_sha256'] = {rows.stem(row):digest(binaries / 'llvm' / f'{rows.stem(row)}.ll') for row in rows.UNITS}
        references = Path(rows.S1.DEFAULT_RUNNER)
        receipt['reference_binaries_sha256'] = {path.name:digest(path) for path in sorted(references.iterdir()) if path.is_file() and path.name.endswith(('-rust', '-zig-safe'))}
        reference_root = references.parents[3]
        receipt['reference_worktree'] = str(reference_root)
        receipt['reference_source'] = subprocess.check_output(['git', '-C', str(reference_root), 'rev-parse', 'HEAD'], text=True).strip()
        receipt['reference_workload_sources_sha256'] = {f'{suite}/main.{kind}':digest(reference_root / f'benchmarks/runtime/expanded/{suite}/main.{kind}') for suite in ('text', 'compute', 'collections') for kind in ('rs', 'zig')}
        apps = load('qualification-combined-final-02/summary.json')
        assert apps['qualified'] and apps['native_executions'] == 137 and apps['source_head'] == SOURCE
        receipt['strict_app_native'] = dict(qualified=True, native_executions=137, modes=['old', 'debug', 'release', 'verify'], leakcheck=True)
        split = load('split-qualification-combined-final-03/summary.json')
        assert split['qualified'] and split['runs'] == ['old', 'debug', 'release', 'verify']
        receipt['pinned_split'] = split
        proof = load('combined35-final-04/summary.json')
        assert proof['qualified'] and proof['source'] == SOURCE and len(proof['rows']) == 35
        assert proof['exact_scalar_stores'] == 6 and proof['exact_trace_calls'] == 2
        assert proof['definitions'] == 343
        receipt['original35'] = dict(qualified=True, rows=35, definitions=343, scalar_stores=6, trace_calls=2, residual=0, full_module_remainders_exact=True)
        split50 = load('fuzz-split-cursor-50-02/summary.json')
        assert split50['qualified'] and split50['compared'] == 750 and split50['mismatch'] == 0
        receipt['split50'] = split50
        old = load('old-gate-combined-final-03/summary.json')
        assert old['qualified'] and old['complete'] and old['source_commit'] == SOURCE
        assert [result['step'] for result in old['results']] == list(gate.STEPS)
        assert all(result['qualified'] and result['exit'] == 0 and not result['errors'] for result in old['results'])
        receipt['full_old_gate'] = old
        scratch = load('old-gate-scratch-tool-03.json')
        assert scratch['source'] == SOURCE
        assert scratch['tool_sha256'] == digest(Path(scratch['tool']))
        preflight = load(scratch['focused_preflight'])
        assert preflight['qualified'] and preflight['source'] == SOURCE
        assert [result['name'] for result in preflight['results']] == ['incremental-120', 'incremental-project-60']
        assert all(result['exit'] == 0 for result in preflight['results'])
        assert Path(preflight['scratch']).parent == Path('/var/tmp')
        receipt['old_gate_tool_provenance'] = scratch
        receipt['old_gate_focused_preflight'] = preflight
        receipt['superseded_tool_receipts'] = load('superseded-tool-receipts-01.json')
        receipt['qualified_sibling_heads'] = dict(packet='d8921b419c2bf3aa0932a728bc7a3f9cf0344f3c', character='0ecd89913b6ab4ce8490f280647906cc316804fd', trace='fb9f72c6da4c0d5e24b429c3e307d5518046003f')
        receipt['retained_failed_performance'] = ['all40-combined-final-01.json', 'word-packet-combined-paired-02.json']
        receipt['s3_exit_qualified'] = False
        receipt['s3_exit_pending'] = 'coordinator final integrated S3-X gates and section 7/S4 decision'
        receipt['qualified'] = True
    except Exception as error:
        receipt['error'] = str(error)
        raise
    finally:
        args.output.write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
