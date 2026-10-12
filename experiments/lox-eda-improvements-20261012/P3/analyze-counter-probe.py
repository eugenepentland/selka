#!/usr/bin/env python3
"""Analyze existing bounded probe counters; this performs no guest execution."""
import hashlib
import json
from pathlib import Path

here = Path(__file__).resolve().parent
snapshots = {'heap::string_obj', 'heap::env_obj', 'heap::function_obj', 'heap::closure_obj', 'heap::class_obj', 'p3_query_probe::snapshot_reads'}
queries = {'heap::string_hash', 'heap::env_enclosing', 'heap::env_slot', 'heap::function_arity', 'heap::function_instruction', 'heap::closure_function', 'heap::closure_upvalue', 'heap::class_name', 'heap::class_method', 'heap::instance_class', 'heap::instance_field', 'p3_query_probe::query_reads'}
rows = []
for width in [1, 1024]:
    outputs = [(here / f'{arm}-{width}.stdout').read_text() for arm in ['query', 'snapshot']]
    assert outputs[0] == outputs[1]
    for arm, names in [('query', queries), ('snapshot', snapshots)]:
        path = here / f'{arm}-{width}-counters.json'
        doc = json.loads(path.read_text())
        assert doc['version'] == 'mylang-counters-v1'
        totals, kinds = doc['totals'], doc['kinds']
        assert totals['live_bytes_at_exit'] == 0
        assert all(totals[k] == 0 for k in ['runtime_retains', 'runtime_releases', 'shared_retains', 'shared_releases', 'share_marks', 'share_bytes'])
        assert all(kinds[k]['count'] == 0 for k in ['retain', 'release', 'unique_test'])
        read_functions = [f for f in doc['functions'] if f['name'] in names]
        traffic = sum(f['alloc_bytes'] + f['realloc_added_bytes'] for f in read_functions)
        if arm == 'query':
            assert traffic == 0
            assert all(f[k] == 0 for f in read_functions for k in ['list_copies', 'dict_copies', 'text_copies', 'buffer_copies'])
        rows.append(dict(width=width, arm=arm, iterations=100, read_allocation_traffic_bytes=traffic,
                         whole_process_allocation_traffic_bytes=totals['alloc_bytes'] + totals['realloc_added_bytes'],
                         managed_peak_live_bytes=totals['peak_live_bytes'], managed_exit_live_bytes=totals['live_bytes_at_exit'],
                         raw_counter_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
(here / 'counter-analysis.json').write_text(json.dumps(rows, indent=2) + '\n')
print(json.dumps(rows, indent=2))
