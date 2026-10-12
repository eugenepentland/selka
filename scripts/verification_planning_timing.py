#!/usr/bin/env python3
"""Paired payload planning slice; S10 owns timing admission.

No native execution or receipts. Compare all semantic fields exactly, allowing
only the reviewed v4/v5 action domain and v1/v2 receipt-version migration. Retain
actual domains/key digests separately; this never asserts production-key equality.
"""
from contextlib import ExitStack
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time

import verification_snapshot as snapshots
import verify_cache as support

DOMAINS = {'selka-verification-action-v4', 'selka-verification-action-v5'}


def load(path, name):
    if str(path.parent) not in sys.path:
        sys.path.append(str(path.parent))
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def semantic_payload(payload):
    """Normalize only explicitly reviewed identity namespaces, never dependencies."""
    if payload['domain'] not in DOMAINS or type(payload['common']['version']) is not int or payload['common']['version'] not in (1, 2):
        raise ValueError('unreviewed identity migration')
    return dict(payload, domain='reviewed-action-v4-v5-comparison',
                common=dict(payload['common'], version='reviewed-receipt-v1-v2-comparison'))


def run(arguments, result):
    root = arguments.root.resolve()
    result['stage'] = 'setup'
    baseline = load(arguments.baseline.resolve(), 'paired_baseline_coordinator')
    candidate = load(arguments.candidate.resolve(), 'paired_candidate_coordinator')
    plan = support.inventory(arguments.inventory.resolve())
    result.update(inventory_sha256=support.key(plan), mode=plan['configuration']['optimize'])
    env = support.normalized_environment(root)
    zig = arguments.zig.resolve()
    env['ZIG'] = str(zig)
    env['MYLANG_ZIG'] = str(zig)
    recipes, tools_files = support.tool_contract(zig, env)
    inputs = sorted({recipe for group in plan['groups'] for recipe in group['inputs']})
    with ExitStack() as stack:
        tools = stack.enter_context(snapshots.Snapshot(root, recipes, tools_files))
        config = stack.enter_context(snapshots.Snapshot(root, support.CONFIG_INPUTS + support.COORDINATOR_INPUTS))
        source = stack.enter_context(snapshots.Snapshot(root, inputs))
        artifacts = stack.enter_context(snapshots.Snapshot(root, [], support.artifact_paths(root)))
        active = [tools, config, source, artifacts]
        providers = support.artifact_providers(root, artifacts)
        manifest = support.read_record(root / 'zig-out/verification/artifacts.json')
        members = {row['id']: row for row in plan['action_metadata']}
        common = {'root': str(root), 'options': [], 'environment': support.key(env),
                  'platform': support.host_contract(), 'tools': support.key(tools.identity),
                  'build_configuration': support.key(config.identity), 'action_controls': plan['configuration'],
                  'artifacts': support.key(artifacts.identity), 'inventory': support.key(plan)}
        result['common_context_sha256_excluding_receipt_version'] = support.key(common)
        result['source_snapshot_identity_sha256'] = support.key(source.identity)
        result['source_records'] = len(source.identity['files'])
        result['setup_elapsed_ns'] = time.perf_counter_ns() - result['started_ns']
        modules = {'baseline': baseline, 'candidate': candidate}
        for pair in range(arguments.pairs):
            if (time.perf_counter_ns() - result['started_ns']) / 1e9 >= arguments.max_seconds:
                result['stage'] = 'budget_exhausted'
                break
            check_started = time.perf_counter_ns()
            if not all(snapshot.unchanged() for snapshot in active):
                raise ValueError('source/tool/artifact authority changed before pair')
            validation_ns = time.perf_counter_ns() - check_started
            order = ('baseline', 'candidate') if pair % 2 == 0 else ('candidate', 'baseline')
            expected = None
            for variant in order:
                result.update(stage='planning', pair=pair, variant=variant)
                before = source.statistics
                phase = time.perf_counter_ns()
                semantic, keys, summaries, actual_summaries, domains = [], [], [], [], []
                context = dict(common, version=modules[variant].VERSION)
                for group in plan['groups']:
                    result['action_id'] = group['id']
                    payload = modules[variant].action_payload(group, source, context, root, providers, members[group['id']], manifest)
                    normalized = semantic_payload(payload)
                    semantic.append(normalized)
                    keys.append(support.key(payload))
                    domains.append(payload['domain'])
                    actual_summaries.append(support.verification_report.dependency_summary(
                        group, payload['files'], dict(payload['common'], membership=members[group['id']])))
                    summaries.append(support.verification_report.dependency_summary(
                        group, normalized['files'], dict(normalized['common'], membership=members[group['id']])))
                planning_ns = time.perf_counter_ns() - phase
                inventory = support.key({'semantic_payloads': semantic, 'summaries': summaries})
                row = {'pair': pair, 'order': list(order), 'variant': variant, 'planning_elapsed_ns': planning_ns,
                       'validation_elapsed_ns_before_pair': validation_ns, 'completed_groups': len(keys),
                       'actual_action_key_digests': keys, 'actual_domains': sorted(set(domains)),
                       'actual_receipt_version': modules[variant].VERSION,
                       'actual_summary_sha256': support.key(actual_summaries),
                       'semantic_payload_and_summary_sha256': inventory,
                       'snapshot_work_unchanged': source.statistics == before}
                result['rows'].append(row)
                if source.statistics != before:
                    raise ValueError('payload construction unexpectedly changed snapshot work')
                if expected is None:
                    expected = (semantic, summaries)
                elif semantic != expected[0] or summaries != expected[1]:
                    different = [plan['groups'][index]['id'] for index, payload in enumerate(semantic)
                                 if payload != expected[0][index] or summaries[index] != expected[1][index]]
                    result['mismatching_actions'] = different[:64]
                    raise ValueError('semantic dependency/member selection mismatch')
            if not all(snapshot.unchanged() for snapshot in active):
                raise ValueError('source/tool/artifact authority changed after pair')
        result['complete'] = len(result['rows']) == arguments.pairs * 2
        result['all_semantic_dependencies_equal'] = True
        result['stage'] = 'complete' if result['complete'] else result['stage']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'inventory', 'baseline', 'candidate', 'zig', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--pairs', type=int, default=40)
    parser.add_argument('--max-seconds', type=float, default=600)
    arguments = parser.parse_args()
    if not 1 <= arguments.pairs <= 100 or not 0 < arguments.max_seconds <= 3600:
        parser.error('bounded pairs/time required')
    result = {'schema': 2, 'scope': 'actual warm payload/key/report planning with reviewed namespace comparison',
              'root': str(arguments.root.resolve()), 'pairs_requested': arguments.pairs, 'rows': [], 'complete': False,
              'allowed_normalizations': ['domain: action-v4/action-v5', 'common.version: receipt-v1/receipt-v2'],
              'admission': 'external S10 timing window required', 'production_receipts_created': False,
              'started_ns': time.perf_counter_ns(),
              'cache_tier': 'fresh snapshot setup then live immutable payload inputs',
              'sources': {label: hashlib.sha256(path.read_bytes()).hexdigest() for label, path in
                          [('baseline', arguments.baseline), ('candidate', arguments.candidate),
                           ('snapshot', Path(snapshots.__file__)), ('harness', Path(__file__))]}}
    status = 2
    try:
        run(arguments, result)
        status = 0 if result['complete'] else 3
    except Exception as error:
        result.update(complete=False, error_type=type(error).__name__, error=str(error)[:1024])
    finally:
        result['status'] = status
        result['elapsed_ns_including_setup_validation'] = time.perf_counter_ns() - result.pop('started_ns')
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        arguments.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({'complete': result['complete'], 'pairs': len(result['rows']) // 2,
                      'stage': result.get('stage'), 'status': status, 'error': result.get('error')}))
    return status


if __name__ == '__main__':
    raise SystemExit(main())
