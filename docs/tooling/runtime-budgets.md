# Runtime budgets

A guest program can be bounded in steps, call depth, wall-clock time and memory, so a runaway program stops with a trap instead of taking the machine. `selka run`, `run-project`, `build --run` and `selka test` take the flags below; a program built with `selka build -o` reads its memory ceiling from its environment.

| Flag | Bounds | Default for `run` | Default per `test` process | Trap |
|---|---|---|---|---|
| `--max-steps N` | blocks executed | none | 1,000,000 | `R_STEP_LIMIT` |
| `--max-frames N` | nested calls | none | 1,024 | `R_FRAME_LIMIT` |
| `--timeout SECONDS` (`--timeout-ms N` for `test`) | elapsed time | none | 60,000 ms | `R_TIMEOUT` |
| `--max-memory SIZE` | memory | 4 GiB | 512 MiB | `R_MEMORY_BUDGET` |

## Nested byte budgets

An *allocation budget* is an embedding API, not a flag: a Zig host wraps an allocator in `language.allocation_budget.Memory` and counts the live bytes handed out through it. A program built by `selka build` does not route its allocations through it; bound a guest with a ceiling (below).

- Budgets nest: a child charges its parent as well, so raising a child above its parent grants nothing, and its reported limit is clamped to the parent's.
- Zero permits no nonempty allocation. A failed acquisition charges nothing, and a release restores live accounting while keeping the peak. A moving reallocation may need the old and new capacity at once.
- Exhaustion is a host `OutOfMemory` with normal cleanup, not a numeric error a guest can recover from.
- Keep both accounting objects at stable addresses until every allocation made through the child is freed. The allocator is single-threaded and is not a capability a guest can be handed.

```sh
# src/allocation_budget_test.zig runs as part of the default unit-test root
zig build test
```

## Instruction and frame budgets

`selka run`, `run-project` and `build --run` have no step or frame ceiling by default: the byte ceiling already contains a runaway allocation, and a development loop should not stop an honest program. Pass `--max-steps N`, `--max-frames N` or `--timeout SECONDS` to impose one. Each takes `--flag N` or `--flag=N` with a positive integer; a zero, negative, empty or non-numeric budget is refused before anything is built.

```console
$ selka run loop.selka --max-steps 1000
error[R_STEP_LIMIT]: native execution failed
instruction budget exhausted; raise it with --max-steps=N
$ selka build loop.selka --run --max-steps=500000000
$ selka run loop.selka --timeout 30     # wall-clock guard; no default
```

- A program built with `selka build -o` carries no budget code and pays nothing for one; to bound it, run it through `selka run` or `build --run`.
- A `selka test` child starts at 1,000,000 steps and 1,024 frames. `--max-steps` and `--max-frames` on `selka test` bound each test process and may be lowered or raised. A test that stops on a default budget says so and names the fix: "this test passed its budget of 1,000,000 steps (every test has one); raise it with `selka test --max-steps=N` or `limits.test.max_steps` in `selka.json`".
- Each trap ends with one advice line naming the flag, in text and in the `message` of `--diagnostics=json`: "instruction budget exhausted; raise it with --max-steps=N", "call-depth budget exhausted; raise it with --max-frames=N (each frame reserves 32 KiB of stack, so --max-memory must cover N x 32 KiB)", "memory budget exhausted; raise it with --max-memory=SIZE".
- `--timeout` arms a timer inside the program; when it fires the process reports `R_TIMEOUT` and exits 1.
- Steps and frames bound compiler-generated work, not elapsed time: a linked C function can spend arbitrary time inside one call.

### What bounds a built binary

A program built with `selka build -o` has no frame budget, so `--max-frames` is not something it can take (setting it in `SELKA_OPTIONS` ends with `R_NO_FRAME_ACCOUNTING`). Its recursion depth is bounded by the native stack: the main thread's `ulimit -s`, 8 MiB unless the shell says otherwise. That holds roughly 3,000 to 6,000 frames of a large function and tens of thousands of a small one.

When the stack fills, the binary reports `R_FRAME_LIMIT` with a located trace of the innermost 16 frames and exits 1. The remedies are `ulimit -s KBYTES` before starting the binary (`ulimit -s unlimited` where the hard limit allows), or running under `selka run --max-frames=N`, which maps a stack of its own.

### What a frame budget costs

`--max-frames N` is only honest if N frames fit on the native stack, so the program runs on a stack of 32 KiB for every frame the budget allows, plus 8 MiB, inside its address space (its `--max-memory` plus 256 MiB). Nothing is touched until the recursion reaches it, but the reservation counts against the limit: 150,000 frames reserve 4.6 GiB and do not fit the 4 GiB default. A budget that cannot fit is refused before anything is built, with status 2 and what it needs:

```console
$ selka run deep.selka --max-frames 150000
selka run: a call-depth budget of 150000 frames (--max-frames) reserves 4.6 GiB of native stack (32 KiB per frame), but a guest may map only 4.3 GiB: raise --max-memory to at least 5G, or lower --max-frames to at most 137984
$ selka run deep.selka --max-frames 150000 --max-memory 5G
```

`selka test` refuses the same way for a per-test ceiling (512 MiB by default, so `--max-frames 30000` needs `--max-memory 1G`). The caller's own `ulimit -v` also bounds what a program may map: a tighter one is refused and must be raised by the caller.

### Project defaults in `selka.json`

A project that always needs the same budgets (a parser test that recurses 20,000 frames deep, say) can say so once. `selka.json` takes an optional `limits` object with a `run` and a `test` entry, each any of `max_steps`, `max_frames` (positive integers up to 4,294,967,295) and `max_memory` (a byte count or a `K`/`M`/`G` size, `0` for no ceiling):

```json
{"version": 1, "limits": {"test": {"max_steps": 4000000000, "max_frames": 30000, "max_memory": "1G"}}}
```

- `selka run`, `run-project` and `test` read the configuration nearest the entry file and use these as defaults for the matching flag. A directory run leaves each program to its nearest configuration.
- A flag always wins, `SELKA_MEMORY_LIMIT` outranks the file's `max_memory`, and built-in defaults fill what the file leaves out.
- A configured budget goes through the same checks as the flag, so a `max_frames` the memory cannot back is refused with what it needs.
- An unknown key, a repeated key, or a budget that is zero, not an integer or out of range is a configuration failure.

## Guest memory ceilings

A ceiling bounds a whole process that runs guest code, so one runaway program cannot take the machine into swap. `selka run`, `run-project`, `build --run` and every `selka test` child run under one. A program built with `selka build -o` and started by hand runs under one only when its environment names one: `--max-memory=SIZE` in `SELKA_OPTIONS`, else `SELKA_MEMORY_LIMIT`, else none. Under `selka run` and `build --run` the program reads neither: the run's own ceiling is built in.

The runtime enforces it twice. Its byte count traps `R_MEMORY_BUDGET` (exit 1) when an allocation passes the ceiling. The program also lowers its own `RLIMIT_AS` (never raises it) to the ceiling plus 256 MiB, so an allocation the OS refuses reports `R_MEMORY_BUDGET` too. A program it starts with `process.run` or `process.start` gets back the address-space limit the guest started with ([io.md](../io.md#processes)).

| Order | Source |
|---|---|
| 1 | `--max-memory SIZE` on `run`, `build --run` and `test` |
| 2 | `SELKA_MEMORY_LIMIT` |
| 3 | `limits` in `selka.json` |
| 4 | the default: 4 GiB for `run` and `build --run`, 512 MiB for one `selka test` child |

Sizes are bytes with an optional `K`, `M` or `G` suffix, and `0` removes the ceiling. Malformed text refuses the run (a built binary ends with status 2 and one line before `main` runs). The resolved test ceiling and frame budget are part of a test receipt's key, so changing them re-executes the test.

**The compiler bounds itself** at 8 GiB unless `SELKA_HOST_MEMORY_LIMIT` says otherwise (`16G` raises it, `0` removes it), so a compiler defect fails loudly instead of swapping. The ceiling covers one process, not a tree: each child of a directory run has its own. A run that outgrows it fails instead of being killed by the kernel:

| What happened | What you see |
|---|---|
| The compiler reached its ceiling | status 2 and `selka: out of memory: the compiler reached its own memory ceiling of 8.0 GiB (SELKA_HOST_MEMORY_LIMIT, ...)` |
| A build tool ran out of memory | a leading line `selka: a build tool ran out of memory under the compiler's own address-space ceiling (SELKA_HOST_MEMORY_LIMIT)`, then the tool's words |
| A build tool crashed with no such words | `selka: a build tool crashed while the compiler's own address-space ceiling (SELKA_HOST_MEMORY_LIMIT) was in force; if it ran out of memory, raise the ceiling ...`, then the tool's words |

An expression nested deeper than the compiler's own 256 MiB stack ends with the crash report and status 134.

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

Built with `selka build -o` and started by hand, the same program takes its ceiling from its environment:

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

## Test fan-out

A directory run (`selka test suite/`) runs each program's tests in their own processes, from one worker budget shared by the whole run: `--jobs N`, else `SELKA_JOBS`, else the CPUs the process may use, capped by how many per-test byte ceilings (each plus 256 MiB of headroom) `MemAvailable` holds, and at least one. It never starts more workers than there is work, and a zero or non-numeric `--jobs` is rejected. An explicit width is not capped by memory: on a loaded machine, leave it out, or lower it or the per-test `--max-memory`.

```console
$ selka test suite/ --jobs 4 --max-memory=256M
```

That bounds one invocation. Several agents on one machine share it through `scripts/build-slot.sh` (`docs/tooling/many-agents.md`).

## Sharded Zig test roots

The compiler's gate runs three slow Zig roots as independent processes of the same root binary:

| Root | Shards | Option |
|---|---|---|
| `src/root_test.zig` | 12 | `-Dtest-shards=N` |
| `test/integration.zig` | `N/2` (6) | `-Dtest-shards=N` |
| `src/core/root_test.zig` | 8 | `-Dcore-shards=M` |

`-Dtest-shards=1` restores one process per unit and CLI root. `test-units` and `test-cli` always run whole roots, and a focused `-Dtest-filter=...` also runs one whole root under `test`; unmatched names still fail. The `test-units-sharded` and `test-cli-sharded` steps split focused selections.

## Deadlines

Every level of a gate has a wall-clock deadline, so a hang becomes one bounded failure rather than a held slot. Hitting a deadline is always a failure, never a skip and never an automatic rerun.

| level | variable or flag | default | `0` |
|---|---|---|---|
| one native test interval, no CPU progress | `SELKA_TEST_IDLE_SECONDS` | 300 s | off |
| one native test interval, wall backstop | `SELKA_TEST_DEADLINE_SECONDS` | 900 s | off |
| one doc example invocation (`selka doctest`) | `timeout_seconds` in `src/doctest_command.zig` | 600 s wall | not configurable |
| one build-graph step | `SELKA_STEP_DEADLINE_SECONDS` | 30 min | off |
| coordinator admitted gate | `--gate-timeout-seconds` | 90 min | off |
| coordinator preparation command | `--build-timeout-seconds` | 20 min | off |

- **Per test**, a test is killed when its process tree shows no CPU progress for `SELKA_TEST_IDLE_SECONDS` (a blocked or deadlocked test) or when it passes the wall backstop (only a busy loop reaches it). The kill takes the whole tree, prints `test deadline: <root>::<test> made no CPU progress for <N> s (limit <L> s); killed` or `test deadline: <root>::<test> ran <N> s (limit <L> s); killed`, records the test as `timed_out` and exits 124.
- **Per step**, `build-env project` kills the step's process group at the limit, prints `step deadline: <command> ran <N> s (limit <L> s); killed` and exits 124.
- **Per gate**, the two coordinator deadlines cover the admitted preparation and the selected gate; queue time is outside both.
- Both environment variables are `placement` in `src/environment_identity.zon`: a receipt never invalidates because a deadline changed.

## Cached test verdicts

A `zig build` test step is re-executed only when its cache key changes: the test binary, the compiler it runs, its command, the environment variables it depends on, and the repository files listed for it in `build_test_inputs.zig`. An edited, added, removed or renamed file re-runs exactly the steps whose lists cover it. `test-inputs-coverage` fails the gate when a test source names an existing repository path its step does not declare, and `-Dtest-rerun=true` re-runs every cached test step when a verdict is in doubt.

Every test step runs in the environment of the `zig build` that runs it; a changed `PATH`, `HOME`, `TMPDIR`, `XDG_CACHE_HOME`, `ZIG_GLOBAL_CACHE_DIR`, `ZIG_LOCAL_CACHE_DIR` or `SELKA_*` variable re-runs the cached verdicts. A driver's standard output is sent to standard error, so the report of a failing driver is not hidden.

---

How the compiler does all this: [the internals notes for this page](https://github.com/eugenepentland/selka/blob/main/docs/internals/runtime-budgets.md).
