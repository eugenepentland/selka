# Structured concurrency, phase 1: packages P1 and P2, 2026-10-08

Status: **P1 and read-only P2-0 are complete (2026-10-09), with merged-source elapsed-time performance unverified under the user's explicit timing waiver.** The final runtime `c26c95de7` includes real main merge `1844fcc33` (`35df839be`), passes all final correctness gates and 300 TSan executions, and has an identical-path allocation/copy/output proxy. Historical timing target misses remain explicit. See [the final P1 report](../../experiments/concurrency-p1-2026-10-08/REPORT.md) and its decision log. P2 has not started and still requires the front-end plan's F4 exit and the user's go (§6).
- **Decisions:** C1–C7, accepted by the user on 2026-10-08 (§2).
- **What it delivers:** CPU fork/join parallelism. `parallel.map` and task groups run on a work-stealing pool of OS threads. Only values that cross into a task get atomic counts.
- **Size (estimates):** P1 about 25–40 h; P2 about 30–45 h. Each package ends with a stop for the user.
- **What it replaces:** for phase 1, this plan supersedes `docs/concurrency-proposal.md` (2026-09-13) and `docs/audits/d9-wp5-concurrency-design-2026-09-26.md`. It is stage 5 of ADR D9 (`docs/adr/D9-value-semantics-then-rc.md`) on the new core.

## Launch instruction (for Codex)

> **Run package P1 to its end (revision 3).**
> - Fast-forward `codex/concurrency-p1` to `claude/concurrency-plan`. It already contains your P1-0 and P1-1 commits.
> - Read §4.8 (R9–R11) and §9.1 (autonomy), then work through §5 from P1-1's revision-2 redo to P1-6, and then P2-0 as a read-only analysis (§5, "After P1").
> - **Do not stop to ask.** Where the plan is silent or a step fails, investigate, decide, log the decision in `DECISIONS.md` (§9.1) and keep going.
> - Stop only at a hard stop in §9.1, or when P1 and the P2-0 analysis are done.
> - Commit at every step with an updated progress section in `REPORT.md`, so the run can be inspected without being interrupted.
> - If `main` moves, merge it with a real merge commit and rerun the current step's gates.
> - Never merge into `main` and never push.
>
> **Later, package P2,** only when the user says so: on `codex/concurrency-p2`, created from P1's tip merged with the `main` of that day. §9.1 applies to it too.

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

**Count reads are `unordered` atomic loads** (revision 1, §4.7 R1). The shared template `count_load_line` becomes `load atomic i32, ptr …, unordered, align 8`, with its TBAA and range metadata. It feeds every emitted count read: `countBlock`, `isUnique` and `freeUnique`'s verification read. The parent's uniqueness test can run while a worker updates the same shared count, so a plain load is a data race (P1-0's probe reproduced it). Fast-path **stores** stay plain: they happen only on plain blocks, which one thread owns.

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
/* Revision 1 (§4.7 R4, R5): no site parameters; `run` is a fastcc thunk called
   through the emitted bridge `myl_core_task_call`. */
void       myl_core_share(myl_block *root);
myl_block *myl_core_group_open(void);
myl_block *myl_core_task_submit(myl_block *group, void *run, myl_block *env, int64_t item);
myl_block *myl_core_task_result(myl_block *task);   /* waits, running other tasks; +1 */
void       myl_core_group_close(myl_block *group);   /* waits for every task of the group */
int64_t    myl_core_threads(void);
int64_t    myl_core_map_chunks(int64_t items);       /* how many tasks a map of `items` uses */
/* Defined by the emitter in LLVM text, C calling convention (§4.7 R4): */
myl_block *myl_core_task_call(void *run, myl_block *env);
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

### 4.7 Revision 1: decisions on P1-0's findings (2026-10-08)

P1-0's inventory (`experiments/concurrency-p1-2026-10-08/REPORT.md` §2 and its evidence) is **accepted as the design for §4.3**, with every proposed treatment in it. Where it left a choice open, R1–R8 decide it.

**R1. Count reads are `unordered`, not `monotonic`.** Claude's probes (2026-10-08, the same pinned toolchain, P1-0's `count-reader` harness):
- **ThreadSanitizer:** the P1-0 probe with `load atomic … unordered` ran 100 times with 0 reports and the expected `unique=0 count=80000002`.
- **Optimisation:** a loop whose body tests one block's count, compiled at `-O2`:
  - a plain load and an `unordered` load are both hoisted out of the loop, and the loop vectorises;
  - a `monotonic` load stays in the loop, is reloaded every iteration (unrolled ×8) and blocks vectorisation.
- Copy-on-write tests are hoisted out of hot loops (E2b found that essential), so `monotonic` risks the tax gate for nothing.
- **Why `unordered` is enough:** a thread holding a reference to a shared block either set the shared bit itself or received the block through an acquire (task pickup, `result()`). No write that clears the bit can come after that while the reference is held. An `unordered` load cannot tear and returns a value at or after that write in happens-before order, so it always sees the bit.
- **Rule:** use `unordered`. Fall back to `monotonic` only if a TSan run or a P1-5 test shows `unordered` failing, and report it if so.
- The `[1, 0)` range and the TBAA tag stay on the load.

**R2. Text caches.** Lazily filled caches on a block (the hash and scalar-count caches in `reserved`, their `kind` flags, the cursor in `cap` or spare bytes) are written only while `myl_core_pool_started` is false, or on a plain block.
- `myl_core_pool_started` is a process-wide flag. The thread that starts the pool sets it once, with a relaxed atomic store, before creating workers.
- After the pool starts, shared and immortal blocks are read-only: a cache that is already filled is read, and a missing one is computed without being stored.
- Immortal string constants are reachable from every thread, which is why they are included.
- A single-threaded program never starts the pool, so it keeps today's behaviour and pays no tax.
- The P2 report counts cache misses on shared text in the scaling programs.
- `core_ascii` (the lazy immortal ASCII table) is initialised before the pool starts.

**R3. The fatal path never blocks.** The thread that wins the trap once-flag:
- tries the stream lock a bounded number of times. If another thread holds it, the winner writes its report straight to fd 2 with `write(2)` and drops staged output;
- once the pool has started, skips I/O, provider and Host cleanup (`core_io_cleanup`, `core_host_cleanup`), because another thread may be inside them, and then `_exit`s;
- leaves the single-threaded path exactly as it is today.

The rules cover every fatal path P1-0 listed: traps, assertion failures, output refusal, out of memory, I/O failure and the stack-floor signal handler. `core_host.c` stays untouched. A trap after the pool starts may lose data a program wrote to its own files but did not flush; that is acceptable for phase 1, and `docs/concurrency.md` (P2) says so.

**R4. Calling a thunk.** Emitted functions use `fastcc`, and a `func_ref` names one directly. The runtime never calls such a pointer from C. Instead:
- The emitter defines one C-ABI bridge in the fixed runtime text beside `@myl_core_free`:

  ```llvm
  define linkonce_odr hidden ptr @myl_core_task_call(ptr %run, ptr %env) {
    %result = call fastcc ptr %run(ptr %env)
    ret ptr %result
  }
  ```

  It is defined in every unit and merged by the linker.
- `core_tasks.c` declares `myl_core_task_call` and calls tasks only through it.
- P1-5's hand-built-IR tests are the proof that a `func_ref` thunk round-trips through the bridge at 1, 2 and 8 threads, and under TSan.
- If the bridge needs a different form (linkage, attributes, a signature that is not `ptr (ptr)`), choose it, test it, and record why in the report. **No `ir.zig` change.**

**R5. Sites come from return addresses.** `myl_core_group_open` and `myl_core_task_submit` take no site. They record `__builtin_return_address(0)`. A trap in a task then names it as `in task submitted at …`, using the same DWARF line lookup that already names a trap's callers.
- `parallel.map` passes the item index in `item`. A plain `submit` passes −1.
- If an emitted helper call can lack line information (a build mode, or an inlined helper), P1-5 tests that case. The report falls back to `in task submitted at <unknown>` rather than failing.

**R6. Allocator registry.** Each thread's allocator state (free lists, chunk cursor, text-walk counter) registers itself, under a mutex, in a process-wide list when the thread starts. Leak checks and the text-walk report sum over that list at exit, after the pool is quiescent.

**R7. Providers.** Provider operations, not only handle-table changes, run under the I/O mutex. The child iterator covers the provider's `pairs`, which today only `core_io_finalize` releases. Startup options and grants are frozen before the pool starts.

**R8. The source guard** matches reference-count accesses on `myl_block`, through P1-0's typed AST inventory or an equivalent check. It does not ban the token `count`, which other structures use for lengths and arities. It allows the helper implementations, block initialisation and the share walk.

### 4.8 Revision 2: decisions on P1-1's tax stop (2026-10-08)

P1-1's stop was correct, and its gate result stands as recorded. What it showed:
- **The encoding costs nothing on average:** geomean 0.9987× and 0.9980× over two runs.
- **One regression is consistent:** `json_transform` came out at 1.039–1.045× (size 4096) and 1.025–1.033× (size 64) in every batch of both runs. The plain-load build reproduces it (1.031×), so the cause is the encoding's emitted code, not the `unordered` loads. `json::read_value` grew from 7,068 to 8,160 bytes, with 30 new slow-call sites.
- **The other cells over 1.03× are layout:** `bytes_scan/64` and `string_search/64` did not recur in the second run. `binary_search/4096` was 0.948× with `unordered` loads and 1.052× with plain loads, although both lower to the same machine loads.

**R9. The slow path is one `preserve_mostcc` call.**
- Inline code stays one load, one unsigned compare and the plain update.
- Everything else (immortal and shared) is a single `call preserve_mostcc void @myl_core_{retain,release}_slow(ptr)` in a block weighted unlikely (`!prof` branch weights).
- The C helpers are `__attribute__((cold, noinline, preserve_most))` and declared `preserve_mostcc ... nounwind cold`, exactly as the ERROR-TRACE-6 twins are (`myl_core_err_trace_*_preserve_most`).
- **Why:** a C-convention call forces values that are live across it into callee-saved registers. Claude's synthetic probe (`experiments/concurrency-p1-2026-10-08/evidence/claude-r2/`: 12 retain sites, 5 live values) gives:
  - 511 bytes before P1;
  - 1,317 bytes as P1-1 built it;
  - **814 bytes with one `preserve_mostcc` call (variant B)**;
  - 934 bytes with `preserve_mostcc` and the immortal test kept inline (variant C).
- **Variant B** costs immortal retains and releases a call, and string constants are immortal. So P1-1 measures B and C on the five cells that crossed 1.03× (`json_transform` ×2, `bytes_scan/64`, `string_search/64`, `binary_search/4096`) and on `json::read_value`'s size. It keeps the variant with the better geomean over those cells, and records both in the report.
- `release_slow` may free; a `preserve_most` helper may call ordinary C functions inside it.

**R10. The tax protocol controls for code layout.**
- **Problem:** two builds that differ only in code layout can differ by about 5% on one cell. A single-build comparison against a 3% per-cell limit therefore partly measures layout luck.
- **Mechanism:** an internal, measurement-only switch, `MYLANG_CORE_LAYOUT=K` (K = 4, 5 or 6). It passes `-mllvm -align-all-functions=K` to every clang compile of an emitted unit and of the runtime archive, and it is part of the object and runtime cache keys. The pinned `zig cc` accepts the flag and moves function addresses (Claude, 2026-10-08). The zig driver rejects `--shuffle-sections` and `--symbol-ordering-file`.
- **Protocol:** the three batches of §7.1's protocol use K = 4, 5 and 6, with base and candidate built at the same K within a batch, so timing costs the same as before.
- **Cell ratio:** the median of the three batch ratios, as before.
- **Thresholds unchanged:** per-corpus geomean ≤ 1.010, and no cell above 1.03×.
- **Report** each batch's ratio, so a cell that is slow at every alignment stands out from one that is slow at one alignment.
- The switch is internal like `MYLANG_CORE_SANITIZE` (§4.5): no CLI flag, no feature slug, one spec bullet `[LAYOUT-SWITCH-1]`.

**R11. The compare-exchange helpers are accepted.** Shared retain and release use compare-exchange loops. A sentinel check followed by a blind fetch-add could race another thread's saturation and wrap past the immortal value. Keep the loops, and keep the near-saturation and contention tests.

## 5. Package P1: the runtime (about 25–40 h)

**P1-0. Inventory (1–2 h).**
- The table of §4.3, completed.
- Every count access in the runtime.
- Confirmation that a hand-built IR program can call the §4.4 ABI with `func_ref`, boxes and helper calls. If something is missing, write it down for P2-0 and carry on.

**P1-1. Count encoding (§4.1), then an early tax check.** Built at `07b0b3dc3`; revision 2 redoes its slow path and its gate.
- **Code (done):**
  - the `unordered` count loads (R1);
  - `countBlock`;
  - the two slow helpers;
  - `count_retain`, `count_release` and `count_is_unique`, with every runtime count site moved onto them;
  - the source test (R8).
- **Revision 2 code:**
  - the `preserve_mostcc` slow path (R9, variants B and C);
  - the `MYLANG_CORE_LAYOUT` switch (R10).
- **Then:**
  1. Choose R9's variant on the five cells and on `json::read_value`'s size.
  2. Measure the single-threaded tax under R10's protocol on **every** corpus of §7.1: the 46 rows, EDA, both Lox engines and parity. Use the merged resume base `54eda9012` (or its successor if `main` is merged again) built with the same switch.
- **Checkpoint, not a stop** (revision 3):
  - **A cell above 1.03×, or a corpus geomean between 1.010 and 1.03:** investigate. Try R9's variants and any other change to the emitted count paths or the runtime that §9.1 allows, for up to about 6 hours. Then log the result, whether fixed or not, and continue with P1-2. P1-2 changes the runtime again, so P1-6 measures the tax once more, and that measurement is the binding one.
  - **A corpus geomean above 1.03 after that investigation is a hard stop** (§9.1). It would contradict C3's premise.
  - Every measurement's table goes into the report, including the failures.
- **Then** run P1-1's correctness gates again (§7.3, without the TSan suite), and continue with P1-2.

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

**P1-6. Measurement and the report** (§7, §8). The tax measured here, under R10's protocol on every corpus, is P1's binding tax result.
- **If it misses** the thresholds after a further bounded investigation (about 6 hours), the report says so, with the cells, the per-alignment ratios and what was tried. The package still finishes; whether to merge is the user's call.

**After P1: P2-0 as a read-only analysis** (about 2–4 h).
- Write `experiments/concurrency-p1-<date>/P2-0.md`: how each P2 construct lowers to P1's ABI with today's Core IR (helper calls, `func_ref`, `box_make`/`box_get`, generated thunks, the R4 bridge, R5's return-address sites); which builder and checker files P2 will touch; and any IR gap.
- Prove the lowering on hand-built IR. P1-5's tests already call the ABI, so extend them with a `parallel.map`-shaped thunk over a range.
- **No front-end edits.** The front-end plan owns those files until its F4 exit.
- **Then stop.** This is the end of the run.

**P1's expected files** (extended in revisions 1 and 2; revision 3 makes this a guide, not a fence; see §9.1):
- `src/core/runtime/core_rt.c`, `core_test.c`, `core_text.c` (whole file: counts, caches, the ASCII table; R2) and the new `core_tasks.c`;
- `core_io.c`: locks, provider serialisation, frozen startup state and the provider's `pairs` in the child iterator (R7);
- `core_dict.c`, `core_bytes.c`, `core_values.c`: count sites and cache rules only;
- the counting runtime (`core_count.c`, `core_count.h`, `src/core/count_runtime.zig` with its anchors, `src/core/emit_count.zig`);
- in `src/core/emit_llvm.zig`, **only**:
  - `count_load_line` and its comment (R1), which is shared by `countBlock`, `isUnique` and `freeUnique`'s verification read; their comparisons do not change;
  - `countBlock`;
  - the fixed runtime text: the `@myl_core_free_lists` declaration, the inline allocation and free text (around lines 3432–3510), and the `@myl_core_task_call` bridge (R4);
  - the slow-helper declarations and call sites (R9);
  - the counting-build global declarations made thread-local (`@myl_count_current`, `@myl_count_copy_site`, `@myl_count_push_site`);
  - the `sanitize_thread` attribute;
- not `core_host.c`: R3 keeps the fatal path out of it;
- the runtime asset build and link flags for the TSan switch, and the clang flags of the layout switch (R10) in the build driver (`src/core/build.zig` or wherever the unit and runtime compiles are assembled; name the file in the report);
- new tests under `src/core/`;
- `SPEC.md` (§7.2 tags), `docs/tooling/native-build.md` (one paragraph on the TSan switch, as internal), and this plan's Status line;
- `experiments/concurrency-p1-<date>/`.

**Never changed in P1** (§9.1 hard stops): the front end (`src/*.zig` outside `src/core/`), `src/core/ir.zig` and `src/core/own.zig`. Changes to any other file are allowed, provided they are logged in `DECISIONS.md`.

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

- **P1:** `[SHARED-COUNTS-1]` (encoding and emitted paths), `[SHARED-COUNTS-2]` (share walk and invariant), `[RUNTIME-THREADS-1]` (per-thread state, staging, traps, stacks, signals), `[TASK-SCHEDULER-1]` (lazy pool, deques, waiting runs work, thread count), `[TSAN-BUILD-1]` (internal switch), `[LAYOUT-SWITCH-1]` (internal layout switch, R10).
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
7. a summary of `DECISIONS.md`: the decisions that changed the plan, files changed outside the expected list, and every hard stop reached or narrowly avoided (§9.1).

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
- **Correctness first.** A race TSan reports, a result that differs between thread counts, or a conformance difference must be fixed before any timing counts. This is fix-and-continue, not a stop for the user (§9.1).
- **The slow-step rule:** a step over about 5 minutes gets a speed investigation before it is repeated. Log what was found; it is not a stop.

### 9.1 Autonomy (revision 3, 2026-10-09)

The user wants Codex to run long and decide for itself. The default is **decide, log, continue**.

**You decide, without stopping:**
- **Implementation choices** where the plan is silent, ambiguous or wrong in a detail. Choose the simplest option consistent with C1–C7 and R1–R11, prefer the one the evidence favours, and measure where you can.
- **Files.** Any file in the repository may change except the hard-stop list below. Each file outside a package's expected list gets a `DECISIONS.md` line explaining why.
- **Gate failures.** Investigate, fix and rerun:
  - a correctness gate (Guardian, the full gate, conformance, fuzz, TSan, Lox, EDA, parity) must end green;
  - a tax gate follows P1-1's and P1-6's checkpoint rules.
  
  Flaky-looking failures: rerun once. If one repeats, it is a real failure.
- **Order within the package.** Steps may be reordered or overlapped when that is faster, provided every gate still runs on the final tree.
- **Infrastructure:** harness scripts, measurement tools and internal switches needed to measure or test. Make each internal and spec-tagged.

**Hard stops: write the report and stop only for these:**
1. **A semantic change.** Anything that would change C1–C7, a user-visible behaviour, or a revision decision (R1–R11) in substance rather than in detail.
2. **A forbidden file.** A change to the front end (`src/*.zig` outside `src/core/`), `src/core/ir.zig` or `src/core/own.zig`. These are frozen by, or shared with, the front-end plan and the CE lanes.
3. **A relaxed gate.** Lowering a numeric threshold or skipping a gate. Measuring a gate better, as R10 does, is allowed and gets logged.
4. **A broken premise:** a corpus tax geomean above 1.03 after investigation.
5. **An unfixable failure:** a correctness failure that about 8 hours of investigation does not fix.
6. **A touch outside the branch:** anything that would need a merge into `main`, a push, or a change to a Claude worktree or branch.
7. **Resources:** exhausted disk, memory or build slots that cannot be recovered within your own files and processes.

**The decision log.** `experiments/concurrency-p1-<date>/DECISIONS.md` (`…-p2-…` for P2) gets one entry per decision, appended as it is made:
- the date and step;
- the question;
- the options considered;
- the evidence (measurements, test results, file and line);
- the choice;
- whether it is easy to reverse.

Claude and the user review this log after the run, so make each entry stand alone.

**Checkpoints.**
- Commit after each step, with `REPORT.md`'s progress section updated: done, measured, decided, next.
- Never wait for a reply. Nobody will answer mid-run, so a question goes into the log as a decision.

**Self-review before P1-6.** Reread the diff of the whole package against this plan. Check every count access path, every runtime global and every fatal path against §4.3, §4.7 and §4.8. Fix what you find before the final measurements.

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
