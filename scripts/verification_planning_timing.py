#!/usr/bin/env python3
"""Paired actual payload planning slice; S10 must own timing admission.

Read-only frozen inputs, no native compiler/gate execution, no success receipts.
Common context is held fixed to compare payload function semantics; this does not
claim equal production receipts across different coordinator implementations.
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


def load(path, name):
    if str(path.parent) not in sys.path:
        sys.path.append(str(path.parent))
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--inventory',type=Path,required=True)
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--zig',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--pairs',type=int,default=40)
    parser.add_argument('--max-seconds',type=float,default=600)
    arguments = parser.parse_args()
    if not 1 <= arguments.pairs <= 100 or not 0 < arguments.max_seconds <= 3600:
        parser.error('bounded pairs/time required')
    started = time.perf_counter_ns()
    root = arguments.root.resolve()
    baseline = load(arguments.baseline.resolve(), 'paired_baseline_coordinator')
    candidate = load(arguments.candidate.resolve(), 'paired_candidate_coordinator')
    plan = support.inventory(arguments.inventory.resolve())
    env = support.normalized_environment(root)
    zig = arguments.zig.resolve()
    env['ZIG'] = str(zig)
    env['MYLANG_ZIG'] = str(zig)
    recipes, tools_files = support.tool_contract(zig, env)
    input_recipes = sorted({recipe for group in plan['groups'] for recipe in group['inputs']})
    rows = []
    result = {'schema':1,'scope':'actual warm action-payload loop including canonical key/report construction',
              'root':str(root),'inventory_sha256':support.key(plan), 'pairs_requested':arguments.pairs,
              'admission':'external S10 timing window required','production_receipts_created':False,
              'sources':{label:hashlib.sha256(path.read_bytes()).hexdigest() for label,path in
                         [('baseline',arguments.baseline),('candidate',arguments.candidate),
                          ('snapshot',Path(snapshots.__file__)),('harness',Path(__file__))]},
              'mode':plan['configuration']['optimize'],'cache_tier':'fresh snapshot setup then live immutable payload inputs',
              'rows':rows,'complete':False}
    with ExitStack() as stack:
        tools = stack.enter_context(snapshots.Snapshot(root,recipes,tools_files))
        config = stack.enter_context(snapshots.Snapshot(root,support.CONFIG_INPUTS+support.COORDINATOR_INPUTS))
        source = stack.enter_context(snapshots.Snapshot(root,input_recipes))
        artifacts = stack.enter_context(snapshots.Snapshot(root,[],support.artifact_paths(root)))
        active = [tools,config,source,artifacts]
        providers = support.artifact_providers(root,artifacts)
        manifest = support.read_record(root/'zig-out/verification/artifacts.json')
        members = {row['id']:row for row in plan['action_metadata']}
        common = {'version':support.VERSION,'root':str(root),'options':[], 'environment':support.key(env),
                  'platform':support.host_contract(),'tools':support.key(tools.identity),
                  'build_configuration':support.key(config.identity),'action_controls':plan['configuration'],
                  'artifacts':support.key(artifacts.identity),'inventory':support.key(plan)}
        result['common_context_sha256'] = support.key(common)
        result['source_snapshot_identity_sha256'] = support.key(source.identity)
        result['source_records'] = len(source.identity['files'])
        result['setup_elapsed_ns'] = time.perf_counter_ns()-started
        functions = {'baseline':baseline.action_payload, 'candidate':candidate.action_payload}
        for pair in range(arguments.pairs):
            if (time.perf_counter_ns()-started)/1e9 >= arguments.max_seconds:
                break
            check_started = time.perf_counter_ns()
            assert all(snapshot.unchanged() for snapshot in active)
            validation_ns = time.perf_counter_ns()-check_started
            order = ('baseline','candidate') if pair%2 == 0 else ('candidate','baseline')
            expected = None
            for variant in order:
                before = source.statistics
                phase = time.perf_counter_ns()
                keys = []
                summaries = []
                for group in plan['groups']:
                    payload = functions[variant](group,source,common,root,providers,members[group['id']],manifest)
                    keys.append(support.key(payload))
                    summaries.append(support.verification_report.dependency_summary(
                        group,payload['files'],dict(payload['common'],membership=members[group['id']])))
                planning_ns = time.perf_counter_ns()-phase
                inventory = support.key({'action_keys':keys,'summaries':summaries})
                expected = inventory if expected is None else expected
                assert inventory == expected
                assert source.statistics == before
                rows.append({'pair':pair,'order':list(order),'variant':variant,'planning_elapsed_ns':planning_ns,
                             'validation_elapsed_ns_before_pair':validation_ns,'completed_groups':len(keys),
                             'payload_and_summary_sha256':inventory,'snapshot_work_unchanged':True})
            assert all(snapshot.unchanged() for snapshot in active)
        result['complete'] = len(rows) == arguments.pairs*2
        result['all_identities_equal'] = True
        result['elapsed_ns_including_setup_validation'] = time.perf_counter_ns()-started
    arguments.output.parent.mkdir(parents=True,exist_ok=True)
    arguments.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'complete':result['complete'],'pairs':len(rows)//2,'groups_per_variant':len(plan['groups'])}))
    return 0 if result['complete'] else 3


if __name__ == '__main__':
    raise SystemExit(main())
