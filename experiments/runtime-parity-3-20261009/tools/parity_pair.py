#!/usr/bin/env python3
"""X parity: base and candidate mylang arms interleaved with all reference arms.

The unchanged parity runner builds/qualifies every arm and shuffles all arms
within each timing round. Base arms are named base-my*, candidate arms my*.
Every compiler build uses the shared admission wrapper; runtime/object caches
are separate per compiler. The quiet guard starts only after all builds.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import tempfile
import time

import parity_locked as locked

BP = locked.bp
ORIGINAL_ARMS = BP.arms_for
ORIGINAL_BUILD = BP.build
ROOT = Path(__file__).resolve().parents[3]


def paired_arms(ports):
    arms = ORIGINAL_ARMS(ports)
    return [*arms, *[{**arm, 'arm': 'base-' + arm['arm']} for arm in arms if arm['lang'] == 'my']]


def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


class TimingFailure(RuntimeError):
    """One actual warmup or timed execution failed qualification."""
    def __init__(self, details):
        self.details = details
        super().__init__(json.dumps(details, sort_keys=True))


def checked_timer(expected):
    """Preserve spawn/wait timing, validating that same execution after the clock stops."""
    def run_timed(binary):
        key = str(Path(binary).resolve())
        if key not in expected:
            raise TimingFailure({'binary': key, 'reason': 'unregistered timed binary'})
        with tempfile.TemporaryFile() as captured:
            started = time.perf_counter_ns()
            pid = os.posix_spawn(key, [key], os.environ,
                                 file_actions=[(os.POSIX_SPAWN_DUP2, captured.fileno(), 1)])
            _, status, usage = os.wait4(pid, 0)
            wall = (time.perf_counter_ns() - started) / 1e9
            captured.seek(0)
            stdout = captured.read()
        cpu = usage.ru_utime + usage.ru_stime
        code = os.waitstatus_to_exitcode(status)
        valid_time = math.isfinite(wall) and wall > 0 and math.isfinite(cpu) and cpu >= 0
        if code != 0 or stdout != expected[key] or not valid_time:
            raise TimingFailure({'binary': key, 'status': code, 'wall_s': wall, 'cpu_s': cpu,
                                 'stdout_sha256': hashlib.sha256(stdout).hexdigest(),
                                 'expected_stdout_sha256': hashlib.sha256(expected[key]).hexdigest(),
                                 'stdout_prefix_hex': stdout[:4096].hex()})
        return wall, cpu, code
    return run_timed


def timing_failure(out, failure):
    """Keep each failed sample independently, without replacing an earlier receipt."""
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', prefix=out.stem + '-timing-failure-',
                                     suffix='.json', dir=out.parent, delete=False) as stream:
        json.dump({'complete': False, 'timing_failure': failure.details}, stream, indent=1)
        stream.write('\n')
        receipt = stream.name
    print('parity_pair: invalid execution; retained ' + receipt, file=sys.stderr, flush=True)


class Processes(locked.SlottedProcesses):
    def __init__(self, caches):
        self.caches = caches

    def run(self, command, *args, **kwargs):
        if isinstance(command, (list, tuple)) and command:
            compiler = str(Path(str(command[0])).resolve())
            if compiler in self.caches:
                kwargs['env'] = {**(kwargs.get('env') or os.environ),
                                 'MYLANG_CORE_RUNTIME_CACHE': str(self.caches[compiler])}
        return super().run(command, *args, **kwargs)


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--base-source', default='41ed360fb361c49938488ad111795bad8a726b73')
    parser.add_argument('--validate-only', action='store_true')
    own, remainder = parser.parse_known_args()
    base = own.base.resolve()
    if own.validate_only:
        counts = {'base': 0, 'candidate': 0, 'references': 0}
        for bench in BP.discover([]):
            arms = paired_arms(bench['ports'])
            assert len({arm['arm'] for arm in arms}) == len(arms)
            for arm in arms:
                key = 'references' if arm['lang'] != 'my' else ('base' if arm['arm'].startswith('base-') else 'candidate')
                counts[key] += 1
        assert counts == {'base': 45, 'candidate': 45, 'references': 108}, counts
        print(json.dumps(counts))
        return 0
    if not remainder or remainder[0] != 'run' or '--write-thresholds' in remainder:
        raise SystemExit('parity_pair requires run and never rewrites thresholds')
    if '--arms' in remainder or '--filter' in remainder:
        raise SystemExit('X parity must include the complete corpus')
    candidate = Path(remainder[remainder.index('--mylang') + 1]).resolve()
    with BP.OffTimingCpus():
        hashes = {str(path): digest(path) for path in (base, candidate)}
    caches = {path: ROOT / '.mylang-cache/rp3' / ('runtime-' + value[:16]) for path, value in hashes.items()}
    for path in caches.values():
        path.mkdir(parents=True, exist_ok=True)

    def build(job, tools, work):
        tools = dict(tools)
        if job['lang'] == 'my':
            if job['arm'].startswith('base-'):
                tools['mylang'] = str(base)
            work = work / ('compiler-' + hashes[str(Path(tools['mylang']).resolve())][:16])
            work.mkdir(parents=True, exist_ok=True)
        return ORIGINAL_BUILD(job, tools, work)

    BP.arms_for = paired_arms
    BP.build = build
    BP.subprocess = Processes(caches)
    sys.argv = [sys.argv[0], *remainder]
    out = Path(remainder[remainder.index('--json') + 1])
    work = Path(remainder[remainder.index('--work') + 1]).resolve()
    expected = {str(work / 'bin' / (bench['name'] + '.' + arm['arm'])): bench['expected']
                for bench in BP.discover([]) for arm in paired_arms(bench['ports'])}
    original_timer = BP.run_timed
    BP.run_timed = checked_timer(expected)
    try:
        status = BP.main()
        if out.exists():
            data = json.loads(out.read_text())
            if any(entry.get('failure') == 'no qualified ' + BP.REFERENCE for entry in data['benchmarks'].values()):
                from parity_standalone import complete
                complete(data, Path(remainder[remainder.index('--work') + 1]).resolve(), BP)
            data['rp3_pair'] = {'base_compiler': str(base), 'base_sha256': hashes[str(base)],
                                'base_source': own.base_source, 'candidate_compiler': str(candidate),
                                'candidate_sha256': hashes[str(candidate)],
                                'method': 'Both compiler arms and all references interleaved in each benchmark round.',
                                'timing_validation': 'Every warmup/timed stdout and exit checked; stdout is captured in a preopened temporary file, with verification outside spawn/wait timing.'}
            out.write_text(json.dumps(data, indent=1) + '\n')
        return status
    except TimingFailure as failure:
        timing_failure(out, failure)
        return 2
    finally:
        BP.run_timed = original_timer
        for guard in reversed(locked.held):
            guard.__exit__(None, None, None)


if __name__ == '__main__':
    raise SystemExit(main())
