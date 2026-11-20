#!/usr/bin/env python3
"""Rebuild the default shard plans from three retained gate cohorts; scheduling hints only.

A cohort is the `last-run.json` of one complete compiler-edit gate (`verify_cache.py --profile complete`).
Its `actions[].test_telemetry` holds one protocol-observed member per shard; a test's weight is the median
of its three passed-test intervals, and every test must pass in exactly one member of each cohort. The
plans are LPT partitions (verification_shard_plan.assign). They are scheduling hints, never verdicts: every
test still runs exactly once in whichever shard the plan names (Guardian's partition check).

The cohort reports live in the evidence archive (SELKA_GATE_COHORTS, default
../mylang-evidence-archive/experiments/gate-schedule-20261028); their hashes are recorded in provenance.json.
"""
from collections import Counter
import gzip
import hashlib
import json
import os
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import verification_shard_plan as planner

ARCHIVE = Path(os.environ.get('SELKA_GATE_COHORTS', ROOT.parent / 'mylang-evidence-archive/experiments/gate-schedule-20261028'))
# Cohort run directories under ARCHIVE; SELKA_GATE_COHORT_RUNS selects three others (comma-separated).
COHORT_RUNS = tuple(name for name in os.environ.get('SELKA_GATE_COHORT_RUNS', 'before-1,before-2,before-3').split(',') if name)
# Tests deleted since the cohorts ran (`retired.json`, by root label): a rebuilt plan leaves them out.
RETIRED = json.loads((HERE / 'retired.json').read_text()) if (HERE / 'retired.json').exists() else {}
# The probe test `experiments/compiler-dev-loop-20261028/m0_edit.py` appends to a source file carries the edit's tag in its name, so
# it differs between measured gates and is in no plan: cohorts of such gates are compared without it.
PROBE_TESTS = '.test.gate profile probe: '
# action id, test root identity, shard count
ROOTS = (('core', 'src/core/root_test.zig', 10), ('unit', 'src/root_test.zig', 12), ('cli', 'test/integration.zig', 6))


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def load_cohort(label, root, count, run):
    """Validate one cohort's shards and return its report, exact-once passed set and archive digest."""
    path = ARCHIVE / run / 'last-run.json.gz'
    raw = gzip.decompress(path.read_bytes())
    report = json.loads(raw)
    require(report.get('success') is True and report.get('inputs_stable') is True, 'unsuccessful cohort ' + run)
    actions = [action for action in report['actions'] if action.get('id') == label]
    require(len(actions) == 1 and actions[0].get('state') == 'execute', label + ' did not execute in ' + run)
    members = actions[0].get('test_telemetry', [])
    require(len(members) == count, 'wrong member count for %s in %s' % (label, run))
    passed, seen = Counter(), set()
    for member in members:
        require(member.get('status') == 'observed' and member.get('complete') is True
                and member.get('producer') == 'zig-test-protocol-v1', 'invalid native telemetry in ' + run)
        require(all(row['state'] in ('passed', 'skipped') for row in member['tests']), 'failed test in ' + run)
        require(member.get('selected') == len(member['tests']), 'incomplete selection in ' + run)
        seen.update(row['test_id'] for row in member['tests'] if PROBE_TESTS not in row['test_id'])
        passed.update(row['test_id'] for row in member['tests'] if row['state'] == 'passed' and PROBE_TESTS not in row['test_id'])
    require(all(value == 1 for value in passed.values()), 'non-exact-once passed tests in ' + run)
    require(set(passed) <= seen and all(name.startswith(root + '::') for name in seen), 'foreign test identity in ' + run)
    return report, frozenset(passed), dict(run=run, file=str(path.relative_to(ARCHIVE)),
                                             sha256=hashlib.sha256(raw).hexdigest())


def main():
    require(len(COHORT_RUNS) == 3, 'a shard plan needs exactly three cohorts')
    provenance = dict(scope='scheduling hints from three compiler-edit gate cohorts; predicted, not measured shard walls',
                      cohorts=list(COHORT_RUNS), roots={})
    for label, root, count in ROOTS:
        reports, expected, digests = [], None, []
        for run in COHORT_RUNS:
            report, passed, digest = load_cohort(label, root, count, run)
            if expected is None:
                expected = passed
            require(passed == expected, 'cohort coverage differs in ' + run)
            reports.append(report)
            digests.append(digest)
        times, samples = planner.median_observations(reports, root)
        retired = set(RETIRED.get(label, ()))
        times = {name: weight for name, weight in times.items() if name not in retired}
        named = sorted(name for name in expected if '.test.' in name and name not in retired)
        require(len(times) == len(named), 'some named tests have fewer than three samples in ' + label)
        plan, summary = planner.assign(times, count, root)
        path = HERE / (label + '.json')
        path.write_text(json.dumps(plan, indent=2, sort_keys=True) + '\n')
        summary.update(samples, exact_once_per_cohort=len(expected), cohort_digests=digests,
                       plan_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                       weighting='per-test median of three compiler-edit gate cohorts (passed-test protocol intervals)')
        summary.pop('samples_per_test', None)
        provenance['roots'][label] = summary
    (HERE / 'provenance.json').write_text(
        json.dumps(provenance, indent=2, sort_keys=True) + '\n')
    print(json.dumps({label: {key: row[key] for key in ('observed_named_tests', 'exact_once_per_cohort', 'longest_first', 'max_to_lower_bound')}
                      for label, row in provenance['roots'].items()}, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
