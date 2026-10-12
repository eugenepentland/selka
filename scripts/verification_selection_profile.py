#!/usr/bin/env python3
"""Count detached record copies for actual action recipes; no timing claim."""
from contextlib import ExitStack
import argparse
import copy
import hashlib
import json
from pathlib import Path
from unittest.mock import patch

import verification_snapshot as snapshots
import verify_cache as coordinator


def profile(root: Path, inventory_path: Path) -> dict:
    """Compare old union-copy projection with selected detached records."""
    plan = coordinator.inventory(inventory_path)
    recipes = sorted({entry for group in plan['groups'] for entry in group['inputs']})
    rows = []
    original = copy.deepcopy
    copied = [0]
    def observe(value, *args, **kwargs):
        if isinstance(value, dict) and 'files' in value:
            copied[0] += len(value['files'])
        elif isinstance(value, list) and all(isinstance(row, dict) and 'sha256' in row for row in value):
            copied[0] += len(value)
        return original(value, *args, **kwargs)
    with snapshots.RetainedSession() as session, session.activate():
        with snapshots.Snapshot(root, recipes) as cold:
            full = cold.identity
        before = session.statistics
        with snapshots.Snapshot(root, recipes) as source:
            acquisition = {key:value-before[key] for key,value in session.statistics.items()}
            validation_before = source.statistics
            with patch.object(copy, 'deepcopy', side_effect=observe):
                for group in plan['groups']:
                    include = lambda path: any(coordinator.matches_recipe(path, recipe, root)
                                               for recipe in group['inputs'])
                    copied[0] = 0
                    old = [row for row in source.identity['files'] if include(row['path'])]
                    old_count = copied[0]
                    copied[0] = 0
                    selected = source.selected_files(include)
                    new_count = copied[0]
                    assert old == selected
                    assert coordinator.key(old) == coordinator.key(selected)
                    rows.append({'group':group['id'], 'selected_records':len(selected),
                                 'baseline_records_copied':old_count,
                                 'candidate_records_copied':new_count})
            selection_work = {key:value-validation_before[key] for key,value in source.statistics.items()}
            assert source.unchanged()
            for _ in range(5):
                assert source.unchanged()
            validation_work = {key:value-validation_before[key] for key,value in source.statistics.items()}
    old_total = sum(row['baseline_records_copied'] for row in rows)
    new_total = sum(row['candidate_records_copied'] for row in rows)
    return {'schema':1,'module_sha256':hashlib.sha256(Path(snapshots.__file__).read_bytes()).hexdigest(),
            'inventory_sha256':coordinator.key(plan),'root':str(root),'union_file_records':len(full['files']),
            'groups':rows,'baseline_records_copied':old_total,'candidate_records_copied':new_total,
            'copies_avoided':old_total-new_total,'warm_acquisition':acquisition,
            'selection_snapshot_work':selection_work,'six_explicit_validations_work':validation_work,
            'all_projections_byte_identical':True,'timing':'not measured; deterministic work only'}


def validation_scope_profile(root: Path, inventory_path: Path, zig: Path, *, initial_tool_check=True) -> dict:
    """Reconstruct six warm scopes and the coordinator's 31 validation calls."""
    plan = coordinator.inventory(inventory_path)
    env = coordinator.normalized_environment(root)
    env['ZIG'] = str(zig)
    env['MYLANG_ZIG'] = str(zig)
    tools_recipes, tools_files = coordinator.tool_contract(zig, env)
    specs = [
        ('tools', tools_recipes, tools_files),
        ('configuration', coordinator.CONFIG_INPUTS, []),
        ('build_configuration', coordinator.CONFIG_INPUTS + coordinator.COORDINATOR_INPUTS, []),
        ('preparation_sources', coordinator.PREPARE_INPUTS, []),
        ('prepared_artifacts', [], coordinator.artifact_paths(root)),
        ('action_inputs', sorted({recipe for group in plan['groups'] for recipe in group['inputs']}), []),
    ]
    rows = []
    with snapshots.RetainedSession() as session, session.activate():
        with ExitStack() as stack:
            cold = [stack.enter_context(snapshots.Snapshot(root, recipes, files))
                    for role, recipes, files in specs]
        before = session.statistics
        with ExitStack() as stack:
            warm = []
            for role, recipes, files in specs:
                source = stack.enter_context(snapshots.Snapshot(root, recipes, files))
                warm.append(source)
                if role == 'tools' and initial_tool_check:
                    assert source.unchanged()  # provider re-resolution check
            for phase in ('cache_lookup', 'admission', 'post_execution', 'publication'):
                assert all(source.unchanged() for source in warm)
            for (role, recipes, files), source in zip(specs, warm):
                owner = source._lease[1] if source._lease is not None else source
                rows.append({'role':role, 'files':len(owner._identity['files']),
                             'observed_paths':len(owner._paths), 'missing_paths':len(owner._missing),
                             'work':source.statistics})
            work = {key:value-before[key] for key,value in session.statistics.items()}
    return {'schema':1,'scope':'warm six-snapshot lifecycle reconstruction; no gate executed',
            'root':str(root),'roles':rows,'warm_work':work,
            'initial_tool_check':initial_tool_check,'historical_metadata_observations':175816,'historical_validation_calls':31,
            'timing':'not measured; deterministic counts only'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--inventory',type=Path,required=True)
    parser.add_argument('--validation-scopes', action='store_true')
    parser.add_argument('--zig',type=Path)
    parser.add_argument('--omit-redundant-tool-check',action='store_true')
    arguments = parser.parse_args()
    if arguments.validation_scopes:
        parser.error('--validation-scopes requires --zig') if arguments.zig is None else None
        result = validation_scope_profile(arguments.root.resolve(),arguments.inventory.resolve(),arguments.zig.resolve(), initial_tool_check=not arguments.omit_redundant_tool_check)
    else:
        result = profile(arguments.root.resolve(),arguments.inventory.resolve())
    print(json.dumps(result,indent=2))


if __name__ == '__main__':
    main()
