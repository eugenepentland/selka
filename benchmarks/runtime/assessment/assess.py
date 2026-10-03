#!/usr/bin/env python3
"""Assess saved runtime evidence by operation family; never execute a benchmark."""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath
import re
import random
import statistics
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EXPANDED = HERE.parent / 'expanded'
DEFAULT_BASELINE = EXPANDED / 'results/baseline_main_20261003.json'
DEFAULT_BASELINE_SHA256 = 'b595d9638e243e18692b5cef491c2b5273949c93ebf22a0ae604a08704c1d3f7'
HISTORICAL_REVISION = 'b725360f5f86ac67bc405db9407ae51c332a9931'
ARMS = ('my-llvm', 'my-qbe', 'rust', 'go', 'zig-safe', 'zig-fast')
APPLICATIONS = ('word_count', 'csv_aggregate', 'json_transform', 'packet_decode', 'lox_eval')
SCHEMA = 'mylang-runtime-family-assessment-v2'

sys.path.insert(0, str(EXPANDED))
spec = importlib.util.spec_from_file_location('assessment_expanded_verifier', EXPANDED / 'verify.py')
independent_verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(independent_verifier)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_verified(path, expected_hash, verifier=None):
    raw = path.read_bytes()
    require(re.fullmatch(r'[0-9a-f]{64}', expected_hash) is not None, 'invalid expected baseline SHA256')
    require(sha(raw) == expected_hash, 'baseline SHA256 mismatch; input is not the selected immutable baseline')
    report = json.loads(raw)
    count = (verifier or independent_verifier.verify)(report, artifacts=False)
    return report, count


def historical_source_audit(identity, revision, repo):
    """Audit recorded measurement-source bytes using Git objects, never live files."""
    require(re.fullmatch(r'[0-9a-f]{40}', revision) is not None, 'historical revision must be a full Git commit SHA')
    rows = []
    for name, expected in sorted(identity['sources'].items()):
        relative = PurePosixPath(name)
        require(not relative.is_absolute() and '..' not in relative.parts, 'invalid historical source path')
        command = ['git', '-C', str(repo), 'show', revision + ':benchmarks/runtime/' + name]
        try:
            done = subprocess.run(command, capture_output=True, timeout=30)
        except (OSError, subprocess.TimeoutExpired) as error:
            rows.append({'path': name, 'expected_sha256': expected, 'status': 'unavailable', 'reason': str(error)})
            continue
        if done.returncode:
            rows.append({'path': name, 'expected_sha256': expected, 'status': 'unavailable',
                         'reason': done.stderr.decode(errors='replace').strip()})
            continue
        actual = sha(done.stdout)
        require(actual == expected, 'historical measurement source mismatch: ' + name)
        rows.append({'path': name, 'expected_sha256': expected, 'git_blob_sha256': actual, 'status': 'verified'})
    require(rows, 'no historical measurement sources recorded')
    return {'revision': revision, 'method': 'git show COMMIT:benchmarks/runtime/PATH; SHA256 of blob bytes',
            'status': 'verified_historical_sources' if all(r['status'] == 'verified' for r in rows)
                      else 'historical_sources_unavailable_or_incomplete',
            'current_artifacts_checked': False, 'sources': rows}


def classify(interval, fastest):
    require(isinstance(interval, list) and len(interval) == 2, 'invalid paired confidence interval')
    low, high = interval
    require(all(type(value) in (float, int) and math.isfinite(value) and value > 0 for value in interval)
            and low <= high, 'invalid paired confidence interval')
    if fastest:
        return 'fastest'
    return 'slower' if low > 1 else 'interval_below_reference' if high < 1 else 'overlapping'


def bootstrap_ratio_interval(values, reference_values, seed, resamples=2000):
    """Resample paired round indexes and divide the two resampled medians."""
    require(len(values) == len(reference_values) and bool(values), 'missing paired raw rounds')
    rng = random.Random(seed)
    estimates = []
    for _ in range(resamples):
        indexes = [rng.randrange(len(values)) for _ in values]
        numerator = statistics.median([values[index] for index in indexes])
        denominator = statistics.median([reference_values[index] for index in indexes])
        estimates.append(numerator / denominator)
    estimates.sort()
    return [estimates[int(resamples*.025)-1], estimates[int(resamples*.975)-1]]


def validate_coverage(report, taxonomy):
    """Reject omissions, duplicate cells and unit drift before deriving any assessment."""
    inventory = report['inventory']
    require(len(inventory) == 40, 'assessment requires the documented 40 cases')
    require(len(taxonomy['areas']) == 8, 'assessment requires eight operation families')
    assigned = [case for cases in taxonomy['areas'].values() for case in cases]
    micros = {case for case, meta in inventory.items() if meta['level'] == 'micro'}
    applications = {case for case, meta in inventory.items() if meta['level'] == 'application'}
    require(len(assigned) == len(set(assigned)) and set(assigned) == micros, 'wrong or duplicate micro case coverage')
    require(applications == set(APPLICATIONS) == set(taxonomy['applications']), 'wrong application case coverage')
    require(set(report['coverage']) == set(inventory) and len(report['coverage']) == 40, 'baseline case coverage mismatch')
    wanted = {(case, size, profile): meta for case, meta in inventory.items()
              for size, profile in zip(meta['sizes'], ('small', 'large'))}
    plans = {}
    for plan in report['plans']:
        key = (plan['case'], plan['size'], plan['profile'])
        require(key in wanted and key not in plans, 'missing/duplicate/unknown plan coverage')
        require(plan['unit'] == wanted[key]['unit'] and plan['level'] == wanted[key]['level'], 'plan units or level mismatch')
        require(isinstance(plan['unit'], str) and bool(plan['unit']), 'empty iteration unit')
        plans[key] = plan
    require(set(plans) == set(wanted), 'incomplete small/large plan coverage')
    expected = {(*key, arm) for key in wanted for arm in ARMS}
    seen = set()
    for row in report['summary']:
        key = (row['case'], row['size'], row['profile'], row['arm'])
        require(key in expected and key not in seen, 'missing/duplicate/unknown summary coverage')
        require(row['iterations'] == plans[key[:3]]['iterations'], 'summary iteration unit mismatch')
        seen.add(key)
    require(seen == expected, 'incomplete all-six-arm small/large comparison coverage')
    return plans


def comparison_rows(report, plans):
    raw = {}
    for sample in report['samples']:
        key = (sample['case'], sample['size'], sample['profile'], sample['arm'])
        by_round = raw.setdefault(key, {})
        require(sample['round'] not in by_round, 'duplicate raw round')
        value = sample['kernel_ns']
        require(type(value) in (int, float) and math.isfinite(value) and value > 0, 'invalid raw kernel time')
        by_round[sample['round']] = value
    summary_times = {(r['case'], r['size'], r['profile'], r['arm']): r['median_ns_per_op'] for r in report['summary']}
    references = {}
    for key, plan in plans.items():
        medians = {}
        for arm in ARMS:
            rounds = raw.get((*key, arm), {})
            require(set(rounds) == set(range(report['rounds'])), 'missing paired raw rounds')
            value = summary_times[(*key, arm)]
            require(type(value) in (float, int) and math.isfinite(value) and value > 0, 'invalid median time')
            require(math.isclose(value, statistics.median(rounds.values()) / plan['iterations'], rel_tol=1e-12), 'summary median differs from raw samples')
            medians[arm] = value
        minimum = min(medians.values())
        fastest = [arm for arm in ARMS if medians[arm] == minimum]
        references[key] = (fastest[0], fastest, minimum, medians)
    result = []
    for row in report['summary']:
        key = (row['case'], row['size'], row['profile'])
        plan = plans[key]
        reference, fastest, minimum, medians = references[key]
        ns = row['median_ns_per_op']
        require(type(ns) in (float, int) and math.isfinite(ns) and ns > 0, 'invalid median time')
        require(math.isclose(ns, medians[row['arm']], rel_tol=1e-12), 'summary median differs from raw samples')
        ratio = medians[row['arm']] / minimum
        values = [raw[(*key, row['arm'])][rnd] for rnd in range(report['rounds'])]
        reference_values = [raw[(*key, reference)][rnd] for rnd in range(report['rounds'])]
        interval = [1.0, 1.0] if row['arm'] == reference else bootstrap_ratio_interval(
            values, reference_values, f"{row['case']}/{row['size']}/{row['arm']}/fastest/{reference}/ratio-of-medians/bootstrap")
        retained = {name: value for name, value in row.items()
                    if name not in ('median_paired_ratio_to_go', 'paired_bootstrap_95_interval', 'classification_vs_go')}
        result.append({**retained, 'unit': plan['unit'], 'level': plan['level'],
                       'median_us_per_iteration': ns / 1000, 'ratio_to_fastest': ratio,
                       'reference_arm': reference, 'fastest_arms': fastest,
                       'reference_median_ns_per_iteration': minimum,
                       'bootstrap_95_interval_to_fastest': interval,
                       'classification_vs_fastest': classify(interval, row['arm'] in fastest),
                       'calibration': plan['calibration']})
    return result


def family_statistics(rows):
    stats = {}
    for arm in ARMS:
        chosen = [row for row in rows if row['arm'] == arm]
        require(chosen, 'family has no comparisons for ' + arm)
        counts = Counter(row['classification_vs_fastest'] for row in chosen)
        worst = max(chosen, key=lambda r: r['ratio_to_fastest'])
        stats[arm] = {'test_profile_comparisons': len(chosen),
                      'counts': {name: counts[name] for name in ('fastest', 'overlapping', 'slower', 'interval_below_reference')},
                      'ratio_to_fastest_range': [min(r['ratio_to_fastest'] for r in chosen),
                                                   max(r['ratio_to_fastest'] for r in chosen)],
                      'worst_observed_comparison':
                      {key: worst[key] for key in ('case', 'profile', 'size', 'unit', 'reference_arm', 'fastest_arms', 'ratio_to_fastest',
                                                   'bootstrap_95_interval_to_fastest', 'classification_vs_fastest')}}
    return stats


def build_assessment(report, taxonomy, baseline_path, expected_hash, audit, verifier_groups):
    plans = validate_coverage(report, taxonomy)
    rows = comparison_rows(report, plans)
    families = []
    for family, cases in taxonomy['areas'].items():
        chosen = [row for row in rows if row['case'] in cases]
        families.append({'family': family, 'cases': cases,
                         'qualitative_review': taxonomy.get('family_review', {}).get(family, {}),
                         'statistics_by_arm': family_statistics(chosen),
                         'statistics_by_profile': {profile: family_statistics([r for r in chosen if r['profile'] == profile]) for profile in ('small', 'large')},
                         'individual_comparisons': chosen})
    apps = [{'case': case, 'unit': report['inventory'][case]['unit'],
             'operation_families': taxonomy['applications'][case],
             'qualitative_review': taxonomy.get('application_review', {}).get(case, {}),
             'large_profile': [row for row in rows if row['case'] == case and row['profile'] == 'large'],
             'small_profile': [row for row in rows if row['case'] == case and row['profile'] == 'small']}
            for case in APPLICATIONS]
    return {'schema': SCHEMA, 'status': 'assessment_complete',
            'input': {'baseline_path': str(baseline_path), 'baseline_sha256': expected_hash,
                      'baseline_schema': report['schema'], 'started_utc': report.get('started_utc'),
                      'measurement_started_utc': report.get('measurement_started_utc'), 'finished_utc': report.get('finished_utc')},
            'evidence_verification': {'independent_verifier': str(EXPANDED / 'verify.py'),
                                      'independent_verifier_sha256': sha((EXPANDED / 'verify.py').read_bytes()),
                                      'result': 'passed', 'groups': verifier_groups, 'artifacts': False,
                                      'historical_measurement_sources': audit,
                                      'compiler_source_revision_recorded': report['identity'].get('source_revision')
                                          or report['identity']['pinned_revision'],
                                      'compiler_source_equivalence_established_by_this_tool': False,
                                      'generator_sha256': sha(Path(__file__).read_bytes())},
            'interpretation': {'breadth_goal': '80% is a qualitative design aspiration for representative everyday-codebase breadth; no population percentage or CPU-time coverage is measured.',
                               'reference_selection': 'For each case and size, select the lowest observed median kernel time per iteration among all six configurations. All exact median ties are fastest; the first tied arm in ARMS order is the fixed bootstrap reference. Never select a different winner for each round.',
                               'bootstrap': '2,000 paired-round index resamples; each replicate divides the arm median by the fixed-reference median. Percentile endpoints use sorted indexes 49 and 1949. Deterministic seeds include case/size/arm/reference. Exploratory intervals condition on the observed winner and do not account for winner selection.',
                               'classification': 'Exact observed median winners are fastest. For other arms, intervals wholly above 1 are slower, intervals containing 1 are overlapping, and intervals wholly below 1 are explicitly interval_below_reference despite the observed point ratio being at least 1. This is descriptive evidence, not an equivalence proof or acceptance threshold; multiple comparisons are not adjusted.',
                               'counts_scope': 'Counts describe these selected test/profile comparisons only, not percentages of real codebases or operation frequencies.',
                               'weights': None, 'overall_language_score': None, 'new_acceptance_thresholds': None,
                               'taxonomy_review': taxonomy.get('interpretation'),
                               'confidence_gaps': taxonomy.get('confidence_gaps'),
                               'excluded_workloads': taxonomy.get('excluded_workloads'),
                               'notes': ['alloc_short permits optimizer elimination of nonescaping allocations; fastest saved pilots are exceptionally short. It is not evidence for the cost of physical allocation.',
                                         'sort_int/sort_records use each language native sorting API and compare language/library policies, rather than one identical algorithm.',
                                         'Ownership, snapshot, copy-on-write, reference-counting, GC and allocator semantics differ as documented; equivalent observable behavior does not imply equivalent physical copying.',
                                         'Optimized default build policies use different instruction sets across arms. Rust default x86_64 and Go v1 differ from default Zig/Clang-derived host features.',
                                         'Intervals use paired raw resampling of ratio-of-medians against a fixed observed winner, not transformed Go-relative intervals. Winner-selection uncertainty is not included. Paired intervals and raw spread describe the saved run. They do not guarantee performance on another machine, input, lifetime or workload.']},
            'inventory': report['inventory'], 'rounds': report['rounds'], 'warmup_rounds': report['warmup_rounds'],
            'target_policy': report['identity']['target_policy'],
            'environment': {key: value for key, value in report['environment'].items() if key != 'cpuinfo'},
            'families': families, 'applications': apps,
            'calibration_limits': [{key: plan[key] for key in ('case', 'size', 'profile', 'iterations', 'unit', 'calibration')}
                                   for plan in report['plans'] if plan['calibration']['limited']],
            'appendix_all_comparisons': rows}


def cell(value):
    return str(value).replace('|', '\\|').replace('\n', ' ')


def comparison_cell(row, time=False):
    lo, hi = row['bootstrap_95_interval_to_fastest']
    label = row['classification_vs_fastest']
    ratio = row['ratio_to_fastest']
    prefix = f"{row['median_us_per_iteration']:.3f} µs; " if time else ''
    display = '1.00' if ratio == 1 else f'{ratio:.3f}'
    return prefix + f'{display}× [{lo:.3f}–{hi:.3f}] {label}'


def narrative(value):
    return value if isinstance(value, str) else '; '.join(value)

def protect_inputs(output, inputs):
    targets = (output.resolve(), output.with_suffix('.md').resolve())
    protected = {path.resolve() for path in inputs}
    require(not any(target in protected or EXPANDED.resolve() in target.parents for target in targets),
            'assessment output must preserve baseline, profiles and taxonomy')

def markdown(report):
    verification = report['evidence_verification']
    lines = ['# Runtime operation-family assessment', '',
             report['interpretation']['breadth_goal'], '',
             'The saved baseline was independently verified: 40 cases, two sizes, all six configurations, '
             f"{report['rounds']} sample rounds and {report['warmup_rounds']} warmups. No benchmark was rerun. "
             'This assessment adds no acceptance gate, population weighting or overall language score.', '',
             report['interpretation']['reference_selection'], '', report['interpretation']['bootstrap'], '',
             report['interpretation']['classification'], '', report['interpretation']['counts_scope'], '',
             f"Baseline SHA256: `{report['input']['baseline_sha256']}`. Historical measurement sources: "
             f"**{verification['historical_measurement_sources']['status']}** at "
             f"`{verification['historical_measurement_sources']['revision']}`. Current artifacts were not checked. "
             f"Recorded compiler source revision: `{verification['compiler_source_revision_recorded']}`; "
             'this tool does not independently establish compiler-source equivalence.', '']
    for note in report['interpretation']['notes']:
        lines.append('- ' + note)
    lines += ['', '## Eight operation families', '',
              'Family counts include small and large profiles separately. Each case/profile uses its own fixed observed fastest reference. '
              'Ranges and worst cases refer to individual ratios of observed medians, not a pooled average. '
              'Every cell below is ratio to fastest [95% paired bootstrap interval] and classification; exact per-iteration times and units follow in the appendix.', '']
    for family in report['families']:
        lines += ['### ' + family['family'].replace('_', ' '), '']
        review = family['qualitative_review']
        for name in ('covers', 'limits'):
            values = review.get(name)
            if values:
                lines += [name.capitalize() + ': ' + narrative(values) + '.', '']
        lines += ['| Arm | Fastest | Overlapping | Slower | Interval below reference | Ratio-to-fastest range | Worst observed case / profile |',
                  '|---|---:|---:|---:|---:|---:|---|']
        for arm, stat in family['statistics_by_arm'].items():
            counts = stat['counts']; low, high = stat['ratio_to_fastest_range']; worst = stat['worst_observed_comparison']
            name = f"{worst['case']} / {worst['profile']} ({worst['ratio_to_fastest']:.3f}×)"
            lines.append(f"| {arm} | {counts['fastest']} | {counts['overlapping']} | {counts['slower']} | {counts['interval_below_reference']} | {low:.3f}–{high:.3f}× | {name} |")
        lines += ['', '| Case / profile | Fastest arm(s); interval reference | ' + ' | '.join(ARMS) + ' |', '|---|---|' + '---|' * len(ARMS)]
        rows = family['individual_comparisons']
        for case in family['cases']:
            for profile in ('small', 'large'):
                selected = {r['arm']: r for r in rows if r['case'] == case and r['profile'] == profile}
                winner = selected[ARMS[0]]
                lines.append('| ' + case + ' / ' + profile + ' | ' + ', '.join(winner['fastest_arms']) + '; ' + winner['reference_arm'] + ' | ' + ' | '.join(comparison_cell(selected[a]) for a in ARMS) + ' |')
        lines.append('')
    lines += ['## Five composed applications', '',
              'Large-profile whole-job median time in microseconds; ratio to fastest and 95% paired bootstrap interval. '
              'Each application keeps its own unit and interpretation. Both sizes appear in the full appendix.', '',
              '| Application / large size | Unit | Fastest arm(s); interval reference | ' + ' | '.join(ARMS) + ' |', '|---|---|---|' + '---|' * len(ARMS)]
    for app in report['applications']:
        selected = {r['arm']: r for r in app['large_profile']}
        winner = selected[ARMS[0]]
        lines.append(f"| {app['case']} / {winner['size']} | {cell(app['unit'])} | " + ', '.join(winner['fastest_arms']) + '; ' + winner['reference_arm'] + ' | ' + ' | '.join(comparison_cell(selected[a], time=True) for a in ARMS) + ' |')
    lines.append('')
    for app in report['applications']:
        review = app['qualitative_review']
        for name in ('represents', 'limits'):
            values = review.get(name)
            if values:
                lines += [app['case'] + ' ' + name + ': ' + narrative(values) + '.', '']
    lines += ['## Calibration limits', '',
              f"{len(report['calibration_limits'])} profiles missed their requested fastest-arm target. "
              'The saved reason slowest_arm_budget also covers growth below 5%, even when close to the target; '
              'it does not establish that every such profile hit a hard time cap.', '',
              '| Case / profile | Iterations | Fastest pilot ms | Slowest pilot ms | Reason |', '|---|---:|---:|---:|---|']
    for plan in report['calibration_limits']:
        c = plan['calibration']
        lines.append(f"| {plan['case']} / {plan['profile']} | {plan['iterations']} | {c['fastest_ns']/1e6:.3f} | {c['slowest_ns']/1e6:.3f} | {c['reason']} |")
    lines += ['', '## Breadth gaps and excluded workloads', '']
    for label, key in (('Confidence gaps', 'confidence_gaps'), ('Excluded workloads', 'excluded_workloads')):
        values = report['interpretation'].get(key)
        if values: lines += [label + ': ' + narrative(values) + '.', '']
    lines += ['', '## Full small/large appendix', '',
              'Times are per documented CLI iteration, which may be a complete dataset/job rather than one scalar primitive. '
              'Raw observed min/max remain attached to each comparison. Lower ratios are faster; no units are pooled.', '',
              '| Case / profile / size | Level | Unit | Arm | Median µs/iteration | Min–max µs | Fastest arm(s); interval reference | Ratio to fastest [95% interval] | Classification |',
              '|---|---|---|---|---:|---:|---|---:|---|']
    for row in report['appendix_all_comparisons']:
        low, high = row['bootstrap_95_interval_to_fastest']
        lines.append(f"| {row['case']} / {row['profile']} / {row['size']} | {row['level']} | {cell(row['unit'])} | {row['arm']} | {row['median_us_per_iteration']:.6f} | {row['min_ns_per_op']/1000:.6f}–{row['max_ns_per_op']/1000:.6f} | {', '.join(row['fastest_arms'])}; {row['reference_arm']} | {row['ratio_to_fastest']:.2f}× [{low:.3f}–{high:.3f}] | {row['classification_vs_fastest']} |")
    return '\n'.join(lines) + '\n'


def write_atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(text)
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, default=DEFAULT_BASELINE)
    parser.add_argument('--expected-baseline-sha256', default=DEFAULT_BASELINE_SHA256)
    parser.add_argument('--taxonomy', type=Path, default=EXPANDED / 'coverage.json')
    parser.add_argument('--historical-revision', default=HISTORICAL_REVISION)
    parser.add_argument('--repo', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, default=HERE / 'results/assessment_main_20261003.json')
    args = parser.parse_args()
    try:
        protect_inputs(args.output, (args.baseline, args.baseline.with_suffix('.md'), args.taxonomy))
        baseline, count = load_verified(args.baseline, args.expected_baseline_sha256)
        taxonomy_raw = args.taxonomy.read_bytes()
        taxonomy = json.loads(taxonomy_raw)
        audit = historical_source_audit(baseline['identity'], args.historical_revision, args.repo)
        report = build_assessment(baseline, taxonomy, args.baseline, args.expected_baseline_sha256, audit, count)
        report['input']['taxonomy_sha256'] = sha(taxonomy_raw)
        report['input']['taxonomy_path'] = str(args.taxonomy)
        require(sha(args.baseline.read_bytes()) == args.expected_baseline_sha256, 'baseline changed during assessment')
        require(args.taxonomy.read_bytes() == taxonomy_raw, 'taxonomy changed during assessment')
        write_atomic(args.output, json.dumps(report, indent=2, ensure_ascii=False) + '\n')
        write_atomic(args.output.with_suffix('.md'), markdown(report))
        print(f'PASS family assessment: {len(report["families"])} families; {len(report["applications"])} applications; {len(report["appendix_all_comparisons"])} comparisons; {audit["status"]}')
        return 0
    except (ValueError, KeyError, TypeError, OSError) as error:
        print('FAILED assessment (no new complete result): ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
