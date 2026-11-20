# The exactness check for compiler lanes

A compiler lane that touches lowering, the stage store, the engine's keys or the object store lands with one more
check than the gate: **a program built through a cache is the program a cold build makes**. `scripts/corpus_exact.py`
builds every program of the standard corpus twice, once through one shared cache directory and once with
`--no-cache`, and compares the two executables byte for byte. A difference means a cache served bytes that a fresh
build would not have made; one build succeeding where the other fails is the same kind of finding.

```sh
source ~/.config/selka/dev-env.sh
zig build -Doptimize=ReleaseFast --prefix ~/ai/.home-cache/mylang-rf        # or use the Debug zig-out/bin/selka
scripts/build-slot.sh build python3 scripts/corpus_exact.py --compiler ~/ai/.home-cache/mylang-rf/bin/selka
```

It prints the corpus count first, then one line, the same one the serial script it replaces printed:

```text
corpus: 742 programs (tests/lang 388, tests/value_semantics 19, tests/ported 21, tests/guest 11, test/core 179, examples 67, bench 53, benchmarks 4); 1484 builds over two passes
builds 1484: identical 1372, different 0, failed both ways 112, failed one way 0
elapsed 56.0 s with 8 workers; 0 builds timed out
```

It exits 1 when any program is `different` or builds one way only, and lists them (the first 20, all in
`different.txt` of the kept work directory). **Landing needs `different 0` and `failed one way 0`; the `failed both
ways` count is the corpus's own baseline** (112 on 9 November: files that need a project, capability or input the bare
build does not give), so compare it with the count of `main`, not with zero.

## The corpus

The programs are the ones every guest-build lane has used (`experiments/guest-build-engine-20261031/G3p/make_corpus.sh`
and `G3r3/langmains.py`): each `.selka` file under `tests/lang`, `tests/value_semantics`, `tests/ported`, `tests/guest`,
`test/core`, `examples`, `bench` and `benchmarks` that has a `main`, or is given one that calls every
`public func test_*` taking nothing or one `out: Stream`. A file with neither is left out. The script copies those
trees into its work directory and writes the mains there, so the repository stays untouched, and prints the count
(742 programs on `dc9b1fa08`; the 707 of 31 October grew with the tests). `--corpus-only` writes the list
(`list.txt` of the work directory) and builds nothing; `--list FILE` builds exactly the programs a file names, and
programs named on the command line are appended to the corpus (a lane's own probes that use a new feature).

## What it checks, and how

For each program `P`, in list order and then in reversed order (the second pass is served by what the first stored):

1. `selka build P -o cached --cache-dir CACHE`, with the engine deciding lowering whatever else the environment says;
2. `selka build P -o plain --no-cache`;
3. a program that fails both ways is counted and not compared; one that fails one way is a finding; two that build are
   compared with `cmp`.

The environment is the serial script's plus isolation: `XDG_CACHE_HOME`, `SELKA_CORE_RUNTIME_CACHE` and
`SELKA_STAGE_SHARED_CACHE` point into the work directory, so a run writes none of the per-user stores
(`ZIG_GLOBAL_CACHE_DIR` keeps its place). A build that runs past `--timeout` (900 s) counts as a failure of that side.

## Workers and the cache layout

`--jobs N` builds with N workers (default half the CPUs the process may use, 2 to 12: 10 on this machine). **By default
all workers share one cache directory**, so the run also exercises concurrent writers (two workers building a unit at
once, a pass-2 build served by an entry another worker wrote a moment ago); the equality it asserts must hold for every
interleaving, and a mismatch under sharing is a real finding even when a serial run would not show it.
`--shard-caches` gives each worker a cache of its own over a striped share of the list, and it runs its share forward
then reversed: deterministic, nothing served across workers, the serial script's behaviour cut into pieces. Both layouts
give the serial script's counts on `dc9b1fa08` (identical 1372, different 0, failed both ways 112, failed one way 0).
`experiments/devloop3-20261109/DECISIONS.md` has the measurements behind the defaults.

## Which compiler

| Compiler | Serial script | `corpus_exact.py`, 8 workers | 12 workers |
| --- | --- | --- | --- |
| ReleaseFast | 162 s | 56 s | not run |
| Debug | 30 min on 8 November under load (not rerun; the check's CPU is about 710 s) | 131 s (118 s with `--shard-caches`; 195 s with 4 workers) | 111 s |

Both finish in well under five minutes on a calm machine, so **use the compiler the lane has at hand**: the Debug
`zig-out/bin/selka` after `zig build`, with no ReleaseFast build to wait for (7.5 minutes). The check is about bytes, and
a Debug compiler's own certificate validators run on every function it compiles, which a ReleaseFast one does not.
A lane that already has a ReleaseFast compiler gets the result in a minute.

## Landing

Run it once per landing, before the gate, through a build slot (`scripts/build-slot.sh build python3
scripts/corpus_exact.py`) or, to time it, a timing window. It does not belong in an exclusive timing window otherwise:
ten workers use the whole machine for two minutes. The script's own tests are `python3 scripts/corpus_exact_test.py`.
