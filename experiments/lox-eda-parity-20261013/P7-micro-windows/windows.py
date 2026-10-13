#!/usr/bin/env python3
"""Resumable guest-boundary windows for the pinned seven-arm text micro protocol."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


class WindowDeferred(Exception):
    """Setup crossed the window boundary before any child was launched."""


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def atomic(path, value):
    temp = path.with_name(path.name + '.pending')
    with temp.open('w') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)


def load_tools(path):
    old = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location('pinned_micro_measure', path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.dont_write_bytecode = old


def expected(tools, spec, count):
    old = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        return tools.registry.checksum(spec['case'], spec['size'], count, spec['seed']) if spec['protocol'] == 'kernel' else spec['expected_stdout']
    finally:
        sys.dont_write_bytecode = old


def new_state(spec_path, tools_path, cpu, timeout, tools):
    spec = json.loads(spec_path.read_text())
    assert len(spec['arms']) == 7 and (spec['warmups'], spec['rounds'], spec['rss_rounds']) == (3, 15, 3)
    registry_dir = tools.REGISTRY_PATH.resolve().parent
    oracle_paths = [registry_dir.parent / 'oracle.py', *[registry_dir / group / 'oracle.py' for group in ('compute', 'collections', 'text')]]
    paths = {str(spec_path.resolve()), str(tools_path.resolve()), str(Path(__file__).resolve()), str(tools.REGISTRY_PATH.resolve()), *spec.get('files', []), *map(str, oracle_paths)}
    for extra in [tools_path.with_name('observe_cell.py'), Path('/usr/bin/time'), Path(sys.executable).resolve(), Path(__file__).resolve().parents[3] / 'scripts/build-slot.sh', Path('/home/epentland/.config/mylang/dev-env.sh')]:
        if extra.exists():
            paths.add(str(extra.resolve()))
    for entry in [*spec['arms'].values(), *spec.get('counted', {}).values()]:
        if entry.get('binary'):
            assert sha(entry['binary']) == entry['sha256']
            paths.add(entry['binary'])
    document = {'schema': 'text-gap-cell-v1', 'spec': spec, 'started_utc': tools.stamp(),
        'identities': {p: sha(p) for p in sorted(paths)}, 'cpu': cpu, 'timeout_seconds': timeout,
        'loadavg_before': os.getloadavg(), 'ordering': 'rotated blocks, reversed every n rounds; full blocks balance positions exactly',
        'environment': {k: tools.runtime_environment()[k] for k in ('GOMAXPROCS', 'GOGC', 'GOMEMLIMIT', 'GOAMD64', 'GOFLAGS', 'GOEXPERIMENT', 'GOTOOLCHAIN')},
        'arm_status': {n: {'status': 'ok'} if e['status'] == 'ok' else e for n, e in spec['arms'].items()},
        'pilots': [], 'warmups': [], 'samples': [], 'rss': [], 'counted': {}, 'cpu_ticks_before': tools.cpu_snapshot()}
    return {'document': document, 'phase': 'pilot' if spec['protocol'] == 'kernel' else 'warmups',
            'round': 0, 'position': 0, 'count': 31 if spec['protocol'] == 'kernel' else 1,
            'pilot_results': [], 'sequence': 0, 'active': None, 'windows': []}


def order(state, tools):
    spec = state['document']['spec']
    names = list(spec['arms'])
    phase = state['phase']
    if phase == 'counted':
        return list(spec.get('counted', {}))
    return tools.balanced_order(names, state['round'], spec['cell'] + '/' + ('samples' if phase == 'samples' else phase))


def advance_round(state, tools):
    spec = state['document']['spec']
    phase = state['phase']
    state['position'] = 0
    if phase == 'pilot':
        results = state['pilot_results']
        count, pilot = state['count'], state['round']
        state['document']['pilots'].append({'iterations': count, 'arms': results})
        if results:
            fastest = min(r['kernel_ns'] for r in results)
            slowest = max(r['kernel_ns'] for r in results)
            state['last_pilot_fastest'] = fastest
            state['last_pilot_slowest'] = slowest
        else:
            fastest = state.get('last_pilot_fastest')
            slowest = state.get('last_pilot_slowest')
        reason = 'target'
        next_count = None
        if not results:
            reason = 'no_admitted_arm'
        elif slowest > spec['max_slowest_kernel_ms'] * 1e6:
            reason = 'one_iteration_exceeds_budget' if count == 1 else 'slowest_arm_budget'
            if count > 1 and pilot < 9:
                next_count = max(1, min(count - 1, int(count * spec['max_slowest_kernel_ms'] * 1e6 / slowest * .9)))
        elif fastest >= spec['target_fastest_kernel_ms'] * 1e6:
            pass
        elif count >= spec['max_iterations']:
            reason = 'iteration_cap'
        else:
            growth = min(20, spec['target_fastest_kernel_ms'] * 1e6 / fastest, spec['max_slowest_kernel_ms'] * 1e6 / slowest)
            if growth < 1.05:
                reason = 'near_target_growth'
            elif pilot == 9:
                reason = 'pilot_limit'
            else:
                next_count = min(spec['max_iterations'], max(count + 1, int(count * growth)))
        if next_count is not None:
            state.update(count=next_count, round=pilot + 1, pilot_results=[])
            return
        state['document']['calibration'] = {'iterations': count, 'fastest_ns': fastest, 'slowest_ns': slowest,
            'reason': reason, 'limited': fastest is None or fastest < spec['target_fastest_kernel_ms'] * 1e6}
        state.update(phase='warmups', round=0, pilot_results=[])
    elif phase == 'counted':
        state['phase'] = 'complete'
    else:
        state['round'] += 1
        maximum = {'warmups': spec['warmups'], 'samples': spec['rounds'], 'rss': spec['rss_rounds']}[phase]
        if state['round'] == maximum:
            state.update(phase={'warmups': 'samples', 'samples': 'rss', 'rss': 'counted'}[phase], round=0)
    if state['phase'] == 'warmups':
        state['document']['iterations'] = state['count']
        state['document']['expected'] = expected(tools, spec, state['count'])


def execute_one(state, tools, output, launch_deadline=None):
    names = order(state, tools)
    if state['position'] == len(names):
        advance_round(state, tools)
        return
    name = names[state['position']]
    doc, phase, count = state['document'], state['phase'], state['count']
    spec = doc['spec']
    counted = phase == 'counted'
    entry = spec['counted' if counted else 'arms'][name]
    admitted = entry['status'] == 'ok' if counted else doc['arm_status'][name]['status'] == 'ok'
    if not admitted:
        if counted:
            doc['counted'][name] = entry
        state['position'] += 1
        return
    argv = [entry['binary']]
    argv += [spec['case'], str(spec['size']), str(count), str(spec['seed'])] if spec['protocol'] == 'kernel' else entry.get('args', [])
    env = tools.runtime_environment()
    counter_path = output / ('cell.' + name + '.counters.json')
    if counted:
        assert not counter_path.exists(), 'never overwrite a counted observation'
        env['MYLANG_COUNTERS'] = str(counter_path.resolve())
    with tempfile.NamedTemporaryFile() as rss_file:
        command = ['/usr/bin/time', '-f', '%M', '-o', rss_file.name, *argv] if phase == 'rss' else argv
        want = expected(tools, spec, count)
        if launch_deadline is not None and time.monotonic() >= launch_deadline:
            raise WindowDeferred()
        result = tools.validate(tools.execute(command, doc['timeout_seconds'], env, spec.get('cwd')), want, spec['protocol'])
        if result['status'] == 'ok' and phase == 'rss':
            value = Path(rss_file.name).read_text().strip()
            if not value.isdigit() or int(value) <= 0:
                result.update(status='invalid_rss', rss_output=value)
            else:
                result['peak_rss_kib'] = int(value)
    if counted and result['status'] == 'ok':
        if not counter_path.exists():
            result['status'] = 'missing_counters'
        else:
            result.update(counter_path=str(counter_path), counter_sha256=sha(counter_path), metrics=tools.counters(counter_path))
            if result['metrics']['live_bytes_at_exit'] != 0:
                result['status'] = 'managed_leak'
            if entry.get('zero_rc') and (result['metrics']['rc_events'] or result['metrics']['unique_test'] or json.loads(counter_path.read_text())['totals'].get('share_marks', 0)):
                result['status'] = 'unexpected_rc'
    result = {'arm': name, 'iterations': count, **result}
    if counted:
        doc['counted'][name] = result
    else:
        result.update(phase='pilot' if phase == 'pilot' else phase, round=state['round'] - spec['warmups'] if phase == 'warmups' else state['round'])
        if result['status'] != 'ok':
            doc['arm_status'][name] = result
        elif phase == 'pilot':
            state['pilot_results'].append(result)
        else:
            doc[phase].append(result)
    state['position'] += 1


def finish(state, tools):
    doc = state['document']
    spec = doc['spec']
    doc['iterations'] = state['count']
    doc['expected'] = expected(tools, spec, state['count'])
    doc['summary'] = {}
    for name in spec['arms']:
        samples = [r for r in doc['samples'] if r['arm'] == name]
        rss = [r['peak_rss_kib'] for r in doc['rss'] if r['arm'] == name]
        complete = doc['arm_status'][name]['status'] == 'ok' and len(samples) == spec['rounds'] and len(rss) == spec['rss_rounds']
        doc['summary'][name] = {'complete': complete, 'status': doc['arm_status'][name],
            'kernel_ns_per_iteration': tools.summarize([r['kernel_ns'] / state['count'] for r in samples]) if complete and spec['protocol'] == 'kernel' else None,
            'process_wall_ns': tools.summarize([r['process_wall_ns'] for r in samples]) if complete else None,
            'peak_rss_kib': tools.summarize(rss) if complete else None}
    doc.update(identities_after={p: sha(p) for p in doc['identities']}, cpu_ticks_after=tools.cpu_snapshot(), loadavg_after=os.getloadavg(), finished_utc=tools.stamp(),
               windows=state['windows'], window_note='Guest-boundary resumptions only; each guest keeps original clocks/deadline. Counted runs never supply timing/RSS. CPU snapshots span all windows and intervening queue time.')
    assert doc['identities'] == doc['identities_after']
    return doc


def save(state, output, kind):
    with (output / 'checkpoint.jsonl').open('a') as stream:
        stream.write(json.dumps({'kind': kind, 'state': state}) + '\n')
        stream.flush()
        os.fsync(stream.fileno())
    atomic(output / 'state.json', state)


def last_checkpoint(path):
    # Read the final full record only; growing journals must not consume a window.
    with path.open('rb') as stream:
        stream.seek(0, os.SEEK_END)
        position = stream.tell()
        data = b''
        while position:
            size = min(position, 65536)
            position -= size
            stream.seek(position)
            data = stream.read(size) + data
            lines = data.splitlines()
            if len(lines) >= 2 or position == 0:
                return json.loads(lines[-1])['state']
    raise AssertionError('empty interrupted checkpoint')


def window(args):
    start = time.monotonic()
    assert os.environ.get('MYLANG_ADMISSION_KIND') == 'timing', 'one outer timing lease required'
    assert args.cpu in os.sched_getaffinity(0)
    os.sched_setaffinity(0, {args.cpu})
    tools = load_tools(args.tools)
    if not args.output.exists():
        args.output.mkdir(parents=True)
        spec = json.loads(args.spec.read_text())
        missing = [Path(p) for p in spec.get('files', []) if not Path(p).exists()]
        for path in missing:
            assert path.name.endswith('.host-before.json') and path.resolve().is_relative_to(args.output), 'missing immutable input or foreign host snapshot; create a fresh spec bound to this worker output'
            observer = load_tools(args.tools.with_name('observe_cell.py'))
            path.parent.mkdir(parents=True, exist_ok=True)
            atomic(path, observer.snapshot(args.cpu))
        state = new_state(args.spec, args.tools, args.cpu, args.timeout, tools)
        save(state, args.output, 'initial')
    else:
        state = last_checkpoint(args.output / 'checkpoint.jsonl')
        assert state['active'] is None, 'interrupted guest is ambiguous; preserve attempt and start a new output'
        assert state['document']['cpu'] == args.cpu and state['document']['timeout_seconds'] == args.timeout
        assert state['document']['spec'] == json.loads(args.spec.read_text())
        assert str(args.spec.resolve()) in state['document']['identities'] and str(args.tools.resolve()) in state['document']['identities']
    expected_receipts = {'window-%04d.json' % r['index'] for r in state['windows']}
    assert {p.name for p in args.output.glob('window-*.json')} == expected_receipts, 'orphan immutable window receipt; preserve attempt before any new guest'
    for r in state['windows']:
        path = args.output / ('window-%04d.json' % r['index'])
        assert json.loads(path.read_text()) == r, 'window receipt changed'
        if r['index']:
            assert r['previous_receipt_sha256'] == sha(args.output / ('window-%04d.json' % (r['index'] - 1))), 'receipt chain changed'
    for value in state['document']['counted'].values():
        if value.get('counter_path'):
            assert sha(value['counter_path']) == value['counter_sha256'], 'counted observation changed'
    assert not (args.output / 'cell.json').exists(), 'completed result cannot be reused'
    assert all(sha(p) == h for p, h in state['document']['identities'].items()), 'input identity changed'
    sequence = state['sequence']
    while state['phase'] != 'complete' and time.monotonic() - start < args.window_seconds:
        state['active'] = {'phase': state['phase'], 'round': state['round'], 'position': state['position']}
        save(state, args.output, 'start')
        try:
            execute_one(state, tools, args.output, start + args.window_seconds)
        except WindowDeferred:
            state['active'] = None
            save(state, args.output, 'unexecuted_boundary')
            break
        state['sequence'] += 1
        state['active'] = None
        save(state, args.output, 'completed_step')
    elapsed = time.monotonic() - start
    assert all(sha(p) == h for p, h in state['document']['identities'].items()), 'input identity changed during window'
    previous = state['windows'][-1] if state['windows'] else None
    elapsed = time.monotonic() - start
    receipt = {'index': len(state['windows']), 'first_sequence': sequence, 'next_sequence': state['sequence'],
        'launch_window_seconds': args.window_seconds, 'guest_deadline_seconds': args.timeout, 'prepublication_elapsed_seconds': elapsed,
        'elapsed_scope': 'through post-guest input validation, excluding immutable receipt/state/COMPLETE publication',
        'previous_receipt_sha256': sha(args.output / ('window-%04d.json' % previous['index'])) if previous else None,
        'identities': state['document']['identities'], 'admission': {'kind': os.environ['MYLANG_ADMISSION_KIND'], 'directory': os.environ.get('MYLANG_ADMISSION_DIR')}}
    path = args.output / ('window-%04d.json' % receipt['index'])
    assert not path.exists()
    atomic(path, receipt)
    state['windows'].append(receipt)
    save(state, args.output, 'window_complete')
    if state['phase'] == 'complete':
        atomic(args.output / 'cell.json', finish(state, tools))
        atomic(args.output / 'COMPLETE.json', {'cell_sha256': sha(args.output / 'cell.json'), 'last_window_sha256': sha(path), 'status': 'complete'})
    print(json.dumps({'phase': state['phase'], 'completed_steps': state['sequence'], 'window': receipt['index']}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--spec', type=Path, required=True)
    parser.add_argument('--tools', type=Path, required=True, help='exact frozen measure.py path')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cpu', type=int, default=8)
    parser.add_argument('--timeout', type=float, default=120)
    parser.add_argument('--window-seconds', type=float, default=55)
    parser.add_argument('--max-windows', type=int, default=0)
    parser.add_argument('--window-worker', action='store_true')
    args = parser.parse_args()
    assert 0 < args.window_seconds <= 55 and args.timeout > 0
    args.spec = args.spec.resolve(); args.tools = args.tools.resolve(); args.output = args.output.resolve()
    worker = Path(__file__).resolve().parents[3]
    assert args.output.is_relative_to(worker), 'write only to this worker'
    if args.window_worker:
        window(args)
        return
    assert not os.environ.get('MYLANG_ADMISSION_KIND'), 'controller must not nest admissions'
    command = [sys.executable, '-B', str(Path(__file__).resolve()), '--window-worker', '--spec', str(args.spec), '--tools', str(args.tools), '--output', str(args.output), '--cpu', str(args.cpu), '--timeout', str(args.timeout), '--window-seconds', str(args.window_seconds)]
    for index in range(args.max_windows or sys.maxsize):
        if (args.output / 'cell.json').exists():
            completed = json.loads((args.output / 'cell.json').read_text())
            marker = json.loads((args.output / 'COMPLETE.json').read_text())
            assert marker['cell_sha256'] == sha(args.output / 'cell.json'), 'completed report changed'
            assert completed['spec'] == json.loads(args.spec.read_text())
            assert all(sha(p) == h for p, h in completed['identities'].items()), 'completed input changed'
            for value in completed['counted'].values():
                if value.get('counter_path'):
                    assert sha(value['counter_path']) == value['counter_sha256']
            return
        admitted = ['bash', '-c', 'source /home/epentland/.config/mylang/dev-env.sh; exec scripts/build-slot.sh timing "$@"', 'micro-window', *command]
        subprocess.run(admitted, cwd=worker, check=True)


if __name__ == '__main__':
    main()
