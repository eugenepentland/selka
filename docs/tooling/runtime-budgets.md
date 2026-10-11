# Runtime budgets

Instruction and frame limits bound how long a guest runs; byte budgets bound how
much memory it may hold while running. There are two distinct mechanisms, and
they measure different things. An *allocation budget* is an embedding API — a
Zig host wraps an allocator in `language.allocation_budget.Memory` and counts the
live bytes handed out through it. A *ceiling* is coarser and applies to a whole
process that runs guest code. The design record is
[runtime byte budgets and allocator attenuation](../experiments/runtime-memory-budgets.md).

## Nested byte budgets

Allocation budgets count live requested bytes routed through the supplied
allocator interface, and they nest: a child budget charges its parent as well as
itself, so raising a child above its parent grants nothing. The reported limit of
a child is clamped to the parent's rather than accepted as written, and an
allocation deep inside a helper cannot evade any ancestor limit. Zero permits no
nonempty allocation. A failed acquisition charges nothing, a release restores
live accounting while retaining the peak, and a moving reallocation may need the
old and new capacity at once, so it can fail below its own final-size limit.
Exhaustion is a host `OutOfMemory` with normal cleanup — it is not a
guest-recoverable numeric error. Embedders must keep both accounting objects at
stable addresses until every allocation made through the child is freed; the
allocator is single-threaded and is not a capability a guest can be handed.

This is accounting for memory an *embedding host* requests, not a cap on a guest
process — a program built by `mylang build` does not route its allocations
through it. Use a ceiling, below, to bound a guest.

```sh
# src/allocation_budget_test.zig runs as part of the default unit-test root
zig build test
```

## Instruction and frame budgets

`mylang run`, `run-project` and `build --run` have **no step or frame ceiling by
default**: the byte ceiling below already contains a runaway allocation, and a
development loop should not stop an honest program. Pass `--max-steps N` or
`--max-frames N` to impose one, and `--timeout SECONDS` to cap elapsed time. Each
takes `--flag N` or `--flag=N`, and N must be a positive integer:

```console
$ mylang run loop.my --max-steps 1000
error[R_STEP_LIMIT]: native execution failed
instruction budget exhausted; raise it with --max-steps=N
$ mylang build loop.my --run --max-steps=500000000
$ mylang run loop.my --timeout 30     # wall-clock guard; no default
```

`mylang run` compiles the budgets it was given into the program: `main` installs
them before anything else runs, every block of a program function charges one step
when steps are bounded, and every call of one counts a frame when frames are.
Generated adapters are not charged. A program built with `mylang build -o` carries
no budget code at all and pays nothing for it; to bound it, run it through
`mylang run` or `build --run`.

A `mylang test` child is different: each test process starts at **1,000,000**
steps and **1,024** frames, because a test is the one place a tight guard is useful.
`--max-steps` and `--max-frames` on `mylang test` bound each test process and may be
lowered or raised; `--timeout-ms N` (default 60,000) bounds each test's wall clock.

`R_STEP_LIMIT`, `R_FRAME_LIMIT` and `R_MEMORY_BUDGET` end with one advice line
naming the flag that raises them, in text and in the `message` of
`--diagnostics=json`: "instruction budget exhausted; raise it with --max-steps=N",
"call-depth budget exhausted; raise it with --max-frames=N (each frame reserves 32
KiB of stack, so --max-memory must cover N x 32 KiB)" and "memory budget exhausted;
raise it with --max-memory=SIZE". `--timeout` arms a timer inside the program; when
it fires the process reports `R_TIMEOUT` and exits 1. A zero, negative, empty or
non-numeric budget is refused before anything is built.

These counters bound *compiler-generated work*, not elapsed time: a program that
calls into a linked C function can spend arbitrary time inside that call. The byte
ceiling below bounds memory, not time.

### What a frame budget costs

A `--max-frames N` ceiling is only honest if N frames fit on the native stack, so
the program runs on a stack of **32 KiB for every frame the budget allows**, plus
8 MiB, inside its address space: its `--max-memory` ceiling plus 256 MiB. Nothing
is touched until the recursion reaches it, but the reservation counts against the
address-space limit, so a large budget needs a large `--max-memory` beside it:
150,000 frames reserve 4.6 GiB and do not fit the 4 GiB default. A budget that
cannot fit is refused before anything is built, with status 2 and what it needs:

```console
$ mylang run deep.my --max-frames 150000
mylang run: a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but a guest may map only 4.3 GiB: raise --max-memory to at least 5G, or lower --max-frames to at most 137984
$ mylang run deep.my --max-frames 150000 --max-memory 5G
```

`mylang test` refuses the same way for a per-test ceiling (512 MiB by default, so
`--max-frames 30000` needs `--max-memory 1G`).

The address space a program may map is also bounded by the original caller's soft
and hard limits. The compiler's own 8 GiB ceiling (`MYLANG_HOST_MEMORY_LIMIT`,
below) is given back to the caller's allowance for the program it runs, so
`--max-frames=400000 --max-memory=64G` can run when the caller allows that
reservation; a tighter caller `ulimit -v` is still refused and must be raised by the
caller.

### Project defaults in `mylang.json`

A project that always needs the same budgets, a parser test that recurses 20,000
frames deep for example, can say so once instead of on every command line.
`mylang.json` takes an optional `limits` object with a `run` entry and a `test`
entry, each any of `max_steps`, `max_frames` (positive integers up to
4,294,967,295) and `max_memory` (a byte count or a `K`/`M`/`G` size, `0` for no
ceiling):

```json
{"version": 1, "limits": {"test": {"max_steps": 4000000000, "max_frames": 30000, "max_memory": "1G"}}}
```

`mylang run`, `run-project` and `test` read the configuration nearest the entry file
and use these as defaults for the matching flag. A flag on the command line always
wins, `MYLANG_MEMORY_LIMIT` outranks the file's `max_memory`, and the built-in
defaults apply to whatever the file leaves out. A configured budget goes through the
same checks as the flag, so a `max_frames` the memory cannot back is refused with
what it needs. A directory run leaves each program to the configuration nearest
that program. An unknown key, a repeated key or a budget that is zero, not an
integer or out of range is a configuration failure.

## Guest memory ceilings

A *ceiling* bounds a whole process that runs guest code, so one runaway program
cannot take the machine into swap. `mylang run`, `run-project`, `build --run` and
every `mylang test` child run under one; a program built with `mylang build -o` and
started by hand carries none and pays nothing for it.

Two mechanisms enforce it. The soft one is the runtime's byte count: it counts the
chunks small blocks are carved from and every live large block, and an allocation
past the ceiling traps `R_MEMORY_BUDGET` with exit status 1, exactly like
`R_STEP_LIMIT` bounds steps. The hard one is the kernel's: the program lowers its
own `RLIMIT_AS` (never raises it) to the ceiling plus 256 MiB, so an allocation the
OS then refuses reports `R_MEMORY_BUDGET` too. A process that bounds itself is also
bounded when you start it by hand.

Precedence is `--max-memory SIZE` on `run`, `build --run` and `test` first, then
`MYLANG_MEMORY_LIMIT`, then the project's `limits` in `mylang.json`, then the
built-in default: **4 GiB** for `run` and `build --run`, **512 MiB** for one
`mylang test` child. Sizes are bytes with an optional `K`, `M` or `G` suffix;
malformed text refuses the run rather than leaving it unbounded, and `0` removes
the ceiling. The resolved test ceiling and frame budget are part of a test receipt's
key, so changing them re-executes rather than reusing.

The compiler bounds itself too, at 8 GiB unless `MYLANG_HOST_MEMORY_LIMIT` says
otherwise, so a compiler defect fails loudly instead of swapping; the `zig cc`
children a build spawns complete under that inherited ceiling, while the program it
runs gets the caller's limit back before applying its own.

Save this checked program as `grow.my`:

```mylang
# doc: check
func grow(mut values: int[], rounds: int) -> int:
    for r in range(rounds):
        values.append(r)
    return len(values)


func main() -> int:
    mut values: int[] = []
    return grow(mut values, 100000000)
```

```console
$ mylang build grow.my --run --max-memory=64M
error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE
  in grow at grow.my:1:0
  in main at grow.my:9:12
$ echo $?
1
```

A `mylang test` child reports the same trap as an ordinary failure, with its trace:

```console
$ mylang test suite/main.my --max-memory=32M --max-steps=400000000
failed main::test_runaway: NativeTestProcessFailed: .{ .exited = 1 }
error[R_MEMORY_BUDGET]: native execution failed
  in main::test_runaway at main.my:11:12
  in __test_trial_352905b6a34bbacc7c39e58cdc29fa1f at main.my:1:1
memory budget exhausted; raise it with --max-memory=SIZE
0 passed, 0 cached, 1 failed, 0 skipped
```

## Test fan-out

A directory run (`mylang test suite/`) runs each program's tests in its own
processes, from one worker budget shared by the whole run: `--jobs N`, else
`MYLANG_JOBS`, else the CPUs the process may use, capped by how many per-test byte
ceilings (each plus the 256 MiB address-space headroom) the machine's `MemAvailable`
holds, and at least one. It never starts more workers than there is work, and a zero
or non-numeric `--jobs` is rejected. An explicit width is not capped by memory: on a
loaded machine, leave it out, or lower it or the per-test `--max-memory`.

```console
$ mylang test suite/ --jobs 4 --max-memory=256M
```

That bounds one invocation. Several agents building and gating on one machine share
it through `scripts/build-slot.sh`, which admits a job only when a slot and enough
`MemAvailable` are free ([many agents on one machine](many-agents.md)).

## Sharded Zig test roots

The gate's two slow Zig test roots run as several processes rather than one:
`zig build test` splits `src/root_test.zig` into `-Dtest-shards=N` shards
(default 12) and `test/integration.zig` into `N/2`, each an independent run of
the same test binary under `--guardian-shard=K/N`, declaring its own `max_rss`
(2.5 GiB per unit shard, 2 GiB per CLI shard) so `zig build --maxrss` still
bounds the whole gate. Guardian's runner gives each shard the named tests whose
position among them is `K` modulo `N`, and the unnamed `test { }` blocks to
shard 0 alone, so the shards partition the root and their `N test(s) selected`
counts sum to the unsharded count.

`-Dtest-shards=1` restores one process per root. `test-units` and `test-cli`
are never sharded, and `-Dtest-filter=…` puts `test` back on their single
whole-root runs too: the compiler has already dropped every non-matching test,
so splitting the remainder would mostly produce empty shards. An empty shard is
not a failure — only a root that selected nothing as a whole still fails.
`test-units-sharded` and `test-cli-sharded` split a filtered run anyway; they
exist for `scripts/affected_tests.py`, whose selections can name a hundred slow
tests and which sums the shards' counts itself.

### Declared memory is a reservation, not a measurement

The build runner starts a step only while the `max_rss` of every running step
fits in `--maxrss` (by default the machine's total memory, 30 GiB here), so the
declarations decide how much of the gate runs at once. A driver's declaration
covers its whole process tree at its peak; a Zig test binary's must also stay
above the largest single process, which the runner checks. The pinned Zig
`0.17.0-dev.1683+5ceec001b` runner currently prints an excess-memory diagnostic
without failing its final build summary; inspect that diagnostic as well as
the exit status when qualifying a memory declaration. On
2026-09-23 a clean-cache `zig build test` never held more than 5.8 GiB at once,
while its declarations summed to far more than 30 GiB: the last unit shards
waited most of a minute for reservations that were never used. The ceilings in
`build.zig` now follow measured peaks — then 1 GiB per unit shard (largest process
570 MiB; 2.5 GiB since a 2.18 GiB shard peak on 2026-10-05), initially 768 MiB per CLI shard (141 MiB), 1.5 GiB for the host-application
roots (since retired) and `tests/guest`, 256 MiB for checks that run no compiler — and a rerun
of every test took 98 s instead of 136 s on the same loaded machine (81 s with
no memory limit at all). Measure a step's tree before raising its ceiling; a
larger number is not a safer one.

The B4 uncached component bootstrap reported a 1,538,023,424-byte CLI shard
peak on 2026-10-11, so CLI shards now reserve 2 GiB. Frontend and body
qualification drivers also rebuild the optimized body component; they reserve
2.5 GiB across the seed and clang. A body test build's process tree was sampled
at 1,304,895,488 bytes before clang's peak. These are build scheduling allowances;
guest memory limits and the selfhost performance budget remain unchanged.

## Cached test verdicts

A `zig build` Run step is re-executed only when its cache key changes, and the
gate's test steps now use that: the root shards,
the Python drivers and `mylang doctest` are keyed on the test binary, the
emitted compiler they run, their command, the environment variables
they depend on, and the repository files listed for them in
`build_test_inputs.zig`. Those lists are
expanded on every build by `tests/input_manifest.py`, which writes one content
manifest per list (a SHA-256 per file); each step declares its manifest, so an
edited, added, removed or renamed file re-runs exactly the steps whose lists
cover it. The walk happens at make time because this Zig version records
`dependOnDirectory` but never re-runs the configure phase for it: a list
expanded in `build.zig` would not see a new fixture. An unchanged `zig build
test` reruns only the manifest walk (0.15 s), Guardian, `doc-coverage`, the guest suites (whose own
receipts make that near-free) and the SPEC merge replay, which reads git
history. `test-inputs-coverage` fails the gate when a test source names an
existing repository path that its step does not declare, and
`-Dtest-rerun=true` re-runs every cached test step when a verdict is in doubt.

Every test step runs in the environment of the `zig build` that runs it. The
build names the native tool (`MYLANG_ZIG`)
and Zig's global cache through a `sh … env NAME=value` prefix on the command,
never through `Step.Run.setEnvironmentVariable`: that call copies the whole
configure-time environment into the step, the build runner stores the copy in
the cached configuration, and every later build with the same `-D` options ran
its tests with the `PATH`, `HOME`, `TMPDIR` and `MYLANG_*` of whichever build
first configured that cache. `build.zig` now refuses to configure when any step
carries its own environment. Because a live environment is not part of a step's
cache key, one small step records the variables a verdict depends on (`PATH`,
`HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `ZIG_GLOBAL_CACHE_DIR`,
`ZIG_LOCAL_CACHE_DIR` and every `MYLANG_*`) on each build, and every cached test
step declares that record as an input: a changed variable re-runs the cached
verdicts, an unchanged one keeps them.

A driver's standard output is sent to standard error, because the build runner
discards a checked step's standard output and would otherwise hide the report
of a failing driver.

A native guest can use an explicit memory budget larger than the compiler's host
ceiling. The compiler records the caller's original soft address-space limit;
the guest restores that limit before applying its own budget. External soft
and hard limits still apply. The compiler and native build tools keep the host
ceiling. Guest test failures that exhaust call depth advise raising
`--max-frames` together with enough `--max-memory` to back the frames.
