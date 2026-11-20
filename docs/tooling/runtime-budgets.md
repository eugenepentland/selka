# Runtime budgets

Instruction and frame limits bound how long a guest runs; byte budgets bound how
much memory it may hold while running. There are two distinct mechanisms, and
they measure different things. An *allocation budget* is an embedding API — a
Zig host wraps an allocator in `language.allocation_budget.Memory` and counts the
live bytes handed out through it. A *ceiling* is coarser and applies to a whole
process that runs guest code. The design record is
runtime byte budgets and allocator attenuation (`docs/experiments/runtime-memory-budgets.md`).

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
process — a program built by `selka build` does not route its allocations
through it. Use a ceiling, below, to bound a guest.

```sh
# src/allocation_budget_test.zig runs as part of the default unit-test root
zig build test
```

## Instruction and frame budgets

`selka run`, `run-project` and `build --run` have **no step or frame ceiling by
default**: the byte ceiling below already contains a runaway allocation, and a
development loop should not stop an honest program. Pass `--max-steps N` or
`--max-frames N` to impose one, and `--timeout SECONDS` to cap elapsed time. Each
takes `--flag N` or `--flag=N`, and N must be a positive integer:

```console
$ selka run loop.selka --max-steps 1000
error[R_STEP_LIMIT]: native execution failed
instruction budget exhausted; raise it with --max-steps=N
$ selka build loop.selka --run --max-steps=500000000
$ selka run loop.selka --timeout 30     # wall-clock guard; no default
```

`selka run` compiles the budgets it was given into the program: `main` installs
them before anything else runs, every block of a program function charges one step
when steps are bounded, and every call of one counts a frame when frames are.
Generated adapters are not charged. A program built with `selka build -o` carries
no budget code at all and pays nothing for it; to bound it, run it through
`selka run` or `build --run`.

A `selka test` child is different: each test process starts at **1,000,000**
steps and **1,024** frames, because a test is the one place a tight guard is useful.
`--max-steps` and `--max-frames` on `selka test` bound each test process and may be
lowered or raised; `--timeout-ms N` (default 60,000) bounds each test's wall clock.

A test that stops on one of these two budgets while it still has the default says so instead of the line below: "this test
passed its budget of 1,000,000 steps (every test has one); raise it with `selka test --max-steps=N` or `limits.test.max_steps` in
`selka.json`" (for frames, "this test went deeper than its budget of 1,024 nested calls ..."). A test whose budget a flag or the project
set keeps the line below, which `selka run`, `build --run` and a built binary always print.

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

### What bounds a built binary

A program built with `selka build -o` has no frame budget, so `--max-frames` is not
something it can take (setting it in `SELKA_OPTIONS` ends with `R_NO_FRAME_ACCOUNTING`).
Its recursion depth is bounded by the native stack: the main thread's `ulimit -s`, 8 MiB
unless the shell says otherwise. A frame keeps a stack slot for each record or union over
four words, but values of one size that are never live together share a slot once a
function's slots pass 4 KiB (FR79): a tree-walking interpreter's `eval` with 30 recursive
call sites has a 1.3 KB frame in a debug build and 2.3 KB with `--release` (8.6 and 8.8 KB
before), so 8 MiB holds roughly 3,000 to 6,000 frames of such a function and tens of thousands
of a small one (a few hundred bytes). When the stack fills, the binary
reports `R_FRAME_LIMIT` with a located trace of the innermost 16 frames and exits 1; the
message names the native stack and the remedy, `ulimit -s KBYTES` before starting the binary
(`ulimit -s unlimited` where the hard limit allows it), or running the program under
`selka run --max-frames=N`, which maps a stack of its own (next section). The budgeted
traps of `selka run` and `selka test` keep their `raise it with --max-frames=N` advice.

### What a frame budget costs

A `--max-frames N` ceiling is only honest if N frames fit on the native stack, so
the program runs on a stack of **32 KiB for every frame the budget allows**, plus
8 MiB, inside its address space: its `--max-memory` ceiling plus 256 MiB. Nothing
is touched until the recursion reaches it, but the reservation counts against the
address-space limit, so a large budget needs a large `--max-memory` beside it:
150,000 frames reserve 4.6 GiB and do not fit the 4 GiB default. A budget that
cannot fit is refused before anything is built, with status 2 and what it needs:

```console
$ selka run deep.selka --max-frames 150000
selka run: a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but a guest may map only 4.3 GiB: raise --max-memory to at least 5G, or lower --max-frames to at most 137984
$ selka run deep.selka --max-frames 150000 --max-memory 5G
```

`selka test` refuses the same way for a per-test ceiling (512 MiB by default, so
`--max-frames 30000` needs `--max-memory 1G`).

The address space a program may map is also bounded by the original caller's soft
and hard limits. The compiler's own 8 GiB ceiling (`SELKA_HOST_MEMORY_LIMIT`,
below) is given back to the caller's allowance for the program it runs, so
`--max-frames=400000 --max-memory=64G` can run when the caller allows that
reservation; a tighter caller `ulimit -v` is still refused and must be raised by the
caller.

### Project defaults in `selka.json`

A project that always needs the same budgets, a parser test that recurses 20,000
frames deep for example, can say so once instead of on every command line.
`selka.json` takes an optional `limits` object with a `run` entry and a `test`
entry, each any of `max_steps`, `max_frames` (positive integers up to
4,294,967,295) and `max_memory` (a byte count or a `K`/`M`/`G` size, `0` for no
ceiling):

```json
{"version": 1, "limits": {"test": {"max_steps": 4000000000, "max_frames": 30000, "max_memory": "1G"}}}
```

`selka run`, `run-project` and `test` read the configuration nearest the entry file
and use these as defaults for the matching flag. A flag on the command line always
wins, `SELKA_MEMORY_LIMIT` outranks the file's `max_memory`, and the built-in
defaults apply to whatever the file leaves out. A configured budget goes through the
same checks as the flag, so a `max_frames` the memory cannot back is refused with
what it needs. A directory run leaves each program to the configuration nearest
that program. An unknown key, a repeated key or a budget that is zero, not an
integer or out of range is a configuration failure.

## Guest memory ceilings

A *ceiling* bounds a whole process that runs guest code, so one runaway program
cannot take the machine into swap. `selka run`, `run-project`, `build --run` and
every `selka test` child run under one. A program built with `selka build -o` and
started by hand runs under one when its environment names one: `--max-memory=SIZE` in
`SELKA_OPTIONS` first, else `SELKA_MEMORY_LIMIT`, else none; without one it pays
nothing for it. The sizes are read as below, `0` removes the ceiling, and a size that
is not one ends the binary with status 2 and one line before `main` runs (an example
follows `grow.selka` below). Under `selka run` and `build --run` the program does not read either: the run's own
ceiling, settled in the order below, is built into it, so a `SELKA_MEMORY_LIMIT` the
program inherits is neither applied twice nor ahead of `--max-memory`.

Two mechanisms enforce it. The soft one is the runtime's byte count: it counts the
chunks small blocks are carved from and every live large block, and an allocation
past the ceiling traps `R_MEMORY_BUDGET` with exit status 1, exactly like
`R_STEP_LIMIT` bounds steps. The hard one is the kernel's: the program lowers its
own `RLIMIT_AS` (never raises it) to the ceiling plus 256 MiB, so an allocation the
OS then refuses reports `R_MEMORY_BUDGET` too. A process that bounds itself is also
bounded when you start it by hand. The ceiling is the guest's own: a program it starts
with `process.run` or `process.start` gets back the address-space limit the guest
started with ([io.md](../io.md#processes)).

Precedence is `--max-memory SIZE` on `run`, `build --run` and `test` first, then
`SELKA_MEMORY_LIMIT`, then the project's `limits` in `selka.json`, then the
built-in default: **4 GiB** for `run` and `build --run`, **512 MiB** for one
`selka test` child. Sizes are bytes with an optional `K`, `M` or `G` suffix;
malformed text refuses the run rather than leaving it unbounded, and `0` removes
the ceiling. The resolved test ceiling and frame budget are part of a test receipt's
key, so changing them re-executes rather than reusing.

The compiler bounds itself too, at 8 GiB unless `SELKA_HOST_MEMORY_LIMIT` says
otherwise, so a compiler defect fails loudly instead of swapping; the `zig cc`
children a build spawns complete under that inherited ceiling, while the program it
runs gets the caller's limit back before applying its own.

**The compiler's own stack.** Checking and lowering recurse on the depth of an
expression: a left-nested sum of 1,024 terms needs about 10 MiB, and the shell's
`ulimit -s` is 8 MiB. So every command of the compiler runs on a thread whose stack the
compiler chose, `compiler_stack_bytes` in `src/memory_budget.zig` (256 MiB of address
space; only the pages a compile touches are used), and the main thread waits for it.
The compiler's depth therefore depends neither on `ulimit -s` nor on how a build of
the compiler was made (an executable made with Zig's incremental back end declares no
stack, so Zig's start code does not raise the shell's soft limit to the 16 MiB an
ordinary build declares). The stack is address space inside the ceiling's headroom, so
a compiler held to a tight ceiling (under 2 GiB, as the memory tests set) keeps the
16 MiB stack Zig gives any thread, and a system that will not start the thread (a
caller's `ulimit -v`) leaves the work on the main thread, as before. A program that
needs more than the stack still ends with the crash report (`crash-state:` lines in a
Debug compiler, then Zig's trace) and status 134.

The ceiling is `RLIMIT_AS` of each compiler process (the limit plus 256 MiB of
headroom), so it bounds one process, not a tree: a directory run's child processes
each have their own. `selka test` holds it for the whole run: it checks, lowers and
builds in one process (a directory run builds the roots that share a check, or own
docstring examples, in its own process), so that process and the `zig cc` builds it
starts stay under the ceiling, and only each test process is started with the
caller's address space back (`process_spawn.Options.address_space`; the program
lowers it again to its own ceiling). A run that outgrows the ceiling fails, rather
than being killed by the kernel's out-of-memory killer:

- the compiler itself ends with status 2 and
  `selka: out of memory: the compiler reached its own memory ceiling of 8.0 GiB
  (SELKA_HOST_MEMORY_LIMIT, with 256 MiB more address space for its program text
  and stacks); raise SELKA_HOST_MEMORY_LIMIT ...`;
- a build tool that ran out of memory under it (`LLVM ERROR: out of memory`, or a
  thread it could not create) is reported by a line that leads the tool's own words,
  `selka: a build tool ran out of memory under the compiler's own address-space
  ceiling (SELKA_HOST_MEMORY_LIMIT)`, which a test verdict keeps as its reason;
- a build tool that crashes with no such words (clang's frontend aborting, which Zig
  reports as `clang frontend command failed with exit code 134`, or a tool killed by
  `SIGABRT`, `SIGSEGV` or `SIGBUS`) gets a line that names the ceiling without
  claiming it was the cause, `selka: a build tool crashed while the compiler's own
  address-space ceiling (SELKA_HOST_MEMORY_LIMIT) was in force; if it ran out of
  memory, raise the ceiling ...`. The tool's own words follow it, so a crash that has
  nothing to do with memory is still shown as the crash it is.

Raise the ceiling with `SELKA_HOST_MEMORY_LIMIT=16G`, or remove it with `0`.

The ceiling is a backstop, not a budget a run should lean on. Before `selka test`
kept it, a directory run of `markdown/sitegen` (146 tests, docstring examples in its
closure) grew one process to 10 to 12 GB: every example opened the shared receipt
store, and each open ran a cache sweep that kept a path for up to a million entries
in the root's arena until the root finished. The sweep now frees its inventory when
it returns (see `cache-retention.md#native-cache-retention`), and the same run stays
under 1 GB.

Save this checked program as `grow.selka`:

```selka
# doc: check
func grow(mut values: int[], rounds: int) -> int:
    for r in range(rounds):
        append(mut values, r)
    return len(values)


func main() -> int:
    mut values: int[] = []
    return grow(mut values, 100000000)
```

```console
$ selka build grow.selka --run --max-memory=64M
error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE
  in grow at grow.selka:1:0
  in main at grow.selka:9:12
$ echo $?
1
```

Built with `selka build -o` and started by hand, the same program takes its ceiling
from its environment:

```console
$ selka build grow.selka -o grow
$ SELKA_MEMORY_LIMIT=64M ./grow; echo $?
error[R_MEMORY_BUDGET]: memory budget exhausted; raise it with --max-memory=SIZE
  in main at grow.selka:0:0
1
$ SELKA_OPTIONS=--max-memory=0 SELKA_MEMORY_LIMIT=64M ./grow    # 0: no ceiling
$ SELKA_MEMORY_LIMIT=12x ./grow; echo $?
selka: SELKA_MEMORY_LIMIT names 12x, which is not a byte size
2
```

A `selka test` child reports the same trap as an ordinary failure, with its trace:

```console
$ selka test suite/main.selka --max-memory=32M --max-steps=400000000
failed main::test_runaway: NativeTestProcessFailed: .{ .exited = 1 }
error[R_MEMORY_BUDGET]: native execution failed
  in main::test_runaway at main.selka:11:12
  in __test_trial_352905b6a34bbacc7c39e58cdc29fa1f at main.selka:1:1
memory budget exhausted; raise it with --max-memory=SIZE
0 passed, 0 cached, 1 failed, 0 skipped
```

## Test fan-out

A directory run (`selka test suite/`) runs each program's tests in its own
processes, from one worker budget shared by the whole run: `--jobs N`, else
`SELKA_JOBS`, else the CPUs the process may use, capped by how many per-test byte
ceilings (each plus the 256 MiB address-space headroom) the machine's `MemAvailable`
holds, and at least one. It never starts more workers than there is work, and a zero
or non-numeric `--jobs` is rejected. An explicit width is not capped by memory: on a
loaded machine, leave it out, or lower it or the per-test `--max-memory`.

```console
$ selka test suite/ --jobs 4 --max-memory=256M
```

That bounds one invocation. Several agents building and gating on one machine share
it through `scripts/build-slot.sh`, which admits a job only when a slot and enough
`MemAvailable` are free (`docs/tooling/many-agents.md`).
Ordinary jobs use all allowed CPUs by default. A `timing` request pauses new
admissions, drains active builds/gates, then holds an exclusive measurement window;
it does not increase the memory limit or the number of concurrent build slots.

## Sharded Zig test roots

The gate runs three slow Zig roots as independent processes of the same root
binary: `src/root_test.zig` has `-Dtest-shards=N` shards (default 12),
`test/integration.zig` has `N/2` (default 6), and `src/core/root_test.zig` has
`-Dcore-shards=M` (default 8). The test runner's (`tools/test_runner/`) `--test-shard=K/N` assigns named
tests by their position modulo N and unnamed `test { }` blocks to shard zero.
The shards partition each root, so their selected counts sum to its whole count.

`-Dtest-shards=1` restores one process per unit/CLI root. `test-units` and
`test-cli` always run whole roots. A focused `-Dtest-filter=…` also uses one
whole-root run under `test`; unmatched names still fail. The explicit
`test-units-sharded` and `test-cli-sharded` steps split focused selections for
`scripts/affected_tests.py`, which sums the shard counts. Empty individual shards
are allowed when the root as a whole matches the request.

`scripts/verification_shard_plan.py` can generate deterministic longest-processing-
time assignments from a complete `last-run.json`; the runner reads a plan
(`--test-shard-plan`) and filters names at run time. A plan is only a scheduling hint. Unknown
tests retain modulo assignment, and plan bytes must enter both the Zig run key
and verification receipt input inventory before build wiring enables it. Plans
must stay fixed during a run; predicted balance is not a measured shard wall.

### Declared memory is a reservation, not a measurement

The verification coordinator defaults to `--maxrss 8589934592` (8 GiB), matching
shared admission, and no longer injects `-j3`. Zig can use the admitted CPU
affinity. The `0.17.0-dev.1683+5ceec001b` runner (the pin until the move to 0.17.1; not remeasured on 0.17.1) did not reliably enforce
the aggregate reservation: `lib/compiler/Maker.zig` restores a completed RSS
claim but dispatches blocked steps without subtracting their claims. R1 observed
8 core, 4 unit and 3 CLI shards together (14.25 GiB declared) despite the 8 GiB
option. Its sampled descendant RSS sum peaked at 6.12 GiB; this is not proof of a
hard bound. No toolchain file was modified. Aggregate enforcement remains
unqualified pending a corrected runner or separately verified control.
Explicit `-jN` and `--maxrss BYTES` are available, but neither is claimed here to
repair that accounting defect. Direct `zig build` without `--maxrss` retains
Zig's machine-memory default.

The R1 reservation trial uses 1 GiB per unit shard, 768 MiB per CLI shard, and
1 GiB per core shard. These include engineering headroom over C0 observations;
they are not measured tree ceilings. Two-second subtree RSS samples can miss
short child peaks and double-count shared pages. Zig run-step MaxRSS summaries
use another scope and must not be substituted for simultaneous tree pressure.
The integrated forced gate records actual shard overlap and memory pressure;
raise reservations if those observations require it. Retain the default 12/6/8
counts until concurrency is no longer the first limiter.

### The complete gate's critical path (9 November 2026)

A complete gate after a back-end edit (17 actions reused, 31 executed) took 222.9, 222.5 and 267.0 s in three exclusive windows
on the 20-CPU machine, from one tree and three edit tags; `experiments/devloop3-20261109/` has the per-second samples, the
device I/O and `timeline.py`, which prints each step's start, end and peak memory. Where the time goes:

| Phase | Time | What runs |
| --- | --- | --- |
| prepare and lookup | 18-20 s | `verification-prepare` builds the edited compiler (9-11 s), and the coordinator hashes inputs and looks the keys up (7-8 s) |
| the gate's own startup | 8 s | discovery, `component-preparation` (its build step re-runs under `-Dtest-rerun=true`, 4-5 s) and the install steps every shard depends on |
| the steps | 180-200 s | four batches that started 8, 23, 73 and 116 s into the gate: golden and 8 drivers; 9 more drivers and 3 unit shards; 8 core and 9 unit shards; last the 6 CLI shards and 2 core shards, which end the gate (the slowest CLI shard runs 70-100 s alone) |

Why the steps start in waves: the pinned runner's `-jN` is a limit on tasks in flight, and `Io.Threaded.groupAsync` does not queue a task
past it: it runs the task in the calling thread. A thread that has just finished a step runs the next ready step itself and cannot start
that step's siblings until it ends. A gate step is a process that mostly waits for its children, so `-j19` (CPUs less one) is reached
with 17-19 steps while more than 50 are ready. The memory budget (`--maxrss`, 8 GiB) adds a second wave structure of its own: blocked
steps wait on a stack, and `Maker.zig` resumes all that fit at once whenever one step ends (see above). Raising `--maxrss` to 24 GiB
changed nothing about the waves (they came at 7, 21, 52 and 91 s); raising `-j` to four steps a CPU started all 52 steps at second 7.

What each change did, in elapsed seconds of a gate with the same 17 reused actions, edit tag new every time:

| Setting | Gates | Elapsed |
| --- | --- | --- |
| as shipped (`-j19`, 8 GiB) | 3 | 222.9, 222.5, 267.0 |
| `--maxrss 24 GiB` | 1 | 207.6 |
| `--maxrss 24 GiB`, `-j76` | 2 | 197.5, 281.6 |
| the same and `-Dtest-shards=24 -Dcore-shards=16` | 1 | 213.3 |

None beats the spread of the shipped setting (the same tree gave 222 and 267 s), so none was adopted, and none reaches 150 s. With every
step started at once the machine is CPU-bound: `vmstat` shows 98-100% of 20 CPUs busy and a run queue of 30-110 for 100-150 s, and the
gate costs 2,000-2,400 CPU seconds however it is ordered (user 1,700-2,000, system 360-410). The long CLI and core shards then share the
CPUs with everything else and take 130-240 s instead of 70-100 s, so they still end the gate. The floor of this gate is its CPU work, about
100 s of a saturated machine, plus the 28 s above, and 150 s needs either a third less work or the long shards to run first at full speed.
Two things were found on the way:

- **Load-sensitive tests.** A gate that starts everything at once exposed three tests that assume a quiet machine: the application-cache
  patience test (it timed a real 50 ms spin and asserted a slowdown under 3), `build_env_death_test` (it read a pid file between the
  step command creating it and writing it) and the 5-second measurement windows of `verification_measurement_test.py`. All three now
  check what they mean on mocked clocks or wait for what they need.
- **`core` shard 4 declares 512 MiB and peaks at 1.01 GB** (a `selka` it compiles; Zig prints `error: memory usage peaked ... exceeding
  the declared upper bound` and the step still passes, so the gate stays green). Declaring 1 GiB would, under the 8 GiB budget, hold core
  shards behind the others, and the budget does not bind anyway, so the declaration is left as measured and recorded here.

### Python drivers that scale with the repository

A Python driver that reads the whole tree pays for every source it adds. The
gate profile of 18 October 2026 found four such groups (the removed-form audit,
the ownership corpora, the cleanup rewriter tests and the ownership-audit helper
tests) at 9,815 of 13,640 CPU seconds, with one single-threaded audit
reserving the whole 8 GiB `--maxrss` budget for about 3,360 s. They were
retired; `program_check` replaces their one unique check, a `selka check`
sweep of the standalone programs, at about six seconds and no memory
reservation beyond a script's. See
"What the complete verification contains" in `docs/tooling/many-agents.md`.

## Deadlines

Every level of a gate has a wall-clock deadline, so a hang becomes one bounded
failure rather than a held slot. Hitting a deadline is always a failure, never a
skip and never an automatic rerun.

| level | variable or flag | default | `0` |
|---|---|---|---|
| one native test interval, no CPU progress | `SELKA_TEST_IDLE_SECONDS` | 300 s | off |
| one native test interval, wall backstop | `SELKA_TEST_DEADLINE_SECONDS` | 900 s | off |
| one doc example invocation (`selka doctest`) | `timeout_seconds` in `src/doctest_command.zig` | 600 s wall | not configurable |
| one build-graph step | `SELKA_STEP_DEADLINE_SECONDS` | 30 min | off |
| coordinator admitted gate | `--gate-timeout-seconds` | 90 min | off |
| coordinator preparation command | `--build-timeout-seconds` | 20 min | off |

- **Per test**, `scripts/verification_native_telemetry.py` watches the protocol
  interval it already measures. A test is killed when its process tree (the
  runner's session) shows no CPU progress for `SELKA_TEST_IDLE_SECONDS`, which
  is how a blocked or deadlocked test looks, or when the interval passes the wall
  backstop `SELKA_TEST_DEADLINE_SECONDS` (900 s, below the 30-minute step
  deadline), which only a busy polling loop reaches. CPU progress is sampled
  from the runner's process tree, found through each task's `children` list
  (fields 14-17 of each `/proc/PID/stat`, every 5 s or every third of the idle
  window if shorter), so a child that calls `setsid` still counts. A sample costs
  about 0.14 ms for a three-process tree, against about 8 ms for a full `/proc`
  scan. A test slowed by other gates keeps its interval; wall time alone was the
  old limit, and it inflated 2-3.5x (median) under load in the 2026-10-28 runs.
  The kill collects the tree, then kills the runner's session (`killpg`) and every
  collected process, so the test's `sh`, `selka` and any child that left the
  session all die, and a sibling outside the tree survives; it prints
  `test deadline: <root>::<test> made no CPU progress for <N> s (limit <L> s); killed`
  or `test deadline: <root>::<test> ran <N> s (limit <L> s); killed`, records the
  test as `timed_out` in its telemetry document and exits 124.
- **Per step**, `build-env project` starts the command as a new process-group
  leader, kills that group at the limit, prints
  `step deadline: <command> ran <N> s (limit <L> s); killed` and exits 124; it
  forwards TERM, INT and HUP to that group. Without a deadline it still replaces
  itself, keeping the step's pid, exit status and resource accounting.
- **Per gate**, the coordinator's two deadlines cover the admitted preparation
  and the selected gate; queue time is outside both, so a busy machine does not
  turn waiting into a failure.
- Both environment variables are `placement` in
  `src/environment_identity.zon`: a receipt never invalidates because a deadline
  changed.

## Cached test verdicts

A `zig build` Run step is re-executed only when its cache key changes, and the
gate's test steps now use that: the root shards,
the Python drivers and `selka doctest` are keyed on the test binary, the
emitted compiler they run, their command, the environment variables
they depend on, and the repository files listed for them in
`build_test_inputs.zig`. Those lists are
expanded on every build by `tests/input_manifest.py`, which writes one content
manifest per list (a SHA-256 per file); each step declares its manifest, so an
edited, added, removed or renamed file re-runs exactly the steps whose lists
cover it. The walk happens at make time because this Zig version records
`dependOnDirectory` but never re-runs the configure phase for it: a list
expanded in `build.zig` would not see a new fixture. An unchanged `zig build
test` reruns only the manifest walk (0.15 s), `doc-coverage`, the guest suites (whose own
receipts make that near-free) and the SPEC merge replay, which reads git
history. `test-inputs-coverage` fails the gate when a test source names an
existing repository path that its step does not declare, and
`-Dtest-rerun=true` re-runs every cached test step when a verdict is in doubt.

Every test step runs in the environment of the `zig build` that runs it. The
build names the native tool (`SELKA_ZIG`)
and Zig's global cache through a `sh … env NAME=value` prefix on the command,
never through `Step.Run.setEnvironmentVariable`: that call copies the whole
configure-time environment into the step, the build runner stores the copy in
the cached configuration, and every later build with the same `-D` options ran
its tests with the `PATH`, `HOME`, `TMPDIR` and `SELKA_*` of whichever build
first configured that cache. `build.zig` now refuses to configure when any step
carries its own environment. Because a live environment is not part of a step's
cache key, one small step records the variables a verdict depends on (`PATH`,
`HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `ZIG_GLOBAL_CACHE_DIR`,
`ZIG_LOCAL_CACHE_DIR` and every `SELKA_*`) on each build, and every cached test
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
