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

Every process that runs guest code also counts **instructions** and **call depth**.
`mylang run`, `mylang build --run` and a binary you built and started yourself
have **no step or frame ceiling by default**: the byte ceiling below already
contains a runaway allocation, and a development loop should not stop an honest
program. Pass `--max-steps=N` or `--max-frames=N` to impose one, and
`--timeout=SECONDS` to cap elapsed time on whichever command runs the program:

```console
$ MYLANG_OPTIONS=--max-steps=500000000 ./loop   # built binary: options in the environment
$ mylang run loop.my --max-steps=500000000
$ mylang build loop.my --run --max-steps=500000000
$ mylang run loop.my --timeout=30     # wall-clock guard; no default
loop.my:3:13: error[R_TIMEOUT]: wall-clock budget exhausted; raise it with --timeout=SECONDS
```

A `mylang test` child is different: each test process starts at **1,000,000**
instructions and **1,024** frames, because a test is the one place a tight guard
is useful. `--max-steps` and `--max-frames` on `mylang test` bound each test
process and may be lowered or raised.

Once a ceiling is in force, `R_STEP_LIMIT` answers "instruction budget
exhausted; raise it with --max-steps=N" and `R_FRAME_LIMIT` answers "call-depth
budget exhausted; raise it with --max-frames=N". The hints appear in text and in
the `message` field of `--diagnostics=json`. A zero, negative, empty or
non-numeric budget is refused before the run rather than treated as unlimited.
`--timeout` arms a monotonic timer inside the guest; when it fires the process
writes `R_TIMEOUT` to standard error and exits 1.

These counters bound *compiler-generated work*, not elapsed time: one step is a
dispatch, so a program that calls into a linked C function can spend arbitrary time
inside that call. The separate byte ceiling below bounds memory, not time.

## Host application guests

A host application — `schematic-svg`, `mylang-io`, `board-trial` — compiles its
guest and runs it in a private child process, so it chooses that child's
ceilings itself rather than taking them from a command line. `schematic-svg`
bounds one render with a **call-depth ceiling and the wall clock** and counts no
instructions, because instruction accounting triples an optimized render while
these two cost nothing measurable. A runaway guest still stops: recursion at the
depth ceiling, a loop that never leaves at the timeout, an allocation at the
byte ceiling.

`--bounded` restores the instruction ceiling for an invocation that wants an
exact, deterministic bound on generated work, and `--backend qbe` builds the
guest with the debug assembler instead of the release code generator:

```bash
# the shipped policy: release code generator, depth and wall-clock ceilings
schematic-svg --project src/schematic/guest circuit.sexp pinout.sexp interface.sexp > out.svg
# count instructions instead, the way a bounded `mylang run` does
schematic-svg --bounded --project src/schematic/guest circuit.sexp pinout.sexp interface.sexp > out.svg
# build the guest with QBE (faster cold build, slower render)
schematic-svg --backend qbe --project src/schematic/guest circuit.sexp pinout.sexp interface.sexp > out.svg
```

The ceilings a host passes always match the accounting it built the guest with,
so a guest is never handed a `--max-steps=` it would refuse with
`R_NO_STEP_ACCOUNTING`.

## Guest memory ceilings

The budgets above bound what one embedded allocator hands out. A *ceiling*
is coarser and applies to every process that runs guest code: the native test
runner's children, `mylang build --run`, and a program you built and started
yourself. It exists so one runaway guest cannot take the machine into swap.

Two mechanisms enforce it. The soft one is the managed heap's byte budget: an
allocation that would exceed it *after a collection* traps with
`R_MEMORY_BUDGET`, "memory budget exhausted", and exit status 1, exactly like
`R_STEP_LIMIT` bounds instructions. The hard one is the kernel's: before its
first allocation the runtime lowers its own `RLIMIT_AS` to the budget plus 256
MiB of headroom, so a defect in the runtime cannot outgrow the budget the heap
is enforcing. `RLIMIT_AS` was chosen over a pre-`exec` hook because Zig's
`std.process.Child` has none, and because a process that bounds itself is also
bounded when you start it by hand. A tighter ceiling already in force is never
loosened, and no ceiling is installed in a sanitizer build, whose shadow mapping
reserves far more address space than any budget would permit.

The budget travels in `MYLANG_MEMORY_LIMIT`, written as bytes with an optional
`K`, `M` or `G` suffix, so no spawner needs a new argument ABI. Precedence is
`--max-memory=BYTES` on `run`, `build --run` and `test` first, then the
variable, then the built-in default: **512 MiB** for one `mylang test` child and
**4 GiB** for `run` and `build --run`. Malformed text refuses the run rather
than leaving it unbounded; `0` removes the ceiling. A program you built with
`-o` and start yourself is unbounded unless the variable is exported. The
resolved test ceiling is part of a receipt key, so raising or lowering it
re-executes rather than reusing.

The compiler bounds itself too, at 8 GiB unless `MYLANG_HOST_MEMORY_LIMIT` says
otherwise, so a compiler defect fails loudly instead of swapping; the `zig cc`
and QBE children a native build spawns complete under that inherited ceiling.

```console
$ cat grow.my
def grow(values: list[int], rounds: int) -> int:
    for r in range(rounds):
        values.append(r)
    return len(values)


def main() -> int:
    values: list[int] = []
    return grow(values, 100000000)
$ mylang build grow.my --run --max-memory=64M
grow.my:3:9: error[R_MEMORY_BUDGET]: memory budget exhausted
  in grow at grow.my:3:9
  in main at grow.my:9:12
$ echo $?
1
```

A `mylang test` child reports the same trap as an ordinary failure, with the
guest source trace, rather than dying:

```console
$ mylang test suite/main.my --max-memory=32M --max-steps=4000000
failed main::test_runaway: R_MEMORY_BUDGET
  in main::grow at main.my:7:9
  in main::test_runaway at main.my:13:12

0 passed, 0 cached, 1 failed, 0 skipped
```

## Fan-out bounded by memory

A directory run (`mylang test suite/`) starts one child per program. Its worker
count is the machine's core count, further limited by how many per-child
ceilings `MemAvailable` in `/proc/meminfo` can hold — each child is counted as
its ceiling plus the same 256 MiB of headroom. A cold fan-out on a loaded
machine therefore waits rather than oversubscribing, and it is never fewer than
one worker or more workers than there are programs. `--jobs N` overrides it,
`MYLANG_JOBS` overrides the derived default, and zero or non-numeric widths are
rejected.

```console
$ mylang test suite/ --jobs 4 --max-memory=256M
8 passed, 0 cached, 0 failed, 0 skipped across 4 programs
```

That bounds one invocation. Several agents building and gating on one machine
share it through `scripts/build-slot.sh`, which admits a job only when a slot and
enough `MemAvailable` are free
([many agents on one machine](many-agents.md)).

## Sharded Zig test roots

The gate's two slow Zig test roots run as several processes rather than one:
`zig build test` splits `src/root_test.zig` into `-Dtest-shards=N` shards
(default 12) and `test/integration.zig` into `N/2`, each an independent run of
the same test binary under `--guardian-shard=K/N`, declaring its own `max_rss`
(1 GiB per unit shard, 768 MiB per CLI shard) so `zig build --maxrss` still
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
above the largest single process, which the runner checks and fails on. On
2026-09-23 a clean-cache `zig build test` never held more than 5.8 GiB at once,
while its declarations summed to far more than 30 GiB: the last unit shards
waited most of a minute for reservations that were never used. The ceilings in
`build.zig` now follow measured peaks — 1 GiB per unit shard (largest process
570 MiB), 768 MiB per CLI shard (141 MiB), 1.5 GiB for the host-application
roots and `tests/guest`, 256 MiB for checks that run no compiler — and a rerun
of every test took 98 s instead of 136 s on the same loaded machine (81 s with
no memory limit at all). Measure a step's tree before raising its ceiling; a
larger number is not a safer one.

## Cached test verdicts

A `zig build` Run step is re-executed only when its cache key changes, and the
gate's test steps now use that: the root shards, the host-application roots,
the Python drivers and `mylang doctest` are keyed on the test binary, the
emitted compiler and `qbe` they run, their command and environment, and the
repository files listed for them in `build_test_inputs.zig`. Those lists are
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

A driver's standard output is sent to standard error, because the build runner
discards a checked step's standard output and would otherwise hide the report
of a failing driver.
