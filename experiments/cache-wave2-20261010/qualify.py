#!/usr/bin/env python3
"""Wave 2 edit qualification with a forced execution and configurable facts oracle."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
ZIG = '/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig'
EDA = Path.home() / '.cache/mylang-large-debug-build-20261009/sources/eda'
LOX = Path.home() / 'ai/canopy/mylang-frontend-redesign/experiments/frontend-followthrough-20261009/external/sources/lox/benchmarks/lox/ports/mylang'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def environment(cache, overrides=()):
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(('MYLANG_', 'MYL_', 'ZIG_'))}
    cache = Path(cache).resolve()
    for directory in ['tmp', 'native', 'zig-global', 'zig-local']:
        (cache / directory).mkdir(parents=True, exist_ok=True)
    env.update(TMPDIR=str(cache / 'tmp'), MYLANG_CORE_RUNTIME_CACHE=str(cache / 'native'),
               MYLANG_ZIG=ZIG, ZIG_GLOBAL_CACHE_DIR=str(cache / 'zig-global'),
               ZIG_LOCAL_CACHE_DIR=str(cache / 'zig-local'))
    for override in overrides:
        name, value = override.split('=', 1)
        env[name] = value
    return env


def work_records(report):
    """Deduplicate additive work by scope, retaining unknown fields verbatim."""
    records = {}
    for test in report.get('tests', []):
        work = test.get('cache', {}).get('work')
        if not isinstance(work, dict):
            continue
        scope = str(work.get('scope', test['name'].split('::')[0]))
        if scope in records and records[scope] != work:
            raise AssertionError(f'inconsistent work counters for {scope}')
        records[scope] = work
    return records


def cache_state(cache):
    files = [p for p in Path(cache).rglob('*') if p.is_file()]
    sizes = [p.stat() for p in files]
    return {'files': len(files), 'logical_bytes': sum(s.st_size for s in sizes),
            'allocated_bytes': sum(s.st_blocks * 512 for s in sizes)}


def run(compiler, source, target, cache, output, label, flags=(), overrides=(), force=False):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    metrics = output / f'{label}.time.json'
    command = [str(Path(compiler).resolve()), 'test', str(target), '--json',
               '--jobs=4', '--cache-dir', str(Path(cache).resolve()), *flags]
    if force:
        command.append('--force')
    native_before = set((Path(cache) / 'native').rglob('*.o'))
    started = time.perf_counter()
    completed = subprocess.run(['/usr/bin/time', '-f',
        '{"peak_rss_kb":%M,"user_s":%U,"system_s":%S,"exit":%x}',
        '-o', str(metrics), *command], cwd=source,
        env=environment(cache, overrides), capture_output=True, text=True, timeout=1800)
    wall = time.perf_counter() - started
    (output / f'{label}.stdout.json').write_text(completed.stdout)
    (output / f'{label}.stderr.txt').write_text(completed.stderr)
    try:
        report = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        raise AssertionError(f'{label}: unusable report, exit {completed.returncode}: {completed.stderr[-4000:]}') from error
    assert report.get('version') == 'native-tests-v1', report
    tests = report['tests']
    names = [t['name'] for t in tests]
    assert len(names) == len(set(names)), f'{label}: duplicate test names: {completed.stderr[-4000:]}'
    counts = Counter(t['status'] for t in tests)
    assert completed.returncode in (0, 1), (label, completed.returncode, completed.stderr)
    assert (completed.returncode == 1) == bool(counts['failed']), (label, counts)
    timed = metrics.read_text().splitlines()[-1]
    added_native = set((Path(cache) / 'native').rglob('*.o')) - native_before
    record = {'label': label, 'wall_s': wall, **json.loads(timed), 'command': command,
              'cwd': str(Path(source).resolve()), 'counts': dict(counts),
              'work': work_records(report), 'report': report,
              'new_native_objects': len(added_native),
              'new_guest_unit_objects': sum(p.parent.name == 'units-v1' for p in added_native),
              'new_runtime_objects': sum(p.parent.name != 'units-v1' for p in added_native),
              'retained_cache': cache_state(cache),
              'warnings_sha256': hashlib.sha256(completed.stderr.encode()).hexdigest()}
    return record


def normalized(record):
    return {t['name']: ('passed' if t['status'] == 'cached' else t['status'],
                        t.get('reason', ''), t.get('at', ''))
            for t in record['report']['tests']}


def keys(record):
    return {t['name']: t.get('cache', {}).get('key') for t in record['report']['tests']}


def warnings(output, record):
    return (Path(output) / f"{record['label']}.stderr.txt").read_bytes()


def assert_warning_parity(output, expected, actual):
    assert warnings(output, expected) == warnings(output, actual), (
        expected['label'], actual['label'], 'observable warning bytes differ')


def warning_matrix(compiler, baseline, output, planner_mode, oracle_env, compression='zlib'):
    """A nonempty diagnostic must survive every replay and forced execution path."""
    output.mkdir(parents=True)
    source = output / 'source'
    source.mkdir()
    (source / 'mylang.json').write_text('{"version":1}\n')
    (source / 'warning_test.my').write_text(
        'func bounded() -> int noalloc:\n    const xs = [1]\n    return len(xs)\n'
        'public func test_warning() -> bool:\n    return bounded() == 1\n')
    mode = ['MYLANG_CACHE_PLAN_MODE=' + planner_mode, 'MYLANG_STAGE_CACHE_COMPRESSION=' + compression]
    records = []
    for label, target, cached in [('warning-cold', 'warning_test.my', False),
                                  ('warning-file-replay', 'warning_test.my', True),
                                  ('warning-directory-replay', '.', True)]:
        actual = run(compiler, source, target, output / 'candidate', output / 'raw', label, overrides=mode)
        forced = run(compiler, source, target, output / 'oracle', output / 'raw', label + '-forced',
                     overrides=[*mode, *oracle_env], force=True)
        assert actual['counts'] == {'cached' if cached else 'passed': 1}, (label, actual['counts'])
        assert normalized(actual) == normalized(forced) and keys(actual) == keys(forced), label
        assert warnings(output / 'raw', actual).count(b'warning[W_NOALLOC_ALLOCATES]') == 1, label
        assert_warning_parity(output / 'raw', actual, forced)
        if records:
            assert_warning_parity(output / 'raw', records[0], actual)
        records.extend([actual, forced])
        if baseline:
            prior = run(baseline, source, target, output / 'baseline', output / 'raw', label + '-baseline', overrides=mode)
            assert normalized(actual) == normalized(prior), label
            assert_warning_parity(output / 'raw', actual, prior)
            records.append(prior)
    return records


def concurrent_edit(compiler, source, original, output, compression='zlib'):
    """Pause a verified planner after source capture, edit, then release execution."""
    output.mkdir(parents=True)
    package = Path(compiler).resolve().parent.parent / 'libexec/mylang/components'
    manifest = json.loads((package / 'cache-plan.json').read_text())
    real = package / manifest['artifact']
    assert digest(real) == manifest['sha256'], 'unverified installed planner'
    private = output / 'components'
    private.mkdir()
    # Preserve test-index deployment should a checked consumer demand it.
    for name in ['cache-plan', 'test-index']:
        m = json.loads((package / f'{name}.json').read_text())
        shutil.copy2(package / m['artifact'], private / m['artifact'])
        shutil.copy2(package / f'{name}.json', private / f'{name}.json')
    ready, release = output / 'ready', output / 'release'
    wrapper = private / 'barrier-cache-plan'
    wrapper.write_text('#!/usr/bin/python3\nimport os, sys, time\nfrom pathlib import Path\n'
        f'ready = Path({str(ready)!r})\nrelease = Path({str(release)!r})\n'
        'ready.write_text("planner reached immutable request")\n'
        'deadline = time.monotonic() + 20\n'
        'while not release.exists():\n'
        '    if time.monotonic() >= deadline:\n        raise SystemExit(253)\n'
        '    time.sleep(0.005)\n'
        f'os.execv({str(real)!r}, [{str(real)!r}, *sys.argv[1:]])\n')
    wrapper.chmod(0o755)
    manifest.update(artifact=wrapper.name, sha256=digest(wrapper))
    (private / 'cache-plan.json').write_text(json.dumps(manifest) + '\n')
    cache = output / 'cache'
    overrides = ['MYLANG_CACHE_PLAN_MODE=component', 'MYLANG_COMPONENT_DIR=' + str(private),
                 'MYLANG_STAGE_CACHE_COMPRESSION=' + compression]
    command = [str(Path(compiler).resolve()), 'test', 'left_test.my', '--json',
               '--cache-dir', str(cache), '--force']
    process = subprocess.Popen(command, cwd=source, env=environment(cache, overrides),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    changed = source / 'shared.my'
    try:
        deadline = time.monotonic() + 20
        while not ready.exists():
            assert process.poll() is None, 'host exited before planner barrier'
            assert time.monotonic() < deadline, 'planner barrier was not reached'
            time.sleep(0.005)
        changed.write_text(original.replace('return 1', 'return 2'))
        release.write_text('source changed; allow planner completion')
        stdout, stderr = process.communicate(timeout=40)
        (output / 'concurrent.stdout.txt').write_bytes(stdout)
        (output / 'concurrent.stderr.txt').write_bytes(stderr)
        assert process.returncode == 1 and b'SourceChanged' in stderr and not stdout, (process.returncode, stdout, stderr)
        for directory in ['tests/receipts-v2', 'tests/manifests-v2']:
            assert not list((cache / directory).glob('*')), f'changed input published success: {directory}'
        current = run(compiler, source, 'left_test.my', cache, output / 'raw', 'current-revision', overrides=overrides)
        forced = run(compiler, source, 'left_test.my', output / 'oracle', output / 'raw', 'current-revision-forced',
                     overrides=overrides, force=True)
        assert normalized(current) == normalized(forced), 'new revision inherited stale success'
        assert keys(current) == keys(forced), 'new revision canonical keys differ'
        assert current['counts'] == {'failed': 2}, current['counts']
        assert_warning_parity(output / 'raw', current, forced)
        return {'command': command, 'exit': process.returncode,
                'diagnostic': stderr.decode(), 'success_publication': False,
                'current': current, 'forced': forced}
    finally:
        release.write_text('cleanup')
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        changed.write_text(original)


def source_copy(source, destination):
    """Copy current sources and fixtures, excluding every cache and native binary."""
    source, destination = Path(source), Path(destination)
    assert not destination.exists(), destination
    def ignored(_directory, names):
        return [n for n in names if n.startswith('.') or n in
                ('zig-out', 'zig-cache', 'target', 'node_modules', '__pycache__')]
    shutil.copytree(source, destination, ignore=ignored)
    files = sorted(destination.rglob('*.my'))
    return {'origin': str(source), 'files': len(files),
            'physical_lines': sum(len(p.read_text().splitlines()) for p in files),
            'source_sha256': {str(p.relative_to(destination)): digest(p) for p in files}}


def fixture(root):
    root.mkdir(parents=True)
    files = {
        'shared.my': 'public func value() -> int:\n    return 1\n',
        'left.my': 'import shared\nfunc leaf_helper() -> int:\n    return shared.value()\npublic func value() -> int:\n    return leaf_helper()\n',
        'right.my': 'import shared\npublic func value() -> int:\n    return shared.value()\n',
        'callback.my': 'import left\nimport right\npublic func choose() -> func() -> int:\n    return left.value\n',
        'left_test.my': 'import left\nimport callback\npublic func test_left() -> bool:\n    return left.value() == 1\npublic func test_callback() -> bool:\n    const selected = callback.choose()\n    return selected() == 1\n',
        'right_test.my': 'import right\npublic func test_right() -> bool:\n    return right.value() == 1\n',
        'payload.bin': 'a',
        'mylang.json': '{"version":1}\n',
    }
    for name, text in files.items():
        (root / name).write_text(text)
    return files


def private_selected_matrix(compiler, output, planner_mode, oracle_env, compression='zlib'):
    """Measure one same-line private edit inside a shared three-test closure."""
    source = output / 'source'
    originals = fixture(source)
    original = originals['left.my'].replace('return shared.value()', 'return shared.value() + 0')
    (source / 'left.my').write_text(original)
    (source / 'combined_test.my').write_text(
        'import left\nimport right\nimport callback\n'
        'public func test_left() -> bool:\n    return left.value() >= 1\n'
        'public func test_callback() -> bool:\n    const selected = callback.choose()\n    return selected() >= 1\n'
        'public func test_right() -> bool:\n    return right.value() >= 1\n')
    mode = ['MYLANG_CACHE_PLAN_MODE=' + planner_mode, 'MYLANG_STAGE_CACHE_COMPRESSION=' + compression]
    records = []
    for label in ['cold', 'noop', 'private']:
        if label == 'private':
            (source / 'left.my').write_text(original.replace('+ 0', '+ 1'))
        records.append(run(compiler, source, 'combined_test.my', output / 'candidate',
                           output / 'raw', label, overrides=mode))
    cold, noop, edited = records
    forced = run(compiler, source, 'combined_test.my', output / 'oracle', output / 'raw',
                 'private-forced', overrides=[*mode, *oracle_env], force=True)
    records.append(forced)
    assert cold['counts'] == {'passed': 3}
    assert noop['counts'] == {'cached': 3}
    assert edited['counts'] == {'passed': 2, 'cached': 1}
    assert normalized(edited) == normalized(forced)
    assert keys(edited) == keys(forced)
    assert_warning_parity(output / 'raw', edited, forced)
    for name, key in keys(cold).items():
        assert (key == keys(edited)[name]) == name.endswith('::test_right'), name
    if planner_mode != 'reference':
        assert len(edited['work']) == 1
        work = next(iter(edited['work'].values()))
        initial = next(iter(cold['work'].values()))
        assert work['producer']['facts']['fresh'] == 1, work
        assert work['producer']['facts']['reused'] == initial['producer']['facts']['fresh'] - 1, work
        assert work['producer']['lowering']['materialized'] == 0, work
        assert work['planner']['reused_tests'] == 1 and work['planner']['planned_tests'] == 2, work
    (source / 'left.my').write_text(original)
    (output / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
    return records


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--baseline', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--oracle-env', action='append', default=[], metavar='NAME=VALUE',
                        help='Disable metadata reuse without changing receipt identity')
    parser.add_argument('--metadata-directory', default='test-keys', help='Candidate cache subdirectory to corrupt and evict; empty skips this qualification')
    parser.add_argument('--planner-mode', choices=['component', 'shadow', 'reference'], default='shadow')
    parser.add_argument('--compression', choices=['zlib', 'none'], default='zlib')
    parser.add_argument('--skip-concurrent', action='store_true', help='Explicitly omit the source-capture barrier qualification')
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    source = root / 'source'
    originals = fixture(source)
    records = []
    summary = {'started_utc': datetime.now(timezone.utc).isoformat(),
               'compiler': {'path': str(args.compiler.resolve()), 'sha256': digest(args.compiler)},
               'baseline': None if not args.baseline else {'path': str(args.baseline.resolve()), 'sha256': digest(args.baseline)},
               'oracle_env': args.oracle_env, 'compression': args.compression, 'planner_mode': args.planner_mode, 'records': records,
               'corruption': 'not requested; no metadata corruption qualification claimed'}

    def save():
        (root / 'results.json').write_text(json.dumps(summary, indent=2) + '\n')

    def compare(label, expected_failed=(), target='.', flags=()):
        mode = ['MYLANG_CACHE_PLAN_MODE=' + args.planner_mode, 'MYLANG_STAGE_CACHE_COMPRESSION=' + args.compression]
        candidate = run(args.compiler, source, target, root / 'candidate', root / 'raw', label, flags=flags, overrides=mode)
        forced = run(args.compiler, source, target, root / 'oracle', root / 'raw', label + '-forced', flags=flags,
                     overrides=[*mode, *args.oracle_env], force=True)
        assert normalized(candidate) == normalized(forced), label
        assert sorted(t['name'] for t in candidate['report']['tests'] if t['status'] == 'failed') == sorted(expected_failed), label
        assert keys(candidate) == keys(forced), f'{label}: key mismatch; oracle env must not enter receipt base identity'
        assert_warning_parity(root / 'raw', candidate, forced)
        assert not forced['counts'].get('cached', 0), label
        records.extend([candidate, forced])
        if args.baseline:
            baseline = run(args.baseline, source, target, root / 'baseline', root / 'raw', label + '-baseline', flags=flags, overrides=mode)
            assert normalized(candidate) == normalized(baseline), label
            assert_warning_parity(root / 'raw', candidate, baseline)
            records.append(baseline)
        save()
        return candidate

    cold = compare('cold')
    assert cold['counts'].get('passed') == 3
    noop = compare('noop')
    assert noop['counts'].get('cached') == 3
    edits = [
        ('private', {'left.my': originals['left.my'].replace('    return shared.value()', '    _ = 101\n    return shared.value()')}, ()),
        ('helper', {'shared.my': originals['shared.my'].replace('    return 1', '    _ = 102\n    return 1')}, ()),
        ('three-file', {name: originals[name] + '\n# three-file qualification\n' for name in ['left.my', 'right.my', 'shared.my']}, ()),
        ('callback', {'callback.my': originals['callback.my'].replace('return left.value', 'return right.value')}, ()),
        ('source-move', {'left.my': '\n\n' + originals['left.my']}, ()),
        ('signature', {'shared.my': 'public func value(seed: int = 1) -> int:\n    return seed\n'}, ()),
        ('effect-ceiling', {'shared.my': 'public func value() -> int effects(managed_allocation):\n    return 1\n'}, ()),
        ('effect-body', {'shared.my': 'public func value() -> int effects(managed_allocation):\n    const values = [1]\n    return len(values)\n'}, ()),
        ('transitive-failure', {'shared.my': originals['shared.my'].replace('return 1', 'return 2')}, ('left_test::test_left', 'left_test::test_callback', 'right_test::test_right')),
        ('discovery-add', {'added_test.my': 'public func test_added() -> bool:\n    return True\n'}, ()),
        ('discovery-delete', {'right_test.my': None}, ()),
    ]
    for label, changes, failures in edits:
        for name, text in changes.items():
            path = source / name
            if text is None:
                path.unlink()
            else:
                path.write_text(text)
        compare(label, failures)
        for name in changes:
            if name in originals:
                (source / name).write_text(originals[name])
            else:
                (source / name).unlink()
        compare(label + '-revert')

    # These episodes intentionally preserve the preceding edited graph until the
    # next step: a split must actually follow a cycle, and an embed byte change
    # must follow publication of the successful embedded dependency.
    failures = ('left_test::test_left', 'left_test::test_callback', 'right_test::test_right')
    embedded = 'const DATA: bytes = embed_bytes("payload.bin")\npublic func value() -> int:\n    return len(DATA)\n'
    episodes = [
        ('layout', [
            ('layout-establish', {'shared.my': 'record Box:\n    value: int\npublic func value() -> int:\n    const box = Box(value=1)\n    return box.value\n'}, ()),
            ('layout-change', {'shared.my': 'record Box:\n    value: int\n    padding: int\npublic func value() -> int:\n    const box = Box(value=1, padding=0)\n    return box.value\n'}, ()),
        ]),
        ('embed', [
            ('embed-establish', {'shared.my': embedded}, ()),
            ('embed-change', {'payload.bin': 'bb'}, failures),
        ]),
        ('recursive', [
            ('recursive-establish', {'shared.my': 'func descend(n: int) -> int:\n    if n == 0:\n        return 1\n    return descend(n - 1)\npublic func value() -> int:\n    return descend(2)\n'}, ()),
            ('recursive-cycle-create', {'shared.my': 'func first(n: int) -> int:\n    if n == 0:\n        return 1\n    return second(n - 1)\nfunc second(n: int) -> int:\n    return first(n)\npublic func value() -> int:\n    return first(2)\n'}, ()),
            ('recursive-cycle-split', {'shared.my': 'func first(n: int) -> int:\n    if n == 0:\n        return 1\n    return second(n - 1)\nfunc second(n: int) -> int:\n    _ = n\n    return 1\npublic func value() -> int:\n    return first(2)\n'}, ()),
        ]),
        ('generated-invariant', [
            ('generated-invariant-establish', {'generated_test.my': '@invariant(self.low <= self.high, "ordered")\npublic record Interval:\n    low: int\n    high: int\npublic func test_interval(interval: Interval) -> bool:\n    return interval == interval\n'}, ()),
            ('generated-invariant-change', {'generated_test.my': '@invariant(self.low >= self.high, "reverse ordered")\npublic record Interval:\n    low: int\n    high: int\npublic func test_interval(interval: Interval) -> bool:\n    return interval == interval\n'}, ()),
        ]),
    ]
    for episode, steps in episodes:
        changed_names = set()
        previous = None
        for label, changes, expected in steps:
            for name, text in changes.items():
                (source / name).write_text(text)
                changed_names.add(name)
            current = compare(label, expected)
            if label == 'generated-invariant-change':
                name = 'generated_test::test_interval'
                assert keys(current)[name] != keys(previous)[name], 'generated invariant root did not change its canonical key'
            previous = current
        for name in changed_names:
            if name in originals:
                (source / name).write_text(originals[name])
            else:
                (source / name).unlink()
        compare(episode + '-revert')

    provider_file = source / 'providers.json'
    provider_flags = ['--cases', str(provider_file)]
    for label, provider, failures in [
        ('provider-establish', originals['shared.my'], ()),
        ('provider-private-edit', originals['shared.my'].replace('return 1', '_ = 103\n    return 1'), ()),
        ('provider-transitive-failure', originals['shared.my'].replace('return 1', 'return 2'), ('left_test::test_left',)),
        ('provider-revert', originals['shared.my'], ()),
    ]:
        provider_file.write_text(json.dumps({'left_test::test_left': {'providers': {'shared.my': provider}}}) + '\n')
        compare(label, failures, 'left_test.my', provider_flags)
    provider_file.unlink()

    if args.metadata_directory:
        metadata = (root / 'candidate' / args.metadata_directory).resolve()
        assert metadata.is_relative_to(root / 'candidate') and metadata.is_dir(), metadata
        payloads = [p for p in metadata.rglob('*') if p.is_file()]
        assert payloads, f'no metadata payloads in {metadata}'
        for payload in payloads:
            payload.write_bytes(b'torn-wave2-metadata')
        # An unobservable source edit bypasses whole-report replay and demands metadata.
        (source / 'left.my').write_text(originals['left.my'] + '\n# metadata corruption demand\n')
        compare('corrupt-metadata')
        shutil.rmtree(metadata)
        (source / 'left.my').write_text(originals['left.my'] + '\n# metadata eviction demand\n')
        compare('evicted-metadata')
        summary['corruption'] = {'directory': args.metadata_directory, 'payload_count': len(payloads)}
        (source / 'left.my').write_text(originals['left.my'])
    summary['private_selected'] = private_selected_matrix(args.compiler, root / 'private-selected', args.planner_mode, args.oracle_env, args.compression)
    summary['warnings'] = warning_matrix(args.compiler, args.baseline, root / 'warnings', args.planner_mode, args.oracle_env, args.compression)
    summary['concurrent_edit'] = 'explicitly skipped' if args.skip_concurrent else {
        'candidate': concurrent_edit(args.compiler, source, originals['shared.my'], root / 'concurrent-candidate', args.compression)}
    if args.baseline and not args.skip_concurrent:
        summary['concurrent_edit']['baseline'] = concurrent_edit(args.baseline, source, originals['shared.my'], root / 'concurrent-baseline', args.compression)
    summary['completed_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    print(json.dumps({'qualified': len(records), 'output': str(root)}))


if __name__ == '__main__':
    main()
