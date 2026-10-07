#!/usr/bin/env python3
"""Execute only actual parser definitions; no wrapper main/compiler runs."""
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
M = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s4-project-tests')
AREA = M / 'experiments/new-core-s4-project-tests-20261006'
SUPPORT = AREA / 'qualification_support.py'
HISTORICAL = M / 'experiments/new-core-s1-20261005/conformance.py'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parser_only(path):
    tree = ast.parse(path.read_text(), filename=str(path))
    main = next(item for item in tree.body if isinstance(item, ast.FunctionDef) and item.name == 'main')
    namespace = {'argparse': argparse, 'Path': Path, 'os': os, 'ROOT': str(M),
                 '__doc__': ast.get_docstring(tree)}
    support_tree = ast.parse(SUPPORT.read_text(), filename=str(SUPPORT))
    receipt = next(item for item in support_tree.body
                   if isinstance(item, ast.FunctionDef) and item.name == 'receipt_arguments')
    exec(compile(ast.Module(body=[receipt], type_ignores=[]), str(SUPPORT), 'exec'), namespace)
    namespace['support'] = SimpleNamespace(receipt_arguments=namespace['receipt_arguments'])
    statements = []
    for item in main.body:
        if isinstance(item, ast.Assign) and isinstance(item.value, ast.Call) \
                and isinstance(item.value.func, ast.Attribute) \
                and item.value.func.attr in ('parse_args', 'parse_known_args'):
            parse_kind = item.value.func.attr
            parser_name = item.value.func.value.id
            break
        if isinstance(item, ast.Expr) and isinstance(item.value, ast.Constant):
            continue
        assert isinstance(item, (ast.Assign, ast.Expr)), ast.dump(item)
        call = item.value
        assert isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
        assert call.func.attr in ('ArgumentParser', 'add_argument', 'receipt_arguments')
        statements.append(item)
    else:
        raise AssertionError('no main parser found')
    exec(compile(ast.Module(body=statements, type_ignores=[]), str(path), 'exec'), namespace)
    return namespace[parser_name], parse_kind


files = [AREA / 'conformance_checked.py', AREA / 'project_matrix.py', AREA / 'fuzz_matrix.py',
         SUPPORT, HISTORICAL]
before = {str(path): sha(path) for path in files}
receipt_flags = ['--evidence', '/owned/evidence', '--old-source', 'a' * 40,
                 '--core-source', 'b' * 40]
historical_flags = ['--mylang', '/oracles/old', '--core', '/oracles/core', '--set', 'all',
                    '--modes', 'debug,release', '--jobs', '4', '--leakcheck', '--verify',
                    '--cache-dir', '/owned/cache']
argv = receipt_flags + historical_flags
parser, kind = parser_only(files[0])
assert kind == 'parse_known_args'
options, forwarded = parser.parse_known_args(argv)
historical, _ = parser_only(HISTORICAL)
selected = historical.parse_args(forwarded)
red = {'argv': argv, 'own_core_source': options.core_source, 'forwarded': forwarded,
       'historical_core': selected.core,
       'expected_core_source': 'b' * 40, 'expected_historical_core': '/oracles/core'}
assert options.core_source == '/oracles/core' and '--core' not in forwarded
assert selected.core != '/oracles/core'

parser.allow_abbrev = False  # In-memory control, not a source edit.
options, forwarded = parser.parse_known_args(argv)
selected = historical.parse_args(forwarded)
green = {'own_core_source': options.core_source, 'forwarded': forwarded,
         'historical_core': selected.core}
assert options.core_source == 'b' * 40 and forwarded == historical_flags
assert selected.core == '/oracles/core'

forwarding_cases = []
for supplied in (historical_flags, historical_flags[:2] + ['--core=/oracles/core'] + historical_flags[4:]):
    for order in (receipt_flags + supplied, supplied + receipt_flags):
        fresh, _ = parser_only(files[0])
        fresh.allow_abbrev = False
        own, rest = fresh.parse_known_args(order)
        actual = historical.parse_args(rest)
        assert own.core_source == 'b' * 40 and rest == supplied and actual.core == '/oracles/core'
        forwarding_cases.append({'argv': order, 'own_core_source': own.core_source, 'forwarded': rest})

direct = []
for path in files[1:3]:
    current, parse_kind = parser_only(path)
    assert parse_kind == 'parse_args'
    direct_argv = ['--old', '/oracles/old', '--core', '/oracles/core', '--cache', '/owned/cache', *receipt_flags]
    actual = current.parse_args(direct_argv)
    assert str(actual.core) == '/oracles/core' and actual.core_source == 'b' * 40
    current.allow_abbrev = False
    controlled = current.parse_args(direct_argv)
    assert vars(actual) == vars(controlled)
    direct.append({'path': str(path), 'exact_core_option_present': True,
                   'parse_kind': parse_kind, 'same_swallowing_bug': False})

after = {str(path): sha(path) for path in files}
assert before == after
result = {'version': 's4-parser-forwarding-audit-v1', 'classification': 'RED reproduced, minimal control GREEN',
          'red': red, 'controlled_fix': green, 'forwarding_cases': forwarding_cases,
          'project_fuzz_review': direct, 'sources': before, 'source_unchanged': True,
          'native_or_compiler_actions': 0, 'affinity': sorted(os.sched_getaffinity(0))}
(HERE / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, indent=2))
