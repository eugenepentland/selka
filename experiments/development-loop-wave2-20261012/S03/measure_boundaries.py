#!/usr/bin/env python3
"""Run bounded paired root/golden cohorts inside an externally admitted window."""
import argparse
from contextlib import suppress
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
SCRATCH = ROOT / '.tmp/s03-paired'
ZIG = Path('/home/epentland/zig-toolchains') / (ROOT / '.zigversion').read_text().strip() / 'zig'
COMPILERS = {
    'C0': {'path': '/home/epentland/ai/canopy/mylang-dl-closeout-20261012-S10/zig-out/bin/mylang', 'sha256': '7755a47e1e3f3eae11073effa41f4716fa7a99c818a4d836b8965c549fd0b57f'},
    'B0': {'path': '/home/epentland/ai/canopy/mylang-dl-closeout-20261012-integration/zig-out/bin/mylang', 'sha256': 'e018f4dc02cba5020dcdb9c74a8bdd4354d11b49d2dfaacf5030b0aa82f176f3'},
}
SELECTED = re.compile(r'guardian/test: (\d+) test\(s\) selected')
RESULT = re.compile(r'guardian/test: RESULT (\{[^\n]+\})')
GOLDEN = re.compile(r'golden parity: checked (\d+) \(source (\d+), fixtures (\d+)\), skipped (\d+) .*mismatches (\d+)')
PREPARED = re.compile(r'golden preparation: executions (\d+), source writes (\d+), source bytes (\d+), fresh work directories (\d+)')

def digest(path):
    with open(path, 'rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def tree_bytes(path):
    total = 0
    for directory, _, files in os.walk(path):
        for name in files:
            try:
                total += (Path(directory) / name).stat().st_size
            except FileNotFoundError:
                pass
    return total

def environment():
    env = os.environ.copy()
    for key in ('MYLANG_COMPILER_SHARED_CACHE', 'MYLANG_TEST_SHARED_CACHE', 'MYLANG_FRONTEND_CACHE'):
        env.pop(key, None)
    env['LC_ALL'] = 'C'
    env['MYLANG_CACHE_PLAN_MODE'] = 'component'
    env['MYLANG_TEST_INDEX_MODE'] = 'component'
    env.pop('MYLANG_COMPONENT_DIR', None)
    return env

def stamp(path):
    stat = Path(path).stat()
    return (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)

def authenticate():
    for label, record in COMPILERS.items():
        assert digest(record['path']) == record['sha256'], label
    tools = json.loads((OUT / 'tool-authority.json').read_text())
    assert digest(ZIG) == tools['zig']['sha256']
    for record in tools['guardian_files'] + tools['component_files']:
        assert digest(record['path']) == record['sha256'], record['path']
    preparation = json.loads((OUT / 'source-preparation.json').read_text())
    for label, snapshot in preparation['sources'].items():
        for record in snapshot['files']:
            assert digest(SCRATCH / label / record['path']) == record['sha256'], (label, record['path'])
    return ({record['path']: stamp(record['path']) for record in COMPILERS.values()} |
            {record['path']: stamp(record['path']) for record in tools['guardian_files'] + tools['component_files']} |
            {str(ZIG): stamp(ZIG)})

def rss(pid):
    try:
        for line in Path(f'/proc/{pid}/status').read_text().splitlines():
            if line.startswith('VmRSS:'):
                return int(line.split()[1])
    except (FileNotFoundError, ProcessLookupError):
        pass
    return 0

def measure(command, cwd, env, name, timeout, require_tests=True):
    raw = OUT / 'raw'
    raw.mkdir(exist_ok=True)
    log = raw / (name + '.log')
    usage = raw / (name + '.usage')
    wrapped = ['/usr/bin/time', '-f', '%e %U %S %M', '-o', str(usage), *map(str, command)]
    started = time.perf_counter()
    peak = 0
    first_pass = None
    observed = b""
    cursor = 0
    with log.open('wb') as output:
        process = subprocess.Popen(wrapped, cwd=cwd, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            while process.poll() is None:
                if time.perf_counter() - started > timeout:
                    raise TimeoutError(name)
                try:
                    children = Path(f'/proc/{process.pid}/task/{process.pid}/children').read_text().split()
                except FileNotFoundError:
                    children = []
                for child in children:
                    peak = max(peak, rss(child))
                with log.open('rb') as captured:
                    captured.seek(cursor)
                    part = captured.read()
                    cursor += len(part)
                observed = (observed + part)[-4096:]
                if first_pass is None and b'guardian/test: PASS' in observed:
                    first_pass = time.perf_counter() - started
                time.sleep(0.01)
        except BaseException:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise
    elapsed = time.perf_counter() - started
    text = log.read_text()
    values = usage.read_text().splitlines()[-1].split()
    row = {'name': name, 'command': list(map(str, command)), 'cwd': str(cwd), 'status': process.returncode,
           'wall_s': elapsed, 'first_useful_feedback_s':first_pass if first_pass is not None else elapsed if b'guardian/test: PASS' in log.read_bytes() else None,
           'feedback_scope':'observed supported whole-root PASS; individual-test feedback unknown; polling10ms', 'user_s': float(values[1]), 'system_s': float(values[2]),
           'max_process_rss_kib': int(values[3]), 'sampled_command_rss_kib': peak,
           'rss_scope': 'GNU time maximum process RSS including waited children; sampled command excludes descendants',
           'selected': [int(value) for value in SELECTED.findall(text)], 'verdicts': [json.loads(value) for value in RESULT.findall(text)],
           'log_sha256': digest(log), 'env_cache_tiers': {key: env.get(key) for key in ('ZIG_LOCAL_CACHE_DIR','ZIG_GLOBAL_CACHE_DIR','TMPDIR','MYLANG_CORE_RUNTIME_CACHE')}}
    row['cache_bytes_after'] = {key: (None if path == '/home/epentland/ai/canopy/.zig-global-cache' else tree_bytes(path)) for key,path in row['env_cache_tiers'].items() if path and key != 'TMPDIR'}
    assert process.returncode == 0, (name, text[-3000:])
    if require_tests:
        assert row['verdicts'] and all(value.get('failed') == 0 and not value.get('aborted') for value in row['verdicts']), name
    return row, text

def build_command(label, cache, global_cache, prefix, kind='scalar', compiler_label=None):
    compiler_label = compiler_label or label
    command = [ZIG, 'build', '--build-file', SCRATCH / label / 'build.zig', 'prepare', 'check',
               '-Dkind=' + kind, '-Dcompiler=' + COMPILERS[compiler_label]['path'],
               '--cache-dir', cache, '--prefix', prefix, '-j4', '--summary', 'all']
    if label == 'C0':
        command.append('-Dbaseline=true')
    return command

def build_pair(index, timeout, only_label=None):
    rows = []
    labels = (only_label,) if only_label else ('C0','B0') if index % 2 == 0 else ('B0','C0')
    for label in labels:
        tree = SCRATCH / label
        store = SCRATCH / f'build-{index:02d}-{label}'
        assert not store.exists(), store
        store.mkdir()
        env = environment()
        env.update(ZIG_LOCAL_CACHE_DIR=str(store / 'local'), ZIG_GLOBAL_CACHE_DIR=str(store / 'global'), TMPDIR=str(ROOT / '.tmp/work'))
        command = build_command(label, store / 'local', store / 'global', store / 'install')
        fixture, compiler = tree / 'src/number_grammar.txt', tree / 'src/compiler.zig'
        originals = {fixture: fixture.read_bytes(), compiler: compiler.read_bytes()}
        try:
            for phase in ('cold', 'warm', 'fixture_edit', 'unrelated_compiler_edit'):
                if phase == 'fixture_edit':
                    fixture.write_bytes(originals[fixture] + b'\n# S03 harmless oracle membership observation\n')
                elif phase == 'unrelated_compiler_edit':
                    # Keep the already validated fixture edit: only compiler now changes.
                    compiler.write_bytes(originals[compiler] + b'\n// S03 unrelated compiler observation.\n')
                row, text = measure(command, ROOT, env, f'build-{index:02d}-{label}-{phase}', timeout)
                artifact = store / 'install/bin/s03-replayed-tests'
                row.update(label=label, phase=phase, pair=index, artifact_bytes=artifact.stat().st_size, artifact_sha256=digest(artifact), named_selected=8,
                           compiled='compile test s03-replayed-tests debug native success' in text,
                           cold_tiers='fresh private Zig local and global' if phase == 'cold' else 'same private local/global from prior phase')
                assert row['selected'] == [15 if label == 'C0' else 9], row['selected']
                assert row['verdicts'][0]['passed'] == row['selected'][0]
                rows.append(row)
        finally:
            for path, data in originals.items():
                path.write_bytes(data)
    return rows

def warm_edits(index, count, timeout):
    rows = []
    originals = {label:(SCRATCH / label / 'src/number_grammar.txt').read_bytes() for label in ('C0','B0')}
    assert originals['C0'] == originals['B0']
    hashes = {'C0':set(),'B0':set()}
    try:
        for edit in range(count):
            labels = ('C0','B0') if edit % 2 == 0 else ('B0','C0')
            for label in labels:
                fixture = SCRATCH / label / 'src/number_grammar.txt'
                payload = originals[label] + f'\n# S03 unique edit cohort{index:02d} case{edit:04d}\n'.encode()
                fixture.write_bytes(payload)
                cache = SCRATCH / (label + '-cache')
                prefix = SCRATCH / (label + '-qualified')
                env = environment()
                env.update(ZIG_LOCAL_CACHE_DIR=str(cache), ZIG_GLOBAL_CACHE_DIR='/home/epentland/ai/canopy/.zig-global-cache', TMPDIR=str(ROOT / '.tmp/work'))
                command = build_command(label,cache,Path(env['ZIG_GLOBAL_CACHE_DIR']),prefix)
                row, text = measure(command,ROOT,env,f'warm-edits-{index:02d}-{edit:02d}-{label}',timeout)
                artifact = prefix / 'bin/s03-replayed-tests'
                artifact_hash = digest(artifact)
                assert artifact_hash not in hashes[label], (label,edit,'constant artifact')
                hashes[label].add(artifact_hash)
                assert row['selected'] == [15 if label=='C0' else 9]
                assert row['verdicts'][0]['passed'] == row['selected'][0]
                assert 'compile test s03-replayed-tests debug native success' in text
                row.update(label=label,phase='unique_oracle_edit',edit=edit,pair=index,named_selected=8,fixture_sha256=digest(fixture),
                           artifact_sha256=artifact_hash,artifact_bytes=artifact.stat().st_size,
                           cold_tiers='qualified private local; pre-existing shared global; fresh unique embedded oracle comment')
                rows.append(row)
                checkpoint = OUT / f'warm-edits-{index:02d}-partial.json'
                checkpoint.write_text(json.dumps({'complete':False,'rows':rows},indent=2)+'\n')
    finally:
        for label, data in originals.items():
            (SCRATCH / label / 'src/number_grammar.txt').write_bytes(data)
    assert len(rows)==2*count
    return rows

def all_units_pair(index, timeout, only_label=None):
    rows = []
    labels = (only_label,) if only_label else ('C0', 'B0') if index % 2 == 0 else ('B0', 'C0')
    for label in labels:
        store = SCRATCH / f'all-units-{index:02d}-{label}'
        assert not store.exists(), store
        store.mkdir()
        env = environment()
        env.update(ZIG_LOCAL_CACHE_DIR=str(store / 'local'), ZIG_GLOBAL_CACHE_DIR=str(store / 'global'), TMPDIR=str(ROOT / '.tmp/work'))
        command = build_command(label, store / 'local', store / 'global', store / 'install', kind='all-units')
        command.remove('check')
        row, _ = measure(command, ROOT, env, f'all-units-{index:02d}-{label}', timeout, require_tests=False)
        files = sorted((store / 'install/bin').iterdir())
        expected = 1 if label == 'C0' else 2
        assert len(files) == expected, files
        row.update(label=label, pair=index, artifact_count=expected,
                   artifacts=[{'path':str(path),'bytes':path.stat().st_size,'sha256':digest(path)} for path in files],
                   artifact_bytes=sum(path.stat().st_size for path in files),
                   selected_work='compile only C0 broad1541 vs B0 broad1532+scalar9; no native test execution',
                   cold_tiers='fresh private Zig local and global, one replay graph invocation')
        rows.append(row)
    return rows

def golden_pair(index, tier, compiler_mode, timeout):
    rows = []
    labels = ('C0','B0') if index % 2 == 0 else ('B0','C0')
    for label in labels:
        artifact = SCRATCH / f'golden-{label}-{compiler_mode}/install/bin/s03-replayed-tests'
        assert artifact.is_file(), artifact
        compiler_label = label if compiler_mode == 'actual' else 'B0'
        store = SCRATCH / (f'golden-cold-{index:02d}-{label}-{compiler_mode}' if tier == 'cold' else f'golden-warm-{label}-{compiler_mode}')
        if tier == 'cold':
            assert not store.exists(), store
        store.mkdir(exist_ok=True)
        env = environment()
        env.update(ZIG_LOCAL_CACHE_DIR=str(store / 'local'), ZIG_GLOBAL_CACHE_DIR=str(store / 'global'),
                   MYLANG_CORE_RUNTIME_CACHE=str(store / 'runtime'), TMPDIR=str(ROOT / '.tmp/work'))
        row, text = measure([artifact], SCRATCH / label, env, f'golden-{tier}-{compiler_mode}-{index:02d}-{label}', timeout)
        match = GOLDEN.search(text)
        assert match and tuple(map(int,match.groups())) == (222,167,55,382,0), text[-2000:]
        prep = PREPARED.search(text)
        if label == 'B0':
            assert prep and tuple(map(int,prep.groups())) == (222,165,66752,222), text[-2000:]
        row.update(label=label, tier=tier, pair=index, compiler_mode=compiler_mode,
                   compiler=COMPILERS[compiler_label], golden_checked=222, mismatches=0,
                   actual_compiler_executions=222, source_writes=222 if label=='C0' else 165,
                   source_bytes=90182 if label=='C0' else 66752, fresh_work_directories=222,
                   artifact_bytes=artifact.stat().st_size, artifact_sha256=digest(artifact),
                   warmth='fresh private runtime/global; fresh program/cache per golden process' if tier=='cold' else 'private runtime/global retained; fresh program/cache per golden process')
        assert row['selected'] == [1] and row['verdicts'][0]['passed'] == 1
        rows.append(row)
    return rows

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('cohort', choices=('build','warm-edits','all-units','golden'))
    parser.add_argument('--pair', type=int, required=True)
    parser.add_argument('--tier', choices=('cold','warm'), default='warm')
    parser.add_argument('--compiler-mode', choices=('actual','controlled'), default='controlled')
    parser.add_argument('--label', choices=('C0','B0'))
    parser.add_argument('--edits', type=int, default=40)
    parser.add_argument('--timeout', type=float, default=240)
    args = parser.parse_args()
    def interrupted(signum, frame):
        raise TimeoutError('measurement window interrupted')
    signal.signal(signal.SIGTERM, interrupted)
    authority = authenticate()
    started = time.perf_counter()
    rows = (build_pair(args.pair,args.timeout,args.label) if args.cohort=='build' else
            warm_edits(args.pair,args.edits,args.timeout) if args.cohort=='warm-edits' else
            all_units_pair(args.pair,args.timeout,args.label) if args.cohort=='all-units' else
            golden_pair(args.pair,args.tier,args.compiler_mode,args.timeout))
    for path, expected in authority.items():
        assert stamp(path) == expected, path
    report = {'schema':'s03-paired-boundary-measurement-v1','cohort':args.cohort,'pair':args.pair,'tier':args.tier,
              'compiler_mode':args.compiler_mode,'label':args.label,'elapsed_s':time.perf_counter()-started,'rows':rows,
              'cpu_affinity':sorted(os.sched_getaffinity(0)),
              'harness_sha256':digest(__file__),'recipe_sha256':digest(OUT / 'replay_build.zig'),
              'tool_authority_sha256':digest(OUT / 'tool-authority.json'),'estimator':'paired ratios and sample median/range; no stable p95 claim'}
    out = OUT / (f'{args.cohort}-pair-{args.pair:02d}' + (f'-{args.label}' if args.label else '') + '.json' if args.cohort!='golden' else f'golden-{args.tier}-{args.compiler_mode}-pair-{args.pair:02d}.json')
    assert not out.exists(), out
    out.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'cohort':args.cohort,'pair':args.pair,'rows':len(rows),'elapsed_s':report['elapsed_s']}))

if __name__ == "__main__":
    main()
