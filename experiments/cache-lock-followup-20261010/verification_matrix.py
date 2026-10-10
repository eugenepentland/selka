#!/usr/bin/env python3
"""Representative coordinator edits and a separate artifact identity comparison.

Run only after the candidate source/artifacts and baseline measurements are
frozen. The coordinator acquires its own normal admission slots; this driver
must never be wrapped in build-slot. Cold means cold action receipts via --force,
not a cold machine, Zig cache or compiler installation. Only the first request
is forced. Raw evidence belongs under .mylang-cache, outside watched source.

    python3 experiments/cache-lock-followup-20261010/verification_matrix.py \
        --root . --zig /path/to/pinned/zig \
        --output .mylang-cache/cache-lock-followup-20261010/verification-matrix

The offline comparison substitutes compiler digests in an in-memory copy of the
real prepared artifact snapshot. It issues no worker command, changes no binary,
and does not measure native body granularity or performance.
"""
from __future__ import annotations

import argparse
import ast
from contextlib import contextmanager
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import uuid


def digest(path):
    result = hashlib.sha256()
    with Path(path).open('rb') as stream:
        while block := stream.read(1024 * 1024):
            result.update(block)
    return result.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def receipts(root):
    folder = root / '.mylang-cache/verification-v1/actions'
    return {path.name: digest(path) for path in sorted(folder.glob('*.json'))}


class OwnedEdit:
    def __init__(self, path, value, *, create=False):
        self.path = path
        if create and path.exists():
            raise RuntimeError('refusing to replace existing probe: ' + str(path))
        self.original = None if create else path.read_bytes()
        self.expected = self.original
        self.replace(value)

    def replace(self, value):
        actual = self.path.read_bytes() if self.path.exists() else None
        if actual != self.expected:
            raise RuntimeError('concurrent edit; refusing to overwrite ' + str(self.path))
        self.path.write_bytes(value)
        self.expected = value

    def restore(self):
        actual = self.path.read_bytes() if self.path.exists() else None
        if actual != self.expected:
            raise RuntimeError('concurrent edit; leaving file intact: ' + str(self.path))
        if self.original is None:
            self.path.unlink()
        else:
            self.path.write_bytes(self.original)
        self.expected = self.original


@contextmanager
def edit(path, value, *, create=False):
    owned = OwnedEdit(path, value, create=create)
    try:
        yield owned
    finally:
        owned.restore()


def stop(process):
    if process.poll() is not None:
        return
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=30)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()


class Matrix:
    def __init__(self, args):
        self.root = args.root.resolve()
        self.zig = args.zig.resolve(strict=True)
        self.output = args.output.resolve()
        self.timeout = args.timeout
        # Do not add profiler or per-case environment values to receipt keys.
        self.environment = dict(os.environ)
        self.rows = []
        self.run_id = uuid.uuid4().hex
        self.options = ['-j3', '--maxrss', '8589934592', '--summary', 'all', '--seed=0']
        if self.output.exists():
            raise RuntimeError('output must be a new directory: ' + str(self.output))
        if self.output.is_relative_to(self.root) and not self.output.is_relative_to(self.root / '.mylang-cache'):
            raise RuntimeError('repository evidence must be outside watched source, under .mylang-cache')
        self.output.mkdir(parents=True)
        self.provenance = {'root': str(self.root), 'zig': str(self.zig), 'zig_sha256': digest(self.zig),
                           'coordinator_sha256': digest(self.root / 'scripts/verify_cache.py'),
                           'run_id': self.run_id, 'options': self.options,
                           'method': 'one forced original gate, unchanged, representative isolated edits, restored unchanged',
                           'timing': 'GNU time covers coordinator and waited descendants, including admission; report phases separate observed occupancy',
                           'cold_scope': 'action receipts only; machine, Zig and preparation caches retained'}
        self.save()

    def save(self):
        write_json(self.output / 'results.json', {'provenance': self.provenance, 'runs': self.rows})

    def run(self, name, expected, *, force=False, failure=False, marker=None):
        command = [sys.executable, '-B', str(self.root / 'scripts/verify_cache.py'), '--zig', str(self.zig)]
        if force:
            command.append('--force')
        command.extend(['--', *self.options])
        before = receipts(self.root)
        report_path = self.root / '.mylang-cache/verification-v1/last-run.json'
        previous = report_path.stat() if report_path.exists() else None
        log = self.output / (name + '.log')
        resources = self.output / (name + '.time.json')
        fmt = '{"wall_seconds":%e,"user_seconds":%U,"system_seconds":%S,"max_rss_kib":%M,"exit_status":%x}'
        started = time.monotonic()
        process = None
        with log.open('wb') as output:
            try:
                process = subprocess.Popen(['/usr/bin/time', '-o', str(resources), '-f', fmt, *command],
                                           cwd=self.root, env=self.environment, stdout=output,
                                           stderr=subprocess.STDOUT, start_new_session=True)
                status = process.wait(timeout=self.timeout)
            except BaseException:
                if process is not None:
                    stop(process)
                raise
        elapsed = time.monotonic() - started
        after = receipts(self.root)
        current = report_path.stat() if report_path.exists() else None
        fresh_report = current is not None and (previous is None or
                       (current.st_ino, current.st_mtime_ns) != (previous.st_ino, previous.st_mtime_ns))
        report = json.loads(report_path.read_text()) if fresh_report else None
        text = log.read_text(errors='replace')
        # GNU time adds a nonzero-exit diagnostic before its requested JSON.
        resource_record = next((json.loads(line) for line in resources.read_text().splitlines()
                                if line.startswith('{')), None)
        row = {'name': name, 'command': command, 'exit_status': status, 'wall_seconds': elapsed,
               'resources': resource_record, 'report': report, 'expected_executed_cacheable': sorted(expected),
               'receipts_before': before, 'receipts_after': after,
               'new_receipts': sorted(set(after) - set(before)), 'receipts_equal': before == after,
               'log_sha256': digest(log), 'time_sha256': digest(resources),
               'unittest_counts': [int(value) for value in re.findall(r'Ran (\d+) tests? in', text)]}
        self.rows.append(row)
        self.save()
        if report is None or report.get('status') != status:
            raise RuntimeError(name + ': missing current coordinator report or status disagreement')
        if failure:
            if status == 0 or report.get('success') or before != after:
                raise RuntimeError(name + ': failed edit retained new or altered success receipts')
            if 'cache lock qualification deliberate failure' not in text:
                raise RuntimeError(name + ': requested assertion failure was not observed')
        elif status != 0 or not report.get('success'):
            raise RuntimeError(name + ': unexpected failure; inspect ' + str(log))
        executed = {item['id'] for item in report['actions'] if item['state'] == 'execute'}
        if not force and executed != set(expected):
            raise RuntimeError(name + ': executed cohorts ' + repr(sorted(executed)) + ', expected ' + repr(sorted(expected)))
        if marker and marker not in text:
            raise RuntimeError(name + ': added test did not produce its execution marker')
        print(name + ': exit=' + str(status) + ' executed=' + repr(sorted(executed)), flush=True)
        return row


def offline_identity(root, output):
    """Compare dependency keys from real metadata without modifying any artifact."""
    sys.path.insert(0, str(root / 'scripts'))
    specification = importlib.util.spec_from_file_location('verification_identity_comparison', root / 'scripts/verify_cache.py')
    coordinator = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(coordinator)
    plan = coordinator.inventory(root / 'zig-out/verification/inventory.json')
    preparation = json.loads((root / '.mylang-cache/verification-v1/preparation.json').read_text())
    identity = preparation['artifacts']

    class View:
        def __init__(self, value):
            self.identity = value

    providers = coordinator.artifact_providers(root, View(identity))
    changed = copy.deepcopy(identity)
    compiler_paths = {item['path'] for item in providers['mylang']}
    for item in changed['files']:
        if item['path'] in compiler_paths:
            item['sha256'] = hashlib.sha256(('hypothetical-compiler-edit:' + item['sha256']).encode()).hexdigest()
    changed_providers = coordinator.artifact_providers(root, View(changed))
    before = {'artifacts': coordinator.key(identity), 'inventory': coordinator.key(plan),
              'context': 'all nonartifact inputs held fixed; fixture file payloads omitted'}
    after = dict(before, artifacts=coordinator.key(changed))
    inputs = View({'files': []})
    rows = []
    for group in plan['groups']:
        broad = dict(group, artifacts=None)
        def different(contract):
            return (coordinator.action_identity(contract, inputs, before, root, providers) !=
                    coordinator.action_identity(contract, inputs, after, root, changed_providers))
        rows.append({'id': group['id'], 'cacheable': group['cacheable'], 'artifacts': group.get('artifacts'),
                     'all_artifacts_key_changes': different(broad), 'scoped_key_changes': different(group)})
    result = {'method': 'identity comparison only; no artifact mutation, worker invocation or timing',
              'input_scope': 'real candidate inventory and prepared artifact metadata; other inputs held fixed',
              'artifact_snapshot_sha256': coordinator.key(identity), 'inventory_sha256': coordinator.key(plan),
              'hypothetical_changed_compiler_paths': sorted(compiler_paths), 'groups': rows,
              'all_artifacts_eligible_changes': sum(row['cacheable'] and row['all_artifacts_key_changes'] for row in rows),
              'scoped_eligible_changes': sum(row['cacheable'] and row['scoped_key_changes'] for row in rows)}
    write_json(output / 'verification-identity-comparison.json', result)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', type=Path, default=Path('.'))
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=7200)
    args = parser.parse_args()
    matrix = Matrix(args)
    def cancelled(signum, _frame):
        raise KeyboardInterrupt('signal ' + str(signum))
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGHUP, cancelled)
    try:
        matrix.run('cold-force', [], force=True)
        matrix.run('unchanged', [])
        offline_identity(matrix.root, matrix.output)
        for name, relative, expected in [
                ('private-script', 'scripts/affected_tests.py', ['affected']),
                ('shared-script', 'scripts/check_my_format.py', ['my_format', 'my_format_self', 'noalloc_lint'])]:
            path = matrix.root / relative
            revised = path.read_bytes() + ('\n# cache lock qualification ' + matrix.run_id + ' ' + name + '\n').encode()
            with edit(path, revised):
                matrix.run(name, expected)
        test_path = matrix.root / 'scripts/verify_cache_test.py'
        original = test_path.read_bytes()
        baseline_count = sum(isinstance(method, (ast.FunctionDef, ast.AsyncFunctionDef)) and method.name.startswith('test_')
                             for node in ast.parse(original).body if isinstance(node, ast.ClassDef) for method in node.body)
        anchor = b"if __name__ == '__main__':"
        if original.count(anchor) != 1:
            raise RuntimeError('ambiguous unittest.main insertion point')
        marker = 'cache-lock-added-test-' + matrix.run_id
        addition = ('class CacheLockQualificationProbe(unittest.TestCase):\n'
                    '    def test_added_case_executes(self):\n'
                    '        print(' + repr(marker) + ', flush=True)\n'
                    '        self.assertTrue(True, "cache lock qualification deliberate failure")\n\n\n').encode()
        passing = original.replace(anchor, addition + anchor)
        failing = passing.replace(b'self.assertTrue(True, "cache lock qualification deliberate failure")',
                                  b'self.assertTrue(False, "cache lock qualification deliberate failure")')
        with edit(test_path, passing) as owned:
            passed = matrix.run('added-test-passing', ['verification_cache'], marker=marker)
            if baseline_count + 1 not in passed['unittest_counts']:
                raise RuntimeError('added passing test did not increase the observed coordinator test count')
            owned.replace(failing)
            failed = matrix.run('added-test-failing', ['verification_cache'], failure=True, marker=marker)
            if baseline_count + 1 not in failed['unittest_counts']:
                raise RuntimeError('added failing test did not increase the observed coordinator test count')
        document = matrix.root / 'docs/audits/cache-lock-qualification-probe.md'
        prose = ('# Cache lock qualification probe\n\nTemporary prose-only qualification evidence ' + matrix.run_id + '.\n').encode()
        with edit(document, prose, create=True):
            matrix.run('nonembedded-documentation', ['doc-coverage', 'doctest'])
        matrix.run('restored-unchanged', [])
        matrix.provenance['completed'] = True
        matrix.save()
    except BaseException as error:
        matrix.provenance.update(completed=False, error=repr(error))
        matrix.save()
        raise


if __name__ == '__main__':
    main()
