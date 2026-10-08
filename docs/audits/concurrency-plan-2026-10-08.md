# Structured concurrency, phase 1: packages P1 and P2, 2026-10-08

Status: **P1 stopped during P1-0 under §9:** the emitted uniqueness count load needs an atomic-read change outside §5's emitter scope; see [the P1 report](../../experiments/concurrency-p1-2026-10-08/REPORT.md). P1 is not implemented or qualified. P2 is fully specified here, but it starts only after the front-end plan's F4 exit and the user's go (§6).
- **Decisions:** C1–C7, accepted by the user on 2026-10-08 (§2).
- **What it delivers:** CPU fork/join parallelism. `parallel.map` and task groups run on a work-stealing pool of OS threads. Only values that cross into a task get atomic counts.
- **Size (estimates):** P1 about 25–40 h; P2 about 30–45 h. Each package ends with a stop for the user.
- **What it replaces:** for phase 1, this plan supersedes `docs/concurrency-proposal.md` (2026-09-13) and `docs/audits/d9-wp5-concurrency-design-2026-09-26.md`. It is stage 5 of ADR D9 (`docs/adr/D9-value-semantics-then-rc.md`) on the new core.

## Launch instruction (for Codex)

> **Now, package P1 only.** Implement package P1 of `docs/audits/concurrency-plan-2026-10-08.md` (branch `claude/concurrency-plan`) on `codex/concurrency-p1`, created from `claude/concurrency-plan`.
> - If `main` has moved, merge `main` into it first with a real merge commit.
> - Follow §9's rules.
> - Never merge into `main` and never push.
> - Finish with P1's report (§8) and stop.
>
> **Later, package P2,** only when the user says so: on `codex/concurrency-p2`, created from P1's tip merged with the `main` of that day. Start with P2-0, follow §9, finish with P2's report and stop.

## 1. Where it starts

Facts on `main` `1edeef830`.

**No concurrency exists.**
- `src/features.json` lists `guest-shared-memory-threads` as unsupported.
- `limits.workers` says "no host worker facility and no guest spawn syntax".
- The runtime is single-threaded throughout. Its own comments say so (`src/core/runtime/core_rt.c`, "Single-threaded, like the counts").

**Blocks and counts** (`core_rt.c`, header comment and "one-count RC").
- Every managed value lives in a block with a 32-byte header: `{u32 count, u32 kind, i64 len, i64 cap, i64 reserved}`.
- `count` is one saturating 32-bit count. `0xFFFFFFFF` means immortal (ADR D4): string constants, never written and never freed.
- The class of a small block sits in the high byte of `kind`. `reserved` holds the element layout of a list or box whose elements hold blocks, so a free can release children. `myl_core_free_block` frees iteratively through a pending chain.
- **Retain and release are emitted inline** by `countBlock` in `src/core/emit_llvm.zig` (around line 2941):
  - load the count (`count_load_line`, TBAA `myl.count`, range `[1, 0)`);
  - `icmp eq -1` (immortal) branches to done;
  - a retain stores `count + 1`;
  - a release stores `count − 1`, or calls `@myl_core_free` when it reaches 0.
- **The uniqueness test** that decides copy-on-write is `icmp eq i32 count, 1` (`isUnique`, around line 1820, and around line 2906).
- **The runtime also touches counts directly:** `retain_block`, the child loop of `myl_core_free_block`, `myl_core_list_copy`, the dictionary, text and byte code, and the I/O finalizer.

**The allocator** (`core_rt.c`, "allocation").
- Blocks up to 1 KiB come from 32 per-size-class free lists. They are carved from 64 KiB chunks that are **never returned**. Larger blocks use `malloc`/`realloc`.
- The common paths are emitted inline against `@myl_core_free_lists = external global [33 x ptr]` (`emit_llvm.zig`, around lines 3432–3510, including the `alwaysinline` `@myl_core_free`).
- The memory ceiling (`heap_ceiling`, `heap_held`) is set only in test children. `RLIMIT_AS` at the ceiling plus 256 MiB backs it (`core_test.c`).

**Process-wide state that threads will touch** (a first list; P1-0 makes it complete):

| state | where |
|---|---|
| free lists, `chunk_next`, `chunk_end` | `core_rt.c`, and the emitter's declaration |
| `heap_ceiling`, `heap_held`, `live_blocks` | `core_rt.c` |
| `streams[2]`: one output buffer each for stdout and stderr | `core_rt.c` |
| the error-return-trace ring (`error_trace`) | `core_rt.c` |
| trap reporting (`trap_capture`, `core_trap_marks_all`, …) | `core_rt.c` |
| the stack-floor guard (`core_stack_top`, its signal stack) | `core_test.c` |
| step and frame budget counters | `core_test.c` |
| `SIGALRM` from `setitimer` (the test timeout) | `core_test.c` |
| I/O handle tables and counters (`core_io_open_count`, `core_io_family_open`, `core_io_seed`) | `core_io.c` |
| `core_text_walked` and other report state | `core_text.c` |
| counting builds: `myl_count_current`, `myl_count_copy_site`, `myl_count_push_site` and the slots | the counting runtime (`src/core/count_runtime.zig`, `core_count.c`/`.h`) |

**The ownership pass** (`src/core/own.zig`).
- Calls borrow their arguments, and call results are owned (+1).
- An in-place update happens in three forms:
  - **form 1:** statically unique, no test (verify builds assert `count == 1` and trap `R_CORE_FACT`);
  - **form 2:** tested with `is_unique`;
  - **form 3:** always copies.
- A value retained into another value, or passed to a call, is no longer form 1.

**Core IR** (`src/core/ir.zig`). It already has what a task needs:
- `func_ref` and `call_indirect`;
- `box_new` and `box_get`;
- calls of runtime helpers declared as extern functions (`test_builder.helper`, used by `run_budget.zig`).

`ir.zig` **is frozen through F0–F4** of the front-end plan (`docs/audits/frontend-implementation-plan-2026-10-06.md`). The values-and-keys plan's V wave unfreezes it after F4. **This plan is designed to need no `ir.zig` change** (P2-0 confirms it).

**The test runner.**
- Plain tests share processes, and each trial is forked from the batch process (NEW-CORE-TEST-BATCH-1).
- A directory run shares job permits among its roots (NEW-CORE-TEST-QUEUE-1).
- Children get `MYLANG_MEMORY_LIMIT` and an `RLIMIT_AS` backstop.

**ThreadSanitizer works with the pinned toolchain.** `zig cc -fsanitize=thread` built and ran a small racy C program on 2026-10-08 and reported the race.

**Work in flight that overlaps:**
- **CE2** (`claude/ce2-effects`, `claude/ce2-results`, integrated on `claude/copy-elim-2`) edits `emit_llvm.zig` and `own.zig`.
- **The front-end plan's waves** (`codex/frontend-integration`) own the front end, keep `ir.zig` frozen, and run F2-C2, which removes effect checking.
- **The values-and-keys plan's V wave** starts after F4.

## 2. Decisions (accepted 2026-10-08)

- **C1. Phase 1 is CPU fork/join only.** A fixed pool of OS threads with work-stealing. Tasks never suspend: no channels, no services, no green threads, no I/O reactor. Phase 2 (§10) waits for an I/O workload.
- **C2. The surface follows Python's `concurrent.futures`.**
  - `parallel.map(fn, items, *context)`;
  - `with parallel.group() as g:`, with `t = g.submit(fn, *args)` and `t.result()`.
  - A task is a top-level function (or a typed function value) plus its arguments; there are no closures.
  - Handles are confined to their function (§3.3).
- **C3. Arguments are lent, and values that cross get a shared mark.** No copies happen at the boundary. A block reachable from a task's arguments gets the top bit of its count set, and counts on such blocks are atomic. Marks are never removed; the parent's first write to a marked value copies it, and the copy is unmarked.
- **C4. No `mut` arguments to tasks.** Results come back by value.
- **C5. A trap in any task ends the process,** with exit status 1 as today. The report names the task.
- **C6. Output from tasks is written a whole line at a time,** in an unspecified order across tasks. Results always come back in input or submit order.
- **C7. Thread counts:**
  - `mylang run` defaults to the CPUs the process may use; test children default to 1;
  - `--threads N` on `run`, `build --run` and `test`, and `MYLANG_THREADS` for any binary;
  - a dedicated concurrency suite runs at 8 threads under ThreadSanitizer.

## 3. Semantics (P2 implements this; P1 builds the runtime for it)

### 3.1 The surface

```python
import parallel

def score_all(sheets: list[Sheet], rules: Rules) -> list[int]:
    return parallel.map(score, sheets, rules)      # == [score(s, rules) for s in sheets]

def totals(board: Board) -> int:
    with parallel.group() as g:
        nets = g.submit(count_nets, board)
        parts = g.submit(count_parts, board)
    return nets.result() + parts.result()           # the block waited for both
```

- **`parallel` is an embedded standard module** (`import parallel`), typed by the checker the way the prelude builtins are. mylang has no variadic parameters, so `map` and `submit` cannot be ordinary generic functions.
- **`parallel.map(fn, items, *context)`.**
  - `items` is a `list[T]`, and there are 0 to 5 `context` arguments.
  - `fn` takes `(T, *context)` and returns `R`.
  - The result is a `list[R]` **equal to `[fn(x, *context) for x in items]`**.
  - There is no special error handling: a `Result`-returning `fn` gives a `list[Result[R, E]]`.
- **`parallel.group()`** is valid only as a `with` item.
  - The block's end waits for every task submitted in it, on every exit path: falling off the end, `return`, `break`, `continue` and `?`.
- **`g.submit(fn, *args)`** takes 0 to 6 arguments and returns a `parallel.Task[R]`.
  - `t.result()` returns `R`, **equal to `fn(*args)`**.
  - Inside the block, `result()` waits for the task, running other tasks meanwhile. After the block it returns at once.
  - `result()` may be read more than once; each read gives the same value.
- **Nesting:** a task may open its own group or call `parallel.map`.

### 3.2 Arguments, results and determinism

- **Arguments are lent exactly as call arguments are.** The task cannot change the caller's variables, and it sees the values they had at `submit`. If the parent writes to its variable afterwards, copy-on-write keeps the task's view intact.
- **Results move to the parent;** they are never copied.
- **The equivalence rule.** For a task whose arguments hold no capability, replacing `parallel.map` with the comprehension, or `t = g.submit(f, a)` … `t.result()` with `f(a)`, never changes what the program computes, at any thread count.
  - A task holding a capability (`Clock`, `Entropy`, `Filesystem`, `Network`, `Environment`, `Stream`) behaves as if the tasks' capability calls ran in an unspecified order.
  - At one thread they run in exactly the sequential order (§3.6).

### 3.3 Checker rules (new diagnostics)

| code | rejects |
|---|---|
| `E_TASK_GROUP` | `parallel.group()` anywhere but as a `with` item |
| `E_TASK_ESCAPE` | a group or task handle stored in a field, collection or tuple; returned; passed as an argument; assigned to another name; or the group used after its block |
| `E_TASK_HANDLE` | a `submit` result bound inside a loop or comprehension, or bound to a name assigned anywhere else in the function. Dynamic fan-out is `parallel.map`, and the message says so. |
| `E_TASK_RESULT_UNREAD` | a `submit` whose handle is never read with `.result()` in the function (including a bare `g.submit(...)` statement) |
| `E_TASK_MUT` | a `mut` argument to `submit` or `map` |
| `E_TASK_HOST` | a task function with a `Host` parameter, or an argument or context whose type can hold a `Host`. `extern def` code is not known to be thread-safe. |
| `E_TASK_RESOURCE` | an argument or context whose type can hold an owned resource (an open file or socket handle). Capabilities themselves are allowed. |

- Each diagnostic names the task site and, where one applies, the rule's alternative.
- The function value rules (noncapturing, typed) apply unchanged.

### 3.4 Traps

- A trap in a task ends the process with exit status 1, as any trap does today.
- The human report adds one line: `in task submitted at PATH:LINE:COL`, or `in parallel.map item N at PATH:LINE:COL`.
- Other tasks are not unwound.
- The test runner's trap record (NEW-CORE-S5-TRACE-1) keeps its format.

### 3.5 Output

- Everything one `print` call writes, up to its `print_end`, reaches the stream as one unit.
- A `stream.write(...)` is one unit, and so is a `debug(...)` line.
- Units from different tasks interleave in an unspecified order.

### 3.6 Thread count

- The runtime reads `MYLANG_THREADS` when the first task is submitted. The default is the number of CPUs in the process's affinity mask (`sched_getaffinity`), at least 1.
- `mylang run --threads N` and `mylang build --run --threads N` set it for the program.
- **`mylang test`** gives test children `MYLANG_THREADS=1` unless `--threads N` is passed. Then:
  - a child running at N threads holds N of the run's job permits (NEW-CORE-TEST-QUEUE-1);
  - its `RLIMIT_AS` headroom grows by N − 1 worker stacks.
- **A run with `--max-steps` or `--max-frames` uses one thread.** Budgets are per process and must stay deterministic.
- **At one thread, no worker thread is started.**
  - `submit` runs the task at once, on the caller's thread.
  - `parallel.map` runs its items in order.
  - The program's behaviour, output order included, is exactly the sequential program's.

## 4. Runtime design (P1)

### 4.1 Count encoding (SHARED-COUNTS-1)

| count value | meaning |
|---|---|
| `1 … 0x7FFFFFFE` | plain count: one thread can reach the block |
| `0x7FFFFFFF` | never stored. A plain retain that would reach it makes the block immortal, as saturation does today. |
| `0x80000001 … 0xFFFFFFFE` | shared: owners = value − `0x80000000`, always updated atomically |
| `0xFFFFFFFF` | immortal (D4), unchanged |

**Emitted retain:**
- `c <u 0x7FFFFFFE` → store `c + 1` (the fast path, one compare as today);
- else `c == -1` → nothing;
- else call the cold `@myl_core_retain_slow(block)`.

**Emitted release:**
- `c <u 0x80000000` → plain `c − 1`, freeing at 0;
- else `c == -1` → nothing;
- else call the cold `@myl_core_release_slow(block)`.

So the fast path keeps one compare. The immortal case gains one compare off the fast path, and string constants still never call out.

**Unchanged:**
- **The uniqueness test** stays `count == 1`. A shared count is never 1, so every update of a shared value copies (form 2 takes its copy path). Form 1 never applies, because a value placed in a task's environment has been retained.
- **The range metadata `[1, 0)`** stays valid.

**Atomics.**
- A shared retain is a relaxed fetch-add.
- A shared release is a release fetch-sub. The release that takes the last owner runs an acquire fence, then frees.
- A shared count that would reach `0xFFFFFFFF` becomes immortal by compare-exchange.

**One door for counts.** Every count access in the C runtime goes through three helpers: `count_retain`, `count_release` and `count_is_unique`. A Zig source test in `src/core/` fails if `core_*.c` touches `->count` outside them.

### 4.2 The share walk (SHARED-COUNTS-2)

- `myl_core_share(root)` marks `root` and every block reachable from it as shared.
- **It stops at shared and immortal blocks.** That relies on the invariant that a shared block points only to shared or immortal blocks. The invariant holds because a shared block is never updated in place.
- **Plain blocks are reachable from one thread only.** So the walk may set the bit with a plain store, but it reads counts with relaxed atomic loads, because a shared block's count may be changing on another thread.
- **It is iterative,** with an explicit work list, so no recursion.
- **Children come from the same iterator as `myl_core_free_block`:**
  - list and box layouts with their guards;
  - dictionary entries;
  - a view's owner;
  - I/O blocks.
  
  Factor that enumeration into one iterator so the two cannot diverge. A test checks, for every block kind, that the walk visits exactly the children a free releases.
- **Cost:** proportional to the plain blocks reachable. It is zero for a value that is already shared, so resubmitting the same large context is free.

### 4.3 Per-thread runtime state (RUNTIME-THREADS-1)

| state | becomes |
|---|---|
| free lists, `chunk_next`, `chunk_end` | `_Thread_local`. The emitter declares `@myl_core_free_lists` `thread_local(initialexec)`, or `localexec` if the static link allows it; P1-1 measures both. A block freed on another thread joins that thread's list, which is safe because chunks are never returned. |
| `heap_ceiling` | read-only after start |
| `heap_held` | atomic, and only touched when a ceiling is set |
| `live_blocks` | atomic |
| `streams[2]` | Once workers exist, each thread stages a unit (§3.5) in a thread-local buffer and appends it under one mutex. Before the pool starts, nothing changes. |
| the error-trace ring | `_Thread_local`. A trace that crosses a task boundary starts at `.result()` (§10). |
| trap reporting | The first trapping thread wins a once-flag, flushes, reports and `_exit`s. Any later trapping thread parks. The report names the current task (thread-local task record: site and item index). |
| `core_stack_top`, the floor signal stack | per thread: each worker records its stack top and installs its own `sigaltstack` |
| step and frame counters | unchanged: budgets force one thread (§3.6) |
| `SIGALRM` | workers block it (`pthread_sigmask`), so the timeout lands on the main thread |
| I/O handle tables and counters | a mutex around handle-table changes; P1-0 classifies the rest |
| counting-build state | thread-local current-function record; counter slots summed across threads at exit |

P1-0 produces the complete inventory: every object with static storage duration in `src/core/runtime/`, and every global the emitter declares. Each gets a decision, and the list goes in the report.

### 4.4 The scheduler (TASK-SCHEDULER-1, new file `src/core/runtime/core_tasks.c`)

**The pool.**
- It starts lazily, on the first `submit` with more than one thread: N − 1 worker threads plus the submitting thread.
- Workers live until the process exits.
- A process that never submits starts no thread.

**Queues.**
- One Chase–Lev deque per thread. `submit` pushes onto the current thread's deque. An idle thread steals the oldest task from another deque.
- Victims are chosen round-robin. No randomness.

**Waiting runs work.**
- `result()` and a group's end run tasks while they wait: first the waiter's own deque, then steals, until the awaited task is done.
- A thread never blocks on a task that only it could run.

**Idling.** An idle worker spins briefly, then sleeps on a futex word that every push increments. No wall clock.

**Task records.**
- A task holds its thunk, environment block, result block, site, item index and an atomic state word.
- Completion is a release store; the waiter reads it with an acquire load.
- A task handle is a managed block of a new kind, `task`, whose one child is the result. Releasing the handle releases the result through the ordinary count path.

**Stacks.**
- A worker's stack is the main thread's `RLIMIT_STACK` soft limit, or 64 MiB when that is unlimited, with a guard page.
- The stack-floor report works on workers too.

**Fork safety.** A process with worker threads must never fork. The test batch parent never runs guest code. P1-4 adds a test that the pool cannot start in a batch parent.

**The internal ABI** (P2 lowers to it; the names may change in P1-0):

```c
void       myl_core_share(myl_block *root);
myl_block *myl_core_group_open(const myl_core_site *site);
myl_block *myl_core_task_submit(myl_block *group, myl_block *(*run)(myl_block *env),
                                myl_block *env, const myl_core_site *site, int64_t item);
myl_block *myl_core_task_result(myl_block *task);   /* waits, running other tasks; +1 */
void       myl_core_group_close(myl_block *group);   /* waits for every task of the group */
int64_t    myl_core_threads(void);
int64_t    myl_core_map_chunks(int64_t items);       /* how many tasks a map of `items` uses */
```

**Ownership follows the IR's call convention:** calls borrow, results are owned.
- `myl_core_task_submit` shares `env`, retains it for the task and publishes the task. The caller's own reference is released by its last use, as for any call argument.
- At one thread, `submit` runs `run(env)` at once and stores the result. No sharing or retain is needed.
- The handle, the group and `myl_core_task_result`'s value are owned by the caller (+1).

### 4.5 The ThreadSanitizer build (TSAN-BUILD-1)

An internal switch, `MYLANG_CORE_SANITIZE=thread`. It is not a CLI flag and not a feature slug. With it:
- the emitter adds `sanitize_thread` to every function;
- the runtime archive is compiled with `-fsanitize=thread`;
- the link adds the TSan runtime;
- object and runtime cache keys include the switch.

Only the concurrency suite uses it. It catches a missing mark, because the emitted plain count updates are ordinary loads and stores.

### 4.6 Counters

`--counters` gains three slots:
- shared retains;
- shared releases;
- share-walk marks (blocks, bytes).

The slow helpers record the first two. The P2 report uses them to show what C3's "marks never come off" costs on a real program.

## 5. Package P1: the runtime (about 25–40 h)

**P1-0. Inventory (1–2 h).**
- The table of §4.3, completed.
- Every count access in the runtime.
- Confirmation that a hand-built IR program can call the §4.4 ABI with `func_ref`, boxes and helper calls. If something is missing, write it down for P2-0 and carry on.

**P1-1. Count encoding (§4.1), then an early tax check.**
- **Code:** `countBlock`; the two slow helpers; `count_retain`/`count_release`/`count_is_unique`, with every runtime count site moved onto them; the source test.
- **Then measure** the single-threaded tax (§7.1) with the TLS declaration still plain.
- **Stop rule:** if the wall-time geomean of any corpus is above 1.010, or any row's median is above 1.03×, stop and report. That would contradict C3's premise.

**P1-2. Per-thread runtime state (§4.3).**
- The TLS free lists, measuring initial-exec against local-exec on the tax rows.
- Stream staging, the trap once-flag, per-thread stacks and signal stacks, `SIGALRM` masking, I/O locks, counting-build state.

**P1-3. The share walk (§4.2).** The shared child iterator and its differential test.

**P1-4. The scheduler (§4.4).**
- Deques, waiting that runs work, futex parking, lazy start, `MYLANG_THREADS`, `myl_core_map_chunks`.
- The fork-safety test.
- C-level unit and stress tests, linked with the runtime: many small tasks, deep nesting, waits on tasks still queued on the waiter's own deque, 10⁶ submits.

**P1-5. End to end without the front end.**
- Hand-built Core IR tests in the style of the S2/S3 hand-built-IR tests (`src/core/*_ir_test.zig`, `test_builder.zig`). Each builds lists, records, dictionaries, strings and nested lists; submits IR thunk functions through the ABI; reads and retains shared parts in the tasks; returns results; and joins.
- Run at 1, 2 and 8 threads.
- The same tests and the C stress tests run under `MYLANG_CORE_SANITIZE=thread`, **100 repetitions at 8 threads, 0 reports**.
- At 1 thread, the results equal the sequential computation.

**P1-6. Measurement and the report** (§7, §8), then **stop**.

**P1 owns:**
- `src/core/runtime/core_rt.c`, `core_test.c`, `core_io.c` (locks only), `core_text.c`, `core_dict.c`, `core_bytes.c`, `core_values.c` (count sites only);
- the counting runtime (`core_count.c`, `core_count.h`, `src/core/count_runtime.zig`, `src/core/emit_count.zig`);
- the new `core_tasks.c`;
- in `src/core/emit_llvm.zig`: **only** `countBlock`, the `@myl_core_free_lists` declaration and the inline allocation and free text (around lines 3432–3510), plus the `sanitize_thread` attribute;
- the runtime asset build and link flags for the TSan switch;
- new tests under `src/core/`;
- `SPEC.md` (§7.2 tags), `docs/tooling/native-build.md` (one paragraph on the TSan switch, as internal), and this plan's Status line;
- `experiments/concurrency-p1-<date>/`.

Nothing in the front end, `own.zig` or `ir.zig`.

**Overlap with CE2.** If CE2 merges into `main` during P1, merge `main` into `codex/concurrency-p1` with a real merge commit and rerun P1's gates. In `emit_llvm.zig`, keep to the functions listed above.

## 6. Package P2: the language surface (about 30–45 h)

**When:** after the front-end plan's F4 exit and the user's go. F1–F4 rewrite the checker, the typed tree (F3-C1 moves desugaring into the core) and the generics path (F3-C3). Lowering `parallel` before then would be written twice.

**The V wave.** The values-and-keys plan's V wave also starts after F4, and it changes `ir.zig`. P2 is designed not to.
- If P2-0 confirms that P2 needs no `ir.zig` change and the two share no files, they may run side by side.
- Otherwise the user orders them.

**P2-0. The lowering decision (1–2 h).**
- Confirm that each construct lowers to helper calls of the §4.4 ABI plus `func_ref`, `box_new`/`box_get` and generated thunk functions, with no `ir.zig` change.
- **If a change is needed, stop and report** with the smallest IR change that would do.

**P2-1. The `parallel` module and the checker.**
- The embedded module and its types `parallel.Group` and `parallel.Task[R]`.
- The typing of `map`, `group`, `submit` and `result` (§3.1).
- §3.3's rules, with structured diagnostics.

**P2-2. Lowering.**
- **Per `submit` site:** an environment record of the arguments, boxed; a generated thunk `run(env) -> box[R]` that unboxes the arguments, calls `fn` and boxes the result; and `myl_core_task_submit` with the site.
- **`result()`:** `myl_core_task_result` and an unbox.
- **Group close** on every exit edge of the `with` block, as `with fs.open(...)` closes on every edge.
- **`parallel.map`:**
  - share `items` and `context` once;
  - `k = myl_core_map_chunks(len(items))` contiguous ranges;
  - one task per range, whose thunk loops over the range, calls `fn` and returns its own `list[R]`;
  - the parent concatenates the ranges' lists in order;
  - at one thread, `k = 1` and the range runs at once.
- **Verify builds** (form 1's `count == 1` assertion) run over the new tests.

**P2-3. CLI and test runner** (THREAD-COUNT-1).
- `--threads N` on `run`, `build --run` and `test`.
- `MYLANG_THREADS` for built binaries.
- Test children default to 1, with permits and `RLIMIT_AS` headroom as in §3.6.
- Budgets force one thread.
- `--threads` is not part of a test's receipt key: by §3.2 the verdict cannot depend on it.

**P2-4. Documentation.**
- `docs/concurrency.md`: the user guide, with runnable examples. It covers §3, the equivalence rule, what a shared mark costs, and the "map then merge" idiom for histograms and other reductions.
- An entry in `docs/standard-library.md`, and a paragraph in `docs/tooling/guest-tests.md` on threads in tests.
- Feature slugs in `src/features.json`, each with a runnable doc anchor:
  - `parallel-map` (language);
  - `task-groups` (language);
  - `thread-count-controls` (tooling).
- Update `limits.workers`. `guest-shared-memory-threads` stays unsupported.
- `docs/concurrency-proposal.md` gets a Status line pointing here and to `docs/concurrency.md`. Add the same to the WP-5 design.
- One bullet in `CLAUDE.md`'s "Where the language differs from Python" section.

**P2-5. Tests.**
- **`tests/lang/parallel.my`:**
  - `map` equal to the comprehension over ints, strings, records, unions, dictionaries and nested lists, with 0, 1 and 5 context arguments, and empty and one-item lists;
  - the copy-on-write snapshot (the parent writes after `submit`);
  - `Result` values;
  - nested groups and `map` inside a task;
  - `return`, `break` and `?` out of a group block;
  - a task that builds a large result.
- **Zig tests** for every `E_TASK_*` code and for the trap report line.
- **`tests/concurrency/`**, run by a new build step `zig build test-concurrency`, which is **not** part of `zig build test`:
  - `tests/lang/parallel.my` plus stress programs at `--threads 8` under `MYLANG_CORE_SANITIZE=thread`, 20 repetitions, 0 reports;
  - the same at 1, 2 and 8 threads without TSan, outputs compared with the one-thread run, excluding interleaved `print` order.

**P2-6. Measurement and the report** (§7, §8), then **stop**.

**P2 owns:**
- the checker and lowering files for the new constructs, as P2-0 names them;
- `src/stdlib/parallel.my` (or the builtin-module registration P2-0 finds);
- the CLI and test-runner flag code (`src/core/cli_args.zig`, `cli_run.zig`, `test_runner_options.zig`, `test_runner_execute.zig`, `test_runner_budget.zig`);
- the `core_tasks.c` hooks the lowering needs;
- `docs/concurrency.md`, `docs/standard-library.md`, `docs/tooling/guest-tests.md`, `docs/concurrency-proposal.md`, the WP-5 design's Status line, `CLAUDE.md` (one bullet), `src/features.json`, `SPEC.md`;
- `tests/lang/parallel.my`, `tests/concurrency/`, `build.zig` (the new step);
- `experiments/concurrency-p2-<date>/`.

`ir.zig` stays untouched unless the user approves P2-0's stop.

## 7. Gates

### 7.1 Measurements

**The single-threaded tax** (P1-1, P1-6, P2-6).
- **What is compared:** wall time of a ReleaseFast compiler built from the package against one built from the launch base. Install each with `scripts/build-slot.sh`, `zig build -Doptimize=ReleaseFast --prefix ~/.cache/mylang/conc-{base,p1,p2}-<sha>`.
- **The corpora are CE-X's** (`experiments/ce-x-20261008/tools/`): the 46 rows, EDA (34 programs), Lox (both engines) and parity.
- **The method is CE-X's:** three runs, every timed process on CPU 10 under `/run/user/1000/mylang-slots/cpu10.lock`, load recorded.
- **Your own copies.** CE-X's scripts point into the Claude worktree `claude-copy-elim`. Make copies that point at your own worktrees:
  - a Codex worktree of eda-bench `claude/eda-bench-newcore`;
  - a Lox checkout prepared as `part1a.sh` prepares one.
  - Never modify a Claude worktree.
- **Rule:** per-corpus geomean ≤ 1.010 and no row's median above 1.03×.
- **For P2:** a program without `parallel` should also emit identical LLVM to P1's tip on CE-X's 47 programs (`identity.py`). Report any difference.

**Scaling** (P2-6).
- **Where:** all CPUs except 2, 3, 10 and 11, under `/run/user/1000/mylang-slots/bench-compile.lock`, with load recorded. Thread counts 1, 2, 4 and 8.
- **Programs:**
  - three synthetic programs in `experiments/concurrency-p2-<date>/programs/`: per-item parsing of independent strings, independent n-body runs, and per-item hashing of byte strings. **Target: ≥ 5× at 8 threads on at least two of the three.**
  - one EDA entry with independent per-item work, rewritten with `parallel.map` on a branch of your eda-bench worktree (never merged into eda-bench). Report its speedup and its shared-count counters (§4.6); there is no target.

### 7.2 Spec tags

- **P1:** `[SHARED-COUNTS-1]` (encoding and emitted paths), `[SHARED-COUNTS-2]` (share walk and invariant), `[RUNTIME-THREADS-1]` (per-thread state, staging, traps, stacks, signals), `[TASK-SCHEDULER-1]` (lazy pool, deques, waiting runs work, thread count), `[TSAN-BUILD-1]` (internal switch).
- **P2:** `[PARALLEL-MAP-1]`, `[TASK-GROUP-1]`, `[TASK-CHECK-1]` and following (one per diagnostic family), `[TASK-TRAP-1]`, `[TASK-OUTPUT-1]`, `[THREAD-COUNT-1]`.
- One `// spec:` test per bullet; further tests carry `// spec-case:`.

### 7.3 Correctness, for each package

- `zig build test --summary all`, every step green, and `zig build fmt-check`. `test-qbe` and `test-qbe-build` no longer exist.
- `experiments/new-core-s5-20261007/tools/qualify_merge.py`: test-core, and conformance 1518/0/0 in both modes. `--evidence` must name a fresh directory inside `experiments/`.
- The frozen fuzz matrix (`fuzz_matrix.py`), 9×50 then 9×200. Never run it beside the full gate.
- Lox conformance, the EDA goldens and its 310 tests, and parity's `.expected` outputs, with your own copies (§7.1).
- Counting builds print what ordinary builds print, on every program counted.
- **P1:** P1-5's TSan runs, 0 reports.
- **P2:** `zig build test-concurrency` green; `mylang doc-coverage .` and the doctests green.

## 8. Reports

`experiments/concurrency-p{1,2}-<date>/REPORT.md` should give:
1. what was built, with commits;
2. P1-0's inventory (P1), or P2-0's decision (P2);
3. the correctness gates;
4. the tax table, base against package per row and corpus, with load; for P1 also the TLS-model comparison;
5. for P2, the scaling table and the EDA entry's speedup and shared-count counters;
6. anything surprising, and what phase 2 should know.

Evidence stays under 10 MB per package. Subagents cannot write `REPORT.md` files: a subagent returns the text, and the coordinator writes it.

## 9. Rules

- **Branches:** work only on `codex/concurrency-p1` or `codex/concurrency-p2`, and your own eda-bench and Lox worktrees. Never merge into `main`, never push, and never modify Claude worktrees or branches. Merges are real merge commits.
- **Builds:**
  - every build through `scripts/build-slot.sh`;
  - ReleaseFast installs for timing, Debug for the gate;
  - at most four build-heavy processes, shared with the front-end plan's waves and any other lane.
- **Processes:** kill only PIDs you started. Never `pkill -f` a pattern.
- **Temporary files:** TMPDIR and every cache on disk, never `/tmp` on tmpfs.
- **Guardian** (it blocks inside `zig build test`):
  - a spec tag per behavioural change;
  - structs ≤ 7 fields; functions ≤ 6 parameters;
  - `///` on every `pub` declaration;
  - explicit error sets;
  - no `std.debug.print` in committed code;
  - no hardcoded `std.heap.page_allocator`;
  - no wall clock or RNG outside sanctioned code;
  - every new file reachable from a Guardian root;
  - straight-line test bodies with at least one `expect`.
- **Correctness first.** A race TSan reports, a result that differs between thread counts, or a conformance difference is a stop-and-fix before any timing counts.
- **The slow-step rule:** a step over about 5 minutes gets a speed investigation before it is repeated.
- **Scope:** stay inside §5's and §6's "owns" lists. A needed change elsewhere is a stop and a report.

## 10. Out of scope (phase 2, each decided later on data)

- channels, services and shared state (`Shared<T>`-like cells);
- green threads and tasks that suspend on I/O, with an I/O reactor;
- cancellation and deadlines;
- catching a trap at a task boundary (the 2026-10-07 decision), so one failing task need not end the process;
- `mut` arguments and in-place parallel writes (`par.chunks`-style);
- removing shared marks when a value returns to one thread;
- a deterministic simulation scheduler for tests;
- error return traces that continue across `.result()`;
- `Host` and `extern def` inside tasks.
