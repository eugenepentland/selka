# Concurrency, part 2: P1 fixes, zero-tax mode and the language surface (2026-10-09)

Status: **ready to resume (revision 1, 2026-10-09).** The run stopped at §9 hard stop 2: merging `main` `8a2fccd2f` would bring in an upstream one-line span change to `src/core/own.zig`. The rule meant edits **by Codex**, not upstream changes; revision 1 says so (§9). P1F is accepted; T is implemented but not yet gated; P2 is not started. The user accepted D1–D4 as recommended on 2026-10-09 (§3).
- **Size (estimates):** P1F about 4–12 h; T about 10–16 h; P2 about 30–45 h.
- **Runtime design:** plan 1's §3–§4 (including revisions R1–R11) stays the runtime design. This plan changes the surface (§6) and how programs without tasks are compiled (§5).

## Launch instruction (for Codex)

> **Resume (revision 1).** On `codex/concurrency-2`:
> 1. Merge `claude/concurrency-plan-2` (this revision) with a real merge commit.
> 2. Merge `main` (`8a2fccd2f` or later) with a real merge commit. The upstream `own.zig` change is allowed (§9, hard stop 2 as revised).
> 3. Rerun P1F's gates on the merged tree, then finish T's gates (G-T1 to G-T4), then do P2.
>
> Everything below otherwise stands.


> **One run: P1F, then T, then P2.**
> - Create `codex/concurrency-2` from `claude/concurrency-plan-2`.
> - Read this plan whole, then plan 1's §3–§4 and its `experiments/concurrency-p1-2026-10-08/P2-0.md`.
> - Work through §4, §5 and §6 in order.
> - **Do not stop to ask** (§9): decide, log the decision in `experiments/concurrency-2-<date>/DECISIONS.md`, and continue.
> - Stop only at a §9 hard stop, or when P2's report is written.
> - Commit at every step, with an updated progress section in `REPORT.md`.
> - If `main` moves, merge it with a real merge commit and rerun the current step's gates.
> - Never merge into `main` and never push.

## 1. Where it starts

Facts on `main` `d21b2dfa9`.

**P1 is merged** (`c26c95de7`, through `ab85c16c2`). It added:
- the plain/shared/immortal count encoding, with `unordered` count loads and one `preserve_mostcc` slow call per count site;
- per-thread runtime state (local-exec TLS free lists, a persistent registry, staged output, the trap winner);
- the common child iterator and the share walk;
- the lazy work-stealing pool (`src/core/runtime/core_tasks.c`) and its C-ABI bridge `myl_core_task_call`;
- the internal switches `MYLANG_CORE_SANITIZE=thread` and `MYLANG_CORE_LAYOUT=K`.

**Its correctness gates were all green:** 88/88, conformance 1518/0/0 in both modes, fuzz 9×200, the Lox, EDA and parity corpora, and 300 TSan runs at 8 threads (`experiments/concurrency-p1-2026-10-08/REPORT.md`).

**P1 missed the single-threaded tax target, and that miss is on `main` now.**
- **The selected runtime C,** measured historically against `94dc1c3a2`:

  | corpus | geomean | cells above 1.03× |
  |---|---:|---:|
  | rows | 1.0027 | 12 |
  | EDA | **1.0190** | 0 |
  | parity | 1.0036 | 1 |
  | Lox tree | **1.0145** | 2 |
  | Lox VM | 1.0025 | 0 |

  The targets were a geomean ≤ 1.010 and every cell ≤ 1.03.
- **The merged source was not timed again,** by the user's waiver.
- **Code size grew:** EDA `.text` by 12.7% (1,067,670 → 1,203,286 bytes), Lox by 8.2%, and `json::read_value` by 14%.
- **Tuning did not converge.** Candidates A–G each moved some corpus by ±2–3% through runtime inlining and registration choices, and none passed every corpus (HISTORY.md, "P1-6").

**The readable syntax redesign is merged** (`a9c1109e8`, through `d21b2dfa9`; `docs/audits/frontend-syntax-redesign-2026-10-09.md`). It brings:
- `func` declarations;
- `const`/`mut` bindings with block scope and no shadowing;
- `named` parameters;
- `T[]` and `T?`;
- `-> T fails E` with `fail` and prefix `try`;
- source-first comprehensions `[for x in xs if c yield e]`;
- `with try fs.open(...) as f:`.

The front-end plan of 2026-10-06 is affected: its language-deletion work is superseded, and its Part C (typed tree, generics, caches) is not running (`codex/frontend-integration` last moved on 2026-10-08). Plan 1 gated P2 on that plan's F4 exit; **D4 replaces that gate.**

**P2-0** (`experiments/concurrency-p1-2026-10-08/P2-0.md`) found no Core IR or ownership-pass gap, with hand-built proofs for `parallel.map`-shaped ranges. Its list of front-end files predates the redesign. The files still exist, but their contents changed.

**`perf` is available** (`/usr/bin/perf`, `perf_event_paranoid` = 1), so user-mode instruction counts can be measured without quiet hardware.

## 2. Review of P1 (Claude, 2026-10-09)

Claude read the report, the decision log, the self-review and P2-0. Two adversarial code reviews then ran against `main` `ab85c16c2`, each with its own probes (C harnesses over the concatenated runtime, ThreadSanitizer builds, LLVM IR):
- **Review A:** the scheduler, the fatal paths and the per-thread state.
- **Review B:** the counts, the share walk, the caches and the emitter.

**Verdict.** P1's design and most of its implementation hold up. Neither reviewer found a defect in the count encoding, the share walk's invariant, the Chase–Lev deque, completion ordering, lost-wakeup handling, handle lifetimes or the `unordered` loads; both checked them and reported them sound. The run itself kept complete evidence, logged every decision and stayed out of the forbidden files.

**What is wrong:**
- **One high-severity defect (A1).**
- **Five medium or low defects:** A2, A3, A5, B1 and B2.
- **Three smaller items:** A4, A6 and B3.
- **The single-threaded tax:** it was missed and then waived, and EDA's code grew 12.7%. That is §3's D1.

**Exposure on `main` today:** none of the findings can affect an existing program on `main`. They all need a started pool, a shared value or a task handle, and only hand-built IR can create those until P2. The tax and the code growth do affect every program now.

| id | severity | finding | confirmed by |
|---|---|---|---|
| **A1** | high | **Cross-thread frees grow memory without bound.** A freed small block joins the *freeing* thread's free list (plan 1's §4.3 said this was safe; it is safe, but not bounded). A worker that allocates results never gets blocks back and carves new chunks, while the consumer's lists grow. | Probe: 40,000 rounds of 64 tasks, live set 1 block. At 1 thread, 133 blocks carved; at 2 threads, 2,032,903 (about 127 MiB, `R_MEMORY_BUDGET` under a 64 MiB ceiling). A `parallel.map` in a loop hits this. |
| **A2** | medium | **Starting the pool can exhaust `RLIMIT_AS`** and is misreported as `R_MEMORY_BUDGET`. It is charged for N − 1 worker stacks, N signal stacks and glibc's per-thread malloc arenas (64 MiB each). `MYLANG_THREADS` has no upper bound. | Probe: fails at 20 threads under budgets from 64 to 512 MiB; starts with `MALLOC_ARENA_MAX=1`. |
| **A3** | medium-low | **The `--timeout` handler can park forever.** It calls `core_fatal_begin`; if another thread won (or the main thread is between its CAS and the owner flag), it parks, and the process hangs. | A simulated probe hung until killed. |
| **A4** | low | **Exit status 2 becomes 1 once the pool has started** (`os_exit` calls `_exit(status ? 1 : 0)`). | Probe. |
| **A5** | low | **The raw-report fallback fires under ordinary contention.** 1,024 back-to-back try-locks last microseconds, so a worker writing a large unit forces a report with no frames and drops stdout. | Code reading. |
| **A6** | low | **Helping waits can need more stack than the sequential program.** A waiter runs *stolen* tasks on its own stack, so depths can stack, and a program that passes at 1 thread can overflow at N. | Code reading. |
| **B1** | medium | **Shared non-ASCII text never caches, so indexing it is quadratic.** `count_can_cache` is false for shared blocks and marks are permanent, including in the parent after the join. | Probe: 20,000 sequential lookups walk 39,998 octets plain and 399,980,000 shared. |
| **B2** | medium (latent) | **A group block is mutated in place even when shared.** If a group handle reaches a task's environment, submit and close race on `group->tasks` and free a shared list. P2's checker forbids that, but the runtime has no backstop. | TSan probe: races in `myl_core_task_submit` and `myl_core_list_grow`. |
| **B3** | low | **The C count helpers' contention and saturation fixtures never run under TSan.** Only the emitted-task matrices and the scheduler fixture do. | Test reading. |

**Also noted (A):** every push and every completion makes a `FUTEX_WAKE(INT32_MAX)` system call, even when no thread is parked. That costs scaling, not correctness.

The probes are in `experiments/concurrency-2-review-2026-10-09/` (see its README for how to build them). P1F turns each one into a fixture before fixing it.

## 3. Decisions (accepted by the user on 2026-10-09, as recommended)

- **D1. Zero-tax mode (package T). Recommended.** A program whose reachable code never calls the task ABI is compiled exactly as it was before P1: the old emitted count paths, non-TLS free lists, no output staging, a single-threaded runtime variant. Only programs that use `parallel` get the thread-capable code and pay P1's tax.
  - **Why:** the tuning in A–G showed the tax moves around rather than going away. A program that cannot start a task gains nothing from paying it. This is the "a program that never spawns keeps today's code" property promised when the design was chosen.
  - **Cost:** two runtime variants and two emission modes, selected per executable, salted into the caches like the sanitizer switch. Adding the first `parallel` use to a program recompiles its units once.
  - **Alternative:** keep one mode and keep tuning against the tax target. It is layout-sensitive and has no end in sight.
- **D2. The P2 surface in the redesigned syntax. Recommended.** This is plan 1's C2 translated (§6.1):
  - `with parallel.group() as g:`;
  - `const t = g.submit(fn, ARGS)`, where ARGS are written exactly as in a direct call `fn(ARGS)`, labels included;
  - `t.result()`, read inside the block, because locals are now block-scoped;
  - `parallel.map(fn, items, ARGS)`;
  - a bare `g.submit(...)` statement is allowed for an infallible procedure.
- **D3. `parallel.map` with a fallible `fn`.** Recommended: **`-> R[] fails E`.** Every item runs, and the failure returned is the one with the lowest input index, so `try parallel.map(load, paths, fs)` works.
  - **The alternative** is a `Result[R, E][]`, equal to the comprehension `[for x in items yield fn(x, ARGS)]`, with the caller looping to `try` each element.
  - The recommendation matches the redesign's "fallible functions use `fails`/`try`", and stays deterministic.
- **D4. Start P2 now,** on the post-redesign `main`, in the same run as P1F and T. **Recommended.**
  - Plan 1's gate (the front-end plan's F4) assumed that plan would rewrite the checker first. The redesign changed course, and that plan is idle.
  - **If you restart its Part C** (F3-C1's typed tree), P2 and F3-C1 will touch the same `sema_*` and `build*` files. Then run them one after the other, in either order.

## 4. Package P1F: fixes from the review (about 4–12 h)

Each fix starts with a failing fixture that reproduces the finding, then the fix, then the fixture passing. That includes a TSan run where the finding is a race.

**P1F-1. Bounded memory with cross-thread frees (A1)** `[RUNTIME-THREADS-2]`.
- **Requirement:**
  - with N threads, the blocks carved stay within a stated bound of the peak live set, for example ≤ 2 × peak live + N × one chunk per size class;
  - A1's probe passes at 2 and 8 threads under a 64 MiB ceiling;
  - `single` mode (§5) is unaffected.
- **Options:**
  - **(a)** Chunks owned by a thread (aligned to `MYL_CHUNK`, with an owner pointer). A free of a foreign block goes to the owner's lock-free remote-free stack, which the owner drains when `small_alloc` misses.
  - **(b)** A per-class depot. Threads donate whole free lists, an O(1) list move, at task and group boundaries. `small_alloc` refills from the depot before it carves.
- **Choose by measurement:** carved blocks, plus instructions on the scaling programs. The inline emitted free path must stay as cheap as it is now, or move its extra work to the slow path. Log the choice.

**P1F-2. Pool start that fits the memory limit (A2)** `[RUNTIME-THREADS-3]`.
- Cap glibc arenas before creating workers (`mallopt(M_ARENA_MAX, …)`).
- Account for each worker's stack and signal stack: raise the soft `RLIMIT_AS` by the reservation where the hard limit allows, and otherwise cap the thread count to fit.
- Bound `MYLANG_THREADS` to 1–256. Any other value, or a start that cannot fit even one worker, traps the new dedicated code `R_THREAD_START`, whose message gives the requested count, the cap and the memory limit. It is never reported as `R_MEMORY_BUDGET`.
- **Fixture:** `--max-memory=64M` with 20 and 64 threads starts or reports `R_THREAD_START`.

**P1F-3. Fatal-path fixes (A3, A4, A5)** `[TASK-FATAL-1]`.
- The timeout handler never parks. It writes its report raw and calls `_exit(1)`.
- `core_fatal_winner` records the winner's thread id, so re-entry on the winning thread is recognised.
- `os_exit` passes the status through.
- The winner waits for the stream lock with `sched_yield`, for a bounded time (about 50 ms), unless the lock is held by its own thread or by a parked loser. Only then does it go raw.
- **Fixtures:**
  - a worker that wins and blocks, plus `--timeout=1`: exits within the bound;
  - exit status 2 at 1 and 2 threads;
  - a worker holding a 1 MiB commit into a slow pipe while another task traps: the report keeps its task line.

**P1F-4. Helping stays on the waiter's own work (A6)** `[TASK-SCHEDULER-2]`.
- A thread waiting in `result()` or at group close runs only tasks from its own deque (its unstolen descendants). Only idle workers steal.
- **Fixture:** a recursion depth that just passes at 1 thread also passes at 8, with tasks waiting at every level.
- Report the effect on the scaling programs (§6.7). If it costs more than 10% at 8 threads, log the trade-off. Keep the bounded-depth rule unless the user decides otherwise.

**P1F-5. Wake only sleepers** `[TASK-SCHEDULER-2]`.
- Keep a count of parked threads. A push wakes one sleeper, and only when there is one. Completion wakes the waiter it releases.
- Measure system calls per task on a 10⁶-submit run, before and after.

**P1F-6. Shared text caches (B1)** `[SHARED-TEXT-CACHE-1]`.
- Shared, non-immortal texts cache the hash, the scalar count and the cursor through benign atomic publication:
  - each value is stored in one atomic word: the cursor as one packed 64-bit word, and not cached if it does not fit;
  - a reader that sees a cache flag must see its value. Use release on the flag and acquire on the read path, or make the value self-validating (for example, a zero sentinel) so the flag is not needed.
- Immortal literals stay unwritten, because they are in `.rodata`.
- The emitted `kind` loads (`emit_text.zig` around lines 60 and 81, `emit_dict.zig` around line 394) become `unordered` in `threads` mode, and stay plain in `single` mode (§5).
- **Fixtures:**
  - B1's walk bound (20,000 sequential lookups on a shared non-ASCII text walk O(n) octets);
  - a TSan run of 8 threads indexing and hashing shared texts.

**P1F-7. Runtime backstop for confined handles (B2)** `[TASK-GROUP-2]`.
- The share walk traps on a group block (a new `R_TASK_ESCAPE`, "a task group cannot be shared with a task").
- Submit and close trap if their group is shared.
- **Fixture:** B2's environment capture now traps instead of racing. P2's `E_TASK_ESCAPE` is the user-facing rule; this is the safety net.

**P1F-8. TSan coverage of the count helpers (B3).** Run the contention and near-saturation fixtures with `.sanitized = true`, and build the `shared_counts_test` harness with `-fsanitize=thread`. Expect 0 reports.

**P1F exit:**
- every fixture above passes;
- P1's three TSan programs, 100 repetitions at 8 threads, 0 reports;
- §7's correctness gates.

Then continue with T.

## 5. Package T: zero-tax mode (about 10–16 h)

### 5.1 What it does

- **Two modes, chosen per executable.**
  - `threads` mode is used when the program's reachable code calls any task-ABI helper (`myl_core_group_open`, `myl_core_task_submit`, `myl_core_task_result`, `myl_core_group_close`, `myl_core_share`, `myl_core_map_chunks`, `myl_core_task_item` and anything P2 adds).
  - Otherwise the program uses `single` mode.
  - The core already lowers whole programs (it decides `@noalloc` and reachability at build time), so this is one fact computed before emission.
  - P1's hand-built IR task tests, P2's programs and every TSan build are `threads`.
- **`single` mode emits what the emitter emitted before P1:**
  - the old inline count paths (`icmp eq -1` immortal test, then a plain update; no slow call; no branch weight);
  - plain count loads, and plain `kind` loads (P1F-6 makes them `unordered` only in `threads` mode);
  - the non-TLS `@myl_core_free_lists` declaration;
  - no `myl_core_task_call` bridge.
  
  Keep P1's emitter code for `threads` mode unchanged. Express the old paths as the `single` branch of the same functions, not as a revert.
- **`single` mode links a single-threaded runtime variant.** It is the same C sources compiled with `MYL_CORE_THREADS=0`, which compiles out:
  - TLS, giving plain globals;
  - thread registration and the registry;
  - output staging and stream locks;
  - the I/O mutex;
  - the trap-winner protocol, so traps behave exactly as before P1;
  - shared-count slow paths, which become an `R_INTERNAL` trap if ever reached;
  - the task ABI itself.
  
  A `single` executable that somehow calls a task helper then fails to link, which is the safety net.
  
  Keep one source tree with `#if` regions. Never fork the runtime files.
- **Cache identity.** The mode salts every unit object, the runtime archive and foreign-object manifests, as P1's sanitizer switch does. Ordinary, counting, layout and sanitizer builds compose with it.
- **Counting builds** (`--counters`) work in both modes.

### 5.2 How it is verified (deterministic: no quiet hardware needed)

- **The baseline arm, "main without P1".**
  - Take `main` (or the run's merge of it) in a scratch worktree, and reverse-apply P1's emitter, runtime and driver changes: `git diff 35df839be c26c95de7 -- src/core/emit_llvm.zig src/core/emit_count.zig src/core/count_runtime.zig src/core/driver.zig src/core/runtime/`. Only the emitter changed after P1 (4 lines) besides `core_values.c` (+5), so this should apply cleanly; record any conflict resolution.
  - Build it ReleaseFast. It compiles the redesigned-syntax corpora, which the pre-P1 compiler cannot.
- **G-T1, emission identity.** For every program in the corpora (the 46 rows, EDA's 34, both Lox engines' programs, parity), `single`-mode LLVM text equals the baseline arm's byte for byte, except differences listed in the report with a reason (a module flag, a declaration). **Target: no function-body differences.** Use `experiments/ce-x-20261008/tools/identity.py` or its successor.
- **G-T2, instructions.** `perf stat -e instructions:u` on every corpus cell, `single` against the baseline arm, with three repetitions and their median.
  - **Target:** per-corpus geomean ≤ 1.003 and no cell above 1.01.
  - What remains after G-T1 is the runtime: the refactored helpers and child iterator are compiled into both modes.
  - **If perf counting is refused,** fall back to wall time under plan 1's R10 protocol and log it.
- **G-T3, `threads` mode keeps P1:**
  - P1's task IR tests;
  - the scheduler and runtime-thread fixtures;
  - 100 TSan repetitions at 8 threads of P1's three programs, with 0 reports;
  - a counting build of a task program, whose exit has zero live bytes.
- **G-T4, mode selection tests:**
  - a program without tasks is `single` and links the single runtime;
  - adding one task-ABI call flips it to `threads`;
  - removing the call flips it back;
  - the two modes never share a cached object.

## 6. Package P2: the language surface, in the redesigned syntax (about 30–45 h)

### 6.1 Semantics

```mylang notest
import parallel

record Sheet:
    name: str
    nets: int[]

func score(sheet: Sheet, named weight: int) -> int:
    mut total = 0
    for net in sheet.nets:
        total += net * weight
    return total

func score_all(sheets: Sheet[], named weight: int) -> int[]:
    return parallel.map(score, sheets, weight=weight)    # == [for s in sheets yield score(s, weight=weight)]

func load_all(fs: Filesystem, paths: str[]) -> Sheet[] fails LoadError:
    return try parallel.map(load_sheet, paths, fs)        # lowest-index failure, every item runs (D3)

func totals(board: Board) -> int:
    with parallel.group() as g:
        const nets = g.submit(count_nets, board)
        const parts = g.submit(count_parts, board)
        return nets.result() + parts.result()             # the group closes on every exit edge
```

- **`parallel`** is an embedded standard module, typed by the checker, because `map` and `submit` are variadic.
- **`parallel.map(fn, items, ARGS)`.**
  - `items: T[]`. ARGS are written exactly as the arguments after the first in a direct call `fn(item, ARGS)`, with positional and `named` labels as `fn` requires. There may be 0 to 5 of them.
  - **Infallible `fn -> R`:** the result is `R[]`, equal to `[for x in items yield fn(x, ARGS)]`.
  - **Fallible `fn -> R fails E`:** the result is `R[] fails E` (D3).
- **`with parallel.group() as g:`.** `g` is only valid inside its block, and the block's end waits for every task on every exit: falling off the end, `return`, `fail`, `try`, `break` and `continue`.
- **`const t = g.submit(fn, ARGS)`.**
  - ARGS are exactly those of a direct call `fn(ARGS)`, with 0 to 6 arguments.
  - **`t.result()`** returns `R`. For a fallible `fn` it returns the checked result, so `try t.result()` or `match t.result()`.
  - Inside the block, `result()` waits for the task and runs other tasks meanwhile. A handle may be read more than once.
  - **A bare `g.submit(fn, ARGS)` statement is allowed only when `fn` is an infallible procedure (`Unit`).**
- **Lent arguments, results by value, the equivalence rule, traps, output and thread counts** are as in plan 1's §3.2 and §3.4–§3.6.

### 6.2 Checker rules

| code | rejects |
|---|---|
| `E_TASK_GROUP` | `parallel.group()` anywhere but as a `with` item |
| `E_TASK_ESCAPE` | a group or task handle stored in a field, array, dictionary or tuple; returned; passed as an argument; or captured by a callable value |
| `E_TASK_HANDLE` | a `submit` result that does not initialise a `const` declaration (`mut`, a reassignment or a nested expression), except the bare-statement form of §6.1 |
| `E_TASK_RESULT_UNREAD` | a handle that has no `.result()` read before its block ends, or a bare `submit` of a function that returns a value or can fail |
| `E_TASK_MUT` | a `mut` argument to `submit` or `map` |
| `E_TASK_HOST` | a task function with a `Host` parameter, or an argument whose type can hold a `Host` (recursively, with a visited-type guard) |
| `E_TASK_RESOURCE` | an argument whose type can hold an owned resource handle. Capabilities themselves are allowed. |

- Each diagnostic names the task site.
- Each carries a structured fix where one is certain. For `E_TASK_HANDLE` inside a loop, the hint points to `parallel.map`.
- Argument labels and arity are checked exactly as for a direct call of `fn`, with the same diagnostics.

### 6.3 Lowering

P2-0's table stands: helper calls, `func_ref`, `box_make`/`box_get`, generated thunks, the R4 bridge, R5's return-address sites and the `myl_core_task_item` cursor.

**What P2 adds:**
- **Group close** joins the existing scope-close mechanism (`build_cap.closeScopes`, the `with` lowering in `build.zig`), so every exit edge closes the group in reverse scope order. Do not add a second exit mechanism.
- **Range bounds:** `parallel.map` uses quotient/remainder partitioning with no overflow; an empty input returns `[]` without starting the pool.
- **Fallible map** (D3): each range thunk returns its `R[]`, or the lowest-index failure it met. The parent gathers in order and fails with the lowest index overall, after every range has finished.
- **Thunks stay reachable** for unit partitioning (`emit_units.zig`).
- **Mode:** any lowered task construct makes the executable `threads` (§5).

**No `ir.zig` or `own.zig` edit by you** (a §9 hard stop; upstream changes merged from `main` are fine). If P2's executable proofs expose a real gap, stop and report the smallest change that would close it.

### 6.4 CLI and test runner (plan 1's P2-3)

- `--threads N` on `run`, `build --run` and `test`, and `MYLANG_THREADS` for built binaries.
- Test children default to 1 thread.
- A child at N threads holds N job permits, and its `RLIMIT_AS` headroom grows by N − 1 worker stacks.
- `--max-steps` and `--max-frames` force one thread.
- `--threads` is not part of a receipt key.

### 6.5 Documentation

- `docs/concurrency.md`: the user guide, in the redesigned syntax, with runnable examples. It covers the semantics, the equivalence rule, what a shared mark costs, the map-then-merge idiom for reductions, and phase 1's limits (a trap ends the process; a parallel fatal exit skips file and provider cleanup).
- `docs/standard-library.md` (the `parallel` module) and `docs/tooling/guest-tests.md` (threads in tests).
- `src/features.json`: `parallel-map`, `task-groups` (language) and `thread-count-controls` (tooling), each with a runnable anchor. Update `limits.workers`; `guest-shared-memory-threads` stays unsupported.
- The Status lines of `docs/concurrency-proposal.md` and `docs/audits/d9-wp5-concurrency-design-2026-09-26.md` point to `docs/concurrency.md`.
- One bullet in `CLAUDE.md`'s "Where the language differs from Python" section.

### 6.6 Tests

**`tests/lang/parallel.my`:**
- `map` equals the comprehension over ints, strings, records, enums with payloads, dictionaries and nested arrays, with 0, 1 and 5 ARGS (positional and `named`), and with empty and one-item inputs;
- fallible `map` returns the lowest-index failure while every item runs (counted through a stand-in capability);
- the copy-on-write snapshot: the parent writes after `submit`;
- fallible `submit` with `try` and with `match`;
- nested groups and `map` inside a task;
- `return`, `fail`, `try`, `break` and `continue` out of a group block;
- a bare procedure `submit`;
- a task that builds a large result.

**Zig tests:** every `E_TASK_*` code with its fix or hint; the trap report line for a task and for a `map` item; `--threads` plumbing.

**`zig build test-concurrency`** (a new step, outside `zig build test`):
- `tests/lang/parallel.my` and stress programs at `--threads 8` under the TSan switch, 20 repetitions, 0 reports;
- the same at 1, 2 and 8 threads without TSan, with outputs equal to the 1-thread run except for the order of interleaved `print` lines.

### 6.7 Measurement

**Scaling** (plan 1's §7.1):
- all CPUs except 2, 3, 10 and 11, under `bench-compile.lock`, at 1, 2, 4 and 8 threads;
- three synthetic programs: per-item parsing, independent n-body runs and per-item hashing. **Target: ≥ 5× at 8 threads on at least two.**
- one EDA entry rewritten with `parallel.map` on a branch of your own eda-bench worktree, reporting speedup and shared-count counters, with no target.

**`single` mode stays zero-tax.** Rerun G-T1 after P2: programs without `parallel` still emit identical LLVM.

## 7. Gates (every package)

**Correctness:**
- `zig build test --summary all`, every step green, and `zig build fmt-check`;
- `experiments/new-core-s5-20261007/tools/qualify_merge.py`: test-core, and conformance 1518/0/0 in both modes (a fresh `--evidence` directory inside `experiments/`);
- the frozen fuzz matrix, 9×50 then 9×200, never beside the full gate;
- the Lox, EDA and parity corpora with your own worktrees, outputs exact;
- `mylang doc-coverage .` and the doctests (P2);
- the TSan suites (G-T3, then `test-concurrency`).

**Performance:**
- T: G-T1 and G-T2;
- P2: scaling, and G-T1 again.

**Spec tags:**
- **P1F:** one per fix family, named in §4.
- **T:** `[SINGLE-MODE-1]` (selection and emission), `[SINGLE-MODE-2]` (runtime variant and link safety net), `[SINGLE-MODE-3]` (cache identity).
- **P2:** `[PARALLEL-MAP-1]`, `[PARALLEL-MAP-2]` (fallible map), `[TASK-GROUP-1]`, `[TASK-CHECK-1]` onward, `[TASK-TRAP-1]`, `[TASK-OUTPUT-1]`, `[THREAD-COUNT-1]`.
- One `// spec:` test per bullet; further tests carry `// spec-case:`.

## 8. Report

`experiments/concurrency-2-<date>/REPORT.md` should give:
1. commits per package;
2. each P1F fix with its test;
3. T's identity and instruction tables, and the mode-selection evidence;
4. P2's checker, lowering and CLI summary;
5. the correctness gates;
6. the scaling table and the EDA entry;
7. a summary of `DECISIONS.md` (decisions that changed the plan, files outside the expected lists, hard stops reached or narrowly avoided);
8. what phase 2 should know.

Evidence stays under 10 MB. Subagents return report text; the coordinator writes the file.

## 9. Rules and autonomy

Plan 1's §9 rules apply. In brief:
- **Branches:** only `codex/concurrency-2` and your own worktrees; real merge commits.
- **Builds:** every build through `scripts/build-slot.sh`; ReleaseFast for timing and instruction counts, Debug for the gate; at most four build-heavy processes.
- **Processes:** kill only your own PIDs; no `pkill -f`.
- **Temporary files:** TMPDIR on disk.
- **Guardian**'s rules.
- **The slow-step rule:** log what it finds; it is not a stop.

**Decide, log, continue.** Implementation choices, files and gate failures are yours to resolve. Record each decision in `DECISIONS.md` with the question, the options, the evidence, the choice and its reversibility. Flaky-looking failures get one rerun; a repeat is real.

**Hard stops (report and stop only for these):**
1. **A semantic change:** to D1–D4 as the user decides them, to plan 1's C1, C3 and C5–C7 or its R1–R11, or to the redesign's syntax rules.
2. **A forbidden file:** an edit **by you** to `src/core/ir.zig` or `src/core/own.zig`. Changes to those files that arrive through a merge of `main` are not edits by you; merge them, and record them in `DECISIONS.md`. If the T baseline arm's reverse patch then conflicts, resolve the conflict in the scratch baseline only.
3. **A relaxed gate:** lowering a numeric threshold or skipping a gate. Measuring better is allowed and gets logged.
4. **A failed identity:** G-T1 shows function-body differences you cannot remove within about 6 hours. Report them; do not change the baseline arm to hide them.
5. **An unfixable failure:** a correctness failure that about 8 hours of investigation does not fix.
6. **A touch outside the branch:** anything that needs a merge into `main`, a push, or a change to a Claude worktree or branch.
7. **Resources:** disk, memory or slots you cannot recover within your own files and processes.

## 10. Out of scope (phase 2, decided later on data)

Plan 1's §10 list, unchanged: channels, services and shared state; green threads and I/O suspension; cancellation and deadlines; catching traps at a task boundary; `mut` task arguments and in-place parallel writes; removing shared marks; a deterministic simulation scheduler; error traces across `.result()`; `Host` inside tasks.
