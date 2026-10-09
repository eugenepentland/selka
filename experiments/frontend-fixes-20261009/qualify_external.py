#!/usr/bin/env python3
"""Replay frozen frontend qualification, retaining summaries and failed output only."""
import argparse
import concurrent.futures
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

HISTORY = '0bbfeb740'
HIST_AREA = 'experiments/frontend-followthrough-20261009/external'
FROZEN = Path('/home/epentland/ai/canopy/mylang-frontend-redesign') / HIST_AREA / 'sources'
REFERENCES = Path('/home/epentland/ai/canopy/mylang-worktrees/codex-frontend-integration/experiments/frontend-current-lang-oracle-20261008')


def sha(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def inventory(root):
    return {p.relative_to(root).as_posix(): sha(p.read_bytes())
            for p in sorted(root.rglob('*')) if p.is_file() and '.git' not in p.parts}


def historical(root, path):
    return subprocess.check_output(['git', 'show', HISTORY + ':' + path], cwd=root)


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def execute(argv, cwd, timeout=600):
    started = time.monotonic()
    try:
        result = subprocess.run(list(map(str, argv)), cwd=cwd, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        result = subprocess.CompletedProcess(argv, 124, error.stdout or b'', error.stderr or b'')
    return result, time.monotonic() - started


def failure(output, label, result):
    path = output / 'failures' / label
    path.parent.mkdir(parents=True, exist_ok=True)
    path.with_suffix('.stdout').write_bytes(result.stdout)
    path.with_suffix('.stderr').write_bytes(result.stderr)
    save(path.with_suffix('.json'), {'command': list(map(str, result.args)), 'status': result.returncode})


def modes(args, corpus):
    reference, source = REFERENCES / corpus, FROZEN / corpus
    identity = json.loads((reference / 'identity.json').read_bytes())
    oldroot = identity['source_worktree']
    items = []
    for category in ('current', 'configured'):
        for mode in ('debug', 'release', 'verify'):
            path = reference / (category + '-' + mode + '.json')
            if path.exists():
                items.extend((category + '/' + mode + '/' + name, row)
                             for name, row in json.loads(path.read_bytes())['files'].items())
    items.extend(('directory/' + mode, row) for mode, row in json.loads((reference / 'directory.json').read_bytes()).items())

    def one(item):
        label, saved = item
        receipt_path = reference / saved['receipt']
        receipt = json.loads(receipt_path.read_bytes())
        argv = receipt['command'].copy()
        assert argv[0] == identity['oracle']['path']
        argv[0] = str(args.compiler)
        argv[argv.index('--cache-dir') + 1] = str(args.scratch / (corpus + '-modes-cache'))
        argv = [str(source) + a[len(oldroot):] if a.startswith(oldroot + '/') else a for a in argv]
        if corpus == 'eda' and (label.startswith('directory/') or label.endswith('/sexpr_parser_test')):
            argv += ['--seed', '8679566789041942096']
        cwd = source if receipt['cwd'] == oldroot else receipt['cwd']
        result, elapsed = execute(argv, cwd)
        expected = json.loads(receipt_path.with_suffix('.stdout').read_bytes())
        try:
            actual = json.loads(result.stdout)
        except (ValueError, UnicodeDecodeError):
            actual = {}
        if not isinstance(actual, dict):
            actual = {}
        mapping = 'src.' if corpus == 'eda' else ''
        wanted = sorted((mapping + t['name'], t['status']) for t in expected['tests'])
        found = sorted((t['name'], t['status']) for t in actual.get('tests', []))
        passed = wanted == found and all(status == 'passed' for _, status in found) and result.returncode == receipt['returncode'] and result.returncode != 124
        if not passed:
            failure(args.output, corpus + '-modes/' + label, result)
        row = {'passed': passed, 'tests': len(found), 'status': result.returncode,
               'membership_and_verdicts_equal': wanted == found, 'seconds': elapsed,
               'membership_verdict_sha256': sha(canonical(found)),
               'reference_membership_verdict_sha256': sha(canonical(wanted)),
               'reference_receipt_sha256': sha(receipt_path.read_bytes()),
               'command_sha256': sha(canonical(argv)), 'stdout_sha256': sha(result.stdout),
               'stderr_sha256': sha(result.stderr)}
        print(corpus, label, 'PASS' if passed else 'FAIL', flush=True)
        return label, row

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = dict(pool.map(one, items))
    result = {'commands': len(rows), 'passed': sum(r['passed'] for r in rows.values()),
              'module_mapping': 'src. prefix' if corpus == 'eda' else 'identity',
              'labels_sha256': sha(canonical(sorted(rows))), 'results': rows}
    save(args.output / (corpus + '-modes.json'), result)
    return result


def native(args, corpus):
    source = FROZEN / corpus
    relative = 'benchmarks/lox/ports/mylang/main.my' if corpus == 'lox' else 'mylang/src/main.my'
    binary = args.scratch / (corpus + '-release')
    build, elapsed = execute([args.compiler, 'build', source / relative, '-o', binary,
                              '--release', '--cache-dir', args.scratch / 'native-cache'], source)
    build_row = {'status': build.returncode, 'seconds': elapsed,
                 'stdout_sha256': sha(build.stdout), 'stderr_sha256': sha(build.stderr)}
    if build.returncode:
        failure(args.output, corpus + '-build', build)
        save(args.output / (corpus + '-native.json'), {'build': build_row, 'passed': False})
        raise RuntimeError(corpus + ' native build failed')
    binary_sha = sha(binary.read_bytes())
    baseline_bytes = historical(args.root, HIST_AREA + '/' + corpus + '-native-final/answers.json')
    baseline = json.loads(baseline_bytes)['files']
    answers = {}
    if corpus == 'lox':
        rules_path = source / 'benchmarks/lox/harness/lox_bench.py'
        spec = importlib.util.spec_from_file_location('frozen_lox_rules', rules_path)
        rules = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = rules
        spec.loader.exec_module(rules)
        items = []
        for engine in ('vm', 'tree'):
            for stress in (False, True):
                for path in sorted(rules.CORPUS.rglob('*.lox')):
                    relative = path.relative_to(rules.CORPUS).as_posix()
                    if rules.skipped(relative, engine):
                        continue
                    expected = rules.parse_expectations(path, 'c' if engine == 'vm' else 'java')
                    if expected is not None:
                        items.append((engine, stress, relative, path, expected))

        def one(item):
            engine, stress, relative, path, expected = item
            key = engine + '/' + ('gc-stress' if stress else 'normal') + '/' + relative
            argv = [binary, '--engine=' + engine, *(['--gc-stress'] if stress else []), path]
            run, _ = execute(argv, source, 60)
            problems = rules.validate(expected, run)
            row = {'source_sha256': sha(path.read_bytes()),
                   'tests': [[key, 'failed' if problems else 'passed', '']],
                   'exit_code': run.returncode, 'stdout_sha256': sha(run.stdout),
                   'stderr_sha256': sha(run.stderr), 'problems': problems}
            if problems or row != baseline.get(key):
                failure(args.output, 'lox-native/' + key, run)
            return key, row

        with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
            answers = dict(pool.map(one, items))
        assert len(answers) == 974
    else:
        golden = source / 'golden'
        manifest = json.loads((golden / 'manifest.json').read_bytes())
        for case in manifest['cases']:
            key = case['id']
            model = golden / 'cases' / key / 'model.sexp'
            project = golden / 'projects' / case['project']
            output = args.scratch / 'eda-outputs' / key
            run, _ = execute([binary, '--model', model, '--project-dir', project,
                              '--out-dir', output, *case['flags']], source)
            files = inventory(output)
            expected = {name: sha((golden / 'cases' / key / 'expected' / name).read_bytes()) for name in case['outputs']}
            problems = ([] if run.returncode == 0 else ['process exit ' + str(run.returncode)])
            if files != expected:
                problems.append('output file set or bytes differ from unchanged goldens')
            row = {'source_sha256': sha(model.read_bytes()), 'project_inputs': inventory(project),
                   'tests': [[key, 'failed' if problems else 'passed', '']], 'exit_code': run.returncode,
                   'stdout_sha256': sha(run.stdout), 'stderr_sha256': sha(run.stderr),
                   'outputs': files, 'problems': problems}
            answers[key] = row
            if problems or row != baseline.get(key):
                failure(args.output, 'eda-native/' + key, run)
                if output.exists():
                    shutil.copytree(output, args.output / 'failures' / 'eda-outputs' / key)
            if output.exists():
                shutil.rmtree(output)
        assert len(answers) == 34
    mismatches = sorted(set(answers) ^ set(baseline)) + sorted(k for k in answers.keys() & baseline.keys() if answers[k] != baseline[k])
    summary = {'build': build_row, 'cases': len(answers), 'mismatches': mismatches,
               'passed': not mismatches and all(not r['problems'] for r in answers.values()),
               'binary_sha256': binary_sha, 'binary_unchanged': sha(binary.read_bytes()) == binary_sha,
               'answers_sha256': sha(canonical(answers)), 'reference_answers_sha256': sha(canonical(baseline)),
               'reference_file_sha256': sha(baseline_bytes), 'case_membership_sha256': sha(canonical(sorted(answers)))}
    save(args.output / (corpus + '-native.json'), summary)
    print(corpus, 'native', summary['cases'], summary['passed'], flush=True)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root', 'compiler', 'output', 'scratch'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=3)
    args = parser.parse_args()
    for name in ('root', 'compiler', 'output', 'scratch'):
        setattr(args, name, getattr(args, name).resolve())
    assert not args.output.exists() and not args.scratch.exists()
    args.output.mkdir(parents=True)
    args.scratch.mkdir(parents=True)
    os.environ.update(MYL_CORE_LEAKCHECK='1', PYTHONDONTWRITEBYTECODE='1')
    sys.dont_write_bytecode = True
    initial = {'compiler': sha(args.compiler.read_bytes()), 'runner': sha(Path(__file__).read_bytes()),
               'sources': {c: inventory(FROZEN / c) for c in ('lox', 'eda')},
               'production': {d: inventory(args.root / d) for d in ('src', 'std', 'stdlib')},
               'build': {p: sha((args.root / p).read_bytes()) for p in ('build.zig', 'build.zig.zon')}}
    result = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.root, text=True).strip(),
              'reference_commit': HISTORY, 'compiler_sha256': initial['compiler'], 'runner_sha256': initial['runner'],
              'compiler_path': str(args.compiler), 'reference_root': str(REFERENCES),
              'source_roots': {c: str(FROZEN / c) for c in ('lox', 'eda')},
              'historical_runner_sha256': {name: sha(historical(args.root, HIST_AREA + '/' + name)) for name in ('qualify_modes.py', 'tools/frontend_external_oracle.py')},
              'qualified': False, 'corpora': {}}
    frozen_inventories = {c: json.loads(historical(args.root, HIST_AREA + '/' + c + '-modes-successor/input-identities.json'))['migrated'] for c in ('lox', 'eda')}
    assert initial['sources'] == frozen_inventories, 'source inputs differ from the frozen qualification inventory'
    try:
        for corpus in ('lox', 'eda'):
            result['corpora'][corpus] = {'modes': modes(args, corpus), 'native': native(args, corpus)}
        assert sum(c['modes']['commands'] for c in result['corpora'].values()) == 450
        result['qualified'] = all(c['modes']['commands'] == c['modes']['passed'] and c['native']['passed'] and c['native']['binary_unchanged'] for c in result['corpora'].values())
    finally:
        guard = {'compiler_unchanged': sha(args.compiler.read_bytes()) == initial['compiler'],
                 'runner_unchanged': sha(Path(__file__).read_bytes()) == initial['runner'],
                 'sources_unchanged': all(inventory(FROZEN / c) == initial['sources'][c] for c in ('lox', 'eda')),
                 'production_unchanged': all(inventory(args.root / d) == initial['production'][d] for d in ('src', 'std', 'stdlib')),
                 'build_unchanged': all(sha((args.root / p).read_bytes()) == value for p, value in initial['build'].items()),
                 'sources_match_frozen_reference': initial['sources'] == frozen_inventories,
                 'source_inventories_sha256': {c: sha(canonical(v)) for c, v in initial['sources'].items()},
                 'production_inventory_sha256': sha(canonical(initial['production']))}
        result['source_guard'] = guard
        result['qualified'] &= all(value for key, value in guard.items() if key.endswith('unchanged'))
        # Per-command rows are in their corpus summaries, not duplicated here.
        for corpus in result['corpora'].values():
            corpus['modes'].pop('results', None)
        save(args.output / 'summary.json', result)
    if not result['qualified']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
