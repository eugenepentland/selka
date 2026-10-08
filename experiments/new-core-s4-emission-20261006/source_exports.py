#!/usr/bin/env python3
"""Private source-unit linkage control; imported entry body policy stays unchanged."""
import argparse
import fcntl
import json
import random
import re
from pathlib import Path
from types import SimpleNamespace
import paired_units as paired
from entry_attributes import DEFINITION, identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attributes', type=Path, required=True)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--actual', type=Path, required=True)
    parser.add_argument('--whole', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    args = parser.parse_args()
    area = args.evidence.resolve()
    area.relative_to(paired.ROOT / 'experiments')
    area.mkdir(exist_ok=False)
    current = json.loads((args.attributes / 'summary.json').read_text())['cases']['result_propagate']
    argv = current['traced_argv']
    paths = [Path(x) for x in argv if x.endswith('.ll')]
    original = {p.name: p for p in (args.base / 'cache/result_propagate').glob('program-*/*.ll')}
    restored = {}
    changes = []
    for path in paths:
        if path.name == 'entry.ll':
            continue
        previous = {m['name']: m['linkage'] for m in DEFINITION.finditer(original[path.name].read_text())}
        changed = []
        text = path.read_text()
        def restore(match):
            if previous.get(match['name'], '').startswith('internal ') and match['linkage'].startswith('hidden '):
                changed.append(match['name'])
                return match[0].replace('define hidden ', 'define internal ', 1)
            return match[0]
        body = DEFINITION.sub(restore, text)
        if body != original[path.name].read_text():
            raise ValueError('restored source body differs from5994 beyond linkage')
        restored[str(path)] = body
        changes += changed
    if not changes:
        raise ValueError('no source export delta')
    references = []
    graph = {name: set() for name in changes}
    for path in paths:
        text = path.read_text()
        for name in changes:
            for line in text.splitlines():
                if '@"' + name + '"' not in line:
                    continue
                if line.startswith('define '):
                    continue
                if 'call fastcc ' not in line or 'store ' in line:
                    raise ValueError('escaping/indirect reference in fixed diagnostic: ' + line)
                references.append({'path': str(path), 'target': name, 'line': line})
        for m in DEFINITION.finditer(text):
            if m['name'] not in graph:
                continue
            end = text.index('\n}', m.end())
            graph[m['name']] |= {n for n in changes if '@"' + n + '"' in text[m.end():end]}
    def visit(name, active, done):
        if name in active:
            raise ValueError('recursive private dependency in fixed diagnostic')
        if name in done:
            return
        for target in graph[name]:
            visit(target, active | {name}, done)
        done.add(name)
    done = set()
    for name in graph:
        visit(name, set(), done)
    report = {'production_change': False, 'complete': False, 'traced_argv': argv, 'restored_functions': changes,
              'reference_audit': references, 'acyclic_graph': {n: sorted(v) for n, v in graph.items()}, 'arms': {}}
    try:
        for arm in ['baseline', 'restore_internal']:
            private = area / arm
            private.mkdir()
            translated = {}
            for path in paths:
                body = restored.get(str(path), path.read_text()) if arm == 'restore_internal' else path.read_text()
                output = private / path.name
                output.write_text(body)
                translated[str(path)] = str(output)
            command = [translated.get(x, x) for x in argv]
            command[command.index('-o') + 1] = str(private / 'program')
            paired.run_build(command, private / 'compile.log')
            report['arms'][arm] = {'argv': command, 'binary': identity(private / 'program'),
                                   'inputs': [identity(private / p.name) for p in paths]}
        with Path('/run/user/1000/mylang-slots/cpu10.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            report['measurement'] = paired.comparison(SimpleNamespace(rounds=7), 'result_propagate', {
                'whole': args.whole, 'actual': args.actual,
                **{arm: area / arm / 'program' for arm in report['arms']},
            }, random.Random(81924))
        report['complete'] = True
    finally:
        (area / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
