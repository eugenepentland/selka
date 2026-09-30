#!/usr/bin/env python3
"""Strict module/whole byte oracle for all distinct 43-row corpus programs."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path('tests').resolve()))
from module_compile_oracle import Program


class ProviderProgram(Program):
    def invoke(self, args, **kwargs):
        if args[0] in ('build', 'link-modules'):
            args = args + ['--provider', str(Path('src/schematic/native_schematic.c').resolve())]
        return super().invoke(args, **kwargs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mylang')
    parser.add_argument('work', type=Path)
    parser.add_argument('--json', required=True, type=Path)
    parser.add_argument('--source', required=True)
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--index', type=Path, default=Path(__file__).with_name('corpus_programs.json'))
    parser.add_argument('--lox-entry', required=True, type=Path)
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error('jobs must be positive')
    if args.work.exists():
        parser.error('work root must be fresh')
    args.work = args.work.resolve()
    args.work.mkdir(parents=True)
    programs = json.loads(args.index.read_text())
    todo = {}
    for row in programs:
        if row['kind'] == 'single':
            key, entry = row['build_key'], Path(row['src'])
        elif row['kind'] == 'schematic':
            key, entry = 'schematic', Path('src/schematic/guest/main.my')
        else:
            key, entry = 'lox', args.lox_entry
        if key not in todo:
            todo[key] = {'entry': str(entry.resolve()), 'kind': row['kind'], 'rows': []}
        todo[key]['rows'].append(row['id'])
    assert len(programs) == 43 and len(todo) == 29
    def compare(item):
        key, row = item
        cls = ProviderProgram if row['kind'] == 'schematic' else Program
        program = cls(args.mylang, row['entry'], args.work / key, False, 'rc')
        program.execute = False
        result = program.result()
        result['build_key'], result['corpus_rows'], result['kind'] = key, row['rows'], row['kind']
        print(key, result['status'], result.get('modules'), result.get('problems'), flush=True)
        return result
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(compare, todo.items()))
    totals = {'distinct_programs': len(results), 'corpus_rows': sum(len(row['corpus_rows']) for row in results),
              'equal': sum(row['status'] == 'equal' for row in results),
              'executables_identical': sum(row.get('executables_identical', False) for row in results),
              'modules': sum(row.get('modules', 0) for row in results),
              'units_compared': sum(row.get('units_compared', 0) for row in results),
              'interfaces_compared': sum(row.get('interfaces_compared', 0) for row in results),
              'reference_failed': sum(row['status'] == 'reference-failed' for row in results),
              'different': [row for row in results if row['status'] != 'equal']}
    receipt = {'source': args.source, 'compiler': str(Path(args.mylang).resolve()),
               'compiler_sha256': hashlib.sha256(Path(args.mylang).read_bytes()).hexdigest(),
               'protocol': 'explicit compile-module for every module; zero whole fallback; provider supplied to both final links; no guest execution in this byte oracle',
               'totals': totals, 'results': results}
    args.json.write_text(json.dumps(receipt, indent=1))
    print(json.dumps(totals, indent=1))
    return int(totals['equal'] != 29 or totals['executables_identical'] != 29 or totals['reference_failed'] != 0)


if __name__ == '__main__':
    sys.exit(main())
