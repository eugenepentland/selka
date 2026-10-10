#!/usr/bin/env python3
"""Actual coordinator acceptance; operational observations, no performance claim.

Run directly: fuzz_campaign.py owns admission for every missing worker. The
output directory must be fresh and outside watched source/fixture directories.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / '.mylang-cache/cache-wave4b/native-smoke'
TARGETS = {'incremental', 'module-projects', 'interfaces', 'interfaces-generic'}


def check(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def atomic_json(path, value):
    temporary = path.with_suffix('.partial')
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    temporary.replace(path)


def load_report(path):
    if not path.exists():
        return None
    return json.loads(path.read_bytes())


def completed(report):
    check(report.get('complete') is True and report.get('success') is True, 'incomplete coordinator report')
    check(not report.get('freshness_reasons'), 'campaign was not eligible for evidence reuse')
    check(all(a.get('success') is True for a in report['actions'] if a['state'] == 'executed'),
          'completed report contains failed action')


def explore_rows(report, state=None):
    return [a for a in report['actions'] if a['operation'] == 'explore' and (state is None or a['state'] == state)]


def warm(report, shards):
    completed(report)
    check(not report['admissions'], 'warm campaign requested admission')
    check(len(explore_rows(report, 'reused')) == shards, 'warm shard count differs')
    check(all(a['state'] == 'reused' for a in report['actions']), 'warm campaign launched a worker')
    check(report['counts']['explored'] == report['counts']['replayed'] == 0, 'warm campaign executed inputs')


class Qualification:
    def __init__(self, options):
        self.options = options
        self.output = options.output.absolute()
        check(not self.output.exists() or not any(self.output.iterdir()), 'output must be fresh')
        self.output.mkdir(parents=True, exist_ok=True)
        self.cases = self.output / 'cases'
        self.cases.mkdir()
        self.inputs = self.output / 'inputs'
        self.inputs.mkdir()
        self.engine = self.inputs / 'libfuzzer'
        shutil.copy2(options.engine, self.engine)
        self.corpus = self.inputs / 'initial-corpus'
        self.corpus.mkdir()
        (self.corpus / 'seed').write_bytes(b'AB')
        self.summary = {'version': 1, 'kind': options.kind, 'scope': 'actual coordinator correctness; no performance comparison',
                        'complete': False, 'success': False, 'cases': [], 'inputs': {
                            'compiler': {'path': str(options.compiler.absolute()), 'sha256': sha256(options.compiler)},
                            'engine': {'path': str(options.engine.absolute()), 'sha256': sha256(options.engine)},
                            'fixture': {'path': 'test/fixtures/fuzz-campaign/libfuzzer_target.c',
                                        'sha256': sha256(ROOT / 'test/fixtures/fuzz-campaign/libfuzzer_target.c')},
                            'coordinator': sha256(ROOT / 'scripts/fuzz_campaign.py'),
                            'worker': sha256(ROOT / 'scripts/fuzz_coverage.py'),
                            'harness': sha256(__file__), 'initial_input_sha256': hashlib.sha256(b'AB').hexdigest()}}
        self.save()

    def save(self):
        atomic_json(self.output / 'results.json', self.summary)

    def command(self, kind, cache, shards, *extra):
        base = [sys.executable, str(ROOT / 'scripts/fuzz_campaign.py'), kind,
                '--cache-dir', str(self.output / cache), '--shards', str(shards), '--seed', '17']
        if kind == 'differential':
            base += ['--compiler', str(self.options.compiler.absolute()), '--zig', str(self.options.zig.absolute()),
                     '--steps', '2', '--deadline', '600']
            if self.options.components:
                base += ['--components', str(self.options.components.absolute())]
        else:
            base += ['--name', 'qualification-native', '--engine', str(self.engine), '--corpus', str(self.corpus),
                     '--hermetic', '--runs', '32', '--timeout', '2', '--max-len', '4096']
        return base + list(extra)

    def run(self, name, command, cancellation=False):
        area = self.cases / name
        area.mkdir()
        report_path = area / 'report.json'
        command = command + ['--report', str(report_path)]
        timed = ['/usr/bin/time', '-f', '{"wall_seconds":%e,"user_seconds":%U,"system_seconds":%S,"max_rss_kib":%M}',
                 '-o', str(area / 'process-tree.json'), *command]
        observed = None
        with (area / 'output.log').open('wb') as log:
            child = subprocess.Popen(timed, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                if cancellation:
                    deadline = time.monotonic() + self.options.wait_seconds
                    while time.monotonic() < deadline:
                        report = load_report(report_path)
                        if report and any(a.get('success') is True for a in explore_rows(report, 'executed')):
                            observed = report
                            # GNU time must survive to wait/reap and save metrics.
                            children = Path(f'/proc/{child.pid}/task/{child.pid}/children').read_text().split()
                            check(len(children) == 1, 'cannot identify owned coordinator process')
                            coordinator_pid = int(children[0])
                            argv = Path(f'/proc/{coordinator_pid}/cmdline').read_bytes()
                            check(str(ROOT / 'scripts/fuzz_campaign.py').encode() in argv,
                                  'owned timing child is not the coordinator')
                            os.kill(coordinator_pid, signal.SIGTERM)
                            break
                        check(child.poll() is None, 'coordinator ended before a completed shard could be interrupted')
                        time.sleep(0.02)
                    check(observed is not None, 'no completed shard before cancellation deadline')
                    status = child.wait(timeout=30)
                else:
                    status = child.wait(timeout=self.options.wait_seconds)
            finally:
                if child.poll() is None:
                    os.killpg(child.pid, signal.SIGTERM)
                    try:
                        child.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        os.killpg(child.pid, signal.SIGKILL)
                        child.wait()
        report = load_report(report_path)
        check(report is not None, 'coordinator did not save a report: ' + name)
        timing = area / 'process-tree.json'
        # GNU time prefixes interrupted-command records with a status line.
        measurement = [line for line in timing.read_text().splitlines() if line.startswith('{')]
        row = {'name': name, 'command': command, 'exit': status,
               'report': str(report_path.relative_to(self.output)), 'report_sha256': sha256(report_path),
               'log': str((area / 'output.log').relative_to(self.output)), 'log_sha256': sha256(area / 'output.log'),
               'process_tree': json.loads(measurement[-1]) if measurement else None,
               'counts': report['counts'], 'admissions': report['admissions']}
        if observed:
            atomic_json(area / 'observed-before-signal.json', observed)
            row['observed_completed_shards'] = len(explore_rows(observed, 'executed'))
        self.summary['cases'].append(row)
        self.save()
        if cancellation:
            check(status in (143, -signal.SIGTERM), 'cancellation did not exit with SIGTERM status')
            check(report.get('complete') is False and report.get('success') is False,
                  'interrupted campaign claimed complete success')
        else:
            check(status == 0, 'coordinator failed: ' + name)
            completed(report)
        return report

    def differential(self):
        cold = self.run('differential-cold', self.command('differential', 'differential-cache', 1))
        check({a['target'] for a in explore_rows(cold)} == TARGETS, 'differential did not cover all four targets')
        check(len(explore_rows(cold, 'executed')) == 4 and cold['counts']['explored'] == 8, 'cold differential counts')
        check(not explore_rows(cold, 'reused'), 'cold differential reused stale shards')
        reused = self.run('differential-warm', self.command('differential', 'differential-cache', 1))
        warm(reused, 4)
        extended = self.run('differential-extended', self.command('differential', 'differential-cache', 2))
        check(len(explore_rows(extended, 'executed')) == len(explore_rows(extended, 'reused')) == 4,
              'extension did not preserve the old four differential shards')
        check(extended['counts']['explored'] == 8 and extended['counts']['replayed'] == 0, 'extension replayed old cases')
        check({a['key'] for a in explore_rows(cold)} == {a['key'] for a in explore_rows(extended, 'reused')},
              'differential extension changed old shard keys')

    def coverage(self):
        cold = self.run('coverage-cold', self.command('coverage', 'coverage-cache', 1))
        check(len(explore_rows(cold, 'executed')) == 1 and cold['counts']['explored'] == 32, 'cold coverage counts')
        reused = self.run('coverage-warm', self.command('coverage', 'coverage-cache', 1))
        warm(reused, 1)
        extended = self.run('coverage-extended', self.command('coverage', 'coverage-cache', 2))
        check(len(explore_rows(extended, 'executed')) == len(explore_rows(extended, 'reused')) == 1,
              'coverage extension did not run just the additional shard')
        check(extended['counts']['explored'] == 32 and extended['counts']['replayed'] == 0, 'coverage extension repeated work')
        before = sha256(self.engine)
        with self.engine.open('ab') as stream:
            stream.write(b'\0')  # ELF loader ignores trailing bytes; executable identity changes.
        after = sha256(self.engine)
        check(before != after, 'engine mutation did not change its identity')
        self.summary['engine_identity_edit'] = {'before': before, 'after': after,
                                               'method': 'append one harmless ELF trailer byte, no semantic edit'}
        self.save()
        changed = self.run('coverage-engine-changed', self.command('coverage', 'coverage-cache', 2))
        replays = [a for a in changed['actions'] if a['operation'] == 'replay']
        check(replays and all(a['state'] == 'executed' for a in replays), 'changed engine reused old replay proof')
        check(changed['counts']['replayed'] > 0, 'changed engine did not execute retained bytes')
        check(len(explore_rows(changed, 'executed')) == 2 and not explore_rows(changed, 'reused'),
              'changed engine reused old exploration proof')
        check(changed['counts']['explored'] == 64, 'changed engine explored wrong fixed budget')
        first_explore = next(i for i, a in enumerate(changed['actions']) if a['operation'] == 'explore')
        check(all(a['operation'] == 'replay' for a in changed['actions'][:first_explore]), 'exploration preceded replay')
        check(not any(a['operation'] == 'replay' for a in changed['actions'][first_explore:]), 'retained replay ordering differs')

    def cancellation(self):
        interrupted = self.run('differential-cancelled',
                               self.command('differential', 'cancellation-cache', 128, '--target', 'incremental'),
                               cancellation=True)
        previous = {a['key'] for a in explore_rows(interrupted, 'executed') if a.get('success') is True and a['value'] < 2}
        check(previous, 'interruption saved no completed requested shard')
        resumed = self.run('differential-resumed',
                           self.command('differential', 'cancellation-cache', 2, '--target', 'incremental'))
        reused = {a['key'] for a in explore_rows(resumed, 'reused')}
        check(reused == previous, 'resume reused an unfinished shard or lost a completed shard')
        check(len(explore_rows(resumed)) == 2, 'resume requested wrong shard count')
        check(resumed['counts']['explored'] == 2 * (2 - len(previous)), 'resume repeated completed work')
        final = self.run('differential-resumed-warm',
                         self.command('differential', 'cancellation-cache', 2, '--target', 'incremental'))
        warm(final, 2)

    def execute(self):
        try:
            if self.options.kind == 'all':
                self.differential()
            self.coverage()
            if self.options.kind == 'all':
                self.cancellation()
            self.summary.update(complete=True, success=True, coordinator_invocations=len(self.summary['cases']))
        except BaseException as error:
            self.summary['failure'] = str(error) or type(error).__name__
            raise
        finally:
            self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind', choices=('all', 'coverage'), default='all')
    parser.add_argument('--compiler', type=Path, default=ROOT / 'zig-out/bin/mylang')
    parser.add_argument('--components', type=Path)
    parser.add_argument('--zig', type=Path, required=True)
    parser.add_argument('--engine', type=Path, default=NATIVE / 'target')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--wait-seconds', type=int, default=1800)
    args = parser.parse_args()
    check(args.wait_seconds > 0, 'wait-seconds must be positive')
    Qualification(args).execute()


if __name__ == '__main__':
    main()
