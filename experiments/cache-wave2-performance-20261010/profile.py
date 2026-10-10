#!/usr/bin/env python3
"""Profile a fresh edit and its revert using a completed, populated benchmark."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'cache-wave2-20261010'))
import qualify


def descendants(pid):
    pending, found = [pid], set()
    while pending:
        current = pending.pop()
        if current in found:
            continue
        found.add(current)
        try:
            tasks = Path(f'/proc/{current}/task').iterdir()
            for task in tasks:
                pending.extend(map(int, (task / 'children').read_text().split()))
        except (OSError, ValueError):
            pass
    return found


def snapshot_loop(pid, output, done):
    """Save bounded process mappings; monitor overhead makes profiles diagnostic."""
    output.mkdir()
    seen = set()
    while not done.wait(0.02):
        for child in descendants(pid):
            try:
                base = Path(f'/proc/{child}')
                comm = (base / 'comm').read_text().strip()
                executable = os.readlink(base / 'exe')
                identity = (comm, executable)
                if identity in seen or len(seen) >= 32:
                    continue
                seen.add(identity)
                record = {'pid': child, 'comm': comm, 'exe': executable,
                          'cmdline': (base / 'cmdline').read_bytes().replace(b'\0', b' ').decode(errors='replace'),
                          'status': (base / 'status').read_text(), 'maps': (base / 'maps').read_text()}
                (output / f'{child}.json').write_text(json.dumps(record, indent=2) + '\n')
            except OSError:
                pass


def stop_group(process):
    """Stop the isolated launch group and reap its direct child before returning."""
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    try:
        process.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        # A descendant that deliberately escaped its group can retain a pipe.
        # Closing capture keeps cleanup bounded without waiting for that pipe.
        for stream in (process.stdout, process.stderr):
            if stream is not None:
                stream.close()
        process.wait(timeout=5)


def profile(compiler, source, cache, output, label, encoding, mode, *, timeout=1800):
    command = [str(compiler), 'test', '.', '--json', '--jobs=4', '--max-frames=1024', '--cache-dir', str(cache)]
    timing = output / f'{label}.time.json'
    if mode == 'perf':
        instrument = ['perf', 'record', '-F', '99', '-e', 'cycles:u', '--call-graph', 'dwarf,8192',
                      '-o', str(output / f'{label}.perf.data'), '--']
    elif mode == 'strace':
        instrument = ['strace', '-f', '-c', '-o', str(output / f'{label}.strace-summary.txt'), '--']
    else:
        instrument = []
    launched = time.monotonic_ns()
    process = subprocess.Popen(['/usr/bin/time', '-f', '{"peak_rss_kb":%M,"user_s":%U,"system_s":%S,"exit":%x}',
                                '-o', str(timing), *instrument, *command], cwd=source,
                               env=qualify.environment(cache, ['MYLANG_STAGE_CACHE_COMPRESSION=' + encoding]),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    done = threading.Event()
    watcher = threading.Thread(target=snapshot_loop, args=(process.pid, output / f'{label}.proc', done), daemon=True)
    try:
        watcher.start()
        stdout, stderr = process.communicate(timeout=timeout)
    except BaseException:
        stop_group(process)
        raise
    finally:
        done.set()
        if watcher.ident is not None:
            watcher.join()
    wall = (time.monotonic_ns() - launched) / 1e9
    (output / f'{label}.stdout.json').write_bytes(stdout)
    (output / f'{label}.stderr.txt').write_bytes(stderr)
    assert process.returncode == 0, (label, process.returncode, stderr.decode(errors='replace'))
    report = json.loads(stdout)
    assert report['version'] == 'native-tests-v1'
    counts = dict(Counter(t['status'] for t in report['tests']))
    measured = json.loads(timing.read_text().splitlines()[-1])
    result = {'label': label, 'command': command, 'instrumentation': instrument, 'wall_s': wall,
              **measured, 'counts': counts, 'report': report, 'work': qualify.work_records(report),
              'cache': qualify.cache_state(cache)}
    if mode == 'perf':
        for suffix, arguments in [('report', ['report', '--stdio', '--children', '--sort', 'comm,dso,symbol']),
                                  ('buildids', ['buildid-list']), ('headers', ['report', '--stdio', '--header-only'])]:
            with (output / f'{label}.perf-{suffix}.txt').open('w') as stream:
                completed = subprocess.run(['perf', *arguments, '-i', str(output / f'{label}.perf.data')],
                                           stdout=stream, stderr=subprocess.STDOUT)
            result['perf_' + suffix + '_exit'] = completed.returncode
    return result


def main():
    admitted = time.monotonic_ns()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--benchmark', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fixture', default='synthetic-510436')
    parser.add_argument('--variant', choices=['baseline', 'candidate-zlib', 'candidate-none'], default='candidate-zlib')
    parser.add_argument('--phase', choices=['helper', 'private'], default='helper')
    parser.add_argument('--token', type=int, default=9000001)
    parser.add_argument('--mode', choices=['perf', 'strace', 'none'], default='perf')
    parser.add_argument('--submitted-monotonic-ns', type=int)
    args = parser.parse_args()
    assert args.token > 0
    benchmark, output = args.benchmark.resolve(), args.output.resolve()
    previous = json.loads((benchmark / 'results.json').read_text())
    assert previous.get('completed_utc') and args.fixture in previous['fixtures']
    kind = 'baseline' if args.variant == 'baseline' else 'candidate'
    compiler = Path(previous['compilers'][kind]['path'])
    assert qualify.digest(compiler) == previous['compilers'][kind]['sha256'], 'frozen compiler changed'
    source, cache = benchmark / args.fixture / 'source', benchmark / args.fixture / args.variant
    assert cache.is_dir(), 'populated variant cache is required'
    output.mkdir(parents=True, exist_ok=False)
    symbols = output / 'symbols'
    symbols.mkdir()
    package = compiler.parent.parent / 'libexec/mylang/components'
    manifest = json.loads((package / 'cache-plan.json').read_text())
    component = package / manifest['artifact']
    assert qualify.digest(component) == manifest['sha256']
    symbol_records = []
    for name, executable in [('mylang', compiler), ('cache-plan', component)]:
        copied = symbols / name
        shutil.copy2(executable, copied)
        indexed = subprocess.run(['perf', 'buildid-cache', '-a', str(copied)], capture_output=True, text=True)
        symbol_records.append({'name': name, 'original': str(executable), 'copy': str(copied),
                               'sha256': qualify.digest(copied), 'buildid_cache_exit': indexed.returncode,
                               'buildid_cache_stderr': indexed.stderr})
    encoding = 'none' if args.variant.endswith('-none') else 'zlib'
    original_row = next(r for r in previous['records'] if (r['fixture'], r['variant'], r['phase']) == (args.fixture, args.variant, 'cold'))
    changed = source / ('shared.my' if args.phase == 'helper' else 'm0000.my')
    original = changed.read_bytes()
    needle = b'    return 1' if args.phase == 'helper' else b'const marker = 0'
    replacement = f'    return {args.token}'.encode() if args.phase == 'helper' else f'const marker = {args.token}'.encode()
    assert needle in original
    evidence = {'started_utc': datetime.now(timezone.utc).isoformat(), 'benchmark': str(benchmark),
                'benchmark_sha256': qualify.digest(benchmark / 'results.json'), 'affinity': sorted(os.sched_getaffinity(0)),
                'compiler': previous['compilers'][kind], 'symbols': symbol_records,
                'variant': args.variant, 'phase': args.phase, 'token': args.token,
                'cache': str(cache), 'source': str(source), 'original_source_sha256': qualify.digest(changed),
                'mode': args.mode, 'admitted_monotonic_ns': admitted,
                'queue_s': None if args.submitted_monotonic_ns is None else (admitted - args.submitted_monotonic_ns) / 1e9,
                'method': 'Diagnostic inherited-process profile, not an uninstrumented timing comparison. '
                          'GNU time RSS is maximum individual process RSS. Profiler is argv-only; compiler environment '
                          'and populated cache paths match the original benchmark. Snapshot polling is bounded.', 'records': []}
    try:
        changed.write_bytes(original.replace(needle, replacement, 1))
        edited = profile(compiler, source, cache, output, args.phase, encoding, args.mode)
        assert edited['counts'].get('passed', 0) > 0 and not edited['counts'].get('failed', 0)
        assert qualify.normalized(edited) == qualify.normalized(original_row)
        assert qualify.keys(edited) != qualify.keys(original_row), 'edit was not fresh or reachable'
        evidence['records'].append(edited)
        changed.write_bytes(original)
        restored = profile(compiler, source, cache, output, 'revert-' + args.phase, encoding, args.mode)
        assert restored['counts'] == {'cached': len(original_row['report']['tests'])}, restored['counts']
        assert qualify.keys(restored) == qualify.keys(original_row)
        evidence['records'].append(restored)
    finally:
        changed.write_bytes(original)
        evidence['restored_source_sha256'] = qualify.digest(changed)
        evidence['held_s'] = (time.monotonic_ns() - admitted) / 1e9
        evidence['completed_utc'] = datetime.now(timezone.utc).isoformat()
        (output / 'results.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({'output': str(output), 'counts': [r['counts'] for r in evidence['records']],
                      'queue_s': evidence['queue_s'], 'held_s': evidence['held_s']}))


if __name__ == '__main__':
    main()
