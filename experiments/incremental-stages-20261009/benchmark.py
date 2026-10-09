#!/usr/bin/env python3
"""Scale a reachable, namespaced EDA port; measure cold and genuinely edited builds."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import statistics
import subprocess
import time

BASE = Path(os.environ.get('SCALING_BASE', str(Path.home() / '.cache/mylang-large-debug-build-20261009')))
COMPILER = Path(os.environ.get('SCALING_COMPILER', str(BASE / 'compiler/bin/mylang')))
SEED = Path(os.environ.get('SCALING_SEED', str(BASE / 'sources/eda')))
DEPENDENCIES = Path(os.environ.get('SCALING_DEPENDENCIES', str(BASE / 'eda-dependencies.json')))
GOLDENS = Path(os.environ.get('SCALING_GOLDENS', str(Path.home() / 'ai/canopy/mylang-frontend-redesign/experiments/frontend-followthrough-20261009/external/sources/eda/golden')))
MODES = {'optimized_debug': ['--optimize-debug'], 'debug': []}
MEASURED_MODES = ['optimized_debug']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, env, timeout=600):
    process = subprocess.Popen([str(x) for x in command], cwd=cwd, env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        raise RuntimeError(f'timeout: {command}, {stderr[-2000:]!r}')
    return process.returncode, stdout, stderr


def generate(root, copies, seed_files, shared=False):
    root.mkdir(parents=True)
    (root / 'mylang.json').write_text('{"version":1}\n')
    for i in range(copies):
        prefix = f'c{i:03d}'
        for relative in seed_files:
            text = (SEED / relative).read_text()
            text = re.sub(r'(?m)^(import )src\.', rf'\g<1>{prefix}.src.', text)
            if relative == 'src/main.my':
                assert text.count('func main(') == 1
                text = text.replace('func main(', 'public func run_copy(')
            if shared and relative == 'src/support_strs.my':
                before = '    return c >= 65 and c <= 90'
                assert text.count(before) == 1
                text = 'import bench_shared\n' + text.replace(before, '    return bench_shared.is_upper(c)')
            path = root / prefix / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    if shared:
        (root / 'bench_shared.my').write_text(
            'public func is_upper(c: int) -> bool:\n    return c >= 65 and c <= 90\n')
    lines = [f'import c{i:03d}.src.main as app{i:03d}' for i in range(copies)]
    lines += ['', 'func main(args: str[], fs: Filesystem, out: Stream, err: Stream) -> int:',
              '    mut status = 0']
    for i in range(copies):
        lines += [f'    if app{i:03d}.run_copy(args, fs, out, err) != 0:', '        status = 2']
    lines += ['    return status', '']
    (root / 'main.my').write_text('\n'.join(lines))
    files = sorted(root.rglob('*.my'))
    reachable = set()
    stack = ['main']
    while stack:
        module = stack.pop()
        if module in reachable:
            continue
        reachable.add(module)
        text = (root / (module.replace('.', '/') + '.my')).read_text()
        for imported in re.findall(r'(?m)^import ([\w.]+)', text):
            if imported.startswith(('c', 'bench_')):
                stack.append(imported)
    assert len(reachable) == len(files) == 60 * copies + 1 + int(shared)
    contents = [f.read_text() for f in files]
    return {'copies': copies, 'shared_helper_fixture': shared, 'project_modules': len(files),
            'physical_lines': sum(len(t.splitlines()) for t in contents),
            'nonblank_noncomment_lines': sum(bool(line.strip()) and not line.lstrip().startswith('#')
                                           for t in contents for line in t.splitlines()),
            'bytes': sum(f.stat().st_size for f in files),
            'source_sha256': {str(f.relative_to(root)): sha(f) for f in files},
            'reachability': 'All generated project modules reachable through imports from main; every replica called unconditionally.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--copies', type=int, nargs='+', default=[12, 32])
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--threshold', type=float, default=15)
    parser.add_argument('--host-memory', help='Override compiler host memory ceiling for this experiment only')
    parser.add_argument('--few-edits', action='store_true', help='Also change three files before each rebuild')
    parser.add_argument('--dependency-edits', action='store_true',
                        help='At 32 copies also measure shared-helper and new-reachable-function edits')
    args = parser.parse_args()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root / 'tmp').mkdir()
    env = {k: v for k, v in os.environ.items() if not k.startswith(('MYLANG_', 'MYL_CORE_', 'ZIG_'))}
    env.update(MYLANG_JOBS='4', TMPDIR=str(root / 'tmp'))
    if args.host_memory:
        env['MYLANG_HOST_MEMORY_LIMIT'] = args.host_memory
    seed_files = [x['path'] for x in json.loads(DEPENDENCIES.read_text())['inputs']
                  if not x['path'].startswith('@')]
    report = {'started_utc': datetime.now(timezone.utc).isoformat(),
              'compiler': str(COMPILER), 'compiler_sha256': sha(COMPILER),
              'compiler_host_mode': 'ReleaseFast', 'guest_modes': {m: MODES[m] for m in MEASURED_MODES},
              'affinity': sorted(os.sched_getaffinity(0)), 'jobs': 4,
              'repeats_per_edit': args.repeats, 'threshold_s': args.threshold,
              'host_memory_limit': args.host_memory or 'default 8 GiB plus 256 MiB headroom',
              'method': 'Synthetic independently namespaced copies of the 60 reachable EDA MyLang port modules. '
                        'All copies called from root entry. Full CLI build wall time, prewarmed runtime/toolchain, '
                        'fresh frontend and native guest caches for each cold build. Incremental edits retain caches '
                        'and use unique new source/IR content each time. No release guest builds. '
                        'At 32 copies optional extra phases change a common predicate consumed by every replica, and add a reachable predicate function in one replica. Shared-fixture baseline preparation is separate and excluded. Source generation, admission wait, and golden execution validation excluded.',
              'seed_sha256': {p: sha(SEED / p) for p in seed_files},
              'sizes': {}, 'records': [], 'fixture_baselines': [], 'summary': {}}

    def save():
        (root / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

    def build(source, directory, mode, phase, sample, copies, measured=True):
        log = directory / f'{phase}-{sample}'
        environment = dict(env, MYLANG_CORE_RUNTIME_CACHE=str(directory / 'native'))
        command = [COMPILER, 'build', 'main.my', '-o', directory / 'program',
                   '--cache-dir', directory / 'cache', '--report', *MODES[mode]]
        metrics = log.with_suffix('.metrics.json')
        wrapped = ['/usr/bin/time', '-f', '{"peak_rss_kb":%M,"user_s":%U,"system_s":%S}',
                   '-o', metrics, *command]
        load = Path('/proc/loadavg').read_text().strip()
        start = time.perf_counter()
        code, stdout, stderr = run(wrapped, source, environment)
        seconds = time.perf_counter() - start
        log.with_suffix('.stdout').write_bytes(stdout)
        log.with_suffix('.stderr').write_bytes(stderr)
        if code:
            raise RuntimeError(f'{copies}/{mode}/{phase}: exit {code}: {stderr[-6000:].decode()}')
        cache_reports = [json.loads(line) for line in stderr.decode().splitlines()
                         if line.startswith('{"version":"cache-report-v1"')]
        assert len(cache_reports) == 1
        cache = cache_reports[0]
        stages = cache.pop('stages', None)
        source_files = list(source.rglob('*.my'))
        source_lines = sum(len(path.read_text().splitlines()) for path in source_files)
        record = {'copies': copies, 'mode': mode, 'phase': phase, 'sample': sample,
                  'seconds': seconds, 'cache': cache, 'stages': stages,
                  'physical_lines': source_lines, 'project_modules': len(source_files), 'loadavg_before': load,
                  'command': [str(x) for x in command], **json.loads(metrics.read_text())}
        if measured:
            if phase == 'cold':
                assert cache['compiled'] == cache['units'] and cache['reused'] == 0
            elif phase == 'unchanged':
                assert cache['program'] == 'replayed'
            else:
                assert cache['compiled'] > 0, 'edit was optimized away or replayed'
            report['records'].append(record)
            save()
        print(copies, mode, phase, sample, f'{seconds:.3f}s', cache, flush=True)
        return record

    warm = root / 'warmup'
    warm.mkdir()
    (warm / 'main.my').write_text('func main(out: Stream) -> int:\n    out.print(1.25)\n    return 0\n')
    build(warm, warm, 'debug', 'warmup', 0, 0, measured=False)
    runtime = list((warm / 'native').glob('*.o'))
    assert runtime
    report['runtime_seed_sha256'] = {f.name: sha(f) for f in runtime}
    golden = next(c for c in json.loads((GOLDENS / 'manifest.json').read_text())['cases']
                  if c['id'] == 'blinky-breakout')
    expected = {k: v['sha256'] for k, v in golden['outputs'].items()}

    def validate(directory, copies, record, entry_token):
        binary = directory / 'program'
        environment = dict(env, MYL_CORE_LEAKCHECK='1')
        code, stdout, stderr = run([binary], directory, environment)
        assert code == 2 and not stdout
        assert stderr.count(b'usage: eda-sch') == copies
        assert stderr.count(entry_token.encode()) == (copies if entry_token == 'usage: eda-sch ' else 1)
        out = directory / 'golden-output'
        if out.exists():
            shutil.rmtree(out)
        out.mkdir()
        code, stdout, stderr = run([binary, '--model', GOLDENS / 'cases/blinky-breakout/model.sexp',
                                  '--project-dir', GOLDENS / 'projects' / golden['project'],
                                  '--out-dir', out, *golden['flags']], directory, environment)
        actual = {str(f.relative_to(out)): sha(f) for f in out.rglob('*') if f.is_file()}
        assert code == 0 and not stderr, (code, stderr[-2000:])
        assert stdout.count(b'eda-sch: ') == copies, 'not every replica executed'
        assert actual == expected, 'export golden mismatch'
        record['execution_check'] = 'passed: all replicas ran; usage verified; export hashes match; leak check enabled'
        record['binary_bytes'] = binary.stat().st_size
        save()

    for copies in args.copies:
        source = root / str(copies) / 'source'
        report['sizes'][str(copies)] = generate(source, copies, seed_files)
        print('GENERATED', copies, report['sizes'][str(copies)]['physical_lines'], 'lines', flush=True)
        save()
        entry = source / 'c000/src/main.my'
        helper = source / 'c000/src/support_strs.my'
        entry_original, helper_original = entry.read_text(), helper.read_text()
        helper2 = source / 'c001/src/support_strs.my'
        helper2_original = helper2.read_text() if copies >= 2 else None
        modes = list(MEASURED_MODES)
        for mode in modes:
            entry.write_text(entry_original)
            helper.write_text(helper_original)
            if helper2_original is not None:
                helper2.write_text(helper2_original)
            directory = root / str(copies) / mode
            (directory / 'native').mkdir(parents=True)
            for f in runtime:
                shutil.copy2(f, directory / 'native' / f.name)
            cold = build(source, directory, mode, 'cold', 0, copies)
            validate(directory, copies, cold, 'usage: eda-sch ')
            replay = build(source, directory, mode, 'unchanged', 0, copies)
            validate(directory, copies, replay, 'usage: eda-sch ')
            for sample in range(args.repeats):
                token = f'usage: eda-sch-bench{sample:03d} '
                assert entry_original.count('usage: eda-sch ') == 1
                entry.write_text(entry_original.replace('usage: eda-sch ', token))
                record = build(source, directory, mode, 'entry_edit', sample, copies)
                validate(directory, copies, record, token)
            # Keep the last entry edit; each subsequent sample changes only a helper body.
            for sample in range(args.repeats):
                before = 'return c >= 65 and c <= 90'
                after = f'return (c >= 65 and c <= 90) or c == {192 + sample}'
                assert helper_original.count(before) == 1
                helper.write_text(helper_original.replace(before, after))
                record = build(source, directory, mode, 'helper_edit', sample, copies)
                validate(directory, copies, record, token)
            if args.few_edits and copies >= 2:
                for sample in range(args.repeats):
                    token = f'usage: eda-sch-few{sample:03d} '
                    entry.write_text(entry_original.replace('usage: eda-sch ', token))
                    before = 'return c >= 65 and c <= 90'
                    after = f'return (c >= 65 and c <= 90) or c == {200 + sample}'
                    helper.write_text(helper_original.replace(before, after))
                    helper2.write_text(helper2_original.replace(before, after))
                    record = build(source, directory, mode, 'three_file_edit', sample, copies)
                    assert record['cache']['compiled'] == 3
                    validate(directory, copies, record, token)
        report['summary'][str(copies)] = {}
        phases = ['cold', 'unchanged', 'entry_edit', 'helper_edit']
        if args.dependency_edits and copies == 32:
            # This starts from the prior normal-fixture incremental state. Each
            # sample creates a new actually called function; global IR IDs may
            # shift, but unaffected units must still be reusable.
            for sample in range(args.repeats):
                name = f'bench_dependency_{sample:03d}'
                body = f'return (c >= 65 and c <= 90) or c == {232 + sample}'
                updated = helper_original.replace('return c >= 65 and c <= 90', f'return {name}(c)')
                updated += f'\n\npublic func {name}(c: int) -> bool:\n    {body}\n'
                helper.write_text(updated)
                record = build(source, directory, mode, 'dependency_edit', sample, copies)
                record['changed_sources'] = {str(helper.relative_to(source)): sha(helper)}
                validate(directory, copies, record, token)
            phases.append('dependency_edit')
            # Shared dependency baseline is independent of the comparable
            # seed/entry/helper/three-file phases and is not a measured sample.
            shared_source = root / str(copies) / 'shared-source'
            report['sizes'][f'{copies}-shared'] = generate(shared_source, copies, seed_files, shared=True)
            shared_directory = root / str(copies) / f'{mode}-shared'
            (shared_directory / 'native').mkdir(parents=True)
            for f in runtime:
                shutil.copy2(f, shared_directory / 'native' / f.name)
            baseline = build(shared_source, shared_directory, mode, 'shared_baseline', 0, copies, measured=False)
            report['fixture_baselines'].append(baseline)
            validate(shared_directory, copies, baseline, 'usage: eda-sch ')
            shared_helper = shared_source / 'bench_shared.my'
            shared_original = shared_helper.read_text()
            for sample in range(args.repeats):
                shared_helper.write_text(shared_original.replace('return c >= 65 and c <= 90',
                    f'return (c >= 65 and c <= 90) or c == {240 + sample}'))
                record = build(shared_source, shared_directory, mode, 'shared_helper_edit', sample, copies)
                record['changed_sources'] = {'bench_shared.my': sha(shared_helper)}
                validate(shared_directory, copies, record, 'usage: eda-sch ')
            phases.append('shared_helper_edit')
        if args.few_edits and copies >= 2:
            phases.append('three_file_edit')
        for phase in phases:
            report['summary'][str(copies)][phase] = {}
            for mode in MEASURED_MODES:
                samples = [r['seconds'] for r in report['records']
                           if (r['copies'], r['mode'], r['phase']) == (copies, mode, phase)]
                report['summary'][str(copies)][phase][mode] = {
                    'median_s': statistics.median(samples), 'min_s': min(samples),
                    'max_s': max(samples), 'samples_s': samples}
        save()
        crossed = [phase for phase in phases if phase.endswith('edit')
                   if report['summary'][str(copies)][phase]['optimized_debug']['median_s'] > args.threshold]
        if crossed:
            report['stopped_at'] = {'copies': copies, 'reason': 'optimized Debug edit median exceeded threshold',
                                    'phases': crossed}
            break
    assert sha(COMPILER) == report['compiler_sha256']
    assert {p: sha(SEED / p) for p in seed_files} == report['seed_sha256']
    report['completed_utc'] = datetime.now(timezone.utc).isoformat()
    save()
    print('COMPLETE', root / 'results.json', flush=True)


if __name__ == '__main__':
    main()
