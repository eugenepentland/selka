"""T3b differential: derived per-test keys (NEW-CORE-TEST-KEYS-1) against the per-test
oracle (MYLANG_TEST_KEYS=per-test) over seeded edits to a real corpus.

For every edit, and again after reverting it, both modes run the corpus's tests in
their own caches. `break` edits insert an assertion that fails at run time into a
function, so every test reaching it must fail: both modes must report the same failing
tests on every run, or a stale `cached` verdict hid a failure (a wrong answer), and the
run fails. Tests one mode reruns and the other does not are counted. Wall times are
recorded per run.

  keys_differential.py --compiler BIN --corpus eda|lox|lang --edits N --seed S --out FILE
"""
import argparse
import json
import os
from pathlib import Path
import random
import re
import shutil
import subprocess
import tarfile
import io
import time

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CORPORA = {
    # name: (git repo, revision, path in the repo, test target, extra flags)
    'eda': (Path('/home/epentland/ai/canopy/eda-bench'), '7e938b6', 'mylang', 'src',
            ['--max-frames', '30000', '--max-steps', '4000000000', '--max-memory', '2G']),
    'lox': (REPO, 'f44302d8', 'benchmarks/lox/ports/mylang', '.', ['--max-steps=100000000']),
    'lang': (REPO, 'd575a1984', 'tests/lang', '.', []),
}


def extract(repo, revision, prefix, dest):
    data = subprocess.check_output(['git', '-C', str(repo), 'archive', revision, prefix])
    with tarfile.open(fileobj=io.BytesIO(data)) as archive:
        for member in archive.getmembers():
            if member.isfile():
                target = dest / Path(member.name).relative_to(prefix)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.extractfile(member).read())


def run(args, work, target, flags, mode):
    env = dict(os.environ)
    env.pop('MYLANG_TEST_KEYS', None)
    if mode == 'oracle':
        env['MYLANG_TEST_KEYS'] = 'per-test'
    cache = work.parent / f'cache-{mode}'
    for name in ('xdg', 'zig-global', 'zig-local', 'tmp'):
        (cache / name).mkdir(parents=True, exist_ok=True)
    env.update(XDG_CACHE_HOME=str(cache / 'xdg'), ZIG_GLOBAL_CACHE_DIR=str(cache / 'zig-global'),
               ZIG_LOCAL_CACHE_DIR=str(cache / 'zig-local'), TMPDIR=str(cache / 'tmp'))
    start = time.monotonic()
    done = subprocess.run([args.compiler, 'test', target, '--json', '--cache-dir', str(cache / 'mylang')] + flags,
                          cwd=work, env=env, capture_output=True, text=True)
    wall = time.monotonic() - start
    try:
        report = json.loads(done.stdout)
    except json.JSONDecodeError:
        return {'exit': done.returncode, 'wall': wall, 'rerun': None, 'error': done.stderr[-2000:]}
    rerun = sorted(t['name'] for t in report['tests'] if t['status'] != 'cached')
    failed = sorted(t['name'] for t in report['tests'] if t['status'] == 'failed')
    return {'exit': done.returncode, 'wall': wall, 'rerun': rerun, 'failed': failed}


DEF = re.compile(r'^(\s*)(public )?def \w+')


def candidates(work):
    files = [p for p in sorted(work.rglob('*.my')) if not p.name.endswith('_test.my')]
    sites = []
    for path in files:
        lines = path.read_text().splitlines(keepends=True)
        for i, line in enumerate(lines):
            m = DEF.match(line)
            if not m or m.group(1):
                continue
            j = i
            while j < len(lines) and not lines[j].rstrip().endswith(':'):
                j += 1
            k = j + 1
            while k < len(lines) and not lines[k].strip():
                k += 1
            if k >= len(lines):
                continue
            indent = re.match(r'\s*', lines[k]).group(0)
            if not indent or lines[k].lstrip().startswith(('"""', "'''")):
                continue
            sites.append((path, k, indent))
    return files, sites


def edit(rng, work, files, sites, kind, n):
    if kind in ('body', 'string', 'break'):
        path, line, indent = rng.choice(sites)
        text = {'body': f'_ = {n}\n', 'string': f'_ = "probe {n}"\n', 'break': f'assert len("probe") == {n}, "probe {n}"\n'}[kind]
        lines = path.read_text().splitlines(keepends=True)
        lines.insert(line, indent + text)
        where = line + 1
    else:
        path = rng.choice(files)
        lines = path.read_text().splitlines(keepends=True)
        if kind == 'interface':
            lines.append(f'\n\npublic def probe_added_{n}() -> int:\n    return {n}\n')
            where = len(lines)
        else:
            header = next((i + 1 for i, l in enumerate(lines) if l.startswith(('module ', 'import '))), 0)
            lines.insert(header, f'# probe {n}\n')
            where = header + 1
    original = path.read_text()
    path.write_text(''.join(lines))
    return path, original, where


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True)
    parser.add_argument('--corpus', choices=sorted(CORPORA), required=True)
    parser.add_argument('--edits', type=int, default=20)
    parser.add_argument('--seed', type=int, default=7)
    parser.add_argument('--scratch', required=True)
    parser.add_argument('--out', required=True)
    args = parser.parse_args()
    repo, revision, prefix, target, flags = CORPORA[args.corpus]
    scratch = Path(args.scratch) / args.corpus
    shutil.rmtree(scratch, ignore_errors=True)
    work = scratch / 'tree'
    extract(repo, revision, prefix, work)
    rng = random.Random(args.seed)
    rows = {'corpus': args.corpus, 'revision': revision, 'compiler': args.compiler, 'seed': args.seed, 'warm': {}, 'edits': []}
    for mode in ('derived', 'oracle'):
        cold = run(args, work, target, flags, mode)
        warm = run(args, work, target, flags, mode)
        rows['warm'][mode] = {'cold_wall': cold['wall'], 'cold_rerun': len(cold['rerun'] or []), 'warm_rerun': warm['rerun'], 'warm_wall': warm['wall']}
    files, sites = candidates(work)
    missed_total = 0
    wrong_total = 0
    for n in range(args.edits):
        kind = rng.choice(['body', 'body', 'string', 'interface', 'move', 'break', 'break'])
        path, original, where = edit(rng, work, files, sites, kind, 1000 + n)
        row = {'kind': kind, 'file': str(path.relative_to(work)), 'line': where}
        for phase in ('edit', 'revert'):
            if phase == 'revert':
                path.write_text(original)
            derived = run(args, work, target, flags, 'derived')
            oracle = run(args, work, target, flags, 'oracle')
            if derived['rerun'] is None or oracle['rerun'] is None:
                row[phase] = {'invalid': True, 'derived': derived, 'oracle': oracle}
                continue
            missed = sorted(set(oracle['rerun']) - set(derived['rerun']))
            extra = sorted(set(derived['rerun']) - set(oracle['rerun']))
            missed_total += len(missed)
            wrong_total += derived['failed'] != oracle['failed']
            row[phase] = {'oracle_rerun': len(oracle['rerun']), 'derived_rerun': len(derived['rerun']), 'missed': missed, 'extra': extra,
                          'oracle_wall': round(oracle['wall'], 3), 'derived_wall': round(derived['wall'], 3),
                          'failed_same': derived['failed'] == oracle['failed']}
        rows['edits'].append(row)
        print(json.dumps({'n': n, **{k: row[k] for k in ('kind', 'file', 'line')},
                          'edit': {k: row['edit'].get(k) for k in ('oracle_rerun', 'derived_rerun', 'missed', 'extra', 'failed_same', 'oracle_wall', 'derived_wall')} if 'edit' in row else None}), flush=True)
    rows['missed_total'] = missed_total
    rows['wrong_total'] = wrong_total
    Path(args.out).write_text(json.dumps(rows, indent=1) + '\n')
    print(json.dumps({'corpus': args.corpus, 'edits': args.edits, 'missed_total': missed_total, 'wrong_total': wrong_total}))
    raise SystemExit(1 if missed_total or wrong_total else 0)


if __name__ == '__main__':
    main()
