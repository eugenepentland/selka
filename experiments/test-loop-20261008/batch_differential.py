"""Item 4 differential: batched test processes (NEW-CORE-TEST-BATCH-1) against one
process per test (MYLANG_TEST_ISOLATE=1) on real suites.

Each corpus runs once in each mode with --force, so every test executes; both modes
share one cache, so the second mode's builds come from the object cache. The reports
must name the same tests with the same status, reason and property evidence; any
difference fails the run. Wall times are recorded.

With --breaks N, N seeded break edits follow, one at a time: an assertion that fails at
run time is inserted into a function (keys_differential.py's sites), so every test
reaching it traps, and both modes must again agree on every verdict before the edit
is reverted.

  batch_differential.py --compiler BIN --corpus eda|lox|lang|core --scratch DIR --out FILE [--breaks N --seed S]
"""
import argparse
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import random
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from keys_differential import candidates  # noqa: E402
REPO = HERE.parents[1]
CORPORA = {
    # name: (git repo, revision, path in the repo, test targets, extra flags)
    'eda': (Path('/home/epentland/ai/canopy/eda-bench'), '7e938b6', 'mylang', ['src'],
            ['--max-frames', '30000', '--max-steps', '4000000000', '--max-memory', '2G']),
    'lox': (REPO, 'f44302d8', 'benchmarks/lox/ports/mylang', ['.'], ['--max-steps=100000000']),
    'lang': (REPO, 'HEAD', 'tests/lang', ['.'], []),
    # The runner fixtures that need no linked helper, each its own entry.
    'core': (REPO, 'HEAD', 'test/core', ['c_runner_properties.my', 'c_runner_standins.my', 'c_runner_failures.my',
                                         'c_runner_state_capture.my', 'c_runner_byte_buffer.my', 'runner_cases.my'],
             ['--seed', '7', '--property-runs', '20']),
}


def extract(repo, revision, prefix, dest):
    data = subprocess.check_output(['git', '-C', str(repo), 'archive', revision, prefix])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            if member.isfile():
                target = dest / Path(member.name).relative_to(prefix)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())


def run(compiler, work, cache, target, flags, mode):
    env = dict(os.environ)
    env.pop('MYLANG_TEST_ISOLATE', None)
    if mode == 'isolated':
        env['MYLANG_TEST_ISOLATE'] = '1'
    for name in ('xdg', 'zig-global', 'zig-local', 'tmp'):
        (cache / name).mkdir(parents=True, exist_ok=True)
    env.update(XDG_CACHE_HOME=str(cache / 'xdg'), ZIG_GLOBAL_CACHE_DIR=str(cache / 'zig-global'),
               ZIG_LOCAL_CACHE_DIR=str(cache / 'zig-local'), TMPDIR=str(cache / 'tmp'), MYL_CORE_LEAKCHECK='1')
    start = time.monotonic()
    done = subprocess.run([compiler, 'test', target, '--json', '--force', '--cache-dir', str(cache / 'mylang')] + flags,
                          cwd=work, env=env, capture_output=True, text=True)
    wall = time.monotonic() - start
    try:
        report = json.loads(done.stdout)
    except json.JSONDecodeError:
        return {'exit': done.returncode, 'wall': wall, 'tests': None, 'stderr': done.stderr[-2000:]}
    tests = {t['name']: {k: t.get(k) for k in ('status', 'reason', 'property')} for t in report['tests']}
    return {'exit': done.returncode, 'wall': wall, 'tests': tests, 'stderr': done.stderr[-2000:]}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--corpus', choices=sorted(CORPORA), required=True)
    parser.add_argument('--scratch', required=True)
    parser.add_argument('--out', required=True)
    parser.add_argument('--breaks', type=int, default=0)
    parser.add_argument('--seed', type=int, default=7)
    args = parser.parse_args()
    repo, revision, prefix, targets, flags = CORPORA[args.corpus]
    scratch = Path(args.scratch) / args.corpus
    shutil.rmtree(scratch, ignore_errors=True)
    work = scratch / 'tree'
    extract(repo, revision, prefix, work)
    cache = scratch / 'cache'
    rows = {'corpus': args.corpus, 'revision': revision, 'compiler': args.compiler, 'targets': []}
    differences = 0
    _, sites = candidates(work)
    rng = random.Random(args.seed)
    plan = [(None, None)] + [(n, rng.choice(sites)) for n in range(args.breaks)]
    for n, site in plan:
        original = None
        if site is not None:
            path, line, indent = site
            original = path.read_text()
            lines = original.splitlines(keepends=True)
            lines.insert(line, f'{indent}assert len("probe") == {1000 + n}, "probe {n}"\n')
            path.write_text(''.join(lines))
        for target in targets:
            # The first run fills the object cache; the timed pair follows, isolated first.
            run(args.compiler, work, cache, target, flags, 'batched')
            isolated = run(args.compiler, work, cache, target, flags, 'isolated')
            batched = run(args.compiler, work, cache, target, flags, 'batched')
            row = {'target': target, 'exit': [batched['exit'], isolated['exit']],
                   'wall': [round(batched['wall'], 3), round(isolated['wall'], 3)]}
            if site is not None:
                row['break'] = {'file': str(site[0].relative_to(work)), 'line': site[1] + 1}
            if batched['tests'] is None or isolated['tests'] is None:
                row['invalid'] = {'batched': batched['stderr'], 'isolated': isolated['stderr']}
                differences += 1
            else:
                names = sorted(set(batched['tests']) | set(isolated['tests']))
                differ = [n for n in names if batched['tests'].get(n) != isolated['tests'].get(n)]
                row['tests'] = len(names)
                row['counts'] = {s: sum(1 for t in batched['tests'].values() if t['status'] == s) for s in ('passed', 'failed', 'unsupported', 'skipped')}
                row['differ'] = [{'name': n, 'batched': batched['tests'].get(n), 'isolated': isolated['tests'].get(n)} for n in differ]
                differences += len(differ) + (batched['exit'] != isolated['exit'])
            rows['targets'].append(row)
            print(json.dumps({k: row[k] for k in row if k != 'differ'} | {'differ': len(row.get('differ', []))}), flush=True)
        if original is not None:
            site[0].write_text(original)
    rows['differences'] = differences
    Path(args.out).write_text(json.dumps(rows, indent=1) + '\n')
    print(json.dumps({'corpus': args.corpus, 'differences': differences}))
    raise SystemExit(1 if differences else 0)


if __name__ == '__main__':
    main()
