#!/usr/bin/env python3
"""Exercise real disk-loaded SVG jobs across isolated agent roots and a shared cache."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
FILES = ('straps-synth-lmx2595.sexp', 'lmx2595rhar.sexp', 'spi.sexp')


def oracle(kind, runner):
    if kind == 'fixtures':
        expected = json.loads(Path('expected.json').read_text())
        for name, checksum in expected.items():
            assert hashlib.sha256((Path('fixtures') / name).read_bytes()).hexdigest() == checksum
    else:
        result = subprocess.run([runner, '--project', 'guest', *[f'fixtures/{name}' for name in FILES]],
                                capture_output=True, timeout=180)
        assert result.returncode == 0, result.stderr.decode(errors='replace')
        svg = ET.fromstring(result.stdout)
        assert svg.tag == '{http://www.w3.org/2000/svg}svg'
        refs = [node.attrib['data-ref'] for node in svg.iter() if 'data-ref' in node.attrib]
        assert len(refs) == len(set(refs)) == 30, refs
        pins = [node for node in svg.iter() if 'data-pin' in node.attrib]
        assert len(pins) == 99, len(pins)
    print('verified')


def runtime_tools(runner):
    # Inventory modules used by this stdlib-only oracle and their ELF dependencies.
    paths = {Path(sys.executable).resolve(), runner.resolve()}
    paths.update(Path(module.__file__).resolve() for module in tuple(sys.modules.values())
                 if getattr(module, '__file__', None) and Path(module.__file__).is_file())
    for path in tuple(paths):
        if path.suffix == '.so' or path == Path(sys.executable).resolve() or path == runner.resolve():
            linked = subprocess.run(['ldd', str(path)], capture_output=True, text=True)
            for token in linked.stdout.split():
                if token.startswith('/') and Path(token).is_file():
                    paths.add(Path(token).resolve())
    return sorted(map(str, paths))


def experiment(runner, output):
    runner = runner.resolve()
    before = hashlib.sha256(runner.read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='schematic-agents-') as directory:
        base = Path(directory)
        first = base / 'agent one'
        first.mkdir()
        shutil.copytree(ROOT / 'src/schematic/guest', first / 'guest')
        (first / 'fixtures').mkdir()
        expected = {}
        for name in FILES:
            data = (ROOT / 'experiments/schematic/fixtures' / name).read_bytes()
            (first / 'fixtures' / name).write_bytes(data)
            expected[name] = hashlib.sha256(data).hexdigest()
        (first / 'expected.json').write_text(json.dumps(expected))
        shutil.copyfile(__file__, first / 'oracle.py')
        tools = runtime_tools(runner)
        manifest = {'version': 2, 'policy': 'schematic-real-jobs-v1', 'steps': []}
        for name, inputs in [('render', ['guest/*.my', 'fixtures/*.sexp']),
                             ('fixtures', ['fixtures/*.sexp', 'expected.json'])]:
            manifest['steps'].append({'id': name, 'kind': 'test', 'complete': True,
                                     'inputs': ['oracle.py', *inputs], 'tools': tools,
                                     'commands': [[sys.executable, '-S', '-B', 'oracle.py', '--oracle', name,
                                                   '--runner', str(runner)]], 'expect_stdout': 'verified\n'})
        (first / 'verify.json').write_text(json.dumps(manifest, indent=2))
        second = base / 'agent two'
        shutil.copytree(first, second)
        observations = []

        def run(label, root, store='shared', previous=None, mode='full', expect=0):
            report = base / f'{label}.json'
            command = [sys.executable, str(ROOT / 'scripts/verify.py'), str(root / 'verify.json'),
                       '--cache-dir', str(base / store), '--scheduler', str(base / f'{store}.sqlite'),
                       '--report', str(report), '--mode', mode]
            if previous:
                command += ['--previous', str(base / f'{previous}.json')]
            start = time.monotonic()
            result = subprocess.run(command, capture_output=True, timeout=240)
            assert result.returncode == expect, (label, result.stdout.decode(), result.stderr.decode())
            payload = json.loads(report.read_text())
            rows = payload['steps']
            row = {'scenario': label, 'elapsed_seconds': round(time.monotonic() - start, 4),
                   'statuses': {step['id']: step['status'] for step in rows},
                   'executed': sum(bool(step.get('executed')) for step in rows),
                   'cached': sum(step['status'] == 'cached' for step in rows),
                   'coalesced': sum(bool(step.get('coalesced')) for step in rows)}
            return row

        observations.append(run('cold', first))
        observations.append(run('warm', first))
        observations.append(run('equivalent-root', second))
        assert observations[0]['executed'] == 2
        assert observations[1]['cached'] == observations[2]['cached'] == 2
        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = [pool.submit(run, f'concurrent-{i}', first if i % 2 == 0 else second, 'concurrent')
                       for i in range(4)]
            concurrent = [future.result() for future in futures]
        observations.extend(concurrent)
        assert sum(row['executed'] for row in concurrent) == 2, concurrent
        renderer = second / 'guest/svg.my'
        original = renderer.read_text()
        renderer.write_text(original + '\n// Verification experiment: renderer-only edit.\n')
        edited = run('renderer-edit', second, previous='equivalent-root', mode='affected')
        observations.append(edited)
        assert edited['statuses'] == {'render': 'executed', 'fixtures': 'not-selected'}, edited
        renderer.write_text('module svg;\nfn broken(\n')
        broken = run('invalid-renderer', second, previous='renderer-edit', mode='affected', expect=1)
        observations.append(broken)
        assert broken['statuses'] == {'render': 'failed', 'fixtures': 'not-selected'}, broken
        repeated = run('invalid-renderer-retry', second, expect=1)
        observations.append(repeated)
        assert repeated['statuses']['render'] == 'failed' and repeated['executed'] == 1, repeated
        assert hashlib.sha256(runner.read_bytes()).hexdigest() == before
        source_hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted((first / 'guest').glob('*.my'))}
        evidence = {'binary_sha256': before, 'source_sha256': source_hashes,
                    'clients': 4, 'manifest': manifest, 'observations': observations,
                    'limitations': ['Trusted local runtime inventory, not an OS sandbox or adversarial filesystem proof.',
                                    'Suite declarations are explicit; selection is not inferred from guest semantics.',
                                    'Independent XML oracle checks shape and connectivity inventory, not pixel equality.',
                                    'Temporary copied roots simulate worktrees; this does not exercise Git merge certificates.',
                                    'Timings are observations on one shared machine, not performance thresholds.']}
        output.write_text(json.dumps(evidence, indent=2) + '\n')
        print(json.dumps(observations, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runner', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--oracle', choices=['render', 'fixtures'])
    args = parser.parse_args()
    if args.oracle:
        oracle(args.oracle, str(args.runner))
    else:
        if args.output is None:
            parser.error('--output is required for the experiment')
        experiment(args.runner, args.output)


if __name__ == '__main__':
    main()
