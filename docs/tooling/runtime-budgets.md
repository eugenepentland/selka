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
$ ./loop --max-steps=500000000        # built binary: the same flags are ordinary arguments
$ mylang run loop.my --max-steps=500000000
$ mylang build loop.my --run -- --max-steps=500000000
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

## Sharded Zig test roots

The gate's two slow Zig test roots run as several processes rather than one:
`zig build test` splits `src/root_test.zig` into `-Dtest-shards=N` shards
(default 12) and `test/integration.zig` into `N/2`, each an independent run of
the same test binary under `--guardian-shard=K/N`, declaring its own `max_rss`
(1.5 GiB per unit shard, 1 GiB per CLI shard) so `zig build --maxrss` still
bounds the whole gate. Guardian's runner gives each shard the named tests whose
position among them is `K` modulo `N`, and the unnamed `test { }` blocks to
shard 0 alone, so the shards partition the root and their `N test(s) selected`
counts sum to the unsharded count.

`-Dtest-shards=1` restores one process per root. `test-units` and `test-cli`
are never sharded, and `-Dtest-filter=…` puts `test` back on their single
whole-root runs too: the compiler has already dropped every non-matching test,
so splitting the remainder would mostly produce empty shards. An empty shard is
not a failure — only a root that selected nothing as a whole still fails.
