#!/usr/bin/env python3
"""Run all wave-3 correctness gates and instruction coverage on one clean tree.

Every invocation uses a fresh evidence basename and owned compiler/cache paths.
Build admission remains in build-slot.sh; conformance manages its own slots.
The final CPU-10 timing and review are separate, mandatory X steps.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
AREA = Path(__file__).resolve().parents[1]
TOOLS = AREA / 'tools'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def corpora_identity():
    manifest = AREA / 'M0/corpora-source-sha256.json'
    expected = json.loads(manifest.read_text())
    count = 0
    for corpus, files in expected.items():
        for relative, sha in files.items():
            path = ROOT / '.mylang-cache' / corpus / relative
            assert digest(path) == sha, ('corpus changed', path)
            count += 1
    return {'manifest_sha256': digest(manifest), 'files_checked': count}


class Gates:
    def __init__(self, tag):
        if not tag or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in tag):
            raise ValueError('tag must contain lowercase letters, digits and hyphens')
        if git('status', '--porcelain', '--untracked-files=no'):
            raise RuntimeError('tracked tree must be clean')
        self.head = git('rev-parse', 'HEAD')
        self.main = git('rev-parse', 'main')
        subprocess.run(['git', 'merge-base', '--is-ancestor', self.main, self.head], cwd=ROOT, check=True)
        self.area = AREA / 'X' / ('gates-' + tag)
        self.area.mkdir(parents=True, exist_ok=False)
        self.scratch = ROOT / '.tmp/rp3' / ('gates-' + tag)
        self.scratch.mkdir(parents=True, exist_ok=False)
        self.tag = tag
        self.records = []
        self.env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', MYLANG_SLOT_POLL='1',
                        TMPDIR=str(self.scratch), ZIG_LOCAL_CACHE_DIR=str(ROOT / '.zig-cache-rp3'),
                        MYLANG_CORE_RUNTIME_CACHE=str(ROOT / '.mylang-cache' / ('runtime-' + tag)))
        Path(self.env['MYLANG_CORE_RUNTIME_CACHE']).mkdir(parents=True, exist_ok=True)
        self.receipt = {'source_commit': self.head, 'main_commit': self.main,
                        'tag': tag, 'complete': False, 'steps': self.records}
        self.receipt['corpora'] = corpora_identity()

    def unchanged(self):
        if git('rev-parse', 'main') != self.main:
            raise RuntimeError('main advanced during qualification; merge it and rerun this step')
        if git('rev-parse', 'HEAD') != self.head or git('status', '--porcelain', '--untracked-files=no'):
            raise RuntimeError('source changed during qualification')

    def save(self):
        (self.area / 'receipt.json').write_text(json.dumps(self.receipt, indent=1) + '\n')

    def run(self, name, command, kind=None, cwd=ROOT, expected=0, extra=None):
        self.unchanged()
        argv = [str(x) for x in command]
        if kind:
            argv = [str(ROOT / 'scripts/build-slot.sh'), kind, *argv]
        log = self.scratch / (name + '.log')
        print('RUN', name, flush=True)
        started = time.time()
        with log.open('x') as stream:
            status = subprocess.run(argv, cwd=cwd, env=dict(self.env, **(extra or {})),
                                    stdout=stream, stderr=subprocess.STDOUT).returncode
        text = log.read_text(errors='replace')
        summary = [line for line in text.splitlines() if any(word in line for word in
                   ('Build Summary:', 'guardian: run-all:', 'passed,', 'conformance engine=',
                    '.my format:', 'matching ', 'complete:', 'qualified:', 'STOP', 'ERROR'))]
        self.records.append({'name': name, 'command': argv, 'cwd': str(cwd), 'status': status,
                             'expected_status': expected, 'seconds': time.time() - started,
                             'log': str(log.relative_to(ROOT)), 'log_sha256': digest(log),
                             'summary': summary[-25:]})
        self.save()
        self.unchanged()
        if status != expected:
            raise RuntimeError(f'{name}: status {status}, expected {expected}\n{text[-4000:]}')
        print('PASS', name, flush=True)


def main():
    os.sched_setaffinity(0, os.sched_getaffinity(0) - {2, 3, 10, 11})
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--fuzz-cases', type=int, choices=(50, 200), default=200)
    parser.add_argument('--repository-jobs', type=int, choices=(1,),
                        help='serialize the complete repository build graph; keeps all default test shards')
    parser.add_argument('--rerun-repository', action='store_true',
                        help='execute every repository test step even when its prior verdict is cached')
    args = parser.parse_args()
    g = Gates(args.tag)
    g.receipt['fuzz_cases_per_family'] = args.fuzz_cases
    g.receipt['repository_jobs'] = args.repository_jobs
    g.receipt['repository_test_rerun'] = args.rerun_repository
    g.save()
    g.run('build', ['zig', 'build', '--summary', 'all'], 'build')
    repository = ['zig', 'build', 'test', '--summary', 'all']
    if args.repository_jobs is not None:
        repository.append('-j' + str(args.repository_jobs))
    if args.rerun_repository:
        repository.append('-Dtest-rerun=true')
    g.run('repository', repository, 'gate')
    g.run('fmt', ['zig', 'build', 'fmt-check', '--summary', 'all'], 'build')
    qualify = ROOT / 'experiments/new-core-s5-20261007/tools/qualify_merge.py'
    # The inherited qualifier keys its temporary cache by evidence basename.
    # Unique parents alone do not isolate successive integration runs.
    raw = g.area / ('qual-' + args.tag + '-raw')
    additive = g.area / ('qual-' + args.tag + '-additive')
    common = ['python3', qualify, '--shards', '64', '--compiler', 'zig-out/bin/mylang', '--install', 'install']
    g.run('raw', [*common, '--evidence', raw], expected=1)
    g.run('validate-raw-qualification', ['python3', TOOLS / 'validate_qualification.py', '--raw', raw])
    g.run('additive', [*common, '--evidence', additive, '--frontend-reference',
                     ROOT / 'experiments/frontend-fixes-20261009/s5-frontend-reference.json'])
    g.run('validate-qualification', ['python3', TOOLS / 'validate_qualification.py', '--raw', raw, '--additive', additive])
    compilers = ROOT / '.mylang-cache/rp3/compilers' / args.tag
    compilers.mkdir(parents=True, exist_ok=False)
    debug = compilers / 'mylang-debug'
    shutil.copy2(ROOT / 'zig-out/bin/mylang', debug)
    g.receipt['debug_compiler'] = {'path': str(debug), 'sha256': digest(debug)}
    fuzz = g.area / 'fuzz'
    g.run('fuzz', ['python3', ROOT / 'experiments/new-core-s5-20261007/tools/fuzz_matrix.py',
                  '--references', ROOT / 'experiments/new-core-s5-20261007/references/fuzz-v1.json.gz',
                  '--cases', args.fuzz_cases, '--new', TOOLS / 'mylang-migrating', '--evidence', fuzz,
                  '--jobs', '3', '--qualified-head', g.head], 'gate', extra={'FU_PORT_REAL': str(debug)})
    g.run('compact-fuzz', ['python3', TOOLS / 'compact_fuzz.py', fuzz, '--summarize-commands'])
    tests = ROOT / '.mylang-cache/rp3' / args.tag
    g.run('lox-tests', [debug, 'test', 'ports/mylang', '--jobs', '4', '--cache-dir', tests / 'lox-tests'],
          'build', ROOT / '.mylang-cache/lox')
    g.run('eda-tests', [debug, 'test', 'src', '--jobs', '4', '--max-frames', '30000',
                       '--max-steps', '4000000000', '--max-memory', '2G', '--cache-dir', tests / 'eda-tests'],
          'build', ROOT / '.mylang-cache/eda-src')
    prefix = compilers / 'release-fast'
    g.run('release-fast', ['zig', 'build', '-Doptimize=ReleaseFast', '--prefix', prefix, '--summary', 'all'], 'build')
    final = prefix / 'bin/mylang'
    g.receipt['release_fast_compiler'] = {'path': str(final), 'sha256': digest(final)}
    g.run('guest-builds', ['python3', TOOLS / 'build_count_batch.py', '--compiler', final, '--tag', args.tag], 'build')
    bins = ROOT / '.mylang-cache/rp3/ce/bin' / args.tag
    binaries = {path.name: digest(path) for path in bins.iterdir() if path.is_file()}
    assert len(binaries) == 186, len(binaries)
    g.receipt['guest_binaries'] = {'directory': str(bins), 'sha256': binaries}
    g.save()
    lox = bins / 'lox-plain'
    g.run('lox-conformance', ['python3', 'harness/lox_bench.py', 'conformance', '--binary', lox,
                             '--engine', 'both', '--stress', '--jobs', '4'], 'build', ROOT / '.mylang-cache/lox')
    g.run('counting', ['python3', TOOLS / 'corpus_counts.py', '--compiler', final, '--tag', args.tag, 'run', 'all'], 'build')
    g.run('validate-counting', ['python3', TOOLS / 'validate_counts.py', '--tag', args.tag,
                              '--out', g.area / 'counting-gate.json'])
    g.run('archive-counting', ['python3', TOOLS / 'archive_counts.py', '--tag', args.tag,
                              '--out', g.area / 'counts.json.gz'])
    perf = g.area / 'instructions.json'
    g.run('instructions', ['python3', TOOLS / 'corpus_perf.py', '--tags', 'base,' + args.tag,
                           '--rounds', '3', '--out', perf], 'build')
    compressed_perf = perf.with_suffix('.json.gz')
    with gzip.open(compressed_perf, 'wb', compresslevel=9) as stream:
        stream.write(perf.read_bytes())
    perf.unlink()
    g.run('compare-instructions', ['python3', TOOLS / 'compare_instructions.py', '--base', compressed_perf,
                                  '--candidate', compressed_perf, '--base-tag', 'base', '--candidate-tag', args.tag,
                                  '--out', g.area / 'instruction-comparison.json',
                                  '--markdown', g.area / 'instruction-comparison.md'])
    assert digest(debug) == g.receipt['debug_compiler']['sha256']
    assert digest(final) == g.receipt['release_fast_compiler']['sha256']
    assert all(digest(bins / name) == sha for name, sha in binaries.items())
    assert corpora_identity() == g.receipt['corpora']
    g.receipt['corpora']['unchanged_after_gates'] = True
    g.receipt['guest_binaries']['unchanged_after_gates'] = True
    g.receipt['complete'] = True
    g.save()
    print('complete: correctness and instruction gates; CPU-10 timing/review remain mandatory', flush=True)


if __name__ == '__main__':
    main()
