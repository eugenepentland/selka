#!/usr/bin/env python3
"""Check archived complete inventory accounting without treating partial evidence as success."""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('inventory', type=Path)
parser.add_argument('report', type=Path)
args = parser.parse_args()
plan = json.loads(args.inventory.read_text())
report = json.loads(args.report.read_text())
expected = {group['id'] for group in plan['groups']}
actions = report.get('actions', [])
seen = [item.get('id', item.get('group')) for item in actions]
# Exact field names are verified against actual exported records; unsupported shape fails.
if any(item is None for item in seen):
    raise SystemExit('unsupported action record shape; cannot establish coverage')
coverage = plan.get('coverage', {})
members = plan.get('action_metadata', [])
coverage_exact = (plan.get('version') == 2 and bool(expected)
                  and type(coverage.get('required_actions')) is int
                  and coverage['required_actions'] > 0
                  and coverage['required_actions'] == coverage.get('registered_actions')
                  and coverage.get('unknown_actions') == []
                  and {item['id'] for item in members} == expected
                  and sum(len(item['steps']) for item in members) == coverage['required_actions']
                  and report.get('action_metadata') == members)
complete = (coverage_exact and len(seen) == len(set(seen)) and set(seen) == expected
            and report.get('success') is True and report.get('status') == 0
            and report.get('inputs_stable') is True)
print(json.dumps({'complete': complete, 'required_count': len(expected),
                  'observed_count': len(seen), 'missing': sorted(expected-set(seen)),
                  'unexpected': sorted(set(seen)-expected)}, indent=2))
raise SystemExit(0 if complete else 1)
