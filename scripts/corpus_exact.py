#!/usr/bin/env python3
"""The exactness check of a compiler lane: every corpus program built through a cache and with `--no-cache`, byte for byte.

    python3 scripts/corpus_exact.py [--compiler BIN] [--jobs N] [--work DIR] [--keep] [PROGRAM.selka ...]

This is the parallel form of `experiments/guest-build-engine-20261031/G3r3/corpus_exact.sh` (a serial loop of about 2,800 builds). It keeps
that script's meaning: each program is built twice, once through one cache directory (the engine deciding lowering, whatever else the
environment says) and once with `--no-cache`, and the two programs are compared byte for byte; then the list again, reversed, so a second
pass restores what the first stored. A program that builds neither way is counted, not compared; one that builds one way only is a
finding, like a difference.

The corpus is the one every guest-build lane has used (`experiments/guest-build-engine-20261031/G3p/make_corpus.sh`, `G3r3/langmains.py`):
the programs of `tests/lang`, `tests/value_semantics`, `tests/ported`, `tests/guest`, `test/core`, `examples`, `bench` and `benchmarks`, each
a file that has a `main` or is given one that calls every `public func test_*` taking nothing or one `out: Stream`. The generated copies
live under the work directory, never in the repository. Programs named on the command line are appended to the list.

`--corpus-only` writes the list and prints its count, building nothing. The default compiler is the repository's `zig-out/bin/selka`.
The cached builds of all workers share one cache directory (`--cache-dir`), so the run also exercises concurrent writers; `--shard-caches`
gives each worker a cache of its own over a striped share of the list instead (deterministic, no cross-worker serving). The stage store's
shared half, the runtime object store and `XDG_CACHE_HOME` point into the work directory, so the run writes none of the per-user stores.

Prints one line, `builds N: identical X, different Y, failed both ways Z, failed one way W`, the same one the serial script prints, and exits
1 when any program differed or built one way only. A build that a signal ends keeps the end of its
stderr in `<work>/deaths` (one file each), a line says how many and where, and the work directory is kept; the counts are unchanged.
"""
import argparse
import filecmp
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

# The corpus roots, in the order `make_corpus.sh` visits them (the order of the list is part of the check: pass 2 reverses it).
ROOTS = ('tests/lang', 'tests/value_semantics', 'tests/ported', 'tests/guest', 'test/core', 'examples', 'bench', 'benchmarks')
MAIN = re.compile(r'^(public )?func main\(', re.M)
TEST = re.compile(r'^public func (test_\w+)\(((?:out: Stream)?)\) -> bool:', re.M)
# One build that runs this long is a hang, not a slow build; it counts as a failure of that side (exit 124).
DEFAULT_TIMEOUT_SECONDS = 900
TIMED_OUT = 124
PROGRESS_STEPS = 4


def with_main(text):
    """The text of a guest file with a `main` that calls every callable test, or None when it has neither a `main` nor a test."""
    if MAIN.search(text):
        return text
    calls = TEST.findall(text)
    if not calls:
        return None
    needs_out = any(args for _, args in calls)
    body = ['', '', 'func main(out: Stream) -> int:' if needs_out else 'func main() -> int:', '    mut failed = 0']
    for name, args in calls:
        body += [f"    if not {name}({'out' if args else ''}):", '        failed = failed + 1']
    body += ['    return failed', '']
    return text.rstrip('\n') + '\n' + '\n'.join(body)


def make_corpus(repo, out, roots=ROOTS):
    """Copy each corpus root of `repo` under `out/src/<root>`, give each file without a `main` one, and return the buildable paths.

    The list is in the order `make_corpus.sh` made it: roots in `ROOTS` order, files sorted by path within each root. A file with
    neither a `main` nor a callable test is left out.
    """
    programs = []
    for root in roots:
        source = Path(repo) / root
        if not source.is_dir():
            continue
        dest = Path(out) / 'src' / root
        shutil.copytree(source, dest, dirs_exist_ok=True)
        for path in sorted(dest.rglob('*.selka')):
            text = path.read_text()
            built = with_main(text)
            if built is None:
                continue
            if built != text:
                path.write_text(built)
            programs.append(path)
    return programs


def child_environment(work, base=None):
    """The environment of every build: temp files, the object store, the stage store's shared half and `XDG_CACHE_HOME` in `work`.

    Zig's global cache keeps its place (it holds the toolchain's own compiled pieces and is safe to share), so a fresh `XDG_CACHE_HOME`
    does not make every build compile the C library again.
    """
    env = dict(os.environ if base is None else base)
    if 'ZIG_GLOBAL_CACHE_DIR' not in env:
        cache_home = env.get('XDG_CACHE_HOME') or str(Path.home() / '.cache')
        env['ZIG_GLOBAL_CACHE_DIR'] = str(Path(cache_home) / 'zig')
    env['XDG_CACHE_HOME'] = str(Path(work) / 'xdg')
    env['SELKA_CORE_RUNTIME_CACHE'] = str(Path(work) / 'store')
    env['SELKA_STAGE_SHARED_CACHE'] = str(Path(work) / 'stage-shared')
    return env


class Deaths:
    """The builds that a signal ended (`died`): the last `STDERR_KEPT` bytes of each one's stderr, a file per build under
    `<work>/deaths`, so a compiler that died once leaves its trace (FR83). Safe to update from every worker."""

    def __init__(self, work):
        self.lock = threading.Lock()
        self.directory = Path(work) / 'deaths'
        self.count = 0

    def keep(self, program, side, status, stderr):
        """Write one death's stderr and return its path."""
        with self.lock:
            self.count += 1
            number = self.count
        self.directory.mkdir(parents=True, exist_ok=True)
        path = self.directory / f'{number:04d}-{Path(program).stem}-{side}-status{status}.stderr'
        path.write_bytes(stderr[-STDERR_KEPT:])
        return path


# The stderr of a build that died is kept up to this many bytes, its end (where a panic's trace is).
STDERR_KEPT = 64 * 1024


def died(status):
    """Whether a build's status is a death: a signal ended it (negative, or 128 and more as a shell reports one). The compiler's
    own statuses are not: 0, a refusal (1), and 2, which a program that cannot link or needs a host file ends with (122 programs
    of the corpus do, every run)."""
    return status < 0 or status >= 128


def run_build(compiler, program, output, extra, env, cwd, timeout, deaths=None):
    """Run one `selka build`; return its exit status, the timeout status 124 when it ran past `timeout`. A build that dies has its
    stderr kept in `deaths` (a `Deaths`), when one is given."""
    command = [str(compiler), 'build', str(program), '-o', str(output)] + extra
    try:
        done = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, env=env, cwd=cwd,
                              timeout=timeout, check=False)
    except subprocess.TimeoutExpired:
        return TIMED_OUT
    if deaths is not None and died(done.returncode):
        deaths.keep(program, 'plain' if '--no-cache' in extra else 'cached', done.returncode, done.stderr or b'')
    return done.returncode


def classify(cached_status, plain_status, same):
    """One program's verdict: `identical`, `different`, `both-fail` or `one-way`."""
    if cached_status != 0 and plain_status != 0:
        return 'both-fail'
    if cached_status != plain_status:
        return 'one-way'
    return 'identical' if same else 'different'


def check_program(job, program, cache_dir):
    """Build `program` through `cache_dir` and with `--no-cache`, compare, and return `(verdict, cached_status, plain_status)`."""
    slot = job['slot']
    cached, plain = slot / 'cached', slot / 'plain'
    for path in (cached, plain):
        path.unlink(missing_ok=True)
    env, cwd, timeout = job['env'], str(slot), job['timeout']
    deaths = job.get('deaths')
    cached_status = run_build(job['compiler'], program, cached, ['--cache-dir', str(cache_dir)], env, cwd, timeout, deaths)
    plain_status = run_build(job['compiler'], program, plain, ['--no-cache'], env, cwd, timeout, deaths)
    same = (cached_status == 0 and plain_status == 0 and filecmp.cmp(cached, plain, shallow=False))
    return classify(cached_status, plain_status, same), cached_status, plain_status


class Tally:
    """Verdict counts, the findings and the progress line, safe to update from every worker."""

    def __init__(self, total):
        self.lock = threading.Lock()
        self.total = total
        self.counts = {'identical': 0, 'different': 0, 'both-fail': 0, 'one-way': 0}
        self.findings = []
        self.timeouts = 0
        self.done = 0
        self.next_report = max(1, total // PROGRESS_STEPS)

    def add(self, program, verdict, cached_status, plain_status, started):
        """Record one program's result; print a progress line every quarter of the builds."""
        with self.lock:
            self.counts[verdict] += 1
            if verdict in ('different', 'one-way'):
                self.findings.append(f'{verdict} {cached_status} {plain_status} {program}')
            if TIMED_OUT in (cached_status, plain_status):
                self.timeouts += 1
            self.done += 1
            if self.done >= self.next_report and self.done < self.total:
                print(f'  {self.done}/{self.total} builds after {time.monotonic() - started:.0f} s', flush=True)
                self.next_report += max(1, self.total // PROGRESS_STEPS)


def make_slots(work, workers):
    """One scratch directory per worker, so no two builds write the same output path."""
    slots = []
    for number in range(workers):
        slot = Path(work) / f'w{number}'
        slot.mkdir(parents=True, exist_ok=True)
        slots.append(slot)
    return slots


def run_shared(job_base, programs, workers, tally):
    """Two passes over one shared cache: the list forward, every worker finished, then the list reversed."""
    cache = Path(job_base['work']) / 'cache'
    slots = make_slots(job_base['work'], workers)
    local = threading.local()
    taken = []
    guard = threading.Lock()

    def start():
        with guard:
            local.slot = slots[len(taken)]
            taken.append(local.slot)

    def one(program):
        job = dict(job_base, slot=local.slot)
        tally.add(program, *check_program(job, program, cache), job_base['started'])

    for order in (programs, programs[::-1]):
        taken.clear()
        with ThreadPoolExecutor(max_workers=workers, initializer=start) as pool:
            list(pool.map(one, order))


def run_sharded(job_base, programs, workers, tally):
    """Each worker owns a striped share of the list and its own cache, and runs its share forward then reversed."""
    slots = make_slots(job_base['work'], workers)

    def shard(number):
        mine = programs[number::workers]
        cache = Path(job_base['work']) / f'cache{number}'
        job = dict(job_base, slot=slots[number])
        for order in (mine, mine[::-1]):
            for program in order:
                tally.add(program, *check_program(job, program, cache), job_base['started'])

    with ThreadPoolExecutor(max_workers=workers) as pool:
        list(pool.map(shard, range(workers)))


def parse_arguments(argv):
    """The command line."""
    repo = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('programs', nargs='*', help='further programs to build both ways, appended to the corpus')
    parser.add_argument('--compiler', default=str(repo / 'zig-out' / 'bin' / 'selka'), help='the compiler to check')
    parser.add_argument('--repo', default=str(repo), help='the tree whose corpus roots are used')
    parser.add_argument('--work', help='work directory (default: $TMPDIR/corpus-exact, else .tmp/corpus-exact under the repository)')
    parser.add_argument('--jobs', type=int, default=default_jobs(), help='worker count (default: %(default)s)')
    parser.add_argument('--timeout', type=int, default=DEFAULT_TIMEOUT_SECONDS, help='seconds one build may run (default: %(default)s)')
    parser.add_argument('--shard-caches', action='store_true', help='one cache per worker over a striped share of the list')
    parser.add_argument('--list', help='build exactly the programs named in this file (one path per line) instead of the corpus')
    parser.add_argument('--corpus-only', action='store_true', help='write the list, print its count and build nothing')
    parser.add_argument('--keep', action='store_true', help='keep the work directory (the list, the findings and the caches)')
    return parser.parse_args(argv)


def default_jobs():
    """Half the CPUs this process may use, between 2 and 12: a build runs its own C compiler processes, and other lanes share the machine."""
    cpus = len(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else (os.cpu_count() or 4)
    return max(2, min(12, cpus // 2))


def work_directory(arguments):
    """The work directory, made empty."""
    if arguments.work:
        work = Path(arguments.work)
    elif os.environ.get('TMPDIR'):
        work = Path(os.environ['TMPDIR']) / 'corpus-exact'
    else:
        work = Path(arguments.repo) / '.tmp' / 'corpus-exact'
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    return work.resolve()


def describe(programs, work):
    """The corpus count line, with each root's share."""
    shares = []
    for root in ROOTS:
        marker = str(Path(work) / 'src' / root) + os.sep
        count = sum(1 for p in programs if str(p).startswith(marker))
        if count:
            shares.append(f'{root} {count}')
    return f'corpus: {len(programs)} programs ({", ".join(shares)}); {2 * len(programs)} builds over two passes'


def main(argv=None):
    """Run the check; the process status is 0 when every program was identical or built neither way."""
    arguments = parse_arguments(argv)
    compiler = Path(arguments.compiler).resolve()
    work = work_directory(arguments)
    if arguments.list:
        programs = [Path(line.strip()).resolve() for line in Path(arguments.list).read_text().splitlines() if line.strip()]
        print(f'list: {len(programs)} programs from {arguments.list}; {2 * len(programs)} builds over two passes', flush=True)
    else:
        programs = make_corpus(arguments.repo, work)
        print(describe(programs, work), flush=True)
    programs += [Path(p).resolve() for p in arguments.programs]
    (work / 'list.txt').write_text(''.join(f'{p}\n' for p in programs))
    if arguments.corpus_only:
        print(f'list: {work / "list.txt"}')
        return 0
    if not compiler.is_file():
        print(f'corpus_exact: no compiler at {compiler}', file=sys.stderr)
        return 2
    started = time.monotonic()
    tally = Tally(2 * len(programs))
    deaths = Deaths(work)
    job_base = {'compiler': compiler, 'env': child_environment(work), 'timeout': arguments.timeout, 'work': work, 'started': started,
                'deaths': deaths}
    workers = max(1, min(arguments.jobs, len(programs))) if programs else 1
    mode = 'one cache per worker' if arguments.shard_caches else 'one shared cache'
    print(f'checking with {workers} workers, {mode}, compiler {compiler}', flush=True)
    (run_sharded if arguments.shard_caches else run_shared)(job_base, programs, workers, tally)
    counts = tally.counts
    # The deaths line comes first: `scripts/lane/finish.sh` shows the last three lines, which must hold the counts.
    if deaths.count:
        print(f'{deaths.count} builds died of a signal: stderr kept in {deaths.directory}')
    print(f'builds {tally.done}: identical {counts["identical"]}, different {counts["different"]}, '
          f'failed both ways {counts["both-fail"]}, failed one way {counts["one-way"]}')
    print(f'elapsed {time.monotonic() - started:.1f} s with {workers} workers; {tally.timeouts} builds timed out')
    findings = sorted(tally.findings)
    (work / 'different.txt').write_text(''.join(f'{line}\n' for line in findings))
    for line in findings[:20]:
        print(line)
    if len(findings) > 20:
        print(f'... {len(findings) - 20} more in {work / "different.txt"}')
    if arguments.keep or findings or deaths.count:
        print(f'work directory kept: {work}')
    else:
        shutil.rmtree(work, ignore_errors=True)
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())
