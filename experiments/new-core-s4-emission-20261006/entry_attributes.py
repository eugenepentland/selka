#!/usr/bin/env python3
"""Private LLVM-only entry import attributes, preserving traced native input order."""
import argparse
import fcntl
import hashlib
import json
import random
import re
import subprocess
from pathlib import Path
from types import SimpleNamespace
import paired_units as paired

DEFINITION = re.compile(r'^define (?P<linkage>[^@\n]*)@"(?P<name>[^"\n]+)"[^\n]*$', re.MULTILINE)


def identity(path):
    return {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def imported(text):
    return {m['name'] for m in DEFINITION.finditer(text) if 'available_externally' in m['linkage']}


def original_command(args, case, area):
    source = (args.input / 'sources' / case / 'app.my').resolve() if case != 'result_propagate' else paired.ROOT / 'test/core/row_result_propagate.my'
    cache = area / 'traced-cache'
    trace = area / 'native-execve.log'
    argv = ['strace', '-f', '-e', 'trace=execve', '-s', '100000', '-o', str(trace), str(args.core.resolve()),
            'build', str(source), '--release', '-o', str(area / 'traced-program'), '--cache-dir', str(cache),
            '--link', str(paired.ROOT / 'benchmarks/runtime/ports/native_clock.c')]
    paired.run_build(argv, area / 'trace-build.log')
    commands = []
    for line in trace.read_text().splitlines():
        match = re.search(r'execve\("[^"\n]+", (\[.*?\]), ', line)
        if not match:
            continue
        command = json.loads(match[1])
        if len(command) > 1 and command[1] == 'cc' and '-c' not in command and any(x.endswith('.ll') for x in command):
            commands.append(command)
    if len(commands) != 1:
        raise ValueError(f'need one actual unit link command: {commands}')
    original = {Path(x['path']).name: x['sha256'] for x in json.loads((args.input / f'units-{case}.json').read_text())}
    paths = [Path(x) for x in commands[0] if x.endswith('.ll')]
    if {p.name: identity(p)['sha256'] for p in paths} != original:
        raise ValueError('traced source emission differs from retained candidate LLVM')
    return commands[0], paths


def compile_arms(args, case, area):
    argv, paths = original_command(args, case, area)
    entry = next(p for p in paths if p.name == 'entry.ll')
    text = entry.read_text()
    cmain = re.search(r'^define i32 @main\([^\n]*\).*?^}', text, re.MULTILINE | re.DOTALL)[0]
    root = re.findall(r'@"(my\.[^"\n]+::main)"', cmain)
    if len(root) != 1:
        raise ValueError(f'entry target ambiguous: {root}')
    owners = [p for p in paths if p != entry and any(m['name'] == root[0] and 'available_externally' not in m['linkage'] for m in DEFINITION.finditer(p.read_text()))]
    if len(owners) != 1:
        raise ValueError('program entry owner ambiguous')
    forced = imported(owners[0].read_text()) | {root[0]}
    report = {'traced_argv': argv, 'inputs': [identity(p) for p in paths], 'forced': sorted(forced), 'arms': {}}
    for arm in ['baseline', 'ordinary_dependencies', 'ordinary_all']:
        private = area / arm
        private.mkdir()
        replacements = []
        translated = {}
        for path in paths:
            body = path.read_text()
            if arm != 'baseline' and path == entry:
                def adjust(match):
                    ordinary = arm == 'ordinary_all' or match['name'] not in forced
                    if 'available_externally' in match['linkage'] and ordinary:
                        if ' alwaysinline ' not in match[0]:
                            raise ValueError('expected forced attribute absent')
                        replacements.append(match['name'])
                        return match[0].replace(' alwaysinline ', ' ', 1)
                    return match[0]
                body = DEFINITION.sub(adjust, body)
            output = private / path.name
            output.write_text(body)
            translated[str(path)] = str(output)
        command = [translated.get(x, x) for x in argv]
        command[command.index('-o') + 1] = str(private / 'program')
        paired.run_build(command, private / 'compile.log')
        report['arms'][arm] = {'argv': command, 'changed_attributes': replacements,
                              'inputs': [identity(private / p.name) for p in paths], 'binary': identity(private / 'program')}
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--whole', type=Path, required=True)
    parser.add_argument('--core', type=Path, required=True)
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--cases', nargs='+', choices=paired.CASES, default=['packet_decode', 'lox_eval', 'result_propagate'])
    args = parser.parse_args()
    args.input = args.input.resolve()
    area = args.evidence.resolve()
    area.relative_to(paired.ROOT / 'experiments')
    area.mkdir(exist_ok=False)
    report = {'production_change': False, 'complete': False, 'compiler': identity(args.core), 'cases': {}}
    try:
        for case in args.cases:
            private = area / case
            private.mkdir()
            result = compile_arms(args, case, private)
            with Path('/run/user/1000/mylang-slots/cpu10.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                result['measurement'] = paired.comparison(SimpleNamespace(rounds=7), case, {
                    'whole': args.whole / f'row_{case}',
                    'actual': args.input / f'split-{case}',
                    'baseline': private / 'baseline/program',
                    'ordinary_dependencies': private / 'ordinary_dependencies/program',
                    'ordinary_all': private / 'ordinary_all/program',
                }, random.Random(81924))
            report['cases'][case] = result
        report['complete'] = True
    finally:
        (area / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
