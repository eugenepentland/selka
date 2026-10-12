#!/usr/bin/env python3
"""Capture direct coordinator-owned windows; this harness owns no admission."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import re
import shutil
import signal
import statistics
import subprocess
import sys
import threading
import time

SELF = Path(__file__).resolve()
OWN_ROOT = SELF.parents[3]
sys.path.insert(0, str(OWN_ROOT / 'scripts'))
from verification_process import ProcessLimits, run_supervised, terminate_owned, wait_owned


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def revision(root):
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()


def reports(root):
    return {path: (path.stat().st_ino, path.stat().st_size, path.stat().st_mtime_ns,
                   path.stat().st_ctime_ns, sha(path))
            for path in (root / '.mylang-cache').glob('verification-v*/last-run.json')
            if re.fullmatch(r'verification-v[1-9][0-9]*', path.parent.name)}


def capture_report(root, before, output, index, status, bound, inventory):
    changed = [path for path, value in reports(root).items() if before.get(path) != value]
    record = {'changed_report_paths': [str(path) for path in changed], 'valid_complete': False}
    if len(changed) != 1:
        record['report_state'] = 'missing-or-ambiguous-current-report'
        return record
    path = changed[0]
    destination = output / ('report-%02d.json' % index)
    shutil.copyfile(path, destination)
    report = json.loads(destination.read_text())
    window = report.get('measurement_window', {})
    expected = {group['id'] for group in inventory['groups']}
    actual = [row['id'] for row in report.get('actions', [])]
    coverage = report.get('action_coverage', {})
    counts = coverage.get('counts', {})
    record.update(report_state='current-success' if report.get('success') is True else 'current-failure',
                  report_namespace=path.parent.name, report_schema=report.get('version'),
                  report_sha256=sha(destination), measurement_window=window,
                  budget_context=report.get('budget_context'),
                  action_keys={row['id']: row.get('action_key') for row in report.get('actions', [])},
                  action_states={row['id']: row['state'] for row in report.get('actions', [])},
                  snapshot_statistics=report.get('snapshot_statistics'),
                  report_elapsed_seconds=report.get('elapsed_seconds'))
    elapsed = window.get('elapsed_seconds')
    record['valid_complete'] = (status == 0 and report.get('status') == 0
        and report.get('success') is True and report.get('inputs_stable') is True
        and report.get('profile_coverage', {}).get('status') == 'complete'
        and report.get('profile_coverage', {}).get('complete_verification') is True
        and report.get('profile_coverage', {}).get('filtered_inventory') is False
        and report.get('profile_coverage', {}).get('outstanding') == []
        and report.get('action_metadata') == inventory.get('action_metadata')
        and len(actual) == len(expected) and set(actual) == expected
        and coverage.get('selected') == len(expected) and coverage.get('unknown') is False
        and sum(counts.get(name, 0) for name in ('executed', 'reused')) == len(expected)
        and path.parent.name == 'verification-v2'
        and window.get('kind') == 'exclusive-coordinator-request'
        and window.get('deadline_seconds') == bound
        and type(elapsed) in (int, float) and math.isfinite(elapsed) and 0 <= elapsed <= bound)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--transport', choices=('one-shot', 'retained'), required=True)
    parser.add_argument('--requests', type=int, default=1)
    parser.add_argument('--force-first', action='store_true')
    parser.add_argument('--window-seconds', type=float, default=1800)
    parser.add_argument('--outer-timeout-seconds', type=float, default=2700)
    args = parser.parse_args()
    if not 1 <= args.requests <= 40 or not 0 < args.window_seconds < args.outer_timeout_seconds <= 7200:
        parser.error('bounded request count and distinct queue-inclusive outer timeout required')
    root = args.root.resolve(); output = args.output.resolve()
    if output.exists(): parser.error('output must be a new private directory')
    output.mkdir(parents=True)
    if revision(root) != args.expected_source: raise RuntimeError('source freeze differs')
    if not os.environ.get('MYLANG_COMPONENT_CACHE'):
        raise RuntimeError('exclusive component-cache handoff environment is required')
    zig = Path(os.environ['MYLANG_ZIG']).resolve()
    inventory_path = root / 'zig-out/verification/inventory.json'
    inventory = json.loads(inventory_path.read_text())
    shutil.copyfile(inventory_path, output / 'inventory.json')
    manifest = {'schema': 1, 'source': args.expected_source, 'transport': args.transport,
                'harness_sha256': sha(__file__), 'zig': str(zig), 'zig_sha256': sha(zig),
                'inventory_sha256': sha(inventory_path), 'requests': [],
                'environment': {name: os.environ.get(name) for name in ('MYLANG_SLOT_DIR',
                    'MYLANG_BUILD_SLOTS', 'MYLANG_GATE_SLOTS', 'MYLANG_DEV_JOBS',
                    'MYLANG_DEV_MAXRSS', 'MYLANG_COMPONENT_CACHE', 'MYLANG_CORE_RUNTIME_CACHE',
                    'MYLANG_COMPILER_SHARED_CACHE', 'ZIG_GLOBAL_CACHE_DIR', 'ZIG_LOCAL_CACHE_DIR', 'TMPDIR')},
                'affinity': sorted(os.sched_getaffinity(0)), 'window_seconds': args.window_seconds,
                'outer_timeout_seconds': args.outer_timeout_seconds,
                'outer_clock': 'before child/request send through response and current report capture; includes queue',
                'inner_clock': 'coordinator measurement_window scope verbatim; no inferred test-body clock',
                'retained_startup': 'session launched before first request; first outer duration may include remaining startup, inner window excludes it'}
    child = None; lines = queue.Queue()
    def save(): (output / 'capture.json').write_text(json.dumps(manifest, indent=2) + '\n')
    def read_lines(stream):
        try:
            while True:
                line = stream.readline(65537)
                if not line: break
                lines.put(line)
        finally: lines.put(None)
    def response():
        line = lines.get(timeout=args.outer_timeout_seconds)
        if line is None or len(line) > 65536: raise RuntimeError('missing or oversized session response')
        return json.loads(line)
    def interrupted(signum, frame): raise KeyboardInterrupt('capture canceled')
    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
    save()
    try:
        with (output / 'stderr.log').open('wb') as errors:
            if args.transport == 'retained':
                child = subprocess.Popen([sys.executable, str(SELF), '--child', sys.executable,
                    str(root / 'scripts/cache_session.py')], cwd=root, env=os.environ.copy(),
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
                    text=True, start_new_session=True)
                threading.Thread(target=read_lines, args=(child.stdout,), daemon=True).start()
            for index in range(args.requests):
                if revision(root) != args.expected_source or sha(inventory_path) != manifest['inventory_sha256']:
                    raise RuntimeError('source/inventory changed before request')
                before = reports(root)
                options = ['--zig', str(zig), '--timing-window-seconds', str(args.window_seconds), '--profile', 'complete']
                if args.force_first and index == 0: options.append('--force')
                start = time.monotonic_ns()
                if args.transport == 'one-shot':
                    argv = [sys.executable, str(root / 'scripts/verify_cache.py'), *options]
                    with (output / ('stdout-%02d.log' % index)).open('wb') as out:
                        child = subprocess.Popen([sys.executable, str(SELF), '--child', *argv],
                            cwd=root, env=os.environ.copy(), stdout=out, stderr=errors, start_new_session=True)
                        verdict = wait_owned(child, limits=ProcessLimits(args.outer_timeout_seconds))
                    result = {'status': verdict.returncode, 'lineage_complete': verdict.complete, 'argv': argv}
                else:
                    request = {'id': 'warm-%02d' % index, 'command': 'verify', 'args': options}
                    child.stdin.write(json.dumps(request) + '\n'); child.stdin.flush()
                    result = response(); result['request'] = request
                observed = capture_report(root, before, output, index, result.get('status'), args.window_seconds, inventory)
                observed.update(index=index, response=result, outer_elapsed_ns=time.monotonic_ns() - start,
                                source_after=revision(root))
                if observed['source_after'] != args.expected_source: observed['valid_complete'] = False
                if args.transport == 'retained' and result.get('id') != request['id']:
                    observed['valid_complete'] = False
                if args.transport == 'one-shot' and result.get('lineage_complete') is not True:
                    observed['valid_complete'] = False
                if manifest['requests']:
                    first = manifest['requests'][0]
                    observed['same_request_context'] = (observed.get('budget_context') == first.get('budget_context')
                        and observed.get('action_keys') == first.get('action_keys'))
                    if not observed['same_request_context']: observed['valid_complete'] = False
                manifest['requests'].append(observed); save()
                if not observed['valid_complete'] or (args.transport == 'retained' and result.get('ok') is not True):
                    raise RuntimeError('request failed or full current window report not validated')
            if args.transport == 'retained':
                child.stdin.write(json.dumps({'id': 'stop', 'command': 'stop'}) + '\n'); child.stdin.flush()
                manifest['stop_response'] = response(); child.stdin.close()
                if manifest['stop_response'].get('status') != 0 or manifest['stop_response'].get('ok') is not True:
                    raise RuntimeError('stop response failed')
                verdict = wait_owned(child, limits=ProcessLimits(30))
                manifest['session_closeout'] = {'status': verdict.returncode, 'complete': verdict.complete}
                if verdict.returncode != 0 or not verdict.complete: raise RuntimeError('session closeout incomplete')
        if sha(__file__) != manifest['harness_sha256'] or sha(zig) != manifest['zig_sha256']:
            raise RuntimeError('collector/tool changed')
        manifest['complete'] = True; save()
        print(json.dumps({'complete': True, 'requests': len(manifest['requests']), 'transport': args.transport}))
    except BaseException as error:
        manifest['complete'] = False; manifest['error'] = type(error).__name__ + ': ' + str(error); save()
        raise
    finally:
        if child is not None and child.poll() is None: terminate_owned(child)
        for sig, handler in previous.items(): signal.signal(sig, handler)


if __name__ == '__main__':
    if sys.argv[1:2] == ['--child']:
        raise SystemExit(run_supervised(sys.argv[2:], dict(os.environ)))
    main()
