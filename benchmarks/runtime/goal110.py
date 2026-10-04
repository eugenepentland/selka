#!/usr/bin/env python3
"""Current-fastest LLVM 1.10 acceptance, separate from the frozen-target campaign."""
import argparse
from collections import Counter
import copy
from datetime import datetime
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tarfile

from compare_candidate import ARMS, bootstrap, require, verify
from registry import inventory

SCHEMA = 'mylang-runtime-goal110-analysis-v1'
DASHBOARD_SCHEMA = 'mylang-runtime-goal110-dashboard-v1'
THRESHOLD = 1.10
MIN_ROUNDS = 15
MIN_WARMUPS = 3
PRODUCTION_INPUTS = ('src', 'vendor/qbe', 'build.zig', 'build.zig.zon', '.zigversion', '.qbeversion')
DISPLAY_ARMS = ('rust', 'go', 'zig-safe', 'zig-fast', 'my-llvm', 'my-qbe')


def content_hash(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def read_document(path):
    path = Path(path).resolve()
    stored = path.read_bytes()
    raw = gzip.decompress(stored) if stored.startswith(b'\x1f\x8b') else stored
    return json.loads(raw), {'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest(),
                             'stored_sha256': hashlib.sha256(stored).hexdigest()}


def read_recorded(entry):
    document, observed = read_document(entry['path'])
    require(observed == entry, 'evidence file changed: ' + entry['path'])
    return document


def production_sources(receipt):
    # docs/ is in the broad build receipt, but does not feed production compilation.
    sources = {name: digest for name, digest in receipt['sources_after'].items()
               if any(name == root or name.startswith(root + '/') for root in PRODUCTION_INPUTS)}
    require(bool(sources) and any(name.startswith('src/') for name in sources), 'missing production source bytes')
    require(all(re.fullmatch('[0-9a-f]{64}', digest or '') for digest in sources.values()), 'invalid production hash')
    return sources


def revision_sources(root, revision):
    require(re.fullmatch('[0-9a-f]{40}', revision or '') is not None, 'source revision must be a full commit SHA')
    raw = subprocess.check_output(['git', '-C', str(root), 'archive', revision, '--', *PRODUCTION_INPUTS])
    with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
        return {member.name: hashlib.sha256(archive.extractfile(member).read()).hexdigest()
                for member in archive.getmembers() if member.isfile()}


def normalized_command(command, identity):
    receipt = identity['compiler_build_receipt']['receipt']
    replacements = {identity['source_root']: '$BENCHMARK_ROOT', receipt['source_root']: '$COMPILER_ROOT',
                    identity['build_wrapper']: '$BUILD_WRAPPER'}
    replacements.update({tool['path']: '$TOOL/' + name for name, tool in identity['tools'].items()})
    replacements.update({path: '$GUEST/' + name for name, path in identity['binary_paths'].items()})
    replacements.update({path: '$CACHE/' + name for name, path in identity['private_cache_environment'].items()
                         if name != 'RUSTC'})
    replacements.update({path: '$COMPILER_CACHE/' + name for name, path in receipt['build_environment'].items()})
    clock = identity['clock_build']
    replacements[clock[clock.index('-o') + 1]] = '$NATIVE_CLOCK'
    result = []
    for argument in command:
        for path in sorted(replacements, key=len, reverse=True):
            argument = argument.replace(path, replacements[path])
        result.append(argument)
    return result


def policy_identity(report):
    identity = report['identity']
    receipt = identity['compiler_build_receipt']['receipt']
    require(receipt.get('compiler_optimize') in ('ReleaseFast', 'Debug'), 'compiler policy must be explicit')
    require('-Doptimize=' + receipt['compiler_optimize'] in receipt['command'], 'compiler command/policy mismatch')
    for name, command in identity['commands'].items():
        arm = name.split('/')[1]
        if arm.startswith('my-'):
            require(command.count('--backend') == 1 and command[command.index('--backend') + 1] == arm[3:],
                    'actual guest backend mismatch: ' + name)
            require(command.count('--mode') == 1 and command[command.index('--mode') + 1] == 'ReleaseFast',
                    'guest build mode mismatch: ' + name)
            if arm == 'my-llvm':
                require(command.count('--llvm-opt') == 1 and command[command.index('--llvm-opt') + 1] == '3'
                        and '--lto' in command, 'LLVM guest policy requires O3/LTO')
    target = copy.deepcopy(identity['target_policy'])
    require(set(ARMS) <= set(target), 'missing target policy')
    probe = target['llvm_target_probe']
    require(probe['exit_status'] == 0 and bool(probe['target_cpu_entries']) and bool(probe['feature_entries']),
            'missing successful ISA policy probe')
    probe['command'] = normalized_command(probe['command'], identity)
    return {'compiler_optimize': receipt['compiler_optimize'],
            'compiler_command': normalized_command(receipt['command'], identity),
            'target_policy': target, 'build_environment': identity['build_environment'],
            'guest_commands': {name: normalized_command(command, identity) for name, command in identity['commands'].items()},
            'clock_command': normalized_command(identity['clock_build'], identity),
            'wrapper_sha256': identity['wrapper_sha256'], 'compiler_wrapper_sha256': receipt['build_wrapper_sha256']}


def execution_identity(report):
    identity = report['identity']
    receipt = identity['compiler_build_receipt']['receipt']
    tools = {name: {field: tool[field] for field in ('sha256', 'version', 'invocation_sha256') if field in tool}
             for name, tool in identity['tools'].items()}
    assets = {str(Path(path).relative_to(receipt['source_root'])): digest
              for path, digest in identity['installed_assets'].items()}
    # Contract Markdown is semantic evidence; ordinary documentation is not a build input.
    sources = {name: digest for name, digest in identity['sources'].items()
               if not name.endswith('.md') or Path(name).name == 'CONTRACT.md'}
    hashes = [*report['binary_hashes'].values(), *sources.values(), *assets.values(), receipt['compiler_sha256']]
    require(all(re.fullmatch('[0-9a-f]{64}', digest or '') for digest in hashes), 'malformed artifact/source hash')
    return {'production_sources': production_sources(receipt), 'compiler_sha256': receipt['compiler_sha256'],
            'assets': assets, 'tools': tools, 'benchmark_sources': sources,
            'binary_hashes': report['binary_hashes'], 'policy': policy_identity(report)}


def check_anchor(candidate, anchor):
    for field in ('benchmark_sources', 'policy'):
        if field == 'policy':
            # Compiler implementation may change; guest/reference and ISA policy may not.
            left, right = copy.deepcopy(candidate[field]), copy.deepcopy(anchor[field])
            for key in ('compiler_command', 'compiler_optimize'):
                left.pop(key)
                right.pop(key)
            require(left == right, 'starting guest/build/ISA policy changed')
        else:
            require(candidate[field] == anchor[field], 'starting benchmark source/input policy changed')
    for tool in anchor['tools']:
        if tool != 'mylang':
            require(candidate['tools'].get(tool) == anchor['tools'][tool], 'starting reference compiler changed: ' + tool)
    for name, digest in anchor['binary_hashes'].items():
        if not name.endswith(('/my-llvm', '/my-qbe')):
            require(candidate['binary_hashes'].get(name) == digest, 'starting reference executable/clock changed: ' + name)


def session_rows(report):
    """Derive every winner and interval using only this session's current rounds."""
    require(report['schema'] == 'mylang-runtime-expanded-v2', 'goal requires expanded-v2 raw evidence')
    require(report['status'] in ('complete', 'subset') and report['profile'] == 'baseline', 'smoke is not goal evidence')
    require(type(report['rounds']) is int and report['rounds'] > 0, 'invalid rounds')
    plans = {(p['case'], p['size']): p for p in report['plans']}
    require(len(plans) == len(report['plans']), 'duplicate plan')
    samples = {}
    for sample in report['samples']:
        key = (sample['case'], sample['size'], sample['arm'])
        require(key[:2] in plans and key[2] in ARMS, 'unknown current sample')
        require(type(sample['round']) is int and sample['round'] not in samples.setdefault(key, {}), 'duplicate/invalid current round')
        require(sample['iterations'] == plans[key[:2]]['iterations'], 'sample iteration drift')
        require(type(sample['kernel_ns']) in (int, float) and 0 < sample['kernel_ns'] < float('inf'), 'invalid kernel duration')
        samples[key][sample['round']] = sample['kernel_ns']
    output = []
    for key, plan in plans.items():
        rounds = range(report['rounds'])
        values = {}
        for arm in ARMS:
            require(set(samples.get((*key, arm), {})) == set(rounds), 'missing current arms/paired rounds')
            values[arm] = [samples[(*key, arm)][rnd] for rnd in rounds]
        medians = {arm: statistics.median(rows) / plan['iterations'] for arm, rows in values.items()}
        fastest = min(medians.values())
        comparisons = {}
        for arm in ('my-llvm', 'my-qbe'):
            intervals = {other: [1., 1.] if other == arm else
                         bootstrap(values[arm], values[other], f'{key}/{arm}/{other}/goal110/bootstrap') for other in ARMS}
            ratio = medians[arm] / fastest
            state = 'O' if ratio > THRESHOLD else 'P' if all(ci[1] <= THRESHOLD for ci in intervals.values()) else 'I'
            comparisons[arm] = {'ratio': ratio, 'intervals': intervals, 'state': state}
        output.append({'case': key[0], 'size': key[1], 'profile': plan['profile'], 'unit': plan['unit'],
                       'iterations': plan['iterations'], 'seed': plan['seed'], 'calibration': plan['calibration'],
                       'fastest_ns_per_iteration': fastest, 'fastest_arms': [arm for arm in ARMS if medians[arm] == fastest],
                       'medians': medians, 'ratios': {arm: ns / fastest for arm, ns in medians.items()},
                       'backends': comparisons})
    return output


def verify_session(report, artifacts=False):
    verify(report, artifacts=artifacts, focused=True)
    require(report['schema'] == 'mylang-runtime-expanded-v2', 'goal requires expanded-v2 raw evidence')
    require(isinstance(report['measurement_session_id'], str), 'invalid session ID')
    dates = [datetime.fromisoformat(report[field]) for field in ('measurement_started_utc', 'finished_utc')]
    require(all(date.utcoffset() is not None for date in dates) and dates[0] < dates[1], 'invalid measurement UTC interval')
    environment = report['environment']
    require(type(environment['cpu']) is int and all(field in environment for field in
            ('platform', 'cpuinfo', 'thread_siblings', 'frequency', 'per_core_busy_percent_sampling', 'warnings')),
            'missing host conditions')
    return execution_identity(report)


def confirmation_identity(first, second, first_identity, second_identity):
    require(first['measurement_session_id'] != second['measurement_session_id'], 'confirmation reuses measurement session')
    require(first['identity']['candidate_id'] == second['identity']['candidate_id'], 'confirmation candidate ID mismatch')
    require(first_identity == second_identity, 'confirmation production/compiler/guest/policy identity mismatch')
    require(set(first['coverage']) == set(second['coverage']), 'confirmation coverage mismatch')
    # Independently calibrated counts may differ; input/seed/unit/size contracts may not.
    contract = lambda report: [{key: plan[key] for key in ('case', 'size', 'profile', 'seed', 'unit', 'group', 'family', 'level')}
                               for plan in sorted(report['plans'], key=lambda p: (p['case'], p['size']))]
    require(contract(first) == contract(second), 'confirmation input contract mismatch')
    for report in (first, second):
        require(report['rounds'] >= MIN_ROUNDS and report['warmup_rounds'] >= MIN_WARMUPS,
                'confirmation requires at least 15 rounds and 3 warmups in both sessions')
        require(report['identity']['compiler_build_receipt']['receipt']['compiler_optimize'] == 'ReleaseFast',
                'confirmation requires explicit ReleaseFast compiler policy')
    start = lambda report: datetime.fromisoformat(report['measurement_started_utc'])
    end = lambda report: datetime.fromisoformat(report['finished_utc'])
    require(end(first) <= start(second) or end(second) <= start(first), 'confirmation measurement sessions overlap')


def correctness_checks(receipt, identity_hash, coverage):
    require(receipt.get('schema') == 'mylang-runtime-goal110-checks-v1' and receipt.get('status') == 'pass',
            'missing successful goal correctness receipt')
    require(receipt['execution_identity_sha256'] == identity_hash, 'correctness production/artifact/policy identity mismatch')
    require(isinstance(receipt['coverage'], list) and len(receipt['coverage']) == len(set(receipt['coverage']))
            and set(coverage) <= set(receipt['coverage']) <= set(inventory()), 'correctness coverage mismatch')
    checks = receipt['checks']
    require(bool(checks), 'missing correctness checks')
    kinds = set()
    for check in checks:
        require(check.get('status') == 'pass' and check.get('name') and check.get('kind') in ('qualification', 'holdout', 'repository'),
                'failed/unnamed correctness check')
        kinds.add(check['kind'])
        path = Path(check['path'])
        require(hashlib.sha256(path.read_bytes()).hexdigest() == check['sha256'], 'correctness log changed: ' + str(path))
    require({'qualification', 'holdout'} <= kinds, 'qualification and nearby-input holdout checks required')
    return set(receipt['coverage']) == set(inventory()) and 'repository' in kinds


def analyze(report, anchor, evidence_id, confirmation=None, checks=None, artifacts=False):
    require(re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*', evidence_id or '') is not None, 'invalid evidence ID')
    identity = verify_session(report, artifacts)
    anchor_identity = verify_session(anchor, artifacts=False)
    require(anchor['status'] == 'complete', 'starting setup requires complete anchor')
    check_anchor(identity, anchor_identity)
    rows = session_rows(report)
    identity_hash = content_hash(identity)
    full_checks = correctness_checks(checks, identity_hash, report['coverage']) if checks is not None else False
    timing_confirmed = False
    if confirmation is not None:
        second_identity = verify_session(confirmation, artifacts)
        check_anchor(second_identity, anchor_identity)
        confirmation_identity(report, confirmation, identity, second_identity)
        second = {(r['case'], r['size']): r for r in session_rows(confirmation)}
        timing_confirmed = True
        for row in rows:
            confirm = second[(row['case'], row['size'])]
            row['confirmation'] = confirm['backends']
            for arm in ('my-llvm', 'my-qbe'):
                state = row['backends'][arm]['state']
                confirmation_state = confirm['backends'][arm]['state']
                accepted = state == confirmation_state == 'P'
                row['backends'][arm]['timing_confirmed'] = accepted
                if state != 'O':
                    row['backends'][arm]['state'] = 'C' if accepted and checks is not None else 'I' if not accepted else 'P'
    full_confirmation = report['status'] == 'complete' and timing_confirmed and all(r['backends']['my-llvm']['state'] == 'C' for r in rows)
    return {'schema': SCHEMA, 'evidence_id': evidence_id, 'threshold': THRESHOLD,
            'analysis_policy': {'minimum_confirmation_rounds': MIN_ROUNDS, 'minimum_confirmation_warmups': MIN_WARMUPS,
                                'bootstrap_resamples': 2000, 'interval': 'paired ratio of resampled medians; per-comparison 95%',
                                'production_inputs': list(PRODUCTION_INPUTS)},
            'anchor_execution_identity_sha256': content_hash(anchor_identity),
            'scope': report['status'], 'coverage': report['coverage'], 'source_revision': report['identity']['source_revision'],
            'candidate_id': report['identity']['candidate_id'], 'execution_identity': identity,
            'execution_identity_sha256': identity_hash,
            'production_sources_sha256': content_hash(identity['production_sources']),
            'sessions': [{'id': r['measurement_session_id'], 'source_revision': r['identity']['source_revision'],
                          'started_utc': r['measurement_started_utc'], 'finished_utc': r['finished_utc'],
                          'rounds': r['rounds'], 'warmup_rounds': r['warmup_rounds'], 'environment': r['environment']}
                         for r in ([report, confirmation] if confirmation is not None else [report])],
            'correctness_accepted': checks is not None, 'full_repository_checks': full_checks,
            'full_suite_confirmation': full_confirmation, 'goal_complete': full_confirmation and full_checks,
            'rows': rows, 'limitations': [
                'Intervals are per comparison, not a simultaneous campaign guarantee; tuning and winner selection remain limitations.',
                'Resampling pairs only current-arm round indices within each session; sessions and archived timings are never pooled.',
                'Local receipts record provenance, not independently attested builds. Host interference and calibration limits remain visible.',
                'Five-round screens and Debug compilers may inform observations but cannot establish confirmation.',
                'QBE is tracked; its ratio changing when another arm improves is not proof of an absolute regression.']}


def replay_analysis(result):
    inputs = result['inputs']
    actual = analyze(read_recorded(inputs['report']), read_recorded(inputs['anchor']), result['evidence_id'],
                     read_recorded(inputs['confirmation']) if inputs.get('confirmation') else None,
                     read_recorded(inputs['checks']) if inputs.get('checks') else None)
    actual['inputs'] = inputs
    require(actual == result, 'analysis content differs from raw evidence')


def dashboard(updates, source_revision=None, sources=None):
    require(bool(updates), 'dashboard needs complete starting evidence')
    require(updates[0]['scope'] == 'complete', 'dashboard must start with complete 80-cell evidence')
    evidence, latest, previously_confirmed = {}, {}, set()
    integrated = None
    for update in updates:
        require(update['schema'] == SCHEMA and update['threshold'] == THRESHOLD, 'wrong goal analysis schema/threshold')
        require(update['anchor_execution_identity_sha256'] == updates[0]['anchor_execution_identity_sha256'],
                'dashboard starting setup/anchor changed')
        name = update['evidence_id']
        require(name not in evidence, 'evidence ID cannot be overwritten')
        evidence[name] = update
        if update['scope'] == 'complete':
            integrated = name
        for row in update['rows']:
            key = (row['case'], row['size'])
            current = copy.deepcopy(row)
            current.update(evidence_id=name, source_revision=update['source_revision'],
                           execution_identity_sha256=update['execution_identity_sha256'])
            current['backends']['my-llvm']['previously_confirmed'] = key in previously_confirmed
            latest[key] = current
            if row['backends']['my-llvm']['state'] == 'C':
                previously_confirmed.add(key)
    active = updates[-1]
    current_sources = sources if sources is not None else active['execution_identity']['production_sources']
    current_hash = content_hash(current_sources)
    wanted = [(case, size) for case, meta in inventory().items() for size in meta['sizes']]
    require(set(latest) == set(wanted), 'missing/unknown dashboard cells')
    rows = [latest[key] for key in wanted]
    for row in rows:
        for arm in ('my-llvm', 'my-qbe'):
            backend = row['backends'][arm]
            if backend['state'] == 'C' and (evidence[row['evidence_id']]['production_sources_sha256'] != current_hash or
                                           row['execution_identity_sha256'] != active['execution_identity_sha256']):
                backend['state'] = 'S'
            if arm == 'my-llvm' and backend['state'] == 'O' and backend['previously_confirmed']:
                backend['state'] = 'R'
    counts = {arm: dict(Counter(row['backends'][arm]['state'] for row in rows)) for arm in ('my-llvm', 'my-qbe')}
    complete = (evidence[integrated]['goal_complete'] and
                evidence[integrated]['execution_identity_sha256'] == active['execution_identity_sha256'] and
                evidence[integrated]['production_sources_sha256'] == current_hash and counts['my-llvm'].get('C') == 80)
    return {'schema': DASHBOARD_SCHEMA, 'current_source_revision': source_revision or active['source_revision'],
            'current_production_sources': current_sources,
            'current_production_sources_sha256': current_hash, 'active_execution_identity_sha256': active['execution_identity_sha256'],
            'latest_complete_integrated_evidence': integrated, 'goal_complete': bool(complete),
            'mixed_production_evidence': any(evidence[row['evidence_id']]['production_sources_sha256'] != current_hash for row in rows),
            'mixed_execution_evidence': any(row['execution_identity_sha256'] != active['execution_identity_sha256'] for row in rows),
            'required_llvm_cells': 80, 'qbe_required_cells': 0, 'counts': counts,
            'observed_at_or_below': {arm: sum(row['ratios'][arm] <= THRESHOLD for row in rows) for arm in ('my-llvm', 'my-qbe')},
            'updates': updates, 'rows': rows}


def markdown(result):
    rows = result['rows']
    lines = [f"LLVM ≤{THRESHOLD:.2f}; 80 required cells. QBE: tracked, 0 required cells.", '']
    if result['schema'] == DASHBOARD_SCHEMA:
        lines += [f"Current source `{result['current_source_revision']}`; latest complete integrated evidence: "
                  f"`{result['latest_complete_integrated_evidence']}`. Goal complete: **{result['goal_complete']}**.",
                  f"Mixed production evidence: {result['mixed_production_evidence']}. States: `{json.dumps(result['counts'], sort_keys=True)}`.", '']
        updates = result['updates']
    else:
        updates = [result]
        lines += [f"Evidence `{result['evidence_id']}`; source `{result['source_revision']}`; scope `{result['scope']}`.",
                  f"Execution identity SHA256: `{result['execution_identity_sha256']}`. Goal complete: **{result['goal_complete']}**.", '']
    lines += ['<!-- DASHBOARD-START -->',
              '| Case / profile (size) | Best ns/iteration | Rust | Go | Zig Safe | Zig Fast | MyLang LLVM | MyLang QBE | State LLVM / QBE | Evidence |',
              '|---|---:|---:|---:|---:|---:|---:|---:|---|---|']
    for row in rows:
        ratios = [f"**{row['ratios'][arm]:.4f}**" if arm in row['fastest_arms'] else f"{row['ratios'][arm]:.4f}" for arm in DISPLAY_ARMS]
        states = ' / '.join(row['backends'][arm]['state'] for arm in ('my-llvm', 'my-qbe'))
        lines.append(f"| {row['case']} / {row['profile']} ({row['size']}) | {row['fastest_ns_per_iteration']:.4f} | "
                     + ' | '.join(ratios) + f" | {states} | {row.get('evidence_id', result.get('evidence_id'))} |")
    lines += ['<!-- DASHBOARD-END -->', '', '| ID | Production source / sessions | Raw evidence (uncompressed SHA256) |', '|---|---|---|']
    for update in updates:
        links = ', '.join(f"[{name}]({entry['path']}) (`{entry['sha256']}`)" for name, entry in update.get('inputs', {}).items())
        sessions = ', '.join(f"`{session['id']}` ({session['rounds']} rounds, {session['warmup_rounds']} warmups)" for session in update['sessions'])
        lines.append(f"| {update['evidence_id']} | `{update['source_revision']}`; {sessions} | {links} |")
    lines += ['', 'C requires independent normal sessions and correctness receipts; I is inconclusive; S is stale; R reopens a previously confirmed LLVM cell.',
              'P is an observation awaiting confirmation; O exceeds the unrounded threshold. QBE states are informational.',
              'The JSON retains all five competitor intervals, self intervals, exact times, calibration, source/guest/policy hashes and host conditions.']
    return '\n'.join(lines) + '\n'


def write_result(output, result, inputs):
    output = Path(output).resolve()
    companion = output.with_suffix('.md')
    require(output != companion and output.name != 'RUNTIME_110_GOAL.md' and companion.name != 'RUNTIME_110_GOAL.md',
            'write a proposed artifact; coordinator owns the canonical goal document')
    require(not output.exists() and not companion.exists(), 'output already exists; preserve evidence under unique names')
    for entry in inputs:
        read_recorded(entry)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('x') as stream:
        stream.write(json.dumps(result, indent=2, allow_nan=False) + '\n')
    with companion.open('x') as stream:
        stream.write(markdown(result))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    analysis = sub.add_parser('analyze')
    analysis.add_argument('report', type=Path)
    analysis.add_argument('--anchor', type=Path, required=True, help='recorded complete starting six-arm expanded-v2 run')
    analysis.add_argument('--evidence-id', required=True)
    analysis.add_argument('--confirmation', type=Path)
    analysis.add_argument('--checks', type=Path)
    analysis.add_argument('--check-artifacts', action='store_true')
    analysis.add_argument('--output', type=Path, required=True)
    merged = sub.add_parser('dashboard')
    merged.add_argument('analysis', nargs='*', type=Path)
    merged.add_argument('--previous', type=Path)
    merged.add_argument('--current-source-revision')
    merged.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[2])
    merged.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.action == 'analyze':
        documents, entries = {}, {}
        for name in ('report', 'anchor', 'confirmation', 'checks'):
            if getattr(args, name) is not None:
                documents[name], entries[name] = read_document(getattr(args, name))
        result = analyze(documents['report'], documents['anchor'], args.evidence_id,
                         documents.get('confirmation'), documents.get('checks'), args.check_artifacts)
        result['inputs'] = entries
        inputs = list(entries.values())
    else:
        updates, inputs = [], []
        inherited_revision, inherited_sources = None, None
        if args.previous:
            previous, entry = read_document(args.previous)
            require(previous['schema'] == DASHBOARD_SCHEMA, 'wrong previous dashboard schema')
            updates.extend(previous['updates'])
            inputs.append(entry)
            inherited_revision = previous['current_source_revision']
            inherited_sources = previous['current_production_sources']
        for path in args.analysis:
            update, entry = read_document(path)
            updates.append(update)
            inputs.append(entry)
        for update in updates:
            replay_analysis(update)
            inputs.extend(update['inputs'].values())
        sources = revision_sources(args.source_root, args.current_source_revision) if args.current_source_revision else None
        if inherited_sources is not None and not args.current_source_revision:
            require(not args.analysis or updates[-1]['execution_identity']['production_sources'] == inherited_sources,
                    'production source switch requires explicit --current-source-revision')
            sources = inherited_sources
        result = dashboard(updates, args.current_source_revision or inherited_revision, sources)
    write_result(args.output, result, inputs)
    print(f"PASS {args.action}: {len(result['rows'])} cells; goal_complete={result['goal_complete']}; {args.output}")


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, IndexError, subprocess.CalledProcessError) as error:
        print('FAIL: ' + str(error), file=sys.stderr)
        sys.exit(1)
